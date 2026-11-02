-- Migration 031: Configurable deposit management
-- Adds admin-managed deposit methods, crypto network configuration, customer
-- deposit configuration, transaction-hash submission, and safe crediting.

-- ---------------------------------------------------------------------------
-- 1. Deposit idempotency and crypto transaction hashes
-- ---------------------------------------------------------------------------
alter table public.deposits add column if not exists request_id text;
alter table public.crypto_deposits add column if not exists request_id text;
alter table public.crypto_deposits add column if not exists submitted_at timestamptz;
alter table public.crypto_deposits add column if not exists admin_note text;

create unique index if not exists uq_deposits_request
  on public.deposits (user_id, request_id) where request_id is not null;
create unique index if not exists uq_crypto_deposits_request
  on public.crypto_deposits (user_id, request_id) where request_id is not null;
do $$
begin
  if not exists (
    select 1
    from public.crypto_deposits
    where tx_hash is not null and btrim(tx_hash) <> ''
    group by upper(asset), lower(network), lower(btrim(tx_hash))
    having count(*) > 1
  ) then
    execute 'create unique index if not exists uq_crypto_deposits_tx_hash
             on public.crypto_deposits (upper(asset), lower(network), lower(btrim(tx_hash)))
             where tx_hash is not null and btrim(tx_hash) <> ''''';
  end if;
end $$;

-- Prevent a deposit from being credited twice. If historical duplicates exist,
-- leave the index out rather than failing the migration; the RPCs still guard
-- the status transition and check for an existing credit transaction.
do $$
begin
  if not exists (
    select 1
    from public.transactions
    where related_id is not null
      and type = 'deposit'
      and direction = 'credit'
    group by related_id
    having count(*) > 1
  ) then
    execute 'create unique index if not exists uq_transactions_deposit_credit
             on public.transactions (related_id)
             where related_id is not null and type = ''deposit'' and direction = ''credit''';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Crypto asset deposit configuration
-- ---------------------------------------------------------------------------
alter table public.crypto_assets add column if not exists deposit_enabled boolean not null default true;
alter table public.crypto_assets add column if not exists deposit_address text;
alter table public.crypto_assets add column if not exists deposit_address_tag text;
alter table public.crypto_assets add column if not exists deposit_min_amount numeric(20, 8);
alter table public.crypto_assets add column if not exists deposit_max_amount numeric(20, 8);
alter table public.crypto_assets add column if not exists deposit_instructions text;
alter table public.crypto_assets add column if not exists sort_order int not null default 0;

update public.crypto_assets
set deposit_min_amount = min_amount
where deposit_min_amount is null;

update public.crypto_assets
set deposit_max_amount = max_amount
where deposit_max_amount is null;

-- Carry over any legacy address settings before deciding whether an asset is
-- ready to be shown to customers.
update public.crypto_assets ca
set deposit_address = coalesce(
  ca.deposit_address,
  (
    select s.value #>> '{}'
    from public.system_settings s
    where s.key = 'deposit_address_' || lower(ca.asset) || '_' || lower(ca.network)
  )
)
where ca.deposit_address is null;

update public.crypto_assets
set deposit_instructions = coalesce(
  deposit_instructions,
  'Send only ' || asset || ' on the ' || network_label || ' network. ' ||
  'Deposits are credited after the transaction is confirmed and verified.'
)
where deposit_instructions is null;

update public.crypto_assets
set deposit_enabled = false
where deposit_address is null or btrim(deposit_address) = '';

-- ---------------------------------------------------------------------------
-- 3. Admin-managed deposit methods
-- ---------------------------------------------------------------------------
create table if not exists public.deposit_methods (
  code          text primary key,
  kind          text not null default 'wallet' check (kind in ('wallet', 'crypto', 'bank')),
  asset         text,
  backend_method text,
  label         text not null,
  description   text,
  icon          text,
  enabled       boolean not null default true,
  sort_order    int not null default 0,
  min_amount    numeric(20, 2) not null default 1,
  max_amount    numeric(20, 2),
  currencies    text[] not null default array['EUR', 'USD']::text[],
  instructions  text,
  config        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.deposit_methods add column if not exists asset text;
alter table public.deposit_methods add column if not exists backend_method text;
alter table public.deposit_methods add column if not exists config jsonb not null default '{}'::jsonb;

create unique index if not exists uq_deposit_methods_crypto_asset
  on public.deposit_methods (upper(asset))
  where kind = 'crypto' and asset is not null;

drop trigger if exists touch_deposit_methods_updated on public.deposit_methods;
create trigger touch_deposit_methods_updated before update on public.deposit_methods
  for each row execute procedure public.touch_updated_at();

alter table public.deposit_methods enable row level security;
drop policy if exists "deposit_methods_select_auth" on public.deposit_methods;
create policy "deposit_methods_select_auth" on public.deposit_methods
  for select using (auth.role() = 'authenticated');

insert into public.deposit_methods
  (code, kind, asset, backend_method, label, description, icon, enabled, sort_order, min_amount, max_amount, currencies, instructions)
values
  ('google_pay', 'wallet', null, 'card', 'Google Pay', 'Pay instantly with Google Pay', '📱', true, 10, 1, 10000, array['EUR', 'USD']::text[],
   'Complete the payment in the Google Pay sheet. Your deposit is credited after the payment is confirmed.'),
  ('apple_pay', 'wallet', null, 'card', 'Apple Pay', 'Pay instantly with Apple Pay', '🍎', true, 20, 1, 10000, array['EUR', 'USD']::text[],
   'Complete the payment in the Apple Pay sheet. Your deposit is credited after the payment is confirmed.'),
  ('usdt', 'crypto', 'USDT', null, 'USDT', 'Tether (USDT) deposits', '💲', true, 30, 1, 20000, array['EUR', 'USD']::text[],
   'Send only USDT on the selected network. Deposits are credited after on-chain confirmation and admin verification.'),
  ('bitcoin', 'crypto', 'BTC', null, 'Bitcoin (BTC)', 'Bitcoin deposits', '₿', true, 40, 0.0001, 5, array['EUR', 'USD']::text[],
   'Send only BTC on the Bitcoin network. Deposits are credited after on-chain confirmation and admin verification.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Global deposit settings
-- ---------------------------------------------------------------------------
insert into public.system_settings (key, value, description)
values
  ('deposits_enabled', 'true'::jsonb, 'Whether customer deposits are enabled'),
  ('deposit_instructions', to_jsonb('Choose a deposit method, complete the payment, and keep the reference for your records. Crypto deposits are credited after confirmation and verification.'::text), 'Default customer deposit instructions')
on conflict (key) do nothing;

-- Grant the verification permission used by crypto approval RPCs.
update public.admin_roles
set permissions = array_append(permissions, 'deposits.verify')
where name in ('super_admin', 'admin')
  and not ('deposits.verify' = any (permissions));

-- ---------------------------------------------------------------------------
-- 5. Customer deposit configuration
-- ---------------------------------------------------------------------------
create or replace function public.customer_get_deposit_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := true;
  v_instructions text := '';
  v_methods jsonb;
  v_assets jsonb;
begin
  select coalesce((s.value #>> '{}')::boolean, true)
  into v_enabled
  from public.system_settings s
  where s.key = 'deposits_enabled';

  select coalesce(s.value #>> '{}', '')
  into v_instructions
  from public.system_settings s
  where s.key = 'deposit_instructions';

  select coalesce(jsonb_agg(to_jsonb(m) order by m.sort_order, m.code), '[]'::jsonb)
  into v_methods
  from public.deposit_methods m
  where m.enabled
    and (
      m.kind <> 'crypto'
      or exists (
        select 1
        from public.crypto_assets a
        where a.is_enabled
          and a.deposit_enabled
          and upper(a.asset) = upper(m.asset)
          and a.deposit_address is not null
          and btrim(a.deposit_address) <> ''
      )
    );

  select coalesce(jsonb_agg(to_jsonb(a) order by a.sort_order, a.asset, a.network), '[]'::jsonb)
  into v_assets
  from public.crypto_assets a
  where a.is_enabled
    and a.deposit_enabled
    and a.deposit_address is not null
    and btrim(a.deposit_address) <> '';

  return jsonb_build_object(
    'enabled', coalesce(v_enabled, true),
    'instructions', coalesce(v_instructions, ''),
    'methods', v_methods,
    'assets', v_assets
  );
end;
$$;

grant execute on function public.customer_get_deposit_config() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Customer fiat deposit creation
-- ---------------------------------------------------------------------------
drop function if exists public.create_customer_deposit(uuid, uuid, numeric, text, text, text, text);

create or replace function public.create_customer_deposit(
  p_user_id    uuid,
  p_account_id uuid,
  p_amount     numeric,
  p_currency   text,
  p_method     text,
  p_note       text default null,
  p_pin        text default null,
  p_method_code text default null,
  p_request_id text default null
)
returns public.deposits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_deposit public.deposits%rowtype;
  v_method public.deposit_methods%rowtype;
  v_enabled boolean := true;
  v_method_code text;
  v_request_id text;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account
  from public.accounts
  where id = p_account_id and user_id = p_user_id and status = 'active';
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if p_currency is distinct from v_account.currency then
    raise exception 'CURRENCY_MISMATCH';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  select coalesce((s.value #>> '{}')::boolean, true)
  into v_enabled
  from public.system_settings s
  where s.key = 'deposits_enabled';
  if not coalesce(v_enabled, true) then
    raise exception 'DEPOSITS_DISABLED';
  end if;

  v_method_code := nullif(btrim(coalesce(p_method_code, p_method)), '');
  v_request_id := nullif(btrim(p_request_id), '');

  select * into v_method
  from public.deposit_methods
  where code = v_method_code;

  if found then
    if not v_method.enabled then
      raise exception 'METHOD_DISABLED';
    end if;
    if v_method.kind not in ('wallet', 'bank') then
      raise exception 'INVALID_METHOD';
    end if;
    if p_amount < v_method.min_amount then
      raise exception 'AMOUNT_BELOW_MIN';
    end if;
    if v_method.max_amount is not null and p_amount > v_method.max_amount then
      raise exception 'AMOUNT_ABOVE_MAX';
    end if;
    if array_length(v_method.currencies, 1) is not null
       and not (p_currency = any (v_method.currencies)) then
      raise exception 'CURRENCY_NOT_SUPPORTED';
    end if;
    p_method := coalesce(p_method, v_method.backend_method, 'online');
  end if;

  if p_method is null or p_method not in ('cash', 'bank_transfer', 'cheque', 'card', 'online') then
    raise exception 'INVALID_METHOD';
  end if;

  if v_request_id is not null then
    select * into v_deposit
    from public.deposits
    where user_id = p_user_id and request_id = v_request_id;
    if found then
      return v_deposit;
    end if;
  end if;

  insert into public.deposits (
    reference, user_id, account_id, amount, currency, method, note, status,
    payment_method, payment_details, request_id
  ) values (
    public.generate_reference('DEP'), p_user_id, p_account_id, p_amount, p_currency,
    p_method, p_note, 'pending',
    v_method_code,
    jsonb_build_object(
      'method_code', v_method_code,
      'method_label', v_method.label,
      'instructions', v_method.instructions
    ),
    v_request_id
  )
  on conflict (user_id, request_id) where request_id is not null do nothing
  returning * into v_deposit;

  if v_deposit.id is null then
    select * into v_deposit
    from public.deposits
    where user_id = p_user_id and request_id = v_request_id;
  end if;

  return v_deposit;
end;
$$;

grant execute on function public.create_customer_deposit(uuid, uuid, numeric, text, text, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Customer crypto deposit creation
-- ---------------------------------------------------------------------------
drop function if exists public.create_crypto_deposit(uuid, uuid, text, text, numeric, text);

create or replace function public.create_crypto_deposit(
  p_user_id    uuid,
  p_account_id uuid,
  p_asset      text,
  p_network    text,
  p_amount     numeric,
  p_pin        text default null,
  p_request_id text default null
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
  v_method public.deposit_methods%rowtype;
  v_enabled boolean := true;
  v_address text;
  v_rate numeric;
  v_fx numeric;
  v_amount_fiat numeric;
  v_min numeric;
  v_max numeric;
  v_request_id text;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account
  from public.accounts
  where id = p_account_id and user_id = p_user_id and status = 'active';
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select coalesce((s.value #>> '{}')::boolean, true)
  into v_enabled
  from public.system_settings s
  where s.key = 'deposits_enabled';
  if not coalesce(v_enabled, true) then
    raise exception 'DEPOSITS_DISABLED';
  end if;

  select * into v_asset
  from public.crypto_assets
  where upper(asset) = upper(p_asset)
    and lower(network) = lower(p_network)
    and is_enabled
    and deposit_enabled;
  if not found then
    raise exception 'ASSET_NOT_SUPPORTED';
  end if;

  select * into v_method
  from public.deposit_methods
  where kind = 'crypto' and upper(asset) = upper(p_asset)
  limit 1;
  if found then
    if not v_method.enabled then
      raise exception 'METHOD_DISABLED';
    end if;
    if array_length(v_method.currencies, 1) is not null
       and not (v_account.currency = any (v_method.currencies)) then
      raise exception 'CURRENCY_NOT_SUPPORTED';
    end if;
  end if;

  v_min := coalesce(v_asset.deposit_min_amount, v_asset.min_amount, 0);
  v_max := coalesce(v_asset.deposit_max_amount, v_asset.max_amount);
  if p_amount is null or p_amount < v_min then
    raise exception 'AMOUNT_BELOW_MIN';
  end if;
  if v_max is not null and p_amount > v_max then
    raise exception 'AMOUNT_ABOVE_MAX';
  end if;

  v_address := btrim(coalesce(v_asset.deposit_address, ''));
  if v_address = '' then
    raise exception 'DEPOSIT_ADDRESS_NOT_CONFIGURED';
  end if;

  v_rate := coalesce(v_asset.rate_usd, 1);
  v_amount_fiat := round(p_amount * v_rate, 2);

  if v_account.currency <> 'USD' then
    select rate into v_fx
    from public.exchange_rates
    where base_currency = 'USD' and quote_currency = v_account.currency;
    if v_fx is not null and v_fx > 0 then
      v_amount_fiat := round(v_amount_fiat * v_fx, 2);
    end if;
  end if;

  v_request_id := nullif(btrim(p_request_id), '');

  if v_request_id is not null then
    select * into v_deposit
    from public.crypto_deposits
    where user_id = p_user_id and request_id = v_request_id;
    if found then
      return jsonb_build_object(
        'success', true,
        'id', v_deposit.id,
        'reference', v_deposit.reference,
        'status', v_deposit.status,
        'asset', v_deposit.asset,
        'network', v_deposit.network,
        'address', v_deposit.address,
        'address_tag', v_asset.deposit_address_tag,
        'amount', v_deposit.amount,
        'amount_crypto', v_deposit.amount_crypto,
        'amount_fiat', v_deposit.amount_fiat,
        'currency', v_deposit.currency,
        'instructions', v_asset.deposit_instructions
      );
    end if;
  end if;

  insert into public.crypto_deposits (
    reference, user_id, account_id, asset, network, address, amount, amount_fiat,
    currency, rate_usd, fee, status, amount_crypto, request_id
  ) values (
    public.generate_reference('DEP'), p_user_id, p_account_id,
    upper(p_asset), lower(p_network), v_address, p_amount, v_amount_fiat,
    v_account.currency, v_rate, 0, 'pending', p_amount, v_request_id
  )
  on conflict (user_id, request_id) where request_id is not null do nothing
  returning * into v_deposit;

  if v_deposit.id is null then
    select * into v_deposit
    from public.crypto_deposits
    where user_id = p_user_id and request_id = v_request_id;
  end if;

  perform public.notify_user(
    p_user_id,
    'Deposit address generated',
    'Your ' || v_deposit.asset || ' deposit address is ready. Send ' ||
    v_deposit.amount || ' ' || v_deposit.asset || ' to ' || v_deposit.address ||
    '. Ref: ' || v_deposit.reference || '.',
    'deposit'
  );

  return jsonb_build_object(
    'success', true,
    'id', v_deposit.id,
    'reference', v_deposit.reference,
    'status', v_deposit.status,
    'asset', v_deposit.asset,
    'network', v_deposit.network,
    'address', v_deposit.address,
    'address_tag', v_asset.deposit_address_tag,
    'amount', v_deposit.amount,
    'amount_crypto', v_deposit.amount_crypto,
    'amount_fiat', v_deposit.amount_fiat,
    'currency', v_deposit.currency,
    'instructions', v_asset.deposit_instructions
  );
end;
$$;

grant execute on function public.create_crypto_deposit(uuid, uuid, text, text, numeric, text, text) to anon, authenticated;

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
-- 8. Customer transaction-hash submission
-- ---------------------------------------------------------------------------
create or replace function public.customer_submit_crypto_tx(
  p_deposit_id uuid,
  p_tx_hash    text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit public.crypto_deposits%rowtype;
  v_hash text;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN';
  end if;

  v_hash := btrim(coalesce(p_tx_hash, ''));
  if length(v_hash) < 8 or length(v_hash) > 200 then
    raise exception 'INVALID_TX_HASH';
  end if;

  select * into v_deposit
  from public.crypto_deposits
  where id = p_deposit_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;

  if v_deposit.status = 'pending_verification' and v_deposit.tx_hash = v_hash then
    return jsonb_build_object(
      'success', true,
      'status', v_deposit.status,
      'tx_hash', v_deposit.tx_hash,
      'reference', v_deposit.reference
    );
  end if;

  if v_deposit.status <> 'pending' then
    raise exception 'DEPOSIT_NOT_PENDING';
  end if;

  begin
    update public.crypto_deposits
    set tx_hash = v_hash,
        status = 'pending_verification',
        submitted_at = now(),
        updated_at = now()
    where id = p_deposit_id
    returning * into v_deposit;
  exception when unique_violation then
    raise exception 'DUPLICATE_TX_HASH';
  end;

  perform public.notify_user(
    v_deposit.user_id,
    'Deposit submitted for verification',
    'We received the transaction hash for your ' || v_deposit.asset ||
    ' deposit. Ref: ' || v_deposit.reference || '.',
    'deposit'
  );

  return jsonb_build_object(
    'success', true,
    'status', v_deposit.status,
    'tx_hash', v_deposit.tx_hash,
    'reference', v_deposit.reference
  );
end;
$$;

grant execute on function public.customer_submit_crypto_tx(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Admin deposit configuration
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_deposit_config(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled boolean := true;
  v_instructions text := '';
  v_methods jsonb;
  v_assets jsonb;
begin
  if not public.admin_can(p_token, 'deposits.view') then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce((s.value #>> '{}')::boolean, true)
  into v_enabled
  from public.system_settings s
  where s.key = 'deposits_enabled';

  select coalesce(s.value #>> '{}', '')
  into v_instructions
  from public.system_settings s
  where s.key = 'deposit_instructions';

  select coalesce(jsonb_agg(to_jsonb(m) order by m.sort_order, m.code), '[]'::jsonb)
  into v_methods
  from public.deposit_methods m;

  select coalesce(jsonb_agg(to_jsonb(a) order by a.sort_order, a.asset, a.network), '[]'::jsonb)
  into v_assets
  from public.crypto_assets a;

  return jsonb_build_object(
    'enabled', coalesce(v_enabled, true),
    'instructions', coalesce(v_instructions, ''),
    'methods', v_methods,
    'assets', v_assets
  );
end;
$$;

grant execute on function public.admin_get_deposit_config(text) to anon, authenticated;

create or replace function public.admin_update_deposit_general(
  p_token        text,
  p_enabled      boolean,
  p_instructions text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old_enabled jsonb;
  v_old_instructions jsonb;
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;

  select value into v_old_enabled
  from public.system_settings where key = 'deposits_enabled';
  select value into v_old_instructions
  from public.system_settings where key = 'deposit_instructions';

  insert into public.system_settings (key, value, description, updated_at)
  values ('deposits_enabled', to_jsonb(coalesce(p_enabled, true)), 'Whether customer deposits are enabled', now())
  on conflict (key) do update set value = excluded.value, updated_at = now();

  insert into public.system_settings (key, value, description, updated_at)
  values ('deposit_instructions', to_jsonb(coalesce(p_instructions, '')), 'Default customer deposit instructions', now())
  on conflict (key) do update set value = excluded.value, updated_at = now();

  perform public.log_audit(
    p_token,
    'UPDATE_DEPOSIT_SETTINGS',
    'deposit_settings',
    'general',
    jsonb_build_object('enabled', v_old_enabled, 'instructions', v_old_instructions),
    jsonb_build_object('enabled', coalesce(p_enabled, true), 'instructions', coalesce(p_instructions, ''))
  );
end;
$$;

grant execute on function public.admin_update_deposit_general(text, boolean, text) to anon, authenticated;

create or replace function public.admin_save_deposit_method(
  p_token         text,
  p_code          text,
  p_kind          text,
  p_asset         text,
  p_backend_method text,
  p_label         text,
  p_description   text,
  p_icon          text,
  p_enabled       boolean,
  p_sort_order    int,
  p_min_amount    numeric,
  p_max_amount    numeric,
  p_currencies    text[],
  p_instructions  text,
  p_config        jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text := lower(btrim(coalesce(p_code, '')));
  v_kind text := lower(btrim(coalesce(p_kind, 'wallet')));
  v_asset text := nullif(upper(btrim(coalesce(p_asset, ''))), '');
  v_old jsonb;
  v_new jsonb;
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;

  if v_code !~ '^[a-z0-9_]+$' then
    raise exception 'INVALID_METHOD_CODE';
  end if;
  if v_kind not in ('wallet', 'crypto', 'bank') then
    raise exception 'INVALID_METHOD_KIND';
  end if;
  if v_kind = 'crypto' and v_asset is null then
    raise exception 'ASSET_REQUIRED';
  end if;
  if btrim(coalesce(p_label, '')) = '' then
    raise exception 'LABEL_REQUIRED';
  end if;
  if p_min_amount is null or p_min_amount < 0 then
    raise exception 'INVALID_MIN_AMOUNT';
  end if;
  if p_max_amount is not null and p_max_amount < p_min_amount then
    raise exception 'INVALID_MAX_AMOUNT';
  end if;

  select to_jsonb(m) into v_old
  from public.deposit_methods m where m.code = v_code;

  insert into public.deposit_methods (
    code, kind, asset, backend_method, label, description, icon, enabled,
    sort_order, min_amount, max_amount, currencies, instructions, config, updated_at
  ) values (
    v_code, v_kind, v_asset, nullif(btrim(coalesce(p_backend_method, '')), ''),
    btrim(p_label), p_description, p_icon, coalesce(p_enabled, true),
    coalesce(p_sort_order, 0), p_min_amount, p_max_amount,
    coalesce(p_currencies, array['EUR', 'USD']::text[]),
    p_instructions, coalesce(p_config, '{}'::jsonb), now()
  )
  on conflict (code) do update set
    kind = excluded.kind,
    asset = excluded.asset,
    backend_method = excluded.backend_method,
    label = excluded.label,
    description = excluded.description,
    icon = excluded.icon,
    enabled = excluded.enabled,
    sort_order = excluded.sort_order,
    min_amount = excluded.min_amount,
    max_amount = excluded.max_amount,
    currencies = excluded.currencies,
    instructions = excluded.instructions,
    config = excluded.config,
    updated_at = now();

  select to_jsonb(m) into v_new
  from public.deposit_methods m where m.code = v_code;

  perform public.log_audit(
    p_token,
    'SAVE_DEPOSIT_METHOD',
    'deposit_method',
    v_code,
    v_old,
    v_new
  );
end;
$$;

grant execute on function public.admin_save_deposit_method(text, text, text, text, text, text, text, text, boolean, int, numeric, numeric, text[], text, jsonb) to anon, authenticated;

create or replace function public.admin_save_crypto_deposit_asset(
  p_token                text,
  p_asset                text,
  p_network              text,
  p_asset_label          text,
  p_network_label        text,
  p_is_enabled           boolean,
  p_deposit_enabled      boolean,
  p_deposit_address      text,
  p_deposit_address_tag  text,
  p_deposit_min_amount   numeric,
  p_deposit_max_amount   numeric,
  p_deposit_instructions text,
  p_rate_usd             numeric,
  p_sort_order           int
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_asset text := upper(btrim(coalesce(p_asset, '')));
  v_network text := lower(btrim(coalesce(p_network, '')));
  v_address text := nullif(btrim(coalesce(p_deposit_address, '')), '');
  v_old jsonb;
  v_new jsonb;
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;

  if v_asset = '' or v_network = '' then
    raise exception 'ASSET_AND_NETWORK_REQUIRED';
  end if;
  if p_rate_usd is null or p_rate_usd <= 0 then
    raise exception 'INVALID_RATE';
  end if;
  if p_deposit_min_amount is null or p_deposit_min_amount < 0 then
    raise exception 'INVALID_MIN_AMOUNT';
  end if;
  if p_deposit_max_amount is not null and p_deposit_max_amount < p_deposit_min_amount then
    raise exception 'INVALID_MAX_AMOUNT';
  end if;
  if coalesce(p_deposit_enabled, true) and v_address is null then
    raise exception 'DEPOSIT_ADDRESS_REQUIRED';
  end if;

  select to_jsonb(a) into v_old
  from public.crypto_assets a
  where upper(a.asset) = v_asset and lower(a.network) = v_network;

  insert into public.crypto_assets (
    asset, network, asset_label, network_label, is_enabled, min_amount, max_amount,
    rate_usd, deposit_enabled, deposit_address, deposit_address_tag,
    deposit_min_amount, deposit_max_amount, deposit_instructions, sort_order, updated_at
  ) values (
    v_asset, v_network,
    coalesce(nullif(btrim(p_asset_label), ''), v_asset),
    coalesce(nullif(btrim(p_network_label), ''), upper(v_network)),
    coalesce(p_is_enabled, true),
    coalesce(p_deposit_min_amount, 0),
    coalesce(p_deposit_max_amount, 1000),
    p_rate_usd,
    coalesce(p_deposit_enabled, true),
    v_address,
    nullif(btrim(coalesce(p_deposit_address_tag, '')), ''),
    p_deposit_min_amount,
    p_deposit_max_amount,
    p_deposit_instructions,
    coalesce(p_sort_order, 0),
    now()
  )
  on conflict (asset, network) do update set
    asset_label = excluded.asset_label,
    network_label = excluded.network_label,
    is_enabled = excluded.is_enabled,
    rate_usd = excluded.rate_usd,
    deposit_enabled = excluded.deposit_enabled,
    deposit_address = excluded.deposit_address,
    deposit_address_tag = excluded.deposit_address_tag,
    deposit_min_amount = excluded.deposit_min_amount,
    deposit_max_amount = excluded.deposit_max_amount,
    deposit_instructions = excluded.deposit_instructions,
    sort_order = excluded.sort_order,
    updated_at = now();

  select to_jsonb(a) into v_new
  from public.crypto_assets a
  where upper(a.asset) = v_asset and lower(a.network) = v_network;

  perform public.log_audit(
    p_token,
    'SAVE_CRYPTO_DEPOSIT_ASSET',
    'crypto_asset',
    v_asset || '/' || v_network,
    v_old,
    v_new
  );
end;
$$;

grant execute on function public.admin_save_crypto_deposit_asset(text, text, text, text, text, boolean, boolean, text, text, numeric, numeric, text, numeric, int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 10. Safe admin verification
-- ---------------------------------------------------------------------------
drop function if exists public.admin_verify_crypto_deposit(text, uuid, text, text);

create or replace function public.admin_verify_crypto_deposit(
  p_token      text,
  p_deposit_id uuid,
  p_action     text,
  p_reason     text default null,
  p_tx_hash    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_deposit public.crypto_deposits%rowtype;
  v_hash text;
  v_action text := lower(btrim(coalesce(p_action, '')));
begin
  if not public.admin_can(p_token, 'deposits.verify') then
    raise exception 'FORBIDDEN';
  end if;

  if v_action not in ('approve', 'reject') then
    raise exception 'INVALID_ACTION';
  end if;

  select * into v_deposit
  from public.crypto_deposits
  where id = p_deposit_id
  for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;

  if v_deposit.status not in ('pending_verification', 'pending') then
    raise exception 'DEPOSIT_NOT_VERIFIABLE';
  end if;

  v_admin := public.admin_from_token(p_token);

  if v_action = 'reject' then
    update public.crypto_deposits
    set status = 'rejected',
        admin_note = p_reason,
        verified_by = v_admin.id,
        verified_at = now(),
        updated_at = now()
    where id = p_deposit_id;

    perform public.notify_user(
      v_deposit.user_id,
      'Deposit Rejected',
      'Your crypto deposit was rejected.' ||
      case when p_reason is not null and p_reason <> '' then ' Reason: ' || p_reason else '' end,
      'deposit'
    );
    perform public.log_audit(
      p_token, 'REJECT_DEPOSIT', 'crypto_deposit', p_deposit_id::text,
      to_jsonb(v_deposit), jsonb_build_object('reason', p_reason)
    );

    return jsonb_build_object('status', 'rejected', 'reference', v_deposit.reference);
  end if;

  v_hash := nullif(btrim(coalesce(p_tx_hash, v_deposit.tx_hash)), '');
  if v_hash is null then
    raise exception 'TX_HASH_REQUIRED';
  end if;

  if exists (
    select 1
    from public.transactions
    where related_id = p_deposit_id
      and type = 'deposit'
      and direction = 'credit'
  ) then
    raise exception 'DEPOSIT_ALREADY_CREDITED';
  end if;

  perform public.apply_balance_change(
    v_deposit.account_id,
    v_deposit.amount_fiat,
    v_deposit.currency
  );

  begin
    update public.crypto_deposits
    set status = 'completed',
        tx_hash = v_hash,
        admin_note = p_reason,
        verified_by = v_admin.id,
        verified_at = now(),
        completed_at = now(),
        updated_at = now()
    where id = p_deposit_id
    returning * into v_deposit;
  exception when unique_violation then
    raise exception 'DUPLICATE_TX_HASH';
  end;

  begin
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
  exception when unique_violation then
    raise exception 'DEPOSIT_ALREADY_CREDITED';
  end;

  perform public.notify_user(
    v_deposit.user_id,
    'Deposit Approved',
    'Your crypto deposit of ' || coalesce(v_deposit.amount_crypto, v_deposit.amount) ||
    ' ' || v_deposit.asset || ' has been approved and credited to your account. Ref: ' ||
    v_deposit.reference || '.',
    'deposit'
  );

  perform public.log_audit(
    p_token, 'APPROVE_DEPOSIT', 'crypto_deposit', p_deposit_id::text,
    to_jsonb(v_deposit), jsonb_build_object('status', 'completed', 'tx_hash', v_hash)
  );

  return jsonb_build_object('status', 'approved', 'reference', v_deposit.reference);
end;
$$;

grant execute on function public.admin_verify_crypto_deposit(text, uuid, text, text, text) to anon, authenticated;

create or replace function public.admin_update_deposit_status(
  p_token      text,
  p_deposit_id uuid,
  p_status     text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_deposit public.deposits%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;

  if v_status not in ('pending', 'processing', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected') then
    raise exception 'INVALID_STATUS';
  end if;

  select * into v_deposit
  from public.deposits
  where id = p_deposit_id
  for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;

  if v_deposit.status = v_status then
    return;
  end if;

  v_admin := public.admin_from_token(p_token);

  if v_status = 'completed' then
    if v_deposit.status not in ('pending', 'processing', 'pending_verification') then
      raise exception 'INVALID_STATUS_TRANSITION';
    end if;

    if exists (
      select 1
      from public.transactions
      where related_id = p_deposit_id
        and type = 'deposit'
        and direction = 'credit'
    ) then
      raise exception 'DEPOSIT_ALREADY_CREDITED';
    end if;

    perform public.apply_balance_change(v_deposit.account_id, v_deposit.amount, v_deposit.currency);

    begin
      perform public.record_transaction(
        v_deposit.user_id,
        v_deposit.account_id,
        'deposit',
        'credit',
        v_deposit.amount,
        v_deposit.currency,
        'completed',
        'Deposit ' || v_deposit.reference,
        v_deposit.user_id::text,
        v_deposit.user_id::text,
        0,
        v_deposit.id
      );
    exception when unique_violation then
      raise exception 'DEPOSIT_ALREADY_CREDITED';
    end;

    update public.deposits
    set status = v_status,
        verified_by = v_admin.id,
        verified_at = now(),
        updated_at = now()
    where id = p_deposit_id;

    perform public.notify_user(
      v_deposit.user_id,
      'Deposit completed',
      'Your deposit of ' || v_deposit.amount || ' ' || v_deposit.currency ||
      ' has been credited to your account. Ref: ' || v_deposit.reference || '.',
      'deposit'
    );
  else
    if v_deposit.status = 'completed' then
      raise exception 'INVALID_STATUS_TRANSITION';
    end if;

    update public.deposits
    set status = v_status,
        verified_by = case when v_status = 'rejected' then v_admin.id else verified_by end,
        verified_at = case when v_status = 'rejected' then now() else verified_at end,
        updated_at = now()
    where id = p_deposit_id;

    if v_status = 'rejected' then
      perform public.notify_user(
        v_deposit.user_id,
        'Deposit rejected',
        'Your deposit request was rejected. Ref: ' || v_deposit.reference || '.',
        'deposit'
      );
    end if;
  end if;

  perform public.log_audit(
    p_token,
    'UPDATE_STATUS',
    'deposit',
    p_deposit_id::text,
    to_jsonb(v_deposit),
    jsonb_build_object('status', v_status)
  );
end;
$$;

grant execute on function public.admin_update_deposit_status(text, uuid, text) to anon, authenticated;
