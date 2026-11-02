-- Migration 030: Complete the customer deposit flow
-- Adds the missing crypto deposit RPCs used by the deposit page, repairs the
-- admin deposit listing/verification functions, and makes the deposit schema
-- safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Schema guards (safe on databases where 027 was partially applied)
-- ---------------------------------------------------------------------------
alter table public.deposits add column if not exists payment_method text;
alter table public.deposits add column if not exists payment_details jsonb;
alter table public.deposits add column if not exists proof_image_url text;
alter table public.deposits add column if not exists verified_by uuid references public.admin_users(id);
alter table public.deposits add column if not exists verified_at timestamptz;

alter table public.deposits drop constraint if exists deposits_status_check;
alter table public.deposits
  add constraint deposits_status_check check (status in (
    'pending', 'processing', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'
  ));

create table if not exists public.crypto_deposits (
    id              uuid primary key default gen_random_uuid(),
    reference       text not null unique,
    user_id         uuid not null references public.profiles (id) on delete cascade,
    account_id      uuid not null references public.accounts (id),
    asset           text not null,
    network         text,
    address         text not null,
    amount          numeric(20, 8) not null check (amount > 0),
    amount_fiat     numeric(20, 2) not null,
    currency        text not null references public.currencies (code),
    rate_usd        numeric(20, 8) not null default 1,
    fee             numeric(20, 2) not null default 0,
    status          text not null default 'pending' check (status in (
                      'pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'
                    )),
    proof_image_url text,
    tx_hash         text,
    amount_crypto   numeric(20, 8),
    completed_at    timestamptz,
    verified_by     uuid references public.admin_users(id),
    verified_at     timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

alter table public.crypto_deposits add column if not exists proof_image_url text;
alter table public.crypto_deposits add column if not exists tx_hash text;
alter table public.crypto_deposits add column if not exists amount_crypto numeric(20, 8);
alter table public.crypto_deposits add column if not exists amount_fiat numeric(20, 2);
alter table public.crypto_deposits add column if not exists completed_at timestamptz;
alter table public.crypto_deposits add column if not exists verified_by uuid references public.admin_users(id);
alter table public.crypto_deposits add column if not exists verified_at timestamptz;

create index if not exists idx_crypto_deposits_user on public.crypto_deposits (user_id);
create index if not exists idx_crypto_deposits_status on public.crypto_deposits (status);
create index if not exists idx_crypto_deposits_reference on public.crypto_deposits (reference);

alter table public.crypto_deposits enable row level security;
drop policy if exists "crypto_deposits_select_own" on public.crypto_deposits;
create policy "crypto_deposits_select_own" on public.crypto_deposits
  for select using (auth.uid() = user_id);
drop policy if exists "crypto_deposits_insert_own" on public.crypto_deposits;
create policy "crypto_deposits_insert_own" on public.crypto_deposits
  for insert with check (auth.uid() = user_id);

drop trigger if exists touch_crypto_deposits_updated on public.crypto_deposits;
create trigger touch_crypto_deposits_updated before update on public.crypto_deposits
  for each row execute procedure public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Customer crypto deposit creation (USDT / BTC)
-- ---------------------------------------------------------------------------
create or replace function public.create_crypto_deposit(
  p_user_id    uuid,
  p_account_id uuid,
  p_asset      text,
  p_network    text,
  p_amount     numeric,
  p_pin        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_asset public.crypto_assets%rowtype;
  v_deposit public.crypto_deposits%rowtype;
  v_address text;
  v_rate numeric;
  v_fx numeric;
  v_amount_fiat numeric;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active';
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select * into v_asset from public.crypto_assets
    where asset = p_asset and network = p_network and is_enabled;
  if not found then
    raise exception 'ASSET_NOT_SUPPORTED';
  end if;

  if p_amount is null or p_amount < v_asset.min_amount or p_amount > v_asset.max_amount then
    raise exception 'ASSET_LIMIT';
  end if;

  -- Deposit addresses are configured in system_settings; fall back to the
  -- platform's published collection addresses when no override exists.
  select value::text into v_address
    from public.system_settings
    where key = 'deposit_address_' || lower(p_asset) || '_' || lower(p_network);
  if v_address is null or trim(v_address) = '' then
    v_address := case
      when p_asset = 'USDT' and p_network = 'trc20' then 'TXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
      when p_asset = 'USDT' and p_network = 'erc20' then '0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
      when p_asset = 'BTC'  and p_network = 'bitcoin' then 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh'
      else null
    end;
  end if;
  if v_address is null then
    raise exception 'ASSET_NOT_SUPPORTED';
  end if;

  v_rate := coalesce(v_asset.rate_usd, 1);
  v_amount_fiat := round(p_amount * v_rate, 2);

  if v_account.currency <> 'USD' then
    select rate into v_fx from public.exchange_rates
      where base_currency = 'USD' and quote_currency = v_account.currency;
    if v_fx is not null and v_fx > 0 then
      v_amount_fiat := round(v_amount_fiat * v_fx, 2);
    end if;
  end if;

  insert into public.crypto_deposits (
    reference, user_id, account_id, asset, network, address, amount, amount_fiat,
    currency, rate_usd, fee, status, amount_crypto
  ) values (
    public.generate_reference('DEP'), p_user_id, p_account_id, p_asset, p_network, v_address,
    p_amount, v_amount_fiat, v_account.currency, v_rate, 0, 'pending', p_amount
  ) returning * into v_deposit;

  perform public.notify_user(p_user_id,
    'Deposit address generated',
    'Your ' || p_asset || ' deposit address is ready. Send ' || p_amount || ' ' || p_asset ||
    ' to ' || v_address || '. Ref: ' || v_deposit.reference || '.',
    'deposit');

  return jsonb_build_object(
    'success', true,
    'id', v_deposit.id,
    'reference', v_deposit.reference,
    'status', v_deposit.status,
    'asset', v_deposit.asset,
    'network', v_deposit.network,
    'address', v_deposit.address,
    'amount', v_deposit.amount,
    'amount_crypto', v_deposit.amount_crypto,
    'amount_fiat', v_deposit.amount_fiat,
    'currency', v_deposit.currency
  );
end;
$$;

grant execute on function public.create_crypto_deposit(uuid, uuid, text, text, numeric, text) to anon, authenticated;

-- Backwards-compatible helper used by older clients.
create or replace function public.create_bitcoin_deposit(
  p_user_id    uuid,
  p_account_id uuid,
  p_amount     numeric,
  p_pin        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.create_crypto_deposit(p_user_id, p_account_id, 'BTC', 'bitcoin', p_amount, p_pin);
end;
$$;

grant execute on function public.create_bitcoin_deposit(uuid, uuid, numeric, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin: approve/reject crypto deposits and credit the account correctly
-- ---------------------------------------------------------------------------
create or replace function public.admin_verify_crypto_deposit(
  p_token text,
  p_deposit_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_deposit public.crypto_deposits%rowtype;
begin
  if not public.admin_can(p_token, 'deposits.verify') then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_deposit from public.crypto_deposits where id = p_deposit_id for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;

  if v_deposit.status not in ('pending_verification', 'pending') then
    raise exception 'DEPOSIT_NOT_VERIFIABLE';
  end if;

  v_admin := public.admin_from_token(p_token);

  if p_action = 'reject' then
    update public.crypto_deposits
      set status = 'rejected', verified_by = v_admin.id, verified_at = now(), updated_at = now()
      where id = p_deposit_id;

    perform public.notify_user(v_deposit.user_id, 'Deposit Rejected',
      'Your crypto deposit was rejected.' ||
      case when p_reason is not null and p_reason <> '' then ' Reason: ' || p_reason else '' end,
      'deposit');
    perform public.log_audit(p_token, 'REJECT_DEPOSIT', 'crypto_deposit', p_deposit_id::text,
      to_jsonb(v_deposit), jsonb_build_object('reason', p_reason));

    return jsonb_build_object('status', 'rejected', 'reference', v_deposit.reference);
  end if;

  perform public.apply_balance_change(v_deposit.account_id, v_deposit.amount_fiat, v_deposit.currency);

  update public.crypto_deposits
    set status = 'completed', verified_by = v_admin.id, verified_at = now(),
        completed_at = now(), updated_at = now()
    where id = p_deposit_id;

  perform public.record_transaction(
    v_deposit.user_id,
    v_deposit.account_id,
    'deposit',
    'credit',
    v_deposit.amount_fiat,
    v_deposit.currency,
    'completed',
    'Crypto deposit ' || v_deposit.asset || coalesce(' ' || v_deposit.network, ''),
    v_deposit.reference,
    'Crypto Deposit',
    0,
    v_deposit.id
  );

  perform public.notify_user(v_deposit.user_id,
    'Deposit Approved',
    'Your crypto deposit of ' || coalesce(v_deposit.amount_crypto, v_deposit.amount) || ' ' || v_deposit.asset ||
    ' has been approved and credited to your account. Ref: ' || v_deposit.reference || '.',
    'deposit');

  perform public.log_audit(p_token, 'APPROVE_DEPOSIT', 'crypto_deposit', p_deposit_id::text,
    to_jsonb(v_deposit), jsonb_build_object('status', 'completed'));

  return jsonb_build_object('status', 'approved', 'reference', v_deposit.reference);
end;
$$;

grant execute on function public.admin_verify_crypto_deposit(text, uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Admin: list fiat + crypto deposits with filters
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_deposits(
  p_token text,
  p_search text default null,
  p_status text default null,
  p_type text default null,
  p_asset text default null,
  p_limit int default 12,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total int;
  v_rows jsonb;
begin
  if not public.admin_can(p_token, 'deposits.view') then
    raise exception 'FORBIDDEN';
  end if;

  with all_deposits as (
    select d.id, d.reference, d.user_id, d.account_id, d.amount, d.currency, d.method,
           d.status, d.note, d.created_at, d.updated_at, d.payment_method,
           d.proof_image_url, d.verified_at,
           'fiat'::text as type, null::text as asset, null::text as network,
           null::text as address, null::text as tx_hash, null::numeric as amount_crypto,
           d.amount as amount_fiat, p.full_name as user_name, p.email as user_email
    from public.deposits d
    join public.profiles p on p.id = d.user_id
    union all
    select cd.id, cd.reference, cd.user_id, cd.account_id, cd.amount, cd.currency, cd.asset as method,
           cd.status, null::text, cd.created_at, cd.updated_at, null::text,
           cd.proof_image_url, cd.verified_at,
           'crypto'::text, cd.asset, cd.network, cd.address, cd.tx_hash,
           coalesce(cd.amount_crypto, cd.amount), cd.amount_fiat,
           p.full_name, p.email
    from public.crypto_deposits cd
    join public.profiles p on p.id = cd.user_id
  )
  select count(*) into v_total
  from all_deposits
  where (p_search is null or p_search = '' or reference ilike '%' || p_search || '%'
         or user_email ilike '%' || p_search || '%' or user_name ilike '%' || p_search || '%'
         or asset ilike '%' || p_search || '%')
    and (p_status is null or p_status = '' or status = p_status)
    and (p_type is null or p_type = '' or type = p_type)
    and (p_asset is null or p_asset = '' or asset = p_asset or currency = p_asset);

  with all_deposits as (
    select d.id, d.reference, d.user_id, d.account_id, d.amount, d.currency, d.method,
           d.status, d.note, d.created_at, d.updated_at, d.payment_method,
           d.proof_image_url, d.verified_at,
           'fiat'::text as type, null::text as asset, null::text as network,
           null::text as address, null::text as tx_hash, null::numeric as amount_crypto,
           d.amount as amount_fiat, p.full_name as user_name, p.email as user_email
    from public.deposits d
    join public.profiles p on p.id = d.user_id
    union all
    select cd.id, cd.reference, cd.user_id, cd.account_id, cd.amount, cd.currency, cd.asset as method,
           cd.status, null::text, cd.created_at, cd.updated_at, null::text,
           cd.proof_image_url, cd.verified_at,
           'crypto'::text, cd.asset, cd.network, cd.address, cd.tx_hash,
           coalesce(cd.amount_crypto, cd.amount), cd.amount_fiat,
           p.full_name, p.email
    from public.crypto_deposits cd
    join public.profiles p on p.id = cd.user_id
  )
  select coalesce(jsonb_agg(to_jsonb(q)), '[]') into v_rows
  from (
    select * from all_deposits
    where (p_search is null or p_search = '' or reference ilike '%' || p_search || '%'
           or user_email ilike '%' || p_search || '%' or user_name ilike '%' || p_search || '%'
           or asset ilike '%' || p_search || '%')
      and (p_status is null or p_status = '' or status = p_status)
      and (p_type is null or p_type = '' or type = p_type)
      and (p_asset is null or p_asset = '' or asset = p_asset or currency = p_asset)
    order by created_at desc
    limit coalesce(p_limit, 12) offset coalesce(p_offset, 0)
  ) q;

  return jsonb_build_object('rows', v_rows, 'total', v_total);
end;
$$;

grant execute on function public.admin_list_deposits(text, text, text, text, text, int, int) to anon, authenticated;
