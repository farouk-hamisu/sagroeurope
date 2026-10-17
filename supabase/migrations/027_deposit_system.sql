-- Migration: Deposit System Overhaul
-- Adds support for multi-method deposits, crypto deposits, and admin verification

-- 1. Update deposits table with new statuses and fields
alter table public.deposits drop constraint if exists deposits_status_check;
alter table public.deposits
  add constraint deposits_status_check check (status in (
    'pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'
  ));

-- Add new columns for payment method tracking
alter table public.deposits add column if not exists payment_method text;
alter table public.deposits add column if not exists payment_details jsonb;
alter table public.deposits add column if not exists proof_image_url text;
alter table public.deposits add column if not exists verified_by uuid references public.admin_users(id);
alter table public.deposits add column if not exists verified_at timestamptz;

-- 2. Create crypto deposits table for USDT/BTC deposits
create table if not exists public.crypto_deposits (
    id              uuid primary key default gen_random_uuid(),
    reference       text not null unique,
    user_id         uuid not null references public.profiles (id) on delete cascade,
    account_id      uuid not null references public.accounts (id),
    asset           text not null,  -- 'USDT', 'BTC'
    network         text,           -- 'trc20', 'erc20', 'bitcoin'
    address         text not null,  -- deposit address
    amount          numeric(20, 8) not null check (amount > 0),
    amount_fiat     numeric(20, 2) not null,  -- fiat equivalent
    currency        text not null references public.currencies (code),
    rate_usd        numeric(20, 8) not null default 1,
    fee             numeric(20, 2) not null default 0,
    status          text not null default 'pending' check (status in (
                      'pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'
                    )),
    proof_image_url text,
    tx_hash         text,
    network         text,
    address         text,  -- deposit address
    amount_crypto   numeric(20, 8),
    amount_fiat     numeric(20, 2),
    fee             numeric(20, 2) not null default 0,
    completed_at    timestamptz,
    verified_by     uuid references public.admin_users(id),
    verified_at     timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index if not exists idx_crypto_deposits_user on public.crypto_deposits (user_id);
create index if not exists idx_crypto_deposits_status on public.crypto_deposits (status);
create index if not exists idx_crypto_deposits_reference on public.crypto_deposits (reference);

alter table public.crypto_deposits enable row level security;
create policy "crypto_deposits_select_own" on public.crypto_deposits
  for select using (auth.uid() = user_id);
create policy "crypto_deposits_insert_own" on public.crypto_deposits
  for insert with check (auth.uid() = user_id);

create trigger touch_crypto_deposits_updated before update on public.crypto_deposits
  for each row execute procedure public.touch_updated_at();

-- 3. Admin verification for crypto deposits
create or replace function public.admin_verify_crypto_deposit(
  p_token text,
  p_deposit_id uuid,
  p_action text,  -- 'approve' or 'reject'
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
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_amount_fiat numeric;
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

  if p_action = 'reject' then
    update public.crypto_deposits set status = 'rejected', updated_at = now() where id = p_deposit_id;
    perform public.notify_user(v_deposit.user_id, 'Deposit Rejected',
      'Your crypto deposit was rejected.' || case when p_reason is not null then ' Reason: ' || p_reason else '' end, 'deposit');
    perform public.log_audit(null, 'REJECT_DEPOSIT', 'crypto_deposit', p_deposit_id::text, to_jsonb(v_deposit),
      jsonb_build_object('reason', p_reason));
    return jsonb_build_object('status', 'rejected');
  end if;

  -- Approve: credit the user's account
  select * into v_account from public.accounts
    where user_id = v_deposit.user_id and currency = v_deposit.currency
    order by created_at limit 1;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;

  -- Credit the account
  perform public.apply_balance_change(v_deposit.account_id, v_deposit.amount_fiat, v_deposit.currency);

  -- Update deposit status
  update public.crypto_deposits
  set status = 'completed', verified_by = (select admin_id from public.admin_users where admin_email = current_setting('request.jwt.claims', true)::json->>'email'), verified_at = now(), updated_at = now()
  where id = p_deposit_id;

  -- Record transaction
  select full_name into v_name from public.profiles where id = (select user_id from public.crypto_deposits where id = p_deposit_id);
  perform public.record_transaction(
    (select user_id from public.crypto_deposits where id = p_deposit_id),
    (select account_id from public.crypto_deposits where id = p_deposit_id),
    'deposit', 'credit', v_amount_fiat, v_deposit.currency,
    'completed', 'Crypto deposit ' || v_asset || ' ' || v_network,
    (select full_name from public.profiles where id = (select user_id from public.crypto_deposits where id = p_deposit_id)),
    'Crypto Deposit', 0, p_deposit_id
  );

  perform public.notify_user((select user_id from public.crypto_deposits where id = p_deposit_id),
    'Deposit Approved',
    'Your crypto deposit of ' || to_char(v_deposit.amount_crypto, 'FM9,999,999,990.00') || ' ' || v_deposit.asset ||
    ' has been approved and credited to your account. Ref: ' || v_reference, 'deposit');

  return jsonb_build_object('status', 'approved', 'reference', v_reference);
end;
$$;

grant execute on function public.admin_verify_crypto_deposit(text, uuid, text, text) to anon, authenticated;

-- Grant for admin deposit listing
grant execute on function public.admin_list_deposits(text, text, int, int) to anon, authenticated;
