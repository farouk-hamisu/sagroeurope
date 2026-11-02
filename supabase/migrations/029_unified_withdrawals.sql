-- Migration 029: Unified Withdrawals System
-- Combines local and international transfers into unified withdrawals table
-- Adds support for multiple withdrawal methods with dynamic forms

-- 1. Create unified withdrawals table
create table if not exists public.withdrawals (
    id                      uuid primary key default gen_random_uuid(),
    reference               text not null unique,
    user_id                 uuid not null references public.profiles (id) on delete cascade,
    from_account_id         uuid not null references public.accounts (id),
    withdrawal_type         text not null check (withdrawal_type in (
        'local', 'international', 'crypto_usdt', 'crypto_btc', 
        'paypal', 'cashapp', 'wire', 'wise', 'payoneer', 'skrill', 'stripe'
    )),
    status                  text not null default 'pending' check (status in (
        'pending', 'pending_otp', 'pending_approval', 'processing', 'completed', 
        'failed', 'cancelled', 'rejected', 'reversed'
    )),
    -- Common fields
    amount                  numeric(20, 2) not null check (amount > 0),
    currency                text not null references public.currencies (code),
    fee                     numeric(20, 2) not null default 0,
    fee_currency            text not null references public.currencies (code) default 'USD',
    description             text,
    -- Sender info
    from_account_id         uuid not null references public.accounts (id),
    -- Recipient details (varies by method)
    recipient_name          text,
    recipient_email         text,
    recipient_account       text,
    recipient_bank          text,
    recipient_bank_address  text,
    recipient_iban          text,
    recipient_swift         text,
    recipient_country       text,
    -- Crypto specific
    crypto_asset            text, -- 'USDT', 'BTC'
    crypto_network          text, -- 'trc20', 'erc20', 'bitcoin'
    crypto_address          text,
    crypto_amount           numeric(20, 8),
    crypto_network          text,
    -- Bank wire specific
    bank_name               text,
    bank_address            text,
    bank_swift              text,
    bank_iban               text,
    bank_account_number     text,
    bank_routing            text,
    beneficiary_name        text,
    beneficiary_address     text,
    -- Wise specific
    wise_recipient_id       text,
    -- PayPal specific
    paypal_email            text,
    -- Cash App specific
    cashapp_tag             text,
    -- Wise specific
    wise_recipient_id       text,
    -- Payoneer specific
    payoneer_email          text,
    -- Skrill specific
    skrill_email            text,
    -- Stripe specific
    stripe_destination_id   text,
    -- Status and tracking
    status                  text not null default 'pending' check (status in (
        'pending', 'pending_otp', 'pending_approval', 'processing', 
        'completed', 'failed', 'cancelled', 'rejected', 'reversed'
    )),
    fee                     numeric(20, 2) not null default 0,
    fee_currency            text not null references public.currencies (code) default 'USD',
    description             text,
    reference               text not null unique,
    otp_required            boolean not null default false,
    otp_verified            boolean not null default false,
    otp_code                text,
    otp_expires_at          timestamptz,
    from_account_id         uuid not null references public.accounts (id),
    from_account_name       text,
    from_account_number     text,
    from_account_currency   text not null references public.currencies (code),
    amount                  numeric(20, 2) not null check (amount > 0),
    currency                text not null references public.currencies (code),
    fee_amount              numeric(20, 2) not null default 0,
    fee_currency            text not null references public.currencies (code) default 'USD',
    description             text,
    status                  text not null default 'pending' check (status in (
        'pending', 'pending_otp', 'pending_approval', 'processing', 
        'completed', 'failed', 'cancelled', 'rejected', 'reversed'
    )),
    completed_at            timestamptz,
    cancelled_at            timestamptz,
    failure_reason          text,
    admin_notes             text,
    created_by              uuid references public.profiles (id),
    approved_by             uuid references public.admin_users (id),
    approved_at             timestamptz,
    rejected_at             timestamptz,
    rejection_reason        text,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

-- Create indexes
create index if not exists idx_withdrawals_user on public.withdrawals (user_id);
create index if not exists idx_withdrawals_status on public.withdrawals (status);
create index if not exists idx_withdrawals_type on public.withdrawals (withdrawal_type);
create index if not exists idx_withdrawals_reference on public.withdrawals (reference);
create index if not exists idx_withdrawals_user_status on public.withdrawals (user_id, status);
create index if not exists idx_withdrawals_created on public.withdrawals (created_at desc);

-- Enable RLS
alter table public.withdrawals enable row level security;

-- Users can only see their own withdrawals
create policy "withdrawals_select_own" on public.withdrawals
  for select using (auth.uid() = user_id);

-- Users can insert their own withdrawals
create policy "withdrawals_insert_own" on public.withdrawals
  for insert with check (auth.uid() = user_id);

-- Users can update their own pending/cancelled withdrawals
create policy "withdrawals_update_own" on public.withdrawals
  for update using (auth.uid() = user_id and status in ('pending', 'cancelled'));

-- Admin can do everything
create policy "withdrawals_admin_all" on public.withdrawals
  for all using (
    exists (
      select 1 from public.admin_users au 
      where au.id = auth.uid() and au.status = 'active'
    )
  );

-- Trigger for updated_at
create trigger touch_withdrawals_updated
  before update on public.withdrawals
  for each row execute procedure public.touch_updated_at();

-- Add withdrawal settings to system_settings
insert into public.system_settings (key, value, description) values
  ('withdrawal_otp_required', 'true', 'Require OTP for all withdrawals'),
  ('withdrawal_local_limit', '10000', 'Maximum amount for local withdrawals without additional verification'),
  ('withdrawal_intl_limit', '5000', 'Maximum amount for international transfers without additional verification'),
  ('withdrawal_crypto_limit', '5000', 'Maximum amount for crypto withdrawals without additional verification'),
  ('withdrawal_daily_limit', '20000', 'Daily withdrawal limit per user'),
  ('withdrawal_monthly_limit', '100000', 'Monthly withdrawal limit per user')
on conflict (key) do nothing;

-- Grant permissions
grant select, insert, update on public.withdrawals to anon, authenticated;
EOF
echo "Created migration 029_unified_withdrawals.sql"