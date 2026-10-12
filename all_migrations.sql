-- marvintlc - Migration 001
-- Enable required extensions

create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";-- marvintlc - Migration 002
-- Core database schema

-- ---------------------------------------------------------------------------
-- PROFILES
-- ---------------------------------------------------------------------------
create table public.profiles (
    id            uuid primary key references auth.users (id) on delete cascade,
    email         text not null,
    full_name     text not null default '',
    phone         text,
    avatar_url    text,
    date_of_birth date,
    address       text,
    city          text,
    country       text,
    status        text not null default 'active'
                  check (status in ('pending', 'active', 'suspended', 'closed')),
    kyc_status    text not null default 'pending'
                  check (kyc_status in ('pending', 'verified', 'rejected')),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- CURRENCIES
-- ---------------------------------------------------------------------------
create table public.currencies (
    id          uuid primary key default gen_random_uuid(),
    code        text not null unique,
    name        text not null,
    symbol      text not null default '$',
    is_base     boolean not null default false,
    enabled     boolean not null default true,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- EXCHANGE RATES
-- ---------------------------------------------------------------------------
create table public.exchange_rates (
    id               uuid primary key default gen_random_uuid(),
    base_currency    text not null references public.currencies (code),
    quote_currency   text not null references public.currencies (code),
    rate             numeric(20, 8) not null check (rate > 0),
    fee_percent      numeric(10, 4) not null default 0,
    updated_by       uuid references public.profiles (id),
    updated_at       timestamptz not null default now(),
    unique (base_currency, quote_currency)
);

-- ---------------------------------------------------------------------------
-- ACCOUNTS
-- ---------------------------------------------------------------------------
create table public.accounts (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null references public.profiles (id) on delete cascade,
    account_number text not null unique,
    account_name   text not null,
    account_type   text not null default 'checking'
                   check (account_type in ('checking', 'savings')),
    currency       text not null default 'USD' references public.currencies (code),
    status         text not null default 'active'
                   check (status in ('active', 'inactive', 'suspended', 'closed')),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- ACCOUNT BALANCES
-- ---------------------------------------------------------------------------
create table public.account_balances (
    id               uuid primary key default gen_random_uuid(),
    account_id       uuid not null references public.accounts (id) on delete cascade,
    available_balance numeric(20, 2) not null default 0 check (available_balance >= 0),
    ledger_balance   numeric(20, 2) not null default 0,
    currency         text not null references public.currencies (code),
    updated_at       timestamptz not null default now(),
    unique (account_id)
);

-- ---------------------------------------------------------------------------
-- TRANSACTIONS
-- ---------------------------------------------------------------------------
create table public.transactions (
    id          uuid primary key default gen_random_uuid(),
    reference   text not null unique,
    user_id     uuid not null references public.profiles (id) on delete cascade,
    account_id  uuid references public.accounts (id),
    type        text not null check (type in (
                  'deposit', 'withdrawal', 'local_transfer', 'international_transfer',
                  'currency_swap', 'loan_disbursement', 'loan_repayment',
                  'fee', 'interest', 'reversal', 'adjustment'
                )),
    direction   text not null check (direction in ('credit', 'debit')),
    amount      numeric(20, 2) not null check (amount > 0),
    currency    text not null references public.currencies (code),
    fee         numeric(20, 2) not null default 0,
    status      text not null default 'pending' check (status in (
                  'pending', 'processing', 'completed', 'failed', 'cancelled', 'reversed'
                )),
    description text,
    sender      text,
    recipient   text,
    related_id  uuid,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- BENEFICIARIES
-- ---------------------------------------------------------------------------
create table public.beneficiaries (
    id                     uuid primary key default gen_random_uuid(),
    user_id                uuid not null references public.profiles (id) on delete cascade,
    name                   text not null,
    bank_name              text,
    account_number         text not null,
    swift_code             text,
    country                text,
    currency               text default 'USD' references public.currencies (code),
    is_international       boolean not null default false,
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- LOCAL TRANSFERS
-- ---------------------------------------------------------------------------
create table public.local_transfers (
    id                      uuid primary key default gen_random_uuid(),
    reference               text not null unique,
    user_id                 uuid not null references public.profiles (id) on delete cascade,
    from_account_id         uuid not null references public.accounts (id),
    beneficiary_id          uuid references public.beneficiaries (id),
    recipient_name          text not null,
    recipient_account_number text not null,
    recipient_bank          text,
    amount                  numeric(20, 2) not null check (amount > 0),
    currency                text not null references public.currencies (code),
    fee                     numeric(20, 2) not null default 0,
    description             text,
    status                  text not null default 'pending' check (status in (
                              'pending', 'processing', 'completed', 'failed', 'cancelled', 'reversed'
                            )),
    completed_at            timestamptz,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- INTERNATIONAL TRANSFERS
-- ---------------------------------------------------------------------------
create table public.international_transfers (
    id                       uuid primary key default gen_random_uuid(),
    reference                text not null unique,
    user_id                  uuid not null references public.profiles (id) on delete cascade,
    from_account_id          uuid not null references public.accounts (id),
    beneficiary_id           uuid references public.beneficiaries (id),
    recipient_name           text not null,
    recipient_bank           text not null,
    recipient_account_number text not null,
    swift_code               text,
    recipient_country        text not null,
    purpose                  text,
    amount                   numeric(20, 2) not null check (amount > 0),
    currency                 text not null references public.currencies (code),
    exchange_rate            numeric(20, 8) not null default 1,
    fee                      numeric(20, 2) not null default 0,
    estimated_delivery       timestamptz,
    status                   text not null default 'pending' check (status in (
                                'pending', 'processing', 'completed', 'failed', 'cancelled', 'reversed'
                              )),
    completed_at             timestamptz,
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- CARDS
-- ---------------------------------------------------------------------------
create table public.cards (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references public.profiles (id) on delete cascade,
    account_id      uuid references public.accounts (id),
    card_number     text not null unique,
    masked_number   text not null,
    card_holder     text not null,
    card_type       text not null default 'debit' check (card_type in ('debit', 'credit', 'virtual')),
    card_brand      text not null default 'visa' check (card_brand in ('visa', 'mastercard')),
    expiry_month    int not null check (expiry_month between 1 and 12),
    expiry_year     int not null,
    cvv             text not null,
    spending_limit  numeric(20, 2) not null default 10000,
    status          text not null default 'active' check (status in ('active', 'frozen', 'blocked', 'expired')),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- CARD TRANSACTIONS
-- ---------------------------------------------------------------------------
create table public.card_transactions (
    id            uuid primary key default gen_random_uuid(),
    card_id       uuid not null references public.cards (id) on delete cascade,
    user_id       uuid not null references public.profiles (id) on delete cascade,
    merchant      text not null,
    amount        numeric(20, 2) not null check (amount > 0),
    currency      text not null references public.currencies (code),
    type          text not null default 'purchase' check (type in ('purchase', 'atm', 'refund', 'online')),
    status        text not null default 'completed' check (status in ('pending', 'completed', 'failed', 'reversed')),
    created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- DEPOSITS
-- ---------------------------------------------------------------------------
create table public.deposits (
    id          uuid primary key default gen_random_uuid(),
    reference   text not null unique,
    user_id     uuid not null references public.profiles (id) on delete cascade,
    account_id  uuid not null references public.accounts (id),
    amount      numeric(20, 2) not null check (amount > 0),
    currency    text not null references public.currencies (code),
    method      text not null check (method in ('cash', 'bank_transfer', 'cheque', 'card', 'online')),
    note        text,
    status      text not null default 'pending' check (status in (
                  'pending', 'processing', 'completed', 'failed', 'rejected'
                )),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- CURRENCY SWAPS
-- ---------------------------------------------------------------------------
create table public.currency_swaps (
    id            uuid primary key default gen_random_uuid(),
    reference     text not null unique,
    user_id       uuid not null references public.profiles (id) on delete cascade,
    account_id    uuid references public.accounts (id),
    from_currency text not null references public.currencies (code),
    to_currency   text not null references public.currencies (code),
    from_amount   numeric(20, 2) not null check (from_amount > 0),
    to_amount     numeric(20, 2) not null check (to_amount > 0),
    rate          numeric(20, 8) not null,
    fee           numeric(20, 2) not null default 0,
    status        text not null default 'completed' check (status in (
                    'pending', 'processing', 'completed', 'failed', 'cancelled'
                  )),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- LOAN PRODUCTS
-- ---------------------------------------------------------------------------
create table public.loan_products (
    id            uuid primary key default gen_random_uuid(),
    name          text not null,
    description   text,
    min_amount    numeric(20, 2) not null default 500,
    max_amount    numeric(20, 2) not null default 100000,
    interest_rate numeric(10, 4) not null default 5,
    term_months   int not null default 12 check (term_months > 0),
    enabled       boolean not null default true,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- LOAN APPLICATIONS
-- ---------------------------------------------------------------------------
create table public.loan_applications (
    id              uuid primary key default gen_random_uuid(),
    reference       text not null unique,
    user_id         uuid not null references public.profiles (id) on delete cascade,
    product_id      uuid not null references public.loan_products (id),
    amount          numeric(20, 2) not null check (amount > 0),
    currency        text not null default 'USD' references public.currencies (code),
    term_months     int not null,
    interest_rate   numeric(10, 4) not null,
    monthly_payment numeric(20, 2) not null default 0,
    purpose         text,
    status          text not null default 'pending' check (status in (
                      'pending', 'under_review', 'approved', 'rejected', 'active', 'completed', 'cancelled'
                    )),
    admin_note      text,
    disbursed_at    timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- LOAN REPAYMENTS
-- ---------------------------------------------------------------------------
create table public.loan_repayments (
    id                  uuid primary key default gen_random_uuid(),
    loan_application_id uuid not null references public.loan_applications (id) on delete cascade,
    user_id             uuid not null references public.profiles (id) on delete cascade,
    account_id          uuid references public.accounts (id),
    amount              numeric(20, 2) not null check (amount > 0),
    currency            text not null references public.currencies (code),
    due_date            date not null,
    paid_at             timestamptz,
    status              text not null default 'scheduled' check (status in ('scheduled', 'paid', 'overdue', 'skipped')),
    reference           text,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
create table public.notifications (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid references public.profiles (id) on delete cascade,
    title       text not null,
    message     text not null,
    type        text not null default 'system' check (type in (
                  'transfer', 'deposit', 'loan', 'card', 'swap', 'security', 'account', 'system'
                )),
    is_read     boolean not null default false,
    is_global   boolean not null default false,
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- ADMIN ROLES
-- ---------------------------------------------------------------------------
create table public.admin_roles (
    id          uuid primary key default gen_random_uuid(),
    name        text not null unique,
    permissions text[] not null default '{}',
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- ADMIN USERS
-- ---------------------------------------------------------------------------
create table public.admin_users (
    id            uuid primary key default gen_random_uuid(),
    email         text not null unique,
    password_hash text not null,
    full_name     text not null default '',
    role_id       uuid references public.admin_roles (id),
    status        text not null default 'active' check (status in ('active', 'suspended')),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- ADMIN SESSIONS
-- ---------------------------------------------------------------------------
create table public.admin_sessions (
    id         uuid primary key default gen_random_uuid(),
    admin_id   uuid not null references public.admin_users (id) on delete cascade,
    token      text not null unique,
    ip_address text,
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- AUDIT LOGS
-- ---------------------------------------------------------------------------
create table public.audit_logs (
    id              uuid primary key default gen_random_uuid(),
    admin_id        uuid references public.admin_users (id) on delete set null,
    admin_email     text,
    action          text not null,
    resource        text not null,
    resource_id     text,
    previous_value  jsonb,
    new_value       jsonb,
    ip_address      text,
    created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- SYSTEM SETTINGS
-- ---------------------------------------------------------------------------
create table public.system_settings (
    id          uuid primary key default gen_random_uuid(),
    key         text not null unique,
    value       jsonb not null,
    description text,
    updated_at  timestamptz not null default now()
);-- marvintlc - Migration 003
-- Indexes for frequently queried fields

create index if not exists idx_profiles_email      on public.profiles (email);
create index if not exists idx_profiles_status     on public.profiles (status);

create index if not exists idx_accounts_user_id    on public.accounts (user_id);
create index if not exists idx_accounts_status     on public.accounts (status);
create index if not exists idx_accounts_currency   on public.accounts (currency);

create index if not exists idx_balances_account    on public.account_balances (account_id);

create index if not exists idx_tx_user_id          on public.transactions (user_id);
create index if not exists idx_tx_account_id       on public.transactions (account_id);
create index if not exists idx_tx_status           on public.transactions (status);
create index if not exists idx_tx_created_at       on public.transactions (created_at desc);
create index if not exists idx_tx_type             on public.transactions (type);

create index if not exists idx_benef_user_id       on public.beneficiaries (user_id);

create index if not exists idx_local_tx_user       on public.local_transfers (user_id);
create index if not exists idx_local_tx_status     on public.local_transfers (status);

create index if not exists idx_intl_tx_user        on public.international_transfers (user_id);
create index if not exists idx_intl_tx_status      on public.international_transfers (status);

create index if not exists idx_cards_user_id       on public.cards (user_id);
create index if not exists idx_cards_status        on public.cards (status);
create index if not exists idx_cards_account       on public.cards (account_id);

create index if not exists idx_card_tx_card        on public.card_transactions (card_id);
create index if not exists idx_card_tx_user        on public.card_transactions (user_id);

create index if not exists idx_deposits_user       on public.deposits (user_id);
create index if not exists idx_deposits_status     on public.deposits (status);

create index if not exists idx_swaps_user          on public.currency_swaps (user_id);
create index if not exists idx_swaps_created       on public.currency_swaps (created_at desc);

create index if not exists idx_loans_user          on public.loan_applications (user_id);
create index if not exists idx_loans_status        on public.loan_applications (status);
create index if not exists idx_loans_product       on public.loan_applications (product_id);

create index if not exists idx_repay_loan          on public.loan_repayments (loan_application_id);
create index if not exists idx_repay_status        on public.loan_repayments (status);

create index if not exists idx_notif_user          on public.notifications (user_id);
create index if not exists idx_notif_read          on public.notifications (is_read);

create index if not exists idx_audit_admin         on public.audit_logs (admin_id);
create index if not exists idx_audit_created       on public.audit_logs (created_at desc);
create index if not exists idx_audit_resource      on public.audit_logs (resource);-- marvintlc - Migration 004
-- Helper + financial functions (atomic financial operations)

-- ---------------------------------------------------------------------------
-- Generate a unique bank reference
-- ---------------------------------------------------------------------------
create or replace function public.generate_reference(prefix text)
returns text
language sql
volatile
as $$
  select upper(prefix || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
$$;

-- ---------------------------------------------------------------------------
-- Updated-at trigger helper
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Create a notification
-- ---------------------------------------------------------------------------
create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, title, message, type)
  values (p_user_id, p_title, p_message, p_type);
end;
$$;

-- ---------------------------------------------------------------------------
-- On new auth user -> create profile
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Credit / debit an account balance (internal)
-- ---------------------------------------------------------------------------
create or replace function public.apply_balance_change(
  p_account_id uuid,
  p_delta numeric,
  p_currency text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
begin
  select * into v_account from public.accounts where id = p_account_id for update;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;
  if v_account.currency <> p_currency then
    raise exception 'CURRENCY_MISMATCH';
  end if;

  insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
  values (p_account_id, p_delta, p_delta, p_currency)
  on conflict (account_id) do update
    set available_balance = account_balances.available_balance + p_delta,
        ledger_balance     = account_balances.ledger_balance + p_delta,
        updated_at         = now();

  if (select available_balance from public.account_balances where account_id = p_account_id) < 0 then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Create a transaction record (internal)
-- ---------------------------------------------------------------------------
create or replace function public.record_transaction(
  p_user_id uuid,
  p_account_id uuid,
  p_type text,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_status text,
  p_description text,
  p_sender text,
  p_recipient text,
  p_fee numeric default 0,
  p_related_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx public.transactions;
begin
  insert into public.transactions (
    reference, user_id, account_id, type, direction, amount, currency, status,
    description, sender, recipient, fee, related_id
  ) values (
    public.generate_reference('NTB'), p_user_id, p_account_id, p_type, p_direction,
    p_amount, p_currency, p_status, p_description, p_sender, p_recipient, p_fee, p_related_id
  )
  returning * into v_tx;
  return v_tx;
end;
$$;

-- ---------------------------------------------------------------------------
-- LOCAL TRANSFER (atomic)
--   Validate user/account/balance, debit, create transfer + transaction,
--   optionally credit the recipient's internal account, notify, and return reference.
-- ---------------------------------------------------------------------------
create or replace function public.create_local_transfer(
  p_user_id uuid,
  p_from_account_id uuid,
  p_recipient_name text,
  p_recipient_account_number text,
  p_recipient_bank text,
  p_amount numeric,
  p_currency text,
  p_description text,
  p_internal_recipient uuid default null
)
returns public.local_transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_transfer public.local_transfers;
  v_sender_name text;
begin
  -- Validate user owns account
  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances
    where account_id = p_from_account_id;
  if v_balance is null or v_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select full_name into v_sender_name from public.profiles where id = p_user_id;

  v_fee := 0;

  -- Debit source account (amount)
  perform public.apply_balance_change(p_from_account_id, -p_amount, p_currency);

  -- Create transfer record (status completed for demo/internal transfers)
  insert into public.local_transfers (
    reference, user_id, from_account_id, recipient_name, recipient_account_number,
    recipient_bank, amount, currency, fee, description, status, completed_at
  ) values (
    public.generate_reference('LT'), p_user_id, p_from_account_id, p_recipient_name,
    p_recipient_account_number, p_recipient_bank, p_amount, p_currency, v_fee,
    p_description, 'completed', now()
  ) returning * into v_transfer;

  -- Record debit transaction
  perform public.record_transaction(
    p_user_id, p_from_account_id, 'local_transfer', 'debit', p_amount, p_currency,
    'completed', coalesce(p_description, 'Local transfer'),
    v_sender_name, p_recipient_name, v_fee, v_transfer.id
  );

  -- If internal recipient, credit them
  if p_internal_recipient is not null then
    declare
      v_dest public.accounts%rowtype;
    begin
      select * into v_dest from public.accounts
        where user_id = p_internal_recipient and currency = p_currency
        order by created_at limit 1;
      if found then
        perform public.apply_balance_change(v_dest.id, p_amount, p_currency);
        perform public.record_transaction(
          p_internal_recipient, v_dest.id, 'local_transfer', 'credit', p_amount, p_currency,
          'completed', 'Incoming local transfer', p_recipient_name, v_sender_name, 0, v_transfer.id
        );
        perform public.notify_user(p_internal_recipient,
          'Transfer received',
          'You received ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
          ' from ' || coalesce(v_sender_name, 'a customer') || '.',
          'transfer');
      end if;
    end;
  end if;

  perform public.notify_user(p_user_id,
    'Transfer completed',
    'Your transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' to ' || p_recipient_name || ' was completed. Ref: ' || v_transfer.reference || '.',
    'transfer');

  return v_transfer;
end;
$$;

-- ---------------------------------------------------------------------------
-- CURRENCY SWAP (atomic)
--   Fetch live rate, compute fees, debit source, credit destination (in USD accounts
--   this is represented as a debit transaction of the source and a credit transaction
--   of the converted amount where possible).
-- ---------------------------------------------------------------------------
create or replace function public.create_currency_swap(
  p_user_id uuid,
  p_account_id uuid,
  p_from_currency text,
  p_to_currency text,
  p_from_amount numeric
)
returns public.currency_swaps
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
begin
  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if p_from_currency = p_to_currency then
    raise exception 'SAME_CURRENCY';
  end if;

  select rate, fee_percent into v_rate, v_fee_pct
    from public.exchange_rates
    where base_currency = p_from_currency and quote_currency = p_to_currency;
  if not found then
    raise exception 'RATE_NOT_AVAILABLE';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_account_id;
  if v_balance is null or v_balance < p_from_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);
  v_to_amount := round((p_from_amount - v_fee) * v_rate, 2);

  select full_name into v_name from public.profiles where id = p_user_id;

  -- Debit the from amount + fee from source account
  perform public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  insert into public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) values (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) returning * into v_swap;

  perform public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  perform public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00') || ' ' || p_to_currency || '.',
    'swap');

  -- Credit a matching destination account if the customer holds one
  declare
    v_dest public.accounts%rowtype;
  begin
    select * into v_dest from public.accounts
      where user_id = p_user_id and currency = p_to_currency and status = 'active'
      order by created_at limit 1;
    if found then
      perform public.apply_balance_change(v_dest.id, v_to_amount, p_to_currency);
      perform public.record_transaction(
        p_user_id, v_dest.id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
        'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
        p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
      );
    end if;
  end;

  return v_swap;
end;
$$;

-- ---------------------------------------------------------------------------
-- LOAN REPAYMENT (atomic)
-- ---------------------------------------------------------------------------
create or replace function public.pay_loan_repayment(
  p_user_id uuid,
  p_repayment_id uuid,
  p_account_id uuid
)
returns public.loan_repayments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_repayment public.loan_repayments%rowtype;
  v_account public.accounts%rowtype;
  v_balance numeric;
begin
  select * into v_repayment from public.loan_repayments
    where id = p_repayment_id and user_id = p_user_id and status = 'scheduled' for update;
  if not found then
    raise exception 'REPAYMENT_NOT_FOUND';
  end if;

  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_account_id;
  if v_balance is null or v_balance < v_repayment.amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  perform public.apply_balance_change(p_account_id, -v_repayment.amount, v_repayment.currency);

  update public.loan_repayments
    set status = 'paid', paid_at = now(), reference = public.generate_reference('RP'),
        account_id = p_account_id
    where id = v_repayment.id
    returning * into v_repayment;

  perform public.record_transaction(
    p_user_id, p_account_id, 'loan_repayment', 'debit', v_repayment.amount, v_repayment.currency,
    'completed', 'Loan repayment', 'marvintlc',
    coalesce((select name from public.loan_products lp
      join public.loan_applications la on la.product_id = lp.id
      where la.id = v_repayment.loan_application_id), 'Loan repayment'),
    0, v_repayment.loan_application_id
  );

  -- If all repayments are paid, mark loan completed
  update public.loan_applications set status = 'completed'
    where id = v_repayment.loan_application_id
      and not exists (
        select 1 from public.loan_repayments lr
        where lr.loan_application_id = v_repayment.loan_application_id and lr.status <> 'paid'
      );

  return v_repayment;
end;
$$;-- marvintlc - Migration 005
-- Row Level Security policies (customer data)

alter table public.profiles             enable row level security;
alter table public.accounts             enable row level security;
alter table public.account_balances     enable row level security;
alter table public.transactions         enable row level security;
alter table public.beneficiaries        enable row level security;
alter table public.local_transfers      enable row level security;
alter table public.international_transfers enable row level security;
alter table public.cards                enable row level security;
alter table public.card_transactions    enable row level security;
alter table public.deposits             enable row level security;
alter table public.currencies           enable row level security;
alter table public.exchange_rates       enable row level security;
alter table public.currency_swaps       enable row level security;
alter table public.loan_products        enable row level security;
alter table public.loan_applications    enable row level security;
alter table public.loan_repayments      enable row level security;
alter table public.notifications        enable row level security;
alter table public.admin_users          enable row level security;
alter table public.admin_roles          enable row level security;
alter table public.admin_sessions       enable row level security;
alter table public.audit_logs           enable row level security;
alter table public.system_settings      enable row level security;

-- ---------------------------------------------------------------------------
-- PROFILES : users manage their own
-- ---------------------------------------------------------------------------
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- ACCOUNTS : users manage their own
-- ---------------------------------------------------------------------------
create policy "accounts_select_own" on public.accounts
  for select using (auth.uid() = user_id);
create policy "accounts_insert_own" on public.accounts
  for insert with check (auth.uid() = user_id);
create policy "accounts_update_own" on public.accounts
  for update using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- ACCOUNT BALANCES : users manage their own (balances never written by client)
-- ---------------------------------------------------------------------------
create policy "balances_select_own" on public.account_balances
  for select using (
    exists (
      select 1 from public.accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- TRANSACTIONS
-- ---------------------------------------------------------------------------
create policy "transactions_select_own" on public.transactions
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- BENEFICIARIES
-- ---------------------------------------------------------------------------
create policy "benef_select_own" on public.beneficiaries
  for select using (auth.uid() = user_id);
create policy "benef_insert_own" on public.beneficiaries
  for insert with check (auth.uid() = user_id);
create policy "benef_update_own" on public.beneficiaries
  for update using (auth.uid() = user_id);
create policy "benef_delete_own" on public.beneficiaries
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- LOCAL / INTERNATIONAL TRANSFERS
-- ---------------------------------------------------------------------------
create policy "local_tx_select_own" on public.local_transfers
  for select using (auth.uid() = user_id);
create policy "local_tx_insert_own" on public.local_transfers
  for insert with check (auth.uid() = user_id);

create policy "intl_tx_select_own" on public.international_transfers
  for select using (auth.uid() = user_id);
create policy "intl_tx_insert_own" on public.international_transfers
  for insert with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- CARDS + CARD TRANSACTIONS
-- ---------------------------------------------------------------------------
create policy "cards_select_own" on public.cards
  for select using (auth.uid() = user_id);
create policy "cards_insert_own" on public.cards
  for insert with check (auth.uid() = user_id);
create policy "cards_update_own" on public.cards
  for update using (auth.uid() = user_id);

create policy "card_tx_select_own" on public.card_transactions
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- DEPOSITS
-- ---------------------------------------------------------------------------
create policy "deposits_select_own" on public.deposits
  for select using (auth.uid() = user_id);
create policy "deposits_insert_own" on public.deposits
  for insert with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- CURRENCIES + EXCHANGE RATES : public read-only
-- ---------------------------------------------------------------------------
create policy "currencies_select_public" on public.currencies
  for select using (true);
create policy "rates_select_public" on public.exchange_rates
  for select using (true);

-- ---------------------------------------------------------------------------
-- CURRENCY SWAPS
-- ---------------------------------------------------------------------------
create policy "swaps_select_own" on public.currency_swaps
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- LOAN PRODUCTS : public read-only
-- ---------------------------------------------------------------------------
create policy "loan_products_select" on public.loan_products
  for select using (enabled);

-- ---------------------------------------------------------------------------
-- LOAN APPLICATIONS / REPAYMENTS
-- ---------------------------------------------------------------------------
create policy "loan_apps_select_own" on public.loan_applications
  for select using (auth.uid() = user_id);
create policy "loan_apps_insert_own" on public.loan_applications
  for insert with check (auth.uid() = user_id);

create policy "repay_select_own" on public.loan_repayments
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
create policy "notif_select_own" on public.notifications
  for select using (auth.uid() = user_id or is_global);
create policy "notif_update_own" on public.notifications
  for update using (auth.uid() = user_id);
create policy "notif_delete_own" on public.notifications
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- ADMIN TABLES : no direct client access (admin flows through security definer fns)
-- ---------------------------------------------------------------------------
create policy "admin_users_no_access" on public.admin_users for all using (false);
create policy "admin_roles_no_access" on public.admin_roles for all using (false);
create policy "admin_sessions_no_access" on public.admin_sessions for all using (false);
create policy "audit_logs_no_access" on public.audit_logs for all using (false);
create policy "system_settings_no_access" on public.system_settings for all using (false);-- marvintlc - Migration 006
-- Admin authentication + CRUD via SECURITY DEFINER functions.
-- All functions validate the admin session token server-side; client-side checks are not trusted.

-- Ensure pgcrypto (crypt / gen_salt) is available even if run standalone.
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Verify a bearer token -> returns admin row or null
create or replace function public.admin_from_token(p_token text)
returns public.admin_users
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_session public.admin_sessions%rowtype;
  v_admin public.admin_users;
begin
  if p_token is null or p_token = '' then
    return null;
  end if;
  select * into v_session from public.admin_sessions
    where token = p_token and expires_at > now();
  if not found then
    return null;
  end if;
  select * into v_admin from public.admin_users
    where id = v_session.admin_id and status = 'active';
  return v_admin;
end;
$$;

-- Permission check
create or replace function public.admin_can(p_token text, p_perm text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_role public.admin_roles;
begin
  v_admin := public.admin_from_token(p_token);
  if v_admin is null then
    return false;
  end if;
  select * into v_role from public.admin_roles where id = v_admin.role_id;
  if not found then
    return false;
  end if;
  if v_role.name = 'super_admin' then
    return true;
  end if;
  return coalesce(p_perm = any (v_role.permissions), false);
end;
$$;

-- Internal audit logger
create or replace function public.log_audit(
  p_token text,
  p_action text,
  p_resource text,
  p_resource_id text default null,
  p_previous jsonb default null,
  p_new jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
begin
  v_admin := public.admin_from_token(p_token);
  insert into public.audit_logs (admin_id, admin_email, action, resource, resource_id, previous_value, new_value)
  values (
    coalesce(v_admin.id, null),
    coalesce(v_admin.email, 'unknown'),
    p_action, p_resource, p_resource_id, p_previous, p_new
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Auth
-- ---------------------------------------------------------------------------

create or replace function public.admin_login(p_email text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_token text;
  v_role text;
begin
  select * into v_admin from public.admin_users where lower(email) = lower(p_email) and status = 'active';
  if not found then
    raise exception 'INVALID_CREDENTIALS';
  end if;
  if v_admin.password_hash <> crypt(p_password, v_admin.password_hash) then
    raise exception 'INVALID_CREDENTIALS';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.admin_sessions (admin_id, token, expires_at)
  values (v_admin.id, v_token, now() + interval '12 hours');

  select r.name into v_role from public.admin_roles r where r.id = v_admin.role_id;
  return jsonb_build_object(
    'token', v_token,
    'admin', jsonb_build_object(
      'id', v_admin.id,
      'email', v_admin.email,
      'full_name', v_admin.full_name,
      'role', coalesce(v_role, 'admin')
    )
  );
end;
$$;

create or replace function public.admin_logout(p_token text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.admin_sessions where token = p_token;
end;
$$;

create or replace function public.admin_validate(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_role public.admin_roles;
begin
  v_admin := public.admin_from_token(p_token);
  if v_admin is null then
    raise exception 'UNAUTHORIZED';
  end if;
  select * into v_role from public.admin_roles where id = v_admin.role_id;
  return jsonb_build_object(
    'id', v_admin.id,
    'email', v_admin.email,
    'full_name', v_admin.full_name,
    'role', coalesce(v_role.name, 'admin'),
    'permissions', coalesce(v_role.permissions, '{}')
  );
end;
$$;

create or replace function public.admin_hash_password(p_password text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select crypt(p_password, gen_salt('bf', 10));
$$;

-- ---------------------------------------------------------------------------
-- DASHBOARD STATS
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_stats(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
begin
  if not public.admin_can(p_token, 'dashboard') then
    raise exception 'FORBIDDEN';
  end if;
  select jsonb_build_object(
    'total_customers', (select count(*) from public.profiles),
    'active_customers', (select count(*) from public.profiles where status = 'active'),
    'suspended_customers', (select count(*) from public.profiles where status = 'suspended'),
    'pending_customers', (select count(*) from public.profiles where status = 'pending'),
    'total_accounts', (select count(*) from public.accounts),
    'total_balances', coalesce((select sum(ledger_balance) from public.account_balances), 0),
    'total_transactions', (select count(*) from public.transactions),
    'pending_transactions', (select count(*) from public.transactions where status = 'pending'),
    'completed_transactions', (select count(*) from public.transactions where status = 'completed'),
    'failed_transactions', (select count(*) from public.transactions where status in ('failed', 'cancelled', 'reversed')),
    'total_deposits', (select count(*) from public.deposits),
    'pending_deposits', (select count(*) from public.deposits where status = 'pending'),
    'local_transfers', (select count(*) from public.local_transfers),
    'international_transfers', (select count(*) from public.international_transfers),
    'active_cards', (select count(*) from public.cards where status = 'active'),
    'frozen_cards', (select count(*) from public.cards where status = 'frozen'),
    'loan_applications', (select count(*) from public.loan_applications),
    'pending_loans', (select count(*) from public.loan_applications where status in ('pending', 'under_review')),
    'active_loans', (select count(*) from public.loan_applications where status = 'active'),
    'total_swaps', (select count(*) from public.currency_swaps),
    'unread_notifications', (select count(*) from public.notifications where is_read = false)
  ) into v_result;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- USERS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_users(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb;
begin
  if not public.admin_can(p_token, 'users.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select p.*,
      (select count(*) from public.accounts a where a.user_id = p.id) as account_count,
      (select coalesce(sum(b.ledger_balance), 0) from public.account_balances b
        join public.accounts a on a.id = b.account_id where a.user_id = p.id) as total_balance
    from public.profiles p
    where (p_search = '' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or p.status = p_status)
    order by p.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object(
    'rows', v_rows,
    'total', (select count(*) from public.profiles p
      where (p_search = '' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
        and (p_status is null or p.status = p_status))
  );
end;
$$;

create or replace function public.admin_get_user(p_token text, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user jsonb;
begin
  if not public.admin_can(p_token, 'users.view') then
    raise exception 'FORBIDDEN';
  end if;
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'accounts', (select coalesce(jsonb_agg(to_jsonb(a)), '[]') from public.accounts a where a.user_id = p_user_id),
    'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]') from public.transactions t where t.user_id = p_user_id limit 50),
    'cards', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.cards c where c.user_id = p_user_id),
    'deposits', (select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc), '[]') from public.deposits d where d.user_id = p_user_id limit 50),
    'swaps', (select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]') from public.currency_swaps s where s.user_id = p_user_id limit 50),
    'loans', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc), '[]') from public.loan_applications l where l.user_id = p_user_id limit 50),
    'notifications', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]') from public.notifications n where n.user_id = p_user_id limit 20)
  ) into v_user
  from public.profiles p where p.id = p_user_id;
  return v_user;
end;
$$;

create or replace function public.admin_create_user(
  p_token text,
  p_email text,
  p_password text,
  p_full_name text,
  p_phone text default null,
  p_address text default null,
  p_city text default null,
  p_country text default null,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid;
  v_profile public.profiles%rowtype;
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;

  select id into v_uid from auth.users where email = lower(p_email);
  if found then
    raise exception 'EMAIL_EXISTS';
  end if;

  v_uid := gen_random_uuid();
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
  values (
    v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    lower(p_email), crypt(p_password, gen_salt('bf', 10)), now(),
    jsonb_build_object('provider', 'email', 'providers', '["email"]'),
    jsonb_build_object('full_name', p_full_name),
    now(), now(), '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_uid, v_uid::text,
    jsonb_build_object('sub', v_uid::text, 'email', lower(p_email)),
    'email', now(), now(), now()
  );

  insert into public.profiles (id, email, full_name, phone, address, city, country, status)
  values (v_uid, lower(p_email), p_full_name, p_phone, p_address, p_city, p_country, p_status)
  on conflict (id) do update set full_name = excluded.full_name, status = excluded.status
  returning * into v_profile;

  perform public.log_audit(p_token, 'CREATE', 'user', v_uid::text, null,
    jsonb_build_object('email', lower(p_email), 'full_name', p_full_name, 'status', p_status));

  return jsonb_build_object('id', v_profile.id, 'email', v_profile.email, 'full_name', v_profile.full_name);
end;
$$;

create or replace function public.admin_update_user(
  p_token text,
  p_user_id uuid,
  p_full_name text default null,
  p_phone text default null,
  p_address text default null,
  p_city text default null,
  p_country text default null,
  p_status text default null,
  p_kyc_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_profile public.profiles%rowtype;
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(p) into v_old from public.profiles p where id = p_user_id;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  update public.profiles set
    full_name = coalesce(p_full_name, full_name),
    phone = coalesce(p_phone, phone),
    address = coalesce(p_address, address),
    city = coalesce(p_city, city),
    country = coalesce(p_country, country),
    status = coalesce(p_status, status),
    kyc_status = coalesce(p_kyc_status, kyc_status),
    updated_at = now()
  where id = p_user_id
  returning * into v_profile;

  select to_jsonb(v_profile) into v_new;
  perform public.log_audit(p_token, 'UPDATE', 'user', p_user_id::text, v_old, v_new);
  return v_new;
end;
$$;

create or replace function public.admin_suspend_user(p_token text, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(p) into v_old from public.profiles p where id = p_user_id;
  update public.profiles set status = 'suspended', updated_at = now() where id = p_user_id;
  update public.accounts set status = 'suspended', updated_at = now() where user_id = p_user_id;
  update public.cards set status = 'blocked', updated_at = now() where user_id = p_user_id;
  perform public.notify_user(p_user_id, 'Account suspended', 'Your account has been suspended. Contact support for assistance.', 'security');
  perform public.log_audit(p_token, 'SUSPEND', 'user', p_user_id::text, v_old, jsonb_build_object('status', 'suspended'));
end;
$$;

create or replace function public.admin_activate_user(p_token text, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;
  update public.profiles set status = 'active', updated_at = now() where id = p_user_id;
  perform public.notify_user(p_user_id, 'Account activated', 'Your account has been re-activated.', 'account');
  perform public.log_audit(p_token, 'ACTIVATE', 'user', p_user_id::text);
end;
$$;

create or replace function public.admin_delete_user(p_token text, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(p) into v_old from public.profiles p where id = p_user_id;
  delete from public.profiles where id = p_user_id;
  perform public.log_audit(p_token, 'DELETE', 'user', p_user_id::text, v_old, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- ACCOUNTS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_accounts(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_currency text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'accounts.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select a.*, p.full_name as owner_name, p.email as owner_email,
      (select b.available_balance from public.account_balances b where b.account_id = a.id) as available_balance,
      (select b.ledger_balance from public.account_balances b where b.account_id = a.id) as ledger_balance
    from public.accounts a
    join public.profiles p on p.id = a.user_id
    where (p_search = '' or a.account_number ilike '%' || p_search || '%' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or a.status = p_status)
      and (p_currency is null or a.currency = p_currency)
    order by a.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_create_account(
  p_token text,
  p_user_id uuid,
  p_account_type text,
  p_currency text,
  p_account_number text,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_account public.accounts%rowtype;
  v_name text;
begin
  if not public.admin_can(p_token, 'accounts.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select full_name into v_name from public.profiles where id = p_user_id;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  insert into public.accounts (user_id, account_number, account_name, account_type, currency, status)
  values (p_user_id, p_account_number, coalesce(v_name, ''), p_account_type, p_currency, p_status)
  returning * into v_account;

  insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
  values (v_account.id, 0, 0, p_currency);

  perform public.notify_user(p_user_id, 'Account opened',
    'A new ' || p_account_type || ' account (' || p_account_number || ') was opened for you.', 'account');
  perform public.log_audit(p_token, 'CREATE', 'account', v_account.id::text, null, to_jsonb(v_account));
  return to_jsonb(v_account);
end;
$$;

create or replace function public.admin_update_account(
  p_token text,
  p_account_id uuid,
  p_account_type text default null,
  p_status text default null,
  p_currency text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_account public.accounts%rowtype;
begin
  if not public.admin_can(p_token, 'accounts.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(a) into v_old from public.accounts a where id = p_account_id;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;
  update public.accounts set
    account_type = coalesce(p_account_type, account_type),
    status = coalesce(p_status, status),
    currency = coalesce(p_currency, currency),
    updated_at = now()
  where id = p_account_id returning * into v_account;
  perform public.log_audit(p_token, 'UPDATE', 'account', p_account_id::text, v_old, to_jsonb(v_account));
  return to_jsonb(v_account);
end;
$$;

create or replace function public.admin_change_account_status(p_token text, p_account_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'accounts.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(a) into v_old from public.accounts a where id = p_account_id;
  update public.accounts set status = p_status, updated_at = now() where id = p_account_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'account', p_account_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

-- ---------------------------------------------------------------------------
-- TRANSACTIONS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_transactions(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_type text default null,
  p_currency text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transactions.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.transactions t
    left join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%'
           or t.recipient ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
      and (p_type is null or t.type = p_type)
      and (p_currency is null or t.currency = p_currency)
    order by t.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_create_transaction(
  p_token text,
  p_user_id uuid,
  p_account_id uuid,
  p_type text,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_tx public.transactions;
begin
  if not public.admin_can(p_token, 'transactions.manage') then
    raise exception 'FORBIDDEN';
  end if;
  v_tx := public.record_transaction(p_user_id, p_account_id, p_type, p_direction, p_amount, p_currency, 'completed', p_description);
  if p_direction = 'credit' then
    perform public.apply_balance_change(p_account_id, p_amount, p_currency);
    perform public.notify_user(p_user_id, 'Credit received',
      to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency || ' credited to your account.', 'account');
  elsif p_direction = 'debit' then
    perform public.apply_balance_change(p_account_id, -p_amount, p_currency);
    perform public.notify_user(p_user_id, 'Debit applied',
      to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency || ' debited from your account.', 'account');
  end if;
  perform public.log_audit(p_token, 'CREATE', 'transaction', v_tx.id::text, null, to_jsonb(v_tx));
  return to_jsonb(v_tx);
end;
$$;

create or replace function public.admin_update_transaction_status(
  p_token text,
  p_tx_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_tx public.transactions%rowtype;
begin
  if not public.admin_can(p_token, 'transactions.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(t) into v_old from public.transactions t where id = p_tx_id;
  if not found then
    raise exception 'TRANSACTION_NOT_FOUND';
  end if;
  update public.transactions set status = p_status, updated_at = now() where id = p_tx_id returning * into v_tx;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'transaction', p_tx_id::text, v_old, jsonb_build_object('status', p_status));
  return to_jsonb(v_tx);
end;
$$;

create or replace function public.admin_reverse_transaction(p_token text, p_tx_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tx public.transactions%rowtype;
  v_ref text;
begin
  if not public.admin_can(p_token, 'transactions.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_tx from public.transactions where id = p_tx_id and status = 'completed' for update;
  if not found then
    raise exception 'TRANSACTION_NOT_COMPLETED';
  end if;

  update public.transactions set status = 'reversed', updated_at = now() where id = p_tx_id;

  -- reverse the money movement
  if v_tx.direction = 'debit' then
    perform public.apply_balance_change(v_tx.account_id, v_tx.amount + v_tx.fee, v_tx.currency);
  else
    perform public.apply_balance_change(v_tx.account_id, -(v_tx.amount - v_tx.fee), v_tx.currency);
  end if;

  perform public.record_transaction(
    v_tx.user_id, v_tx.account_id, 'reversal', v_tx.direction, v_tx.amount, v_tx.currency,
    'completed', 'Reversal of ' || v_tx.reference, v_tx.sender, v_tx.recipient, 0, v_tx.id
  );

  perform public.notify_user(v_tx.user_id, 'Transaction reversed',
    'Transaction ' || v_tx.reference || ' was reversed. Amount ' || to_char(v_tx.amount, 'FM9,999,999,990.00') || ' ' || v_tx.currency || ' returned to your account.', 'security');

  perform public.log_audit(p_token, 'REVERSE', 'transaction', p_tx_id::text, to_jsonb(v_tx), jsonb_build_object('status', 'reversed'));
  return to_jsonb(v_tx);
end;
$$;

-- ---------------------------------------------------------------------------
-- TRANSFERS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_local_transfers(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transfers.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.local_transfers t join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%' or t.recipient_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
    order by t.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_intl_transfers(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transfers.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.international_transfers t join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%' or t.recipient_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
    order by t.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_update_local_transfer(
  p_token text, p_transfer_id uuid, p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'transfers.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(t) into v_old from public.local_transfers t where id = p_transfer_id;
  if not found then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  update public.local_transfers set status = p_status,
    completed_at = case when p_status = 'completed' then now() else completed_at end,
    updated_at = now()
  where id = p_transfer_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'local_transfer', p_transfer_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

create or replace function public.admin_update_intl_transfer(
  p_token text, p_transfer_id uuid, p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'transfers.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(t) into v_old from public.international_transfers t where id = p_transfer_id;
  if not found then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  update public.international_transfers set status = p_status,
    completed_at = case when p_status = 'completed' then now() else completed_at end,
    updated_at = now()
  where id = p_transfer_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'international_transfer', p_transfer_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

-- ---------------------------------------------------------------------------
-- DEPOSITS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_deposits(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'deposits.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select d.*, p.full_name as user_name, p.email as user_email
    from public.deposits d join public.profiles p on p.id = d.user_id
    where (p_search = '' or d.reference ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or d.status = p_status)
    order by d.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_update_deposit(
  p_token text, p_deposit_id uuid, p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_deposit public.deposits%rowtype;
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_deposit from public.deposits where id = p_deposit_id for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;
  select to_jsonb(v_deposit) into v_old;

  update public.deposits set status = p_status, updated_at = now() where id = p_deposit_id;

  if p_status = 'completed' and v_deposit.status in ('pending', 'processing') then
    perform public.apply_balance_change(v_deposit.account_id, v_deposit.amount, v_deposit.currency);
    perform public.record_transaction(
      v_deposit.user_id, v_deposit.account_id, 'deposit', 'credit', v_deposit.amount,
      v_deposit.currency, 'completed', 'Deposit ' || v_deposit.reference, v_deposit.user_id::text, v_deposit.user_id::text, 0, v_deposit.id
    );
    perform public.notify_user(v_deposit.user_id, 'Deposit completed',
      'Your deposit of ' || to_char(v_deposit.amount, 'FM9,999,999,990.00') || ' ' || v_deposit.currency || ' was completed. Ref: ' || v_deposit.reference || '.', 'deposit');
  elsif p_status = 'rejected' then
    perform public.notify_user(v_deposit.user_id, 'Deposit rejected',
      'Your deposit of ' || to_char(v_deposit.amount, 'FM9,999,999,990.00') || ' ' || v_deposit.currency || ' was rejected. Contact support for details.', 'deposit');
  end if;

  perform public.log_audit(p_token, 'UPDATE_STATUS', 'deposit', p_deposit_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

-- ---------------------------------------------------------------------------
-- CARDS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_cards(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'cards.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select c.*, p.full_name as user_name, p.email as user_email
    from public.cards c join public.profiles p on p.id = c.user_id
    where (p_search = '' or c.masked_number ilike '%' || p_search || '%' or p.card_holder ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or c.status = p_status)
    order by c.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_create_card(
  p_token text,
  p_user_id uuid,
  p_account_id uuid,
  p_card_type text,
  p_card_brand text,
  p_expiry_month int,
  p_expiry_year int,
  p_spending_limit numeric,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_number text;
  v_masked text;
  v_card public.cards%rowtype;
  v_name text;
begin
  if not public.admin_can(p_token, 'cards.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select full_name into v_name from public.profiles where id = p_user_id;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_number := lpad(floor(random() * 9000000000000000)::bigint::text, 16, '4');
  v_masked := substr(v_number, 1, 4) || ' •••• •••• ' || substr(v_number, 13, 4);

  insert into public.cards (user_id, account_id, card_number, masked_number, card_holder, card_type, card_brand,
    expiry_month, expiry_year, cvv, spending_limit, status)
  values (p_user_id, p_account_id, v_number, v_masked, v_name, p_card_type, p_card_brand,
    p_expiry_month, p_expiry_year, lpad(floor(random()*900+100)::int::text,3,'0'), p_spending_limit, p_status)
  returning * into v_card;

  perform public.notify_user(p_user_id, 'Card issued',
    'A new ' || p_card_type || ' ' || p_card_brand || ' card ending in ' || substr(v_number, 13, 4) || ' was issued.', 'card');
  perform public.log_audit(p_token, 'CREATE', 'card', v_card.id::text, null, jsonb_build_object('masked_number', v_masked, 'card_type', p_card_type, 'card_brand', p_card_brand));
  return jsonb_build_object('id', v_card.id, 'masked_number', v_masked, 'status', v_card.status);
end;
$$;

create or replace function public.admin_update_card(
  p_token text, p_card_id uuid, p_status text default null, p_spending_limit numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_card public.cards%rowtype;
begin
  if not public.admin_can(p_token, 'cards.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(c) into v_old from public.cards c where id = p_card_id;
  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;
  update public.cards set
    status = coalesce(p_status, status),
    spending_limit = coalesce(p_spending_limit, spending_limit),
    updated_at = now()
  where id = p_card_id returning * into v_card;

  if p_status is not null and p_status <> (v_old->>'status') then
    perform public.notify_user(v_card.user_id, 'Card status changed',
      'Your card ending ' || substr(v_card.card_number, -4) || ' is now ' || p_status || '.', 'card');
  end if;

  perform public.log_audit(p_token, 'UPDATE', 'card', p_card_id::text, v_old, to_jsonb(v_card));
  return to_jsonb(v_card);
end;
$$;

-- ---------------------------------------------------------------------------
-- CURRENCIES + EXCHANGE RATES
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_currencies(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'currencies.view') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'currency', to_jsonb(c),
        'rates', (select coalesce(jsonb_agg(to_jsonb(r) order by r.quote_currency), '[]')
                  from public.exchange_rates r where r.base_currency = c.code)
      ) order by c.code), '[]')
    from public.currencies c
  );
end;
$$;

create or replace function public.admin_create_currency(
  p_token text, p_code text, p_name text, p_symbol text, p_is_base boolean default false, p_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_cur public.currencies%rowtype;
begin
  if not public.admin_can(p_token, 'currencies.manage') then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.currencies (code, name, symbol, is_base, enabled)
  values (upper(p_code), p_name, p_symbol, p_is_base, p_enabled) returning * into v_cur;
  perform public.log_audit(p_token, 'CREATE', 'currency', v_cur.id::text, null, to_jsonb(v_cur));
  return to_jsonb(v_cur);
end;
$$;

create or replace function public.admin_update_currency(
  p_token text, p_code text, p_name text default null, p_symbol text default null,
  p_enabled boolean default null, p_is_base boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_cur public.currencies%rowtype;
begin
  if not public.admin_can(p_token, 'currencies.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(c) into v_old from public.currencies c where code = p_code;
  if not found then
    raise exception 'CURRENCY_NOT_FOUND';
  end if;
  update public.currencies set
    name = coalesce(p_name, name),
    symbol = coalesce(p_symbol, symbol),
    enabled = coalesce(p_enabled, enabled),
    is_base = coalesce(p_is_base, is_base),
    updated_at = now()
  where code = p_code returning * into v_cur;
  perform public.log_audit(p_token, 'UPDATE', 'currency', p_code, v_old, to_jsonb(v_cur));
  return to_jsonb(v_cur);
end;
$$;

create or replace function public.admin_delete_currency(p_token text, p_code text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'currencies.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(c) into v_old from public.currencies c where code = p_code;
  if (select count(*) from public.accounts where currency = p_code) > 0 then
    raise exception 'CURRENCY_IN_USE';
  end if;
  delete from public.exchange_rates where base_currency = p_code or quote_currency = p_code;
  delete from public.currencies where code = p_code;
  perform public.log_audit(p_token, 'DELETE', 'currency', p_code, v_old, null);
end;
$$;

create or replace function public.admin_set_exchange_rate(
  p_token text, p_base text, p_quote text, p_rate numeric, p_fee_percent numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rate public.exchange_rates%rowtype;
begin
  if not public.admin_can(p_token, 'currencies.manage') then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
  values (p_base, p_quote, p_rate, p_fee_percent)
  on conflict (base_currency, quote_currency) do update
    set rate = p_rate, fee_percent = p_fee_percent, updated_at = now()
  returning * into v_rate;
  perform public.log_audit(p_token, 'UPDATE_RATE', 'exchange_rate', p_base || '/' || p_quote, null,
    jsonb_build_object('base_currency', p_base, 'quote_currency', p_quote, 'rate', p_rate, 'fee_percent', p_fee_percent));
  return to_jsonb(v_rate);
end;
$$;

-- ---------------------------------------------------------------------------
-- LOANS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_loan_products(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'loans.view') then
    raise exception 'FORBIDDEN';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(lp) order by lp.created_at), '[]') from public.loan_products lp);
end;
$$;

create or replace function public.admin_create_loan_product(
  p_token text, p_name text, p_description text, p_min_amount numeric, p_max_amount numeric,
  p_interest_rate numeric, p_term_months int, p_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_lp public.loan_products%rowtype;
begin
  if not public.admin_can(p_token, 'loans.manage') then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.loan_products (name, description, min_amount, max_amount, interest_rate, term_months, enabled)
  values (p_name, p_description, p_min_amount, p_max_amount, p_interest_rate, p_term_months, p_enabled)
  returning * into v_lp;
  perform public.log_audit(p_token, 'CREATE', 'loan_product', v_lp.id::text, null, to_jsonb(v_lp));
  return to_jsonb(v_lp);
end;
$$;

create or replace function public.admin_update_loan_product(
  p_token text, p_product_id uuid, p_name text default null, p_description text default null,
  p_min_amount numeric default null, p_max_amount numeric default null, p_interest_rate numeric default null,
  p_term_months int default null, p_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_lp public.loan_products%rowtype;
begin
  if not public.admin_can(p_token, 'loans.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(lp) into v_old from public.loan_products lp where id = p_product_id;
  if not found then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;
  update public.loan_products set
    name = coalesce(p_name, name), description = coalesce(p_description, description),
    min_amount = coalesce(p_min_amount, min_amount), max_amount = coalesce(p_max_amount, max_amount),
    interest_rate = coalesce(p_interest_rate, interest_rate), term_months = coalesce(p_term_months, term_months),
    enabled = coalesce(p_enabled, enabled), updated_at = now()
  where id = p_product_id returning * into v_lp;
  perform public.log_audit(p_token, 'UPDATE', 'loan_product', p_product_id::text, v_old, to_jsonb(v_lp));
  return to_jsonb(v_lp);
end;
$$;

create or replace function public.admin_delete_loan_product(p_token text, p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'loans.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(lp) into v_old from public.loan_products lp where id = p_product_id;
  if (select count(*) from public.loan_applications where product_id = p_product_id) > 0 then
    raise exception 'PRODUCT_IN_USE';
  end if;
  delete from public.loan_products where id = p_product_id;
  perform public.log_audit(p_token, 'DELETE', 'loan_product', p_product_id::text, v_old, null);
end;
$$;

create or replace function public.admin_list_loan_applications(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'loans.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(u)), '[]')
  from (
    select la.*, p.full_name as user_name, p.email as user_email, lp.name as product_name
    from public.loan_applications la
    join public.profiles p on p.id = la.user_id
    join public.loan_products lp on lp.id = la.product_id
    where (p_search = '' or la.reference ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or la.status = p_status)
    order by la.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_update_loan_application(
  p_token text, p_loan_id uuid, p_status text, p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_loan public.loan_applications%rowtype;
begin
  if not public.admin_can(p_token, 'loans.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_loan from public.loan_applications where id = p_loan_id for update;
  if not found then
    raise exception 'LOAN_NOT_FOUND';
  end if;
  select to_jsonb(v_loan) into v_old;

  update public.loan_applications set status = p_status,
    admin_note = coalesce(p_admin_note, admin_note),
    disbursed_at = case when p_status = 'active' then now() else disbursed_at end,
    updated_at = now()
  where id = p_loan_id;

  if p_status = 'approved' then
    perform public.notify_user(v_loan.user_id, 'Loan approved',
      'Congratulations! Your loan application ' || v_loan.reference || ' has been approved.', 'loan');
  elsif p_status = 'rejected' then
    perform public.notify_user(v_loan.user_id, 'Loan rejected',
      'Your loan application ' || v_loan.reference || ' was not approved.' || coalesce(' Reason: ' || p_admin_note, ''), 'loan');
  elsif p_status = 'active' then
    -- disburse into the customer's account of matching currency
    declare v_acc uuid;
    begin
      select id into v_acc from public.accounts
        where user_id = v_loan.user_id and currency = v_loan.currency and status = 'active'
        order by created_at limit 1;
      if found then
        perform public.apply_balance_change(v_acc, v_loan.amount, v_loan.currency);
        perform public.record_transaction(
          v_loan.user_id, v_acc, 'loan_disbursement', 'credit', v_loan.amount, v_loan.currency,
          'completed', 'Loan disbursement ' || v_loan.reference, 'marvintlc', v_loan.user_id::text, 0, v_loan.id
        );
        perform public.notify_user(v_loan.user_id, 'Loan disbursed',
          'Your approved loan of ' || to_char(v_loan.amount, 'FM9,999,999,990.00') || ' ' || v_loan.currency || ' has been disbursed.', 'loan');
      end if;
    end;
  end if;

  perform public.log_audit(p_token, 'UPDATE_STATUS', 'loan_application', p_loan_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

create or replace function public.admin_list_loan_repayments(
  p_token text, p_loan_id uuid default null, p_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'loans.view') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(row_to_jsonb(u) order by r.due_date), '[]')
    from (
      select r.*, la.reference as loan_reference, p.full_name as user_name, p.email as user_email
      from public.loan_repayments r
      join public.loan_applications la on la.id = r.loan_application_id
      join public.profiles p on p.id = r.user_id
      where (p_loan_id is null or r.loan_application_id = p_loan_id)
        and (p_status is null or r.status = p_status)
    ) u
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS (admin)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_notifications(
  p_token text, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'notifications.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(n)), '[]')
  from (
    select n.*, p.full_name as user_name, p.email as user_email
    from public.notifications n left join public.profiles p on p.id = n.user_id
    order by n.created_at desc limit p_limit offset p_offset
  ) n into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_send_notification(
  p_token text, p_user_id uuid, p_title text, p_message text, p_type text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_notif public.notifications%rowtype;
begin
  if not public.admin_can(p_token, 'notifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.notifications (user_id, title, message, type)
  values (p_user_id, p_title, p_message, p_type) returning * into v_notif;
  perform public.log_audit(p_token, 'SEND', 'notification', v_notif.id::text, null, to_jsonb(v_notif));
  return to_jsonb(v_notif);
end;
$$;

create or replace function public.admin_send_global_notification(
  p_token text, p_title text, p_message text, p_type text default 'system'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'notifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.notifications (user_id, title, message, type, is_global)
  values (null, p_title, p_message, p_type, true);
  perform public.log_audit(p_token, 'SEND_GLOBAL', 'notification', null, null,
    jsonb_build_object('title', p_title, 'message', p_message, 'type', p_type));
end;
$$;

create or replace function public.admin_delete_notification(p_token text, p_notif_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'notifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(n) into v_old from public.notifications n where id = p_notif_id;
  delete from public.notifications where id = p_notif_id;
  perform public.log_audit(p_token, 'DELETE', 'notification', p_notif_id::text, v_old, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- AUDIT LOGS
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_audit_logs(
  p_token text, p_search text default '', p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'audit.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(row_to_jsonb(a)), '[]')
  from (
    select a.*, au.full_name as admin_name
    from public.audit_logs a left join public.admin_users au on au.id = a.admin_id
    where (p_search = '' or a.action ilike '%' || p_search || '%' or a.resource ilike '%' || p_search || '%'
           or a.admin_email ilike '%' || p_search || '%' or a.resource_id ilike '%' || p_search || '%')
    order by a.created_at desc limit p_limit offset p_offset
  ) a into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

-- ---------------------------------------------------------------------------
-- ADMIN USER MANAGEMENT
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_admins(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'admins.manage') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', au.id, 'email', au.email, 'full_name', au.full_name,
      'status', au.status, 'role', coalesce(ar.name, 'admin'),
      'created_at', au.created_at
    ) order by au.created_at), '[]')
    from public.admin_users au left join public.admin_roles ar on ar.id = au.role_id
  );
end;
$$;

create or replace function public.admin_create_admin(
  p_token text, p_email text, p_password text, p_full_name text, p_role_name text default 'support', p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role uuid; v_admin public.admin_users%rowtype;
begin
  if not public.admin_can(p_token, 'admins.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select id into v_role from public.admin_roles where name = p_role_name;
  if not found then
    raise exception 'ROLE_NOT_FOUND';
  end if;
  insert into public.admin_users (email, password_hash, full_name, role_id, status)
  values (lower(p_email), public.admin_hash_password(p_password), p_full_name, v_role, p_status)
  returning * into v_admin;
  perform public.log_audit(p_token, 'CREATE', 'admin_user', v_admin.id::text, null, to_jsonb(v_admin));
  return to_jsonb(v_admin);
end;
$$;

create or replace function public.admin_update_admin(
  p_token text, p_admin_id uuid, p_full_name text default null, p_role_name text default null,
  p_status text default null, p_password text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb; v_role uuid; v_admin public.admin_users%rowtype;
begin
  if not public.admin_can(p_token, 'admins.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(au) into v_old from public.admin_users au where id = p_admin_id;
  if not found then
    raise exception 'ADMIN_NOT_FOUND';
  end if;
  if p_role_name is not null then
    select id into v_role from public.admin_roles where name = p_role_name;
    if not found then
      raise exception 'ROLE_NOT_FOUND';
    end if;
  end if;
  update public.admin_users set
    full_name = coalesce(p_full_name, full_name),
    role_id = coalesce(v_role, role_id),
    status = coalesce(p_status, status),
    password_hash = case when p_password is not null and p_password <> '' then public.admin_hash_password(p_password) else password_hash end,
    updated_at = now()
  where id = p_admin_id returning * into v_admin;
  perform public.log_audit(p_token, 'UPDATE', 'admin_user', p_admin_id::text, v_old, to_jsonb(v_admin));
  return to_jsonb(v_admin);
end;
$$;

-- ---------------------------------------------------------------------------
-- SYSTEM SETTINGS
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_settings(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'settings.view') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_object_agg(key, value), '{}') from public.system_settings
  );
end;
$$;

create or replace function public.admin_update_setting(p_token text, p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'settings.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select value into v_old from public.system_settings where key = p_key;
  insert into public.system_settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set value = p_value, updated_at = now();
  perform public.log_audit(p_token, 'UPDATE_SETTING', 'setting', p_key, v_old, p_value);
end;
$$;

-- Grant execute to anon/authenticated so the frontend can call RPCs.
grant execute on function public.admin_login, public.admin_logout, public.admin_validate,
  public.admin_from_token, public.admin_can, public.admin_hash_password, public.log_audit,
  public.admin_get_stats, public.admin_list_users, public.admin_get_user, public.admin_create_user,
  public.admin_update_user, public.admin_suspend_user, public.admin_activate_user, public.admin_delete_user,
  public.admin_list_accounts, public.admin_create_account, public.admin_update_account, public.admin_change_account_status,
  public.admin_list_transactions, public.admin_create_transaction, public.admin_update_transaction_status, public.admin_reverse_transaction,
  public.admin_list_local_transfers, public.admin_list_intl_transfers, public.admin_update_local_transfer, public.admin_update_intl_transfer,
  public.admin_list_deposits, public.admin_update_deposit,
  public.admin_list_cards, public.admin_create_card, public.admin_update_card,
  public.admin_list_currencies, public.admin_create_currency, public.admin_update_currency, public.admin_delete_currency, public.admin_set_exchange_rate,
  public.admin_list_loan_products, public.admin_create_loan_product, public.admin_update_loan_product, public.admin_delete_loan_product,
  public.admin_list_loan_applications, public.admin_update_loan_application, public.admin_list_loan_repayments,
  public.admin_list_notifications, public.admin_send_notification, public.admin_send_global_notification, public.admin_delete_notification,
  public.admin_list_audit_logs,
  public.admin_list_admins, public.admin_create_admin, public.admin_update_admin,
  public.admin_get_settings, public.admin_update_setting,
  public.generate_reference, public.notify_user, public.apply_balance_change, public.record_transaction,
  public.create_local_transfer, public.create_currency_swap, public.pay_loan_repayment
to anon, authenticated;

grant usage on schema public to anon, authenticated;-- marvintlc - Migration 007
-- Triggers

-- New auth user -> profile
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- New profile -> default account + welcome notification + base currency default
create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_base text;
begin
  select code into v_base from public.currencies where is_base = true limit 1;
  if not found then
    v_base := 'USD';
  end if;

  insert into public.accounts (user_id, account_number, account_name, account_type, currency)
  values (
    new.id,
    '48' || lpad(floor(random() * 100000000000000000)::bigint::text, 14, '0'),
    new.full_name,
    'checking',
    v_base
  )
  on conflict do nothing
  returning id into v_account_id;

  if found then
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (v_account_id, 0, 0, v_base)
    on conflict (account_id) do nothing;

    insert into public.notifications (user_id, title, message, type)
    values (new.id, 'Welcome to marvintlc',
      'Your account has been created. Explore your dashboard to get started.', 'account');
  end if;

  return new;
end;
$$;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created
  after insert on public.profiles
  for each row execute procedure public.handle_new_profile();

-- Mark overdue repayments
create or replace function public.mark_overdue_repayments()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.loan_repayments
    set status = 'overdue', updated_at = now()
    where status = 'scheduled' and due_date < current_date;
end;
$$;

-- updated_at triggers
create trigger touch_profiles_updated       before update on public.profiles             for each row execute procedure public.touch_updated_at();
create trigger touch_accounts_updated       before update on public.accounts             for each row execute procedure public.touch_updated_at();
create trigger touch_tx_updated             before update on public.transactions         for each row execute procedure public.touch_updated_at();
create trigger touch_local_updated          before update on public.local_transfers      for each row execute procedure public.touch_updated_at();
create trigger touch_intl_updated           before update on public.international_transfers for each row execute procedure public.touch_updated_at();
create trigger touch_cards_updated          before update on public.cards                for each row execute procedure public.touch_updated_at();
create trigger touch_deposits_updated       before update on public.deposits             for each row execute procedure public.touch_updated_at();
create trigger touch_swaps_updated          before update on public.currency_swaps       for each row execute procedure public.touch_updated_at();
create trigger touch_loans_updated          before update on public.loan_applications    for each row execute procedure public.touch_updated_at();
create trigger touch_repay_updated          before update on public.loan_repayments      for each row execute procedure public.touch_updated_at();
create trigger touch_admin_updated          before update on public.admin_users           for each row execute procedure public.touch_updated_at();-- marvintlc - Migration 008
-- Additional customer-facing financial functions

-- ---------------------------------------------------------------------------
-- INTERNATIONAL TRANSFER (atomic)
--   Validates account + balance, charges SWIFT fee, debits account, records
--   the transfer + transaction and notifies the customer.
-- ---------------------------------------------------------------------------
create or replace function public.create_international_transfer(
  p_user_id uuid,
  p_from_account_id uuid,
  p_recipient_name text,
  p_recipient_bank text,
  p_recipient_account_number text,
  p_swift_code text,
  p_recipient_country text,
  p_amount numeric,
  p_currency text,
  p_purpose text default null
)
returns public.international_transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_rate numeric;
  v_xfer public.international_transfers;
  v_name text;
begin
  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_from_account_id;
  if v_balance is null then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  -- fee from settings (default $15)
  select coalesce((value::text)::numeric, 15) into v_fee
    from public.system_settings where key = 'intl_transfer_fee';
  if v_fee is null then v_fee := 15; end if;

  if v_balance < (p_amount + v_fee) then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  v_rate := 1;
  -- FX rate when converting from account currency to destination currency
  select rate into v_rate from public.exchange_rates
    where base_currency = p_currency and quote_currency = p_currency; -- identity

  select full_name into v_name from public.profiles where id = p_user_id;

  perform public.apply_balance_change(p_from_account_id, -(p_amount + v_fee), p_currency);

  insert into public.international_transfers (
    reference, user_id, from_account_id, recipient_name, recipient_bank, recipient_account_number,
    swift_code, recipient_country, purpose, amount, currency, exchange_rate, fee,
    estimated_delivery, status, completed_at
  ) values (
    public.generate_reference('IT'), p_user_id, p_from_account_id, p_recipient_name, p_recipient_bank,
    p_recipient_account_number, p_swift_code, p_recipient_country, p_purpose, p_amount, p_currency,
    v_rate, v_fee, now() + interval '2 days', 'processing', null
  ) returning * into v_xfer;

  perform public.record_transaction(
    p_user_id, p_from_account_id, 'international_transfer', 'debit', p_amount, p_currency,
    'processing', coalesce(p_purpose, 'International transfer'),
    v_name, p_recipient_name || ' (' || p_recipient_country || ')', v_fee, v_xfer.id
  );

  perform public.notify_user(p_user_id,
    'International transfer submitted',
    'Your international transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' to ' || p_recipient_name || ' has been submitted. Ref: ' || v_xfer.reference || '.',
    'transfer');

  return v_xfer;
end;
$$;

grant execute on function public.create_international_transfer to anon, authenticated;-- marvintlc - Migration 009
-- Profile extras + storage bucket for avatars

alter table public.profiles
  add column if not exists notification_prefs jsonb not null default
    '{"transfers": true, "deposits": true, "loans": true, "cards": true, "swaps": true, "security": true, "marketing": false}';

-- Avatar storage bucket (public read, owner write)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatars_owner_write" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatars_owner_update" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatars_owner_delete" on storage.objects
  for delete using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);-- marvintlc - Migration 010
-- Bootstrap reference data (base infrastructure, NOT demo data).
-- Required for real user signup: handle_new_profile() creates a default
-- USD account, which needs at least one base currency to exist.
-- Safe to run more than once (idempotent: on conflict do nothing).

-- ---------------------------------------------------------------------------
-- Currencies
-- ---------------------------------------------------------------------------
insert into public.currencies (code, name, symbol, is_base, enabled) values
  ('USD', 'US Dollar',     '$',  true,  true),
  ('EUR', 'Euro',          '€',  false, true),
  ('GBP', 'British Pound', '£',  false, true),
  ('NGN', 'Nigerian Naira','₦',  false, true),
  ('CAD', 'Canadian Dollar','C$', false, true)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Exchange rates (base -> quote)
-- ---------------------------------------------------------------------------
insert into public.exchange_rates (base_currency, quote_currency, rate, fee_percent) values
  ('USD', 'EUR', 0.9200, 0.50),
  ('USD', 'GBP', 0.7900, 0.50),
  ('USD', 'NGN', 1580.00, 1.00),
  ('USD', 'CAD', 1.3700, 0.50),
  ('EUR', 'USD', 1.0870, 0.50),
  ('GBP', 'USD', 1.2660, 0.50),
  ('NGN', 'USD', 0.00063, 1.00),
  ('CAD', 'USD', 0.7300, 0.50)
on conflict (base_currency, quote_currency) do nothing;

-- ---------------------------------------------------------------------------
-- Loan products
-- ---------------------------------------------------------------------------
insert into public.loan_products (name, description, min_amount, max_amount, interest_rate, term_months, enabled) values
  ('Personal Loan', 'Flexible personal loan for your everyday needs.', 500, 50000, 5.50, 12, true),
  ('Auto Loan', 'Finance your next vehicle with competitive rates.', 2000, 80000, 4.75, 60, true),
  ('Home Improvement', 'Upgrade and renovate your home.', 5000, 200000, 4.25, 84, true),
  ('Business Loan', 'Working capital to grow your business.', 10000, 500000, 6.25, 48, true);

-- ---------------------------------------------------------------------------
-- Admin roles
-- ---------------------------------------------------------------------------
insert into public.admin_roles (name, permissions) values
  ('super_admin', array[
    'dashboard','users.view','users.manage','accounts.view','accounts.manage',
    'transactions.view','transactions.manage','transfers.view','transfers.manage',
    'deposits.view','deposits.manage','cards.view','cards.manage',
    'currencies.view','currencies.manage','loans.view','loans.manage',
    'notifications.view','notifications.manage','audit.view','settings.view',
    'settings.manage','admins.manage'
  ]),
  ('admin', array[
    'dashboard','users.view','users.manage','accounts.view','accounts.manage',
    'transactions.view','transactions.manage','transfers.view','transfers.manage',
    'deposits.view','deposits.manage','cards.view','cards.manage',
    'currencies.view','currencies.manage','loans.view','loans.manage',
    'notifications.view','notifications.manage','audit.view','settings.view'
  ])
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- System settings
-- ---------------------------------------------------------------------------
insert into public.system_settings (key, value, description) values
  ('bank_name', '"marvintlc"', 'Institution display name'),
  ('currency', '"USD"', 'Default currency code'),
  ('local_transfer_fee', '0', 'Flat local transfer fee'),
  ('intl_transfer_fee', '15', 'Flat international transfer fee'),
  ('swap_fee_percent', '0.5', 'Default currency swap fee percentage'),
  ('maintenance_mode', 'false', 'Maintenance mode flag')
on conflict (key) do nothing;-- marvintlc - Migration 011
-- Platform correctness fixes + feature completion
--  1. row_to_jsonb() does not exist -> replaced with to_jsonb() in 11 admin functions.
--  2. admin_create_transaction called record_transaction() missing sender/recipient.
--  3. admin_list_loan_repayments referenced invalid r.due_date alias.
--  4. admin_get_user missing local/international transfers (used by customer detail tab).
--  5. New admin_get_chart_data() for the admin dashboard charts (RLS-safe).
--  6. create_currency_swap: fee-inclusive balance check + guaranteed destination credit.
--  7. Luhn-valid card number generation for admin_create_card.
--  8. Security: internal SECURITY DEFINER helpers + admin_hash_password revoked from anon/auth.
--  9. system_settings readable by authenticated users (intl fee preview).
-- 10. Loan repayments auto-marked overdue.
-- Safe on a fresh database: all statements are idempotent create/replace/grant/revoke.

-- ---------------------------------------------------------------------------
-- 1. record_transaction: give sender/recipient defaults so 8-arg callers work
-- ---------------------------------------------------------------------------
create or replace function public.record_transaction(
  p_user_id uuid,
  p_account_id uuid,
  p_type text,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_status text,
  p_description text,
  p_sender text default null,
  p_recipient text default null,
  p_fee numeric default 0,
  p_related_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx public.transactions;
begin
  insert into public.transactions (
    reference, user_id, account_id, type, direction, amount, currency, status,
    description, sender, recipient, fee, related_id
  ) values (
    public.generate_reference('NTB'), p_user_id, p_account_id, p_type, p_direction,
    p_amount, p_currency, p_status, p_description, p_sender, p_recipient, p_fee, p_related_id
  )
  returning * into v_tx;
  return v_tx;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. row_to_jsonb -> to_jsonb fixes (admin list functions)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_users(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb;
begin
  if not public.admin_can(p_token, 'users.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select p.*,
      (select count(*) from public.accounts a where a.user_id = p.id) as account_count,
      (select coalesce(sum(b.ledger_balance), 0) from public.account_balances b
        join public.accounts a on a.id = b.account_id where a.user_id = p.id) as total_balance
    from public.profiles p
    where (p_search = '' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or p.status = p_status)
    order by p.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object(
    'rows', v_rows,
    'total', (select count(*) from public.profiles p
      where (p_search = '' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
        and (p_status is null or p.status = p_status))
  );
end;
$$;

create or replace function public.admin_list_accounts(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_currency text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'accounts.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select a.*, p.full_name as owner_name, p.email as owner_email,
      (select b.available_balance from public.account_balances b where b.account_id = a.id) as available_balance,
      (select b.ledger_balance from public.account_balances b where b.account_id = a.id) as ledger_balance
    from public.accounts a
    join public.profiles p on p.id = a.user_id
    where (p_search = '' or a.account_number ilike '%' || p_search || '%' or p.full_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or a.status = p_status)
      and (p_currency is null or a.currency = p_currency)
    order by a.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_transactions(
  p_token text,
  p_search text default '',
  p_status text default null,
  p_type text default null,
  p_currency text default null,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transactions.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.transactions t
    left join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%'
           or t.recipient ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
      and (p_type is null or t.type = p_type)
      and (p_currency is null or t.currency = p_currency)
    order by t.created_at desc
    limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_local_transfers(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transfers.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.local_transfers t join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%' or t.recipient_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
    order by t.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_intl_transfers(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'transfers.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select t.*, p.full_name as user_name, p.email as user_email
    from public.international_transfers t join public.profiles p on p.id = t.user_id
    where (p_search = '' or t.reference ilike '%' || p_search || '%' or t.recipient_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or t.status = p_status)
    order by t.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_deposits(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'deposits.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select d.*, p.full_name as user_name, p.email as user_email
    from public.deposits d join public.profiles p on p.id = d.user_id
    where (p_search = '' or d.reference ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or d.status = p_status)
    order by d.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_cards(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'cards.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select c.*, p.full_name as user_name, p.email as user_email
    from public.cards c join public.profiles p on p.id = c.user_id
    where (p_search = '' or c.masked_number ilike '%' || p_search || '%' or c.card_holder ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or c.status = p_status)
    order by c.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_loan_applications(
  p_token text, p_search text default '', p_status text default null, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'loans.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(u)), '[]')
  from (
    select la.*, p.full_name as user_name, p.email as user_email, lp.name as product_name
    from public.loan_applications la
    join public.profiles p on p.id = la.user_id
    join public.loan_products lp on lp.id = la.product_id
    where (p_search = '' or la.reference ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
      and (p_status is null or la.status = p_status)
    order by la.created_at desc limit p_limit offset p_offset
  ) u into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_loan_repayments(
  p_token text, p_loan_id uuid default null, p_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_can(p_token, 'loans.view') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(u) order by u.due_date), '[]')
    from (
      select r.*, la.reference as loan_reference, p.full_name as user_name, p.email as user_email
      from public.loan_repayments r
      join public.loan_applications la on la.id = r.loan_application_id
      join public.profiles p on p.id = r.user_id
      where (p_loan_id is null or r.loan_application_id = p_loan_id)
        and (p_status is null or r.status = p_status)
    ) u
  );
end;
$$;

create or replace function public.admin_list_notifications(
  p_token text, p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'notifications.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(n)), '[]')
  from (
    select n.*, p.full_name as user_name, p.email as user_email
    from public.notifications n left join public.profiles p on p.id = n.user_id
    order by n.created_at desc limit p_limit offset p_offset
  ) n into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

create or replace function public.admin_list_audit_logs(
  p_token text, p_search text default '', p_limit int default 100, p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public.admin_can(p_token, 'audit.view') then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(to_jsonb(a)), '[]')
  from (
    select a.*, au.full_name as admin_name
    from public.audit_logs a left join public.admin_users au on au.id = a.admin_id
    where (p_search = '' or a.action ilike '%' || p_search || '%' or a.resource ilike '%' || p_search || '%'
           or a.admin_email ilike '%' || p_search || '%' or a.resource_id ilike '%' || p_search || '%')
    order by a.created_at desc limit p_limit offset p_offset
  ) a into v_rows;
  return jsonb_build_object('rows', v_rows, 'total', jsonb_array_length(v_rows));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. admin_create_transaction: pass meaningful sender/recipient
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_transaction(
  p_token text,
  p_user_id uuid,
  p_account_id uuid,
  p_type text,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_tx public.transactions; v_name text;
begin
  if not public.admin_can(p_token, 'transactions.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select full_name into v_name from public.profiles where id = p_user_id;
  v_tx := public.record_transaction(
    p_user_id, p_account_id, p_type, p_direction, p_amount, p_currency, 'completed', p_description,
    case when p_direction = 'credit' then 'marvintlc' else coalesce(v_name, 'Customer') end,
    case when p_direction = 'credit' then coalesce(v_name, 'Customer') else 'marvintlc' end
  );
  if p_direction = 'credit' then
    perform public.apply_balance_change(p_account_id, p_amount, p_currency);
    perform public.notify_user(p_user_id, 'Credit received',
      to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency || ' credited to your account.', 'account');
  elsif p_direction = 'debit' then
    perform public.apply_balance_change(p_account_id, -p_amount, p_currency);
    perform public.notify_user(p_user_id, 'Debit applied',
      to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency || ' debited from your account.', 'account');
  end if;
  perform public.log_audit(p_token, 'CREATE', 'transaction', v_tx.id::text, null, to_jsonb(v_tx));
  return to_jsonb(v_tx);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. admin_get_user: include local + international transfers for the customer tab
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_user(p_token text, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user jsonb;
begin
  if not public.admin_can(p_token, 'users.view') then
    raise exception 'FORBIDDEN';
  end if;
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'accounts', (select coalesce(jsonb_agg(to_jsonb(a)), '[]') from public.accounts a where a.user_id = p_user_id),
    'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]') from public.transactions t where t.user_id = p_user_id limit 50),
    'cards', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.cards c where c.user_id = p_user_id),
    'deposits', (select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc), '[]') from public.deposits d where d.user_id = p_user_id limit 50),
    'swaps', (select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]') from public.currency_swaps s where s.user_id = p_user_id limit 50),
    'loans', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc), '[]') from public.loan_applications l where l.user_id = p_user_id limit 50),
    'local_transfers', (select coalesce(jsonb_agg(to_jsonb(lt) order by lt.created_at desc), '[]') from public.local_transfers lt where lt.user_id = p_user_id limit 50),
    'international_transfers', (select coalesce(jsonb_agg(to_jsonb(ix) order by ix.created_at desc), '[]') from public.international_transfers ix where ix.user_id = p_user_id limit 50),
    'notifications', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]') from public.notifications n where n.user_id = p_user_id limit 20)
  ) into v_user
  from public.profiles p where p.id = p_user_id;
  return v_user;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. admin_get_chart_data: last-6-months volume + status breakdown (RLS-safe)
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_chart_data(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
begin
  if not public.admin_can(p_token, 'dashboard') then
    raise exception 'FORBIDDEN';
  end if;
  select jsonb_build_object(
    'months', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'month', to_char(m, 'Mon'),
        'credits', coalesce((select sum(t.amount) from public.transactions t
          where t.status = 'completed' and t.direction = 'credit'
            and date_trunc('month', t.created_at) = m), 0),
        'debits', coalesce((select sum(t.amount) from public.transactions t
          where t.status = 'completed' and t.direction = 'debit'
            and date_trunc('month', t.created_at) = m), 0)
      )), '[]')
      from generate_series(
        date_trunc('month', now()) - interval '5 months',
        date_trunc('month', now()),
        interval '1 month'
      ) as m
    ),
    'status_breakdown', (
      select coalesce(jsonb_object_agg(t.status, t.cnt), '{}')
      from (select status, count(*) as cnt from public.transactions group by status) t
    )
  ) into v_result;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Card number generation (Luhn-valid, brand-prefixed, collision-safe)
-- ---------------------------------------------------------------------------
create or replace function public.generate_card_number(p_brand text default 'mastercard')
returns text
language plpgsql
set search_path = public
as $$
declare
  v_prefix text := case when p_brand = 'mastercard' then '5' else '4' end;
  v_rest text;
  v_num text;
  v_sum int;
  v_i int;
  v_d int;
  v_check int;
begin
  loop
    v_rest := '';
    for v_i in 1..14 loop
      v_rest := v_rest || floor(random() * 10)::int::text;
    end loop;
    v_num := v_prefix || v_rest;
    v_sum := 0;
    for v_i in 1..15 loop
      v_d := substr(v_num, v_i, 1)::int;
      if (v_i % 2) = 1 then
        v_d := v_d * 2;
        if v_d > 9 then v_d := v_d - 9; end if;
      end if;
      v_sum := v_sum + v_d;
    end loop;
    v_check := (10 - (v_sum % 10)) % 10;
    v_num := v_num || v_check::text;
    exit when not exists (select 1 from public.cards where card_number = v_num);
  end loop;
  return v_num;
end;
$$;

create or replace function public.admin_create_card(
  p_token text,
  p_user_id uuid,
  p_account_id uuid,
  p_card_type text,
  p_card_brand text,
  p_expiry_month int,
  p_expiry_year int,
  p_spending_limit numeric,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_number text;
  v_masked text;
  v_card public.cards%rowtype;
  v_name text;
begin
  if not public.admin_can(p_token, 'cards.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select full_name into v_name from public.profiles where id = p_user_id;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_number := public.generate_card_number(p_card_brand);
  v_masked := substr(v_number, 1, 4) || ' •••• •••• ' || substr(v_number, 13, 4);

  insert into public.cards (user_id, account_id, card_number, masked_number, card_holder, card_type, card_brand,
    expiry_month, expiry_year, cvv, spending_limit, status)
  values (p_user_id, p_account_id, v_number, v_masked, v_name, p_card_type, p_card_brand,
    p_expiry_month, p_expiry_year, lpad(floor(random()*900+100)::int::text,3,'0'), p_spending_limit, p_status)
  returning * into v_card;

  perform public.notify_user(p_user_id, 'Card issued',
    'A new ' || p_card_type || ' ' || p_card_brand || ' card ending in ' || substr(v_number, 13, 4) || ' was issued.', 'card');
  perform public.log_audit(p_token, 'CREATE', 'card', v_card.id::text, null, jsonb_build_object('masked_number', v_masked, 'card_type', p_card_type, 'card_brand', p_card_brand));
  return jsonb_build_object('id', v_card.id, 'masked_number', v_masked, 'status', v_card.status);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Account number generation (collision-safe) + currency swap money safety
-- ---------------------------------------------------------------------------
create or replace function public.apply_balance_change(
  p_account_id uuid,
  p_delta numeric,
  p_currency text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
begin
  select * into v_account from public.accounts where id = p_account_id for update;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;
  if v_account.currency <> p_currency then
    raise exception 'CURRENCY_MISMATCH';
  end if;

  -- Read the current balance first so we can raise a friendly error instead of
  -- tripping the CHECK constraint. NOTE: an "insert ... on conflict do update"
  -- would evaluate available_balance >= 0 against the raw VALUES tuple (the delta
  -- alone), so negative deltas always failed even with sufficient funds.
  select available_balance into v_balance from public.account_balances
    where account_id = p_account_id for update;
  if v_balance is null then
    v_balance := 0;
  end if;
  if (v_balance + p_delta) < 0 then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  update public.account_balances
    set available_balance = available_balance + p_delta,
        ledger_balance     = ledger_balance + p_delta,
        updated_at         = now()
    where account_id = p_account_id;
  if not found then
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (p_account_id, p_delta, p_delta, p_currency)
    on conflict (account_id) do update
      set available_balance = account_balances.available_balance + excluded.available_balance,
          ledger_balance     = account_balances.ledger_balance + excluded.ledger_balance,
          updated_at         = now();
  end if;
end;
$$;

create or replace function public.generate_account_number()
returns text
language plpgsql
set search_path = public
as $$
declare v_num text;
begin
  loop
    v_num := '48' || lpad(floor(random() * 100000000000000)::bigint::text, 14, '0');
    exit when not exists (select 1 from public.accounts where account_number = v_num);
  end loop;
  return v_num;
end;
$$;

create or replace function public.create_currency_swap(
  p_user_id uuid,
  p_account_id uuid,
  p_from_currency text,
  p_to_currency text,
  p_from_amount numeric
)
returns public.currency_swaps
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
  v_dest_id uuid;
begin
  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if p_from_currency = p_to_currency then
    raise exception 'SAME_CURRENCY';
  end if;

  select rate, fee_percent into v_rate, v_fee_pct
    from public.exchange_rates
    where base_currency = p_from_currency and quote_currency = p_to_currency;
  if not found then
    raise exception 'RATE_NOT_AVAILABLE';
  end if;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);

  select available_balance into v_balance from public.account_balances where account_id = p_account_id;
  if v_balance is null or v_balance < (p_from_amount + v_fee) then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  v_to_amount := round((p_from_amount - v_fee) * v_rate, 2);

  select full_name into v_name from public.profiles where id = p_user_id;

  perform public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  insert into public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) values (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) returning * into v_swap;

  perform public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  perform public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00') || ' ' || p_to_currency || '.',
    'swap');

  -- Guarantee the converted funds are never lost: use an existing destination
  -- account or create one for the customer.
  select id into v_dest_id from public.accounts
    where user_id = p_user_id and currency = p_to_currency and status = 'active'
    order by created_at limit 1;
  if not found then
    insert into public.accounts (user_id, account_number, account_name, account_type, currency, status)
    values (p_user_id, public.generate_account_number(), coalesce(v_name, ''), 'checking', p_to_currency, 'active')
    returning id into v_dest_id;
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (v_dest_id, 0, 0, p_to_currency);
  end if;

  perform public.apply_balance_change(v_dest_id, v_to_amount, p_to_currency);
  perform public.record_transaction(
    p_user_id, v_dest_id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
  );

  return v_swap;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Security hardening: revoke internal SECURITY DEFINER helpers + hash fn
--    (must also revoke from PUBLIC, which holds default EXECUTE on functions)
-- ---------------------------------------------------------------------------
revoke execute on function public.apply_balance_change(uuid, numeric, text) from public, anon, authenticated;
revoke execute on function public.record_transaction(uuid, uuid, text, text, numeric, text, text, text, text, text, numeric, uuid) from public, anon, authenticated;
revoke execute on function public.notify_user(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.generate_reference(text) from public, anon, authenticated;
revoke execute on function public.admin_hash_password(text) from public, anon, authenticated;
revoke execute on function public.generate_card_number(text) from public, anon, authenticated;
revoke execute on function public.generate_account_number() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. system_settings: allow authenticated clients to read config (intl fee preview)
-- ---------------------------------------------------------------------------
drop policy if exists "system_settings_no_access" on public.system_settings;
drop policy if exists "system_settings_select_auth" on public.system_settings;
create policy "system_settings_select_auth" on public.system_settings
  for select using (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------------
-- 10. Loan repayments auto-marked overdue (row-level, recursion-safe)
-- ---------------------------------------------------------------------------
create or replace function public.refresh_repayment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'scheduled' and new.due_date < current_date then
    new.status := 'overdue';
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_repayment_status_tg on public.loan_repayments;
create trigger refresh_repayment_status_tg
  before insert or update on public.loan_repayments
  for each row execute procedure public.refresh_repayment_status();

-- ---------------------------------------------------------------------------
-- Grants for new/changed customer + admin functions
-- ---------------------------------------------------------------------------
grant execute on function public.create_currency_swap(uuid, uuid, text, text, numeric) to anon, authenticated;
grant execute on function public.admin_get_chart_data(text) to anon, authenticated;-- marvintlc - Migration 012
-- 4-digit customer security PIN
--  1. customer_pins table (bcrypt hash + failed-attempt lockout). No grants
--     and no RLS policies -> invisible and unmodifiable via the client API.
--  2. Internal hash/verify helpers (SECURITY DEFINER, revoked from clients).
--  3. Customer RPCs: set_customer_pin (setup/change), customer_verify_pin (login),
--     customer_has_pin (app-shell guard).
--  4. Signup: handle_new_user stores the hashed PIN from raw_user_meta_data.pin.
--  5. Every customer money-movement RPC now takes p_pin (backend-enforced) and
--     requires p_user_id to match auth.uid() (closes spoofed-user gap).
--  6. Deposit + loan-application creation converted to PIN-enforced RPCs.
--  7. Revokes/grants.

-- ---------------------------------------------------------------------------
-- 1. customer_pins (secret hash table)
-- ---------------------------------------------------------------------------
create table if not exists public.customer_pins (
  user_id         uuid primary key references public.profiles (id) on delete cascade,
  pin_hash        text not null,
  failed_attempts integer not null default 0,
  locked_until    timestamptz,
  updated_at      timestamptz not null default now()
);

alter table public.customer_pins enable row level security;
-- No policies and no grants: only SECURITY DEFINER functions (owner) can touch it.
-- Supabase's default ACLs grant anon/authenticated table privileges automatically,
-- so revoke them explicitly (RLS also blocks every row/policy-less access).
revoke all on table public.customer_pins from anon, authenticated, service_role;
comment on table public.customer_pins is 'Hashed 4-digit customer PIN. Not directly accessible via the API.';

-- ---------------------------------------------------------------------------
-- 2. Internal hash + verify helpers (with committed lockout)
-- ---------------------------------------------------------------------------
create or replace function public.hash_customer_pin(p_pin text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select crypt(p_pin, gen_salt('bf', 10));
$$;

-- Returns a status string; never raises for wrong/locked so the failed-attempt
-- counter and lock timestamp COMMIT with the calling statement (an exception
-- inside the same transaction would roll them back and defeat the lockout).
--   'ok'            -> correct PIN (attempts reset)
--   'invalid'       -> wrong PIN (attempt counter advanced / lock applied)
--   'invalid_format'-> PIN not exactly 4 digits
--   'not_set'       -> no PIN row
--   'locked'        -> locked_until is in the future
create or replace function public.verify_customer_pin(
  p_user_id uuid,
  p_pin     text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rec public.customer_pins%rowtype;
  v_ok   boolean;
  v_fail integer;
begin
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    return 'invalid_format';
  end if;

  select * into v_rec from public.customer_pins where user_id = p_user_id;
  if not found then
    return 'not_set';
  end if;

  -- An expired lock yields a fresh window of attempts.
  if v_rec.locked_until is not null and v_rec.locked_until <= now() then
    v_rec.failed_attempts := 0;
    v_rec.locked_until    := null;
  end if;
  if v_rec.locked_until is not null then
    return 'locked';
  end if;

  v_ok := crypt(p_pin, v_rec.pin_hash) = v_rec.pin_hash;
  if v_ok then
    update public.customer_pins
      set failed_attempts = 0, locked_until = null, updated_at = now()
      where user_id = p_user_id;
    return 'ok';
  end if;

  v_fail := v_rec.failed_attempts + 1;
  if v_fail >= 5 then
    update public.customer_pins
      set failed_attempts = 0, locked_until = now() + interval '15 minutes', updated_at = now()
      where user_id = p_user_id;
  else
    update public.customer_pins
      set failed_attempts = v_fail, updated_at = now()
      where user_id = p_user_id;
  end if;
  return 'invalid';
end;
$$;

-- Raise the correct exception for a PIN that must be satisfied (money RPCs).
create or replace function public.require_customer_pin(
  p_user_id uuid,
  p_pin     text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_status text := public.verify_customer_pin(p_user_id, p_pin);
begin
  if v_status = 'locked' then
    raise exception 'PIN_LOCKED';
  elsif v_status = 'not_set' then
    raise exception 'PIN_NOT_SET';
  elsif v_status <> 'ok' then
    raise exception 'INVALID_PIN';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Customer-facing PIN RPCs
-- ---------------------------------------------------------------------------
create or replace function public.set_customer_pin(
  p_pin         text,
  p_current_pin text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    raise exception 'INVALID_PIN_FORMAT';
  end if;
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- Changing an existing PIN requires the current PIN (first-time setup does not).
  if exists (select 1 from public.customer_pins where user_id = v_uid) then
    if p_current_pin is null or public.verify_customer_pin(v_uid, p_current_pin) <> 'ok' then
      raise exception 'INVALID_PIN';
    end if;
  end if;

  insert into public.customer_pins (user_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (v_uid, public.hash_customer_pin(p_pin), 0, null, now())
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
end;
$$;

-- Login / sensitive-op gate. Returns a JSON status (never raises except for
-- unauthenticated callers) so the counter commits and the UI can act on it.
create or replace function public.customer_verify_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid      uuid := auth.uid();
  v_status   text;
  v_attempts int;
  v_locked   timestamptz;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED';
  end if;
  v_status := public.verify_customer_pin(v_uid, p_pin);
  select failed_attempts, locked_until into v_attempts, v_locked
    from public.customer_pins where user_id = v_uid;
  return jsonb_build_object(
    'status', v_status,
    'attempts_left', greatest(0, 5 - coalesce(v_attempts, 0)),
    'locked_until', to_char(v_locked, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
end;
$$;

create or replace function public.customer_has_pin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.customer_pins where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- 4. Signup: store hashed PIN from raw_user_meta_data.pin
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_pin text := new.raw_user_meta_data ->> 'pin';
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;

  if v_pin is not null and v_pin ~ '^[0-9]{4}$' then
    insert into public.customer_pins (user_id, pin_hash, updated_at)
    values (new.id, public.hash_customer_pin(v_pin), now())
    on conflict (user_id) do update
      set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Money-movement RPCs: add p_pin + enforce auth.uid() ownership
-- ---------------------------------------------------------------------------
drop function if exists public.create_local_transfer(uuid, uuid, text, text, text, numeric, text, text, uuid);
create or replace function public.create_local_transfer(
  p_user_id               uuid,
  p_from_account_id       uuid,
  p_recipient_name        text,
  p_recipient_account_number text,
  p_recipient_bank        text,
  p_amount                numeric,
  p_currency              text,
  p_description           text,
  p_internal_recipient    uuid default null,
  p_pin                   text default null
)
returns public.local_transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_transfer public.local_transfers;
  v_sender_name text;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances
    where account_id = p_from_account_id;
  if v_balance is null or v_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select full_name into v_sender_name from public.profiles where id = p_user_id;

  v_fee := 0;

  perform public.apply_balance_change(p_from_account_id, -p_amount, p_currency);

  insert into public.local_transfers (
    reference, user_id, from_account_id, recipient_name, recipient_account_number,
    recipient_bank, amount, currency, fee, description, status, completed_at
  ) values (
    public.generate_reference('LT'), p_user_id, p_from_account_id, p_recipient_name,
    p_recipient_account_number, p_recipient_bank, p_amount, p_currency, v_fee,
    p_description, 'completed', now()
  ) returning * into v_transfer;

  perform public.record_transaction(
    p_user_id, p_from_account_id, 'local_transfer', 'debit', p_amount, p_currency,
    'completed', coalesce(p_description, 'Local transfer'),
    v_sender_name, p_recipient_name, v_fee, v_transfer.id
  );

  if p_internal_recipient is not null then
    declare
      v_dest public.accounts%rowtype;
    begin
      select * into v_dest from public.accounts
        where user_id = p_internal_recipient and currency = p_currency
        order by created_at limit 1;
      if found then
        perform public.apply_balance_change(v_dest.id, p_amount, p_currency);
        perform public.record_transaction(
          p_internal_recipient, v_dest.id, 'local_transfer', 'credit', p_amount, p_currency,
          'completed', 'Incoming local transfer', p_recipient_name, v_sender_name, 0, v_transfer.id
        );
        perform public.notify_user(p_internal_recipient,
          'Transfer received',
          'You received ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
          ' from ' || coalesce(v_sender_name, 'a customer') || '.',
          'transfer');
      end if;
    end;
  end if;

  perform public.notify_user(p_user_id,
    'Transfer completed',
    'Your transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' to ' || p_recipient_name || ' was completed. Ref: ' || v_transfer.reference || '.',
    'transfer');

  return v_transfer;
end;
$$;

drop function if exists public.create_currency_swap(uuid, uuid, text, text, numeric);
create or replace function public.create_currency_swap(
  p_user_id       uuid,
  p_account_id    uuid,
  p_from_currency text,
  p_to_currency   text,
  p_from_amount   numeric,
  p_pin           text default null,
  p_rate          numeric default null
)
returns public.currency_swaps
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
  v_dest_id uuid;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if p_from_currency = p_to_currency then
    raise exception 'SAME_CURRENCY';
  end if;

  -- Try table lookup first; fall back to frontend-supplied rate if missing
  select rate, fee_percent into v_rate, v_fee_pct
    from public.exchange_rates
    where base_currency = p_from_currency and quote_currency = p_to_currency;

  if v_rate is null and p_rate is not null and p_rate > 0 then
    v_rate := p_rate;
    v_fee_pct := 0.5;
    -- Upsert the rate for next time
    insert into public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
    values (p_from_currency, p_to_currency, p_rate, v_fee_pct)
    on conflict (base_currency, quote_currency) do update
      set rate = excluded.rate, fee_percent = excluded.fee_percent, updated_at = now();
  end if;

  if v_rate is null then
    raise exception 'RATE_NOT_AVAILABLE';
  end if;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);

  select available_balance into v_balance from public.account_balances where account_id = p_account_id;
  if v_balance is null or v_balance < (p_from_amount + v_fee) then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  v_to_amount := round((p_from_amount - v_fee) * v_rate, 2);

  select full_name into v_name from public.profiles where id = p_user_id;

  perform public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  insert into public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) values (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) returning * into v_swap;

  perform public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  perform public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00') || ' ' || p_to_currency || '.',
    'swap');

  select id into v_dest_id from public.accounts
    where user_id = p_user_id and currency = p_to_currency and status = 'active'
    order by created_at limit 1;
  if not found then
    insert into public.accounts (user_id, account_number, account_name, account_type, currency, status)
    values (p_user_id, public.generate_account_number(), coalesce(v_name, ''), 'checking', p_to_currency, 'active')
    returning id into v_dest_id;
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (v_dest_id, 0, 0, p_to_currency);
  end if;

  perform public.apply_balance_change(v_dest_id, v_to_amount, p_to_currency);
  perform public.record_transaction(
    p_user_id, v_dest_id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
  );

  return v_swap;
end;
$$;

drop function if exists public.pay_loan_repayment(uuid, uuid, uuid);
create or replace function public.pay_loan_repayment(
  p_user_id       uuid,
  p_repayment_id  uuid,
  p_account_id    uuid,
  p_pin           text default null
)
returns public.loan_repayments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_repayment public.loan_repayments%rowtype;
  v_account public.accounts%rowtype;
  v_balance numeric;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_repayment from public.loan_repayments
    where id = p_repayment_id and user_id = p_user_id and status = 'scheduled' for update;
  if not found then
    raise exception 'REPAYMENT_NOT_FOUND';
  end if;

  select * into v_account from public.accounts
    where id = p_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_account_id;
  if v_balance is null or v_balance < v_repayment.amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  perform public.apply_balance_change(p_account_id, -v_repayment.amount, v_repayment.currency);

  update public.loan_repayments
    set status = 'paid', paid_at = now(), reference = public.generate_reference('RP'),
        account_id = p_account_id
    where id = v_repayment.id
    returning * into v_repayment;

  perform public.record_transaction(
    p_user_id, p_account_id, 'loan_repayment', 'debit', v_repayment.amount, v_repayment.currency,
    'completed', 'Loan repayment', 'marvintlc',
    coalesce((select name from public.loan_products lp
      join public.loan_applications la on la.product_id = lp.id
      where la.id = v_repayment.loan_application_id), 'Loan repayment'),
    0, v_repayment.loan_application_id
  );

  update public.loan_applications set status = 'completed'
    where id = v_repayment.loan_application_id
      and not exists (
        select 1 from public.loan_repayments lr
        where lr.loan_application_id = v_repayment.loan_application_id and lr.status <> 'paid'
      );

  return v_repayment;
end;
$$;

drop function if exists public.create_international_transfer(uuid, uuid, text, text, text, text, text, numeric, text, text);
create or replace function public.create_international_transfer(
  p_user_id               uuid,
  p_from_account_id       uuid,
  p_recipient_name        text,
  p_recipient_bank        text,
  p_recipient_account_number text,
  p_swift_code            text,
  p_recipient_country     text,
  p_amount                numeric,
  p_currency              text,
  p_purpose               text default null,
  p_pin                   text default null
)
returns public.international_transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_rate numeric;
  v_xfer public.international_transfers;
  v_name text;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_from_account_id;
  if v_balance is null then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select coalesce((value::text)::numeric, 15) into v_fee
    from public.system_settings where key = 'intl_transfer_fee';
  if v_fee is null then v_fee := 15; end if;

  if v_balance < (p_amount + v_fee) then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  v_rate := 1;

  select full_name into v_name from public.profiles where id = p_user_id;

  perform public.apply_balance_change(p_from_account_id, -(p_amount + v_fee), p_currency);

  insert into public.international_transfers (
    reference, user_id, from_account_id, recipient_name, recipient_bank, recipient_account_number,
    swift_code, recipient_country, purpose, amount, currency, exchange_rate, fee,
    estimated_delivery, status, completed_at
  ) values (
    public.generate_reference('IT'), p_user_id, p_from_account_id, p_recipient_name, p_recipient_bank,
    p_recipient_account_number, p_swift_code, p_recipient_country, p_purpose, p_amount, p_currency,
    v_rate, v_fee, now() + interval '2 days', 'processing', null
  ) returning * into v_xfer;

  perform public.record_transaction(
    p_user_id, p_from_account_id, 'international_transfer', 'debit', p_amount, p_currency,
    'processing', coalesce(p_purpose, 'International transfer'),
    v_name, p_recipient_name || ' (' || p_recipient_country || ')', v_fee, v_xfer.id
  );

  perform public.notify_user(p_user_id,
    'International transfer submitted',
    'Your international transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' to ' || p_recipient_name || ' has been submitted. Ref: ' || v_xfer.reference || '.',
    'transfer');

  return v_xfer;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Deposit + loan-application creation (PIN-enforced RPCs)
-- ---------------------------------------------------------------------------
create or replace function public.create_customer_deposit(
  p_user_id    uuid,
  p_account_id uuid,
  p_amount     numeric,
  p_currency   text,
  p_method     text,
  p_note       text default null,
  p_pin        text default null
)
returns public.deposits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_deposit public.deposits;
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

  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if p_method is null or p_method not in ('cash', 'bank_transfer', 'cheque', 'card', 'online') then
    raise exception 'INVALID_METHOD';
  end if;

  insert into public.deposits (reference, user_id, account_id, amount, currency, method, note, status)
  values (
    public.generate_reference('DEP'), p_user_id, p_account_id, p_amount, p_currency, p_method,
    p_note, 'pending'
  ) returning * into v_deposit;

  perform public.notify_user(p_user_id,
    'Deposit submitted',
    'Your deposit request of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' was submitted for review. Ref: ' || v_deposit.reference || '.',
    'deposit');

  return v_deposit;
end;
$$;

create or replace function public.submit_loan_application(
  p_user_id      uuid,
  p_product_id   uuid,
  p_amount       numeric,
  p_term_months  int,
  p_purpose      text default null,
  p_pin          text default null
)
returns public.loan_applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.loan_products%rowtype;
  v_rate numeric;
  v_monthly numeric;
  v_loan public.loan_applications;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_product from public.loan_products where id = p_product_id and enabled = true;
  if not found then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;

  if p_amount is null or p_amount < v_product.min_amount or p_amount > v_product.max_amount then
    raise exception 'INVALID_AMOUNT';
  end if;
  if p_term_months is null or p_term_months <= 0 then
    raise exception 'INVALID_TERM';
  end if;

  v_rate := v_product.interest_rate;
  if v_rate = 0 then
    v_monthly := p_amount / p_term_months;
  else
    v_monthly := p_amount * (v_rate / 100 / 12) /
      (1 - power(1 + (v_rate / 100 / 12), -p_term_months));
  end if;

  insert into public.loan_applications (
    reference, user_id, product_id, amount, currency, term_months, interest_rate,
    monthly_payment, purpose, status
  ) values (
    public.generate_reference('LN'), p_user_id, p_product_id, p_amount, 'USD',
    p_term_months, v_rate, round(v_monthly, 2), p_purpose, 'pending'
  ) returning * into v_loan;

  return v_loan;
end;
$$;

-- Card control RPCs (PIN-enforced, ownership-checked)
create or replace function public.customer_freeze_card(
  p_user_id uuid,
  p_card_id uuid,
  p_pin     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card public.cards%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_card from public.cards where id = p_card_id and user_id = p_user_id for update;
  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  update public.cards set status = 'frozen', updated_at = now() where id = p_card_id;
  perform public.notify_user(p_user_id, 'Card frozen',
    'Your card ending ' || right(v_card.masked_number, 4) || ' has been frozen.', 'card');
end;
$$;

create or replace function public.customer_unfreeze_card(
  p_user_id uuid,
  p_card_id uuid,
  p_pin     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card public.cards%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  select * into v_card from public.cards where id = p_card_id and user_id = p_user_id for update;
  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  update public.cards set status = 'active', updated_at = now() where id = p_card_id;
  perform public.notify_user(p_user_id, 'Card unfrozen',
    'Your card ending ' || right(v_card.masked_number, 4) || ' is active again.', 'card');
end;
$$;

create or replace function public.customer_set_card_limit(
  p_user_id uuid,
  p_card_id uuid,
  p_limit   numeric,
  p_pin     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card public.cards%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);

  if p_limit is null or p_limit < 0 then
    raise exception 'INVALID_LIMIT';
  end if;

  select * into v_card from public.cards where id = p_card_id and user_id = p_user_id for update;
  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  update public.cards set spending_limit = p_limit, updated_at = now() where id = p_card_id;
  perform public.notify_user(p_user_id, 'Card limit updated',
    'Your card ending ' || right(v_card.masked_number, 4) || ' spending limit is now ' ||
    to_char(p_limit, 'FM9,999,999,990.00') || '.', 'card');
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Revokes + grants
-- ---------------------------------------------------------------------------
revoke execute on function public.hash_customer_pin(text) from public, anon, authenticated;
revoke execute on function public.verify_customer_pin(uuid, text) from public, anon, authenticated;
revoke execute on function public.require_customer_pin(uuid, text) from public, anon, authenticated;

grant execute on function public.set_customer_pin(text, text) to anon, authenticated;
grant execute on function public.customer_verify_pin(text) to anon, authenticated;
grant execute on function public.customer_has_pin() to anon, authenticated;

grant execute on function public.create_local_transfer(uuid, uuid, text, text, text, numeric, text, text, uuid, text) to anon, authenticated;
grant execute on function public.create_currency_swap(uuid, uuid, text, text, numeric, text, numeric) to anon, authenticated;
grant execute on function public.pay_loan_repayment(uuid, uuid, uuid, text) to anon, authenticated;
grant execute on function public.create_international_transfer(uuid, uuid, text, text, text, text, text, numeric, text, text, text) to anon, authenticated;
grant execute on function public.create_customer_deposit(uuid, uuid, numeric, text, text, text, text) to anon, authenticated;
grant execute on function public.submit_loan_application(uuid, uuid, numeric, integer, text, text) to anon, authenticated;
grant execute on function public.customer_freeze_card(uuid, uuid, text) to anon, authenticated;
grant execute on function public.customer_unfreeze_card(uuid, uuid, text) to anon, authenticated;
grant execute on function public.customer_set_card_limit(uuid, uuid, numeric, text) to anon, authenticated;-- marvintlc - Migration 013
-- Auto-issue a default card for every new account created at signup so the
-- Cards section is never empty after registration.

-- handle_new_profile already runs on every profile insert (which every signup
-- and every admin-created user triggers). Extend it to also issue a default
-- debit card linked to the freshly created account. The whole block runs in
-- the same transaction as the auth.users insert, so if card creation ever
-- fails the entire signup rolls back - no account without a card, and no
-- partial profile/account/card state.
create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_base text;
  v_card_number text;
  v_card_brand text;
  v_masked text;
  v_holder text;
  v_exp_month int;
  v_exp_year int;
begin
  select code into v_base from public.currencies where is_base = true limit 1;
  if not found then
    v_base := 'USD';
  end if;

  insert into public.accounts (user_id, account_number, account_name, account_type, currency)
  values (
    new.id,
    '48' || lpad(floor(random() * 100000000000000000)::bigint::text, 14, '0'),
    new.full_name,
    'checking',
    v_base
  )
  on conflict do nothing
  returning id into v_account_id;

  if found then
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (v_account_id, 0, 0, v_base)
    on conflict (account_id) do nothing;

    -- Auto-issue a default debit card for the new account. The number is
    -- Luhn-valid and uniqueness-checked inside generate_card_number.
    v_card_brand := 'mastercard';
    v_card_number := public.generate_card_number(v_card_brand);
    v_masked := substr(v_card_number, 1, 4) || ' •••• •••• ' || substr(v_card_number, 13, 4);
    v_holder := coalesce(nullif(new.full_name, ''), 'Card Holder');
    v_exp_month := extract(month from now())::int;
    v_exp_year := (extract(year from now())::int) + 4;

    insert into public.cards (user_id, account_id, card_number, masked_number, card_holder, card_type,
      card_brand, expiry_month, expiry_year, cvv, spending_limit, status)
    values (new.id, v_account_id, v_card_number, v_masked, v_holder, 'debit', v_card_brand,
      v_exp_month, v_exp_year, lpad(floor(random() * 900 + 100)::int::text, 3, '0'), 10000, 'active');

    insert into public.notifications (user_id, title, message, type)
    values (new.id, 'Your card is ready',
      'A debit ' || v_card_brand || ' card ending in ' || substr(v_card_number, 13, 4) ||
      ' was issued to your account.', 'card');

    insert into public.notifications (user_id, title, message, type)
    values (new.id, 'Welcome to marvintlc',
      'Your account has been created. Explore your dashboard to get started.', 'account');
  end if;

  return new;
end;
$$;

-- Backfill: give every existing profile without a card a default card too
-- (idempotent). Uses the base account so the card is linked to the primary
-- checking account, mirroring what new signups receive.
with gen as (
  select
    p.id        as user_id,
    a.id        as account_id,
    public.generate_card_number('mastercard') as card_number,
    coalesce(nullif(p.full_name, ''), 'Card Holder') as holder
  from public.profiles p
  join lateral (
    select a.id from public.accounts a where a.user_id = p.id order by a.created_at limit 1
  ) a on true
  where not exists (select 1 from public.cards c where c.user_id = p.id)
)
insert into public.cards (user_id, account_id, card_number, masked_number, card_holder, card_type,
  card_brand, expiry_month, expiry_year, cvv, spending_limit, status)
select
  user_id,
  account_id,
  card_number,
  substr(card_number, 1, 4) || ' •••• •••• ' || substr(card_number, 13, 4),
  holder,
  'debit',
  'mastercard',
  extract(month from now())::int,
  (extract(year from now())::int) + 4,
  lpad(floor(random() * 900 + 100)::int::text, 3, '0'),
  10000,
  'active'
from gen;-- marvintlc - Migration 014
-- Auto-issued cards default to the mastercard brand (dark card face) instead of
-- visa (blue card face).

create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_base text;
  v_card_number text;
  v_card_brand text;
  v_masked text;
  v_holder text;
  v_exp_month int;
  v_exp_year int;
begin
  select code into v_base from public.currencies where is_base = true limit 1;
  if not found then
    v_base := 'USD';
  end if;

  insert into public.accounts (user_id, account_number, account_name, account_type, currency)
  values (
    new.id,
    '48' || lpad(floor(random() * 100000000000000000)::bigint::text, 14, '0'),
    new.full_name,
    'checking',
    v_base
  )
  on conflict do nothing
  returning id into v_account_id;

  if found then
    insert into public.account_balances (account_id, available_balance, ledger_balance, currency)
    values (v_account_id, 0, 0, v_base)
    on conflict (account_id) do nothing;

    -- Auto-issue a default debit card for the new account. The number is
    -- Luhn-valid and uniqueness-checked inside generate_card_number.
    v_card_brand := 'mastercard';
    v_card_number := public.generate_card_number(v_card_brand);
    v_masked := substr(v_card_number, 1, 4) || ' •••• •••• ' || substr(v_card_number, 13, 4);
    v_holder := coalesce(nullif(new.full_name, ''), 'Card Holder');
    v_exp_month := extract(month from now())::int;
    v_exp_year := (extract(year from now())::int) + 4;

    insert into public.cards (user_id, account_id, card_number, masked_number, card_holder, card_type,
      card_brand, expiry_month, expiry_year, cvv, spending_limit, status)
    values (new.id, v_account_id, v_card_number, v_masked, v_holder, 'debit', v_card_brand,
      v_exp_month, v_exp_year, lpad(floor(random() * 900 + 100)::int::text, 3, '0'), 10000, 'active');

    insert into public.notifications (user_id, title, message, type)
    values (new.id, 'Your card is ready',
      'A debit ' || v_card_brand || ' card ending in ' || substr(v_card_number, 13, 4) ||
      ' was issued to your account.', 'card');

    insert into public.notifications (user_id, title, message, type)
    values (new.id, 'Welcome to marvintlc',
      'Your account has been created. Explore your dashboard to get started.', 'account');
  end if;

  return new;
end;
$$;

-- Restyle cards that were auto-issued by migration 013's backfill (the user's
-- only card, debit, visa) to mastercard so they match the new default color.
update public.cards c
  set card_brand = 'mastercard', updated_at = now()
where c.card_brand = 'visa'
  and c.card_type = 'debit'
  and (select count(*) from public.cards c2 where c2.user_id = c.user_id) = 1;-- marvintlc - Migration 015
-- Admin-controlled verification workflow for cryptocurrency withdrawals and
-- international transfers, plus per-customer outgoing-transfer restrictions.

-- ---------------------------------------------------------------------------
-- 1. Expand transfer status vocabularies
-- ---------------------------------------------------------------------------
alter table public.international_transfers drop constraint if exists international_transfers_status_check;
alter table public.international_transfers
  add constraint international_transfers_status_check check (status in (
    'pending', 'awaiting_admin_verification', 'processing', 'completed',
    'failed', 'cancelled', 'rejected', 'reversed'
  ));

alter table public.transactions drop constraint if exists transactions_status_check;
alter table public.transactions
  add constraint transactions_status_check check (status in (
    'pending', 'awaiting_admin_verification', 'processing', 'completed',
    'failed', 'cancelled', 'rejected', 'reversed'
  ));

-- ---------------------------------------------------------------------------
-- 2. Idempotency key for international transfers (prevents duplicate submits)
-- ---------------------------------------------------------------------------
alter table public.international_transfers add column if not exists request_id text;
create unique index if not exists uq_intl_transfer_request
  on public.international_transfers (user_id, request_id) where request_id is not null;

-- ---------------------------------------------------------------------------
-- 3. Per-customer outgoing transfer restriction
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists outgoing_transfers_enabled boolean not null default true;
alter table public.profiles
  add column if not exists outgoing_transfers_disabled_reason text;

-- ---------------------------------------------------------------------------
-- 4. Supported crypto assets (asset + network pairs)
-- ---------------------------------------------------------------------------
create table public.crypto_assets (
    asset         text not null,
    network       text not null,
    asset_label   text not null,
    network_label text not null,
    is_enabled    boolean not null default true,
    min_amount    numeric(20, 8) not null default 0,
    max_amount    numeric(20, 8) not null default 1000,
    rate_usd      numeric(20, 8) not null default 1,
    updated_at    timestamptz not null default now(),
    primary key (asset, network)
);

alter table public.crypto_assets enable row level security;
create policy "crypto_assets_select_all" on public.crypto_assets
  for select using (true);

insert into public.crypto_assets (asset, network, asset_label, network_label, is_enabled, min_amount, max_amount, rate_usd) values
  ('BTC',  'bitcoin', 'Bitcoin',    'Bitcoin (BTC)',              true, 0.0001, 5.0,   60000.0),
  ('ETH',  'erc20',   'Ethereum',   'Ethereum (ETH) · ERC-20',    true, 0.001,  50.0,  3000.0),
  ('USDT', 'trc20',   'Tether',     'Tether (USDT) · TRC-20',     true, 1,      20000, 1.0),
  ('USDT', 'erc20',   'Tether',     'Tether (USDT) · ERC-20',     true, 1,      20000, 1.0)
on conflict (asset, network) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Cryptocurrency withdrawals
-- ---------------------------------------------------------------------------
create table public.crypto_withdrawals (
    id              uuid primary key default gen_random_uuid(),
    reference       text not null unique,
    request_id      text,
    user_id         uuid not null references public.profiles (id) on delete cascade,
    from_account_id uuid not null references public.accounts (id),
    asset           text not null,
    network         text not null,
    wallet_address  text not null,
    amount          numeric(20, 8) not null check (amount > 0),
    amount_fiat     numeric(20, 2) not null,
    currency        text not null references public.currencies (code),
    rate            numeric(20, 8) not null default 1,
    fee             numeric(20, 2) not null default 0,
    status          text not null default 'pending' check (status in (
                      'pending', 'processing', 'completed', 'failed', 'cancelled', 'rejected', 'reversed'
                    )),
    completed_at    timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create unique index if not exists uq_crypto_withdrawal_request
  on public.crypto_withdrawals (user_id, request_id) where request_id is not null;
create index if not exists idx_crypto_wd_user  on public.crypto_withdrawals (user_id);
create index if not exists idx_crypto_wd_status on public.crypto_withdrawals (status);

alter table public.crypto_withdrawals enable row level security;
create policy "crypto_wd_select_own" on public.crypto_withdrawals
  for select using (auth.uid() = user_id);
create policy "crypto_wd_insert_own" on public.crypto_withdrawals
  for insert with check (auth.uid() = user_id);

create trigger touch_crypto_wd_updated before update on public.crypto_withdrawals
  for each row execute procedure public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Transfer verification codes (hashed, short-lived, single-use)
-- ---------------------------------------------------------------------------
-- Transfer verification codes (kept for potential future use, but no active transfer types require verification)
create table public.transfer_verification_codes (
    id           uuid primary key default gen_random_uuid(),
    transfer_type text not null check (transfer_type in ('local_transfer')),
    transfer_id  uuid not null,
    user_id      uuid not null references public.profiles (id) on delete cascade,
    code_hash    text not null,
    code_prefix  text not null,
    expires_at   timestamptz not null,
    max_attempts int not null default 3,
    attempts     int not null default 0,
    status       text not null default 'active' check (status in ('active', 'used', 'revoked', 'expired')),
    used_at      timestamptz,
    created_by   uuid references public.admin_users (id),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

create index if not exists idx_vcode_transfer on public.transfer_verification_codes (transfer_type, transfer_id);
create index if not exists idx_vcode_user on public.transfer_verification_codes (user_id);

-- Backend-only: no client policies.
alter table public.transfer_verification_codes enable row level security;
revoke all on table public.transfer_verification_codes from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Transfer verification attempt history (for admins + audit)
-- ---------------------------------------------------------------------------
create table public.transfer_verification_logs (
    id           uuid primary key default gen_random_uuid(),
    transfer_type text not null,
    transfer_id  uuid not null,
    code_id      uuid,
    user_id      uuid references public.profiles (id) on delete cascade,
    result       text not null,
    attempts     int not null default 1,
    created_at   timestamptz not null default now()
);

create index if not exists idx_vlog_transfer on public.transfer_verification_logs (transfer_type, transfer_id);

alter table public.transfer_verification_logs enable row level security;
revoke all on table public.transfer_verification_logs from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Permissions + roles
-- ---------------------------------------------------------------------------
update public.admin_roles
  set permissions = permissions || array['verifications.view', 'verifications.manage']
where name in ('super_admin', 'admin')
  and not (permissions @> array['verifications.manage']);

-- ---------------------------------------------------------------------------
-- 9. System settings
-- ---------------------------------------------------------------------------
insert into public.system_settings (key, value, description) values
  ('crypto_withdrawal_fee', '1.00', 'Flat cryptocurrency withdrawal fee'),
  ('verification_code_ttl_minutes', '30', 'Lifetime of a transfer verification code in minutes'),
  ('verification_code_max_attempts', '3', 'Maximum attempts before a verification code is invalidated')
on conflict (key) do nothing;-- marvintlc - Migration 016
-- RPCs for the admin-controlled verification workflow: transfer creation,
-- code generation/verification, admin review, and outgoing-transfer controls.

-- ---------------------------------------------------------------------------
-- Internal helpers (revoked from clients at the bottom)
-- ---------------------------------------------------------------------------

-- Secure, unambiguous verification code (no 0/O/1/I).
create or replace function public.generate_verification_code()
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text := '';
begin
  for v_i in 1..8 loop
    v_code := v_code || substr(v_chars, (get_byte(gen_random_bytes(1), 0) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- Hash a code for storage (codes are high-entropy + short-lived, SHA-256 is fine).
create or replace function public.hash_verification_code(p_code text)
returns text
language sql
stable
set search_path = public, extensions
as $$
  select encode(digest(trim(p_code)::bytea, 'sha256'), 'hex');
$$;

-- Raise if outgoing transfers are disabled for the customer.
create or replace function public.require_outgoing_transfers(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
begin
  select outgoing_transfers_enabled into v_enabled from public.profiles where id = p_user_id;
  if v_enabled is not true then
    raise exception 'OUTGOING_TRANSFERS_DISABLED';
  end if;
end;
$$;

-- Record a verification attempt (success or failure) for audit/history.
create or replace function public.log_verification_attempt(
  p_transfer_type text,
  p_transfer_id uuid,
  p_code_id uuid,
  p_user_id uuid,
  p_result text,
  p_attempts int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.transfer_verification_logs (transfer_type, transfer_id, code_id, user_id, result, attempts)
  values (p_transfer_type, p_transfer_id, p_code_id, p_user_id, p_result, p_attempts);
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer: create cryptocurrency withdrawal (awaiting admin verification)
-- ---------------------------------------------------------------------------
create or replace function public.create_crypto_withdrawal(
  p_user_id         uuid,
  p_from_account_id uuid,
  p_asset           text,
  p_network         text,
  p_wallet_address  text,
  p_amount          numeric,
  p_pin             text default null,
  p_request_id      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_asset public.crypto_assets%rowtype;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_amount_fiat numeric;
  v_wd public.crypto_withdrawals;
  v_created boolean := true;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);
  perform public.require_outgoing_transfers(p_user_id);

  select code into v_base from public.currencies where is_base = true limit 1;
  if not found then v_base := 'USD'; end if;

  select * into v_asset from public.crypto_assets
    where asset = p_asset and network = p_network and is_enabled;
  if not found then
    raise exception 'ASSET_NOT_SUPPORTED';
  end if;
  if p_amount is null or p_amount < v_asset.min_amount or p_amount > v_asset.max_amount then
    raise exception 'ASSET_LIMIT';
  end if;

  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;
  if v_account.currency <> v_base and v_account.currency <> p_asset then
    raise exception 'CRYPTO_REQUIRES_BASE_CURRENCY';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_from_account_id;
  if v_balance is null then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select coalesce((value::text)::numeric, 1) into v_fee
    from public.system_settings where key = 'crypto_withdrawal_fee';
  if v_fee is null then v_fee := 1; end if;

  -- If withdrawing from a BTC account, the amount is in BTC directly
  if v_account.currency = p_asset then
    if v_balance < (p_amount + v_fee) then
      raise exception 'INSUFFICIENT_FUNDS';
    end if;
    v_amount_fiat := round(p_amount * v_asset.rate_usd, 2);
    -- Debit BTC account directly
    perform public.apply_balance_change(p_from_account_id, -(p_amount + v_fee), p_asset);
  else
    -- Fiat account: convert to fiat equivalent
    v_amount_fiat := round(p_amount * v_asset.rate_usd, 2);
    if v_balance < (v_amount_fiat + v_fee) then
      raise exception 'INSUFFICIENT_FUNDS';
    end if;
    perform public.apply_balance_change(p_from_account_id, -(v_amount_fiat + v_fee), v_base);
  end if;

  insert into public.crypto_withdrawals (
    reference, request_id, user_id, from_account_id, asset, network, wallet_address,
    amount, amount_fiat, currency, rate, fee, status, completed_at
  ) values (
    public.generate_reference('CW'), p_request_id, p_user_id, p_from_account_id, p_asset, p_network,
    p_wallet_address, p_amount, v_amount_fiat, v_base, v_asset.rate_usd, v_fee,
    'completed', now()
  )
  on conflict (user_id, request_id) where request_id is not null do nothing
  returning * into v_wd;

  if not found then
    select * into v_wd from public.crypto_withdrawals
      where user_id = p_user_id and request_id = p_request_id;
    v_created := false;
  end if;

  if v_created then
    perform public.notify_user(p_user_id,
      'Crypto withdrawal completed',
      'Your withdrawal of ' || p_amount || ' ' || p_asset || ' to ' || p_wallet_address ||
      ' has been completed. Ref: ' || v_wd.reference || '.', 'transfer');
  end if;

  return jsonb_build_object(
    'id', v_wd.id, 'reference', v_wd.reference, 'status', v_wd.status,
    'created', v_created, 'amount', p_amount, 'asset', p_asset,
    'amount_fiat', v_amount_fiat, 'currency', v_base, 'fee', v_fee
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer: create international transfer (awaiting admin verification)
-- ---------------------------------------------------------------------------
drop function if exists public.create_international_transfer(uuid, uuid, text, text, text, text, text, numeric, text, text, text);
create or replace function public.create_international_transfer(
  p_user_id               uuid,
  p_from_account_id       uuid,
  p_recipient_name        text,
  p_recipient_bank        text,
  p_recipient_account_number text,
  p_swift_code            text,
  p_recipient_country     text,
  p_amount                numeric,
  p_currency              text,
  p_purpose               text default null,
  p_pin                   text default null,
  p_request_id            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_xfer public.international_transfers;
  v_created boolean := true;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);
  perform public.require_outgoing_transfers(p_user_id);

  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances where account_id = p_from_account_id;
  if v_balance is null then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select coalesce((value::text)::numeric, 15) into v_fee
    from public.system_settings where key = 'intl_transfer_fee';
  if v_fee is null then v_fee := 15; end if;

  if v_balance < (p_amount + v_fee) then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  insert into public.international_transfers (
    reference, request_id, user_id, from_account_id, recipient_name, recipient_bank,
    recipient_account_number, swift_code, recipient_country, purpose, amount, currency,
    exchange_rate, fee, estimated_delivery, status, completed_at
  ) values (
    public.generate_reference('IT'), p_request_id, p_user_id, p_from_account_id, p_recipient_name,
    p_recipient_bank, p_recipient_account_number, p_swift_code, p_recipient_country, p_purpose,
    p_amount, p_currency, 1, v_fee, now() + interval '2 days', 'completed', now()
  )
  on conflict (user_id, request_id) where request_id is not null do nothing
  returning * into v_xfer;

  if not found then
    select * into v_xfer from public.international_transfers
      where user_id = p_user_id and request_id = p_request_id;
    v_created := false;
  end if;

  -- Debit sender account immediately
  perform public.apply_balance_change(p_from_account_id, -(p_amount + v_fee), p_currency);

  -- Record transaction for sender
  perform public.record_transaction(
    p_user_id, p_from_account_id, 'international_transfer', 'debit', p_amount, p_currency,
    'completed', coalesce(p_purpose, 'International transfer'), v_sender_name,
    p_recipient_name || ' (' || p_recipient_country || ')', v_fee, v_xfer.id);

  if v_created then
    perform public.notify_user(p_user_id,
      'International transfer completed',
      'Your international transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
      ' to ' || p_recipient_name || ' has been completed. Ref: ' ||
      v_xfer.reference || '.', 'transfer');
  end if;

  return jsonb_build_object(
    'id', v_xfer.id, 'reference', v_xfer.reference, 'status', v_xfer.status,
    'created', v_created, 'amount', p_amount, 'currency', p_currency, 'fee', v_fee
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer: verify a transfer with the admin-issued one-time code
-- Returns a status jsonb instead of raising, so failed attempts persist and
-- the attempts counter commits even though the client sees an error.
-- ---------------------------------------------------------------------------
create or replace function public.customer_verify_transfer(
  p_transfer_type text,
  p_transfer_id   uuid,
  p_code          text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_code public.transfer_verification_codes%rowtype;
  v_hash text;
  v_fail integer;
  v_ref text;
  v_xfer public.international_transfers%rowtype;
  v_wd public.crypto_withdrawals%rowtype;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_name text;
begin
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal') then
    return jsonb_build_object('status', 'invalid_type');
  end if;
  if p_code is null or trim(p_code) = '' then
    return jsonb_build_object('status', 'invalid_format');
  end if;

  if p_transfer_type = 'international_transfer' then
    select user_id into v_uid from public.international_transfers where id = p_transfer_id;
  else
    select user_id into v_uid from public.crypto_withdrawals where id = p_transfer_id;
  end if;
  if v_uid is null or v_uid is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_code from public.transfer_verification_codes
    where transfer_type = p_transfer_type and transfer_id = p_transfer_id and user_id = v_uid
    order by created_at desc limit 1
    for update;

  if not found then
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, null, v_uid, 'no_code', 0);
    return jsonb_build_object('status', 'no_code');
  end if;

  -- Exhausted attempts invalidates the code (before expiry is even checked).
  if v_code.status = 'active' and v_code.attempts >= v_code.max_attempts then
    update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'attempts_exceeded', v_code.max_attempts);
    return jsonb_build_object('status', 'attempts_exceeded', 'attempts_left', 0);
  end if;

  if v_code.status = 'used' then
    return jsonb_build_object('status', 'used');
  end if;
  if v_code.status = 'revoked' then
    return jsonb_build_object('status', 'revoked');
  end if;
  if v_code.status = 'expired' then
    return jsonb_build_object('status', 'expired');
  end if;
  if v_code.expires_at <= now() then
    update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'expired', v_code.attempts);
    return jsonb_build_object('status', 'expired');
  end if;

  v_hash := public.hash_verification_code(p_code);
  if v_hash <> v_code.code_hash then
    v_fail := v_code.attempts + 1;
    update public.transfer_verification_codes set attempts = v_fail, updated_at = now() where id = v_code.id;
    if v_fail >= v_code.max_attempts then
      update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'attempts_exceeded', v_fail);
      return jsonb_build_object('status', 'attempts_exceeded', 'attempts_left', 0);
    else
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'invalid_code', v_fail);
    end if;
    return jsonb_build_object('status', 'invalid_code', 'attempts_left', greatest(0, v_code.max_attempts - v_fail));
  end if;

  -- Correct code: mark the code used and advance the transfer to processing.
  -- Funds are deducted NOW - never before verification completes.
  update public.transfer_verification_codes set status = 'used', used_at = now(), updated_at = now() where id = v_code.id;

  if p_transfer_type = 'international_transfer' then
    select * into v_xfer from public.international_transfers where id = p_transfer_id for update;
    select * into v_account from public.accounts where id = v_xfer.from_account_id for update;
    select available_balance into v_balance from public.account_balances where account_id = v_account.id;
    if v_balance is null or v_balance < (v_xfer.amount + v_xfer.fee) then
      update public.international_transfers set status = 'failed', updated_at = now() where id = v_xfer.id;
      perform public.notify_user(v_uid, 'International transfer failed',
        'Transfer ' || v_xfer.reference || ' could not be processed due to insufficient funds.', 'transfer');
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'failed_insufficient_funds', v_code.attempts + 1);
      return jsonb_build_object('status', 'failed_insufficient_funds', 'reference', v_xfer.reference);
    end if;
    perform public.apply_balance_change(v_account.id, -(v_xfer.amount + v_xfer.fee), v_account.currency);
    update public.international_transfers set status = 'processing', updated_at = now() where id = v_xfer.id;
    select full_name into v_name from public.profiles where id = v_uid;
    perform public.record_transaction(
      v_uid, v_account.id, 'international_transfer', 'debit', v_xfer.amount, v_account.currency,
      'processing', coalesce(v_xfer.purpose, 'International transfer'), v_name,
      v_xfer.recipient_name || ' (' || v_xfer.recipient_country || ')', v_xfer.fee, v_xfer.id);
    perform public.notify_user(v_uid, 'International transfer verified',
      'Transfer ' || v_xfer.reference || ' has been verified and is now processing.', 'transfer');
    v_ref := v_xfer.reference;
  else
    select * into v_wd from public.crypto_withdrawals where id = p_transfer_id for update;
    select * into v_account from public.accounts where id = v_wd.from_account_id for update;
    select available_balance into v_balance from public.account_balances where account_id = v_account.id;
    if v_balance is null or v_balance < (v_wd.amount_fiat + v_wd.fee) then
      update public.crypto_withdrawals set status = 'failed', updated_at = now() where id = v_wd.id;
      perform public.notify_user(v_uid, 'Crypto withdrawal failed',
        'Withdrawal ' || v_wd.reference || ' could not be processed due to insufficient funds.', 'transfer');
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'failed_insufficient_funds', v_code.attempts + 1);
      return jsonb_build_object('status', 'failed_insufficient_funds', 'reference', v_wd.reference);
    end if;
    perform public.apply_balance_change(v_account.id, -(v_wd.amount_fiat + v_wd.fee), v_account.currency);
    update public.crypto_withdrawals set status = 'processing', updated_at = now() where id = v_wd.id;
    select full_name into v_name from public.profiles where id = v_uid;
    perform public.record_transaction(
      v_uid, v_account.id, 'withdrawal', 'debit', v_wd.amount_fiat, v_account.currency,
      'processing', 'Crypto withdrawal ' || v_wd.amount || ' ' || v_wd.asset, v_name,
      v_wd.wallet_address, v_wd.fee, v_wd.id);
    perform public.notify_user(v_uid, 'Crypto withdrawal verified',
      'Withdrawal ' || v_wd.reference || ' has been verified and is now processing.', 'transfer');
    v_ref := v_wd.reference;
  end if;

  perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'success', v_code.attempts + 1);
  return jsonb_build_object('status', 'ok', 'reference', v_ref, 'transfer_id', p_transfer_id::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer: read-only verification status (never exposes the code itself)
-- ---------------------------------------------------------------------------
create or replace function public.customer_transfer_verification_status(
  p_transfer_type text,
  p_transfer_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_code public.transfer_verification_codes%rowtype;
begin
  if p_transfer_type = 'international_transfer' then
    select user_id into v_uid from public.international_transfers where id = p_transfer_id;
  elsif p_transfer_type = 'crypto_withdrawal' then
    select user_id into v_uid from public.crypto_withdrawals where id = p_transfer_id;
  else
    return jsonb_build_object('status', 'invalid_type');
  end if;
  if v_uid is null or v_uid is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_code from public.transfer_verification_codes
    where transfer_type = p_transfer_type and transfer_id = p_transfer_id and user_id = v_uid
    order by created_at desc limit 1;

  if not found then
    return jsonb_build_object('status', 'none');
  end if;
  return jsonb_build_object(
    'status', v_code.status,
    'code_issued', v_code.status in ('active', 'used', 'revoked', 'expired'),
    'attempts_left', greatest(0, v_code.max_attempts - v_code.attempts),
    'expires_at', v_code.expires_at,
    'code_prefix', v_code.code_prefix
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: pending verifications
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_transfer_verifications(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_intl jsonb;
  v_crypto jsonb;
begin
  if not public.admin_can(p_token, 'verifications.view') then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_intl
  from (
    select t.*, 'international_transfer' as transfer_type, p.full_name as user_name, p.email as user_email,
      vc.status as code_status, vc.code_prefix as code_prefix, vc.expires_at as code_expires_at,
      vc.attempts as code_attempts, vc.max_attempts as code_max_attempts, vc.id as code_id
    from public.international_transfers t
    join public.profiles p on p.id = t.user_id
    left join lateral (
      select v.* from public.transfer_verification_codes v
      where v.transfer_type = 'international_transfer' and v.transfer_id = t.id
      order by v.created_at desc limit 1
    ) vc on true
    where t.status = 'awaiting_admin_verification'
    order by t.created_at desc
  ) u;

  select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_crypto
  from (
    select t.*, 'crypto_withdrawal' as transfer_type, p.full_name as user_name, p.email as user_email,
      vc.status as code_status, vc.code_prefix as code_prefix, vc.expires_at as code_expires_at,
      vc.attempts as code_attempts, vc.max_attempts as code_max_attempts, vc.id as code_id
    from public.crypto_withdrawals t
    join public.profiles p on p.id = t.user_id
    left join lateral (
      select v.* from public.transfer_verification_codes v
      where v.transfer_type = 'crypto_withdrawal' and v.transfer_id = t.id
      order by v.created_at desc limit 1
    ) vc on true
    where t.status = 'awaiting_admin_verification'
    order by t.created_at desc
  ) u;

  return jsonb_build_object(
    'international', v_intl,
    'crypto', v_crypto,
    'total', jsonb_array_length(v_intl) + jsonb_array_length(v_crypto)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: verification history for one transfer
-- ---------------------------------------------------------------------------
create or replace function public.admin_transfer_verification_history(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_transfer jsonb;
  v_codes jsonb;
  v_logs jsonb;
begin
  if not public.admin_can(p_token, 'verifications.view') then
    raise exception 'FORBIDDEN';
  end if;

  if p_transfer_type = 'international_transfer' then
    select to_jsonb(t) into v_transfer from public.international_transfers t where id = p_transfer_id;
  elsif p_transfer_type = 'crypto_withdrawal' then
    select to_jsonb(t) into v_transfer from public.crypto_withdrawals t where id = p_transfer_id;
  else
    raise exception 'INVALID_TYPE';
  end if;
  if v_transfer is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.id, 'status', v.status, 'code_prefix', v.code_prefix, 'created_at', v.created_at,
    'used_at', v.used_at, 'expires_at', v.expires_at, 'attempts', v.attempts, 'max_attempts', v.max_attempts,
    'created_by', (select au.email from public.admin_users au where au.id = v.created_by)
  ) order by v.created_at), '[]') into v_codes
  from public.transfer_verification_codes v
  where v.transfer_type = p_transfer_type and v.transfer_id = p_transfer_id;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at), '[]') into v_logs
  from public.transfer_verification_logs l
  where l.transfer_type = p_transfer_type and l.transfer_id = p_transfer_id;

  return jsonb_build_object('transfer', v_transfer, 'codes', v_codes, 'logs', v_logs);
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: approve (issues a single-use code) / reject a transfer
-- ---------------------------------------------------------------------------
create or replace function public.admin_approve_transfer(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_status text;
  v_code text;
  v_hash text;
  v_prefix text;
  v_ttl_min int;
  v_max_attempts int;
  v_expires timestamptz;
  v_code_id uuid;
  v_old jsonb;
begin
  if not public.admin_can(p_token, 'verifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal') then
    raise exception 'INVALID_TYPE';
  end if;

  if p_transfer_type = 'international_transfer' then
    select status, to_jsonb(t) into v_status, v_old from public.international_transfers t where id = p_transfer_id;
  else
    select status, to_jsonb(t) into v_status, v_old from public.crypto_withdrawals t where id = p_transfer_id;
  end if;
  if v_old is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  if v_status <> 'awaiting_admin_verification' then
    raise exception 'TRANSFER_NOT_VERIFIABLE';
  end if;

  v_admin := public.admin_from_token(p_token);

  -- Invalidate any previously active code for this transfer (revoke before re-issue).
  update public.transfer_verification_codes
    set status = 'revoked', updated_at = now()
  where transfer_type = p_transfer_type and transfer_id = p_transfer_id and status = 'active';

  select coalesce((value::text)::int, 30) into v_ttl_min
    from public.system_settings where key = 'verification_code_ttl_minutes';
  if v_ttl_min is null then v_ttl_min := 30; end if;
  select coalesce((value::text)::int, 3) into v_max_attempts
    from public.system_settings where key = 'verification_code_max_attempts';
  if v_max_attempts is null then v_max_attempts := 3; end if;

  v_code := public.generate_verification_code();
  v_hash := public.hash_verification_code(v_code);
  v_prefix := '••••-' || right(v_code, 4);
  v_expires := now() + (v_ttl_min * interval '1 minute');

  insert into public.transfer_verification_codes (
    transfer_type, transfer_id, user_id, code_hash, code_prefix, expires_at, max_attempts, attempts, status, created_by
  )
  select p_transfer_type, p_transfer_id,
    case when p_transfer_type = 'international_transfer' then (select user_id from public.international_transfers where id = p_transfer_id)
         else (select user_id from public.crypto_withdrawals where id = p_transfer_id) end,
    v_hash, v_prefix, v_expires, v_max_attempts, 0, 'active', v_admin.id
  returning id into v_code_id;

  perform public.log_audit(p_token, 'APPROVE_TRANSFER', p_transfer_type, p_transfer_id::text, v_old,
    jsonb_build_object('status', 'approved', 'code_id', v_code_id::text));
  perform public.log_audit(p_token, 'GENERATE_CODE', 'transfer_verification_code', v_code_id::text, null,
    jsonb_build_object('transfer_type', p_transfer_type, 'transfer_id', p_transfer_id::text, 'code_prefix', v_prefix, 'expires_at', v_expires));

  -- The plaintext code is returned ONLY to the authorized admin, never stored.
  return jsonb_build_object('code', v_code, 'code_prefix', v_prefix, 'code_id', v_code_id::text, 'expires_at', v_expires);
end;
$$;

create or replace function public.admin_reject_transfer(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
  v_status text;
  v_user_id uuid;
begin
  if not public.admin_can(p_token, 'verifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal') then
    raise exception 'INVALID_TYPE';
  end if;

  if p_transfer_type = 'international_transfer' then
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id
      from public.international_transfers t where id = p_transfer_id for update;
  else
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id
      from public.crypto_withdrawals t where id = p_transfer_id for update;
  end if;
  if v_old is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  if v_status <> 'awaiting_admin_verification' then
    raise exception 'TRANSFER_NOT_VERIFIABLE';
  end if;

  update public.transfer_verification_codes
    set status = 'revoked', updated_at = now()
  where transfer_type = p_transfer_type and transfer_id = p_transfer_id and status = 'active';

  if p_transfer_type = 'international_transfer' then
    update public.international_transfers set status = 'rejected', updated_at = now() where id = p_transfer_id;
  else
    update public.crypto_withdrawals set status = 'rejected', updated_at = now() where id = p_transfer_id;
  end if;

  perform public.notify_user(v_user_id, 'Transfer rejected',
    'Your transfer was rejected by our verification team.' ||
    case when p_reason is not null and p_reason <> '' then ' Reason: ' || p_reason else '' end ||
    '. Contact support for details.', 'transfer');

  perform public.log_audit(p_token, 'REJECT_TRANSFER', p_transfer_type, p_transfer_id::text, v_old,
    jsonb_build_object('status', 'rejected', 'reason', coalesce(p_reason, '')));
end;
$$;

create or replace function public.admin_revoke_transfer_code(p_token text, p_code_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
begin
  if not public.admin_can(p_token, 'verifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(v) into v_old from public.transfer_verification_codes v where id = p_code_id;
  if not found then
    raise exception 'CODE_NOT_FOUND';
  end if;
  update public.transfer_verification_codes set status = 'revoked', updated_at = now() where id = p_code_id;
  perform public.log_audit(p_token, 'REVOKE_CODE', 'transfer_verification_code', p_code_id::text, v_old,
    jsonb_build_object('status', 'revoked'));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: complete / manage crypto withdrawal + sync intl transaction status
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_crypto_withdrawal(
  p_token text,
  p_withdrawal_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
  v_wd public.crypto_withdrawals%rowtype;
begin
  if not public.admin_can(p_token, 'transfers.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_wd from public.crypto_withdrawals where id = p_withdrawal_id for update;
  if not found then
    raise exception 'WITHDRAWAL_NOT_FOUND';
  end if;
  select to_jsonb(v_wd) into v_old;
  update public.crypto_withdrawals set status = p_status,
    completed_at = case when p_status = 'completed' then now() else completed_at end,
    updated_at = now()
  where id = p_withdrawal_id;
  update public.transactions set status = p_status, updated_at = now() where related_id = p_withdrawal_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'crypto_withdrawal', p_withdrawal_id::text, v_old,
    jsonb_build_object('status', p_status));
end;
$$;

create or replace function public.admin_update_intl_transfer(
  p_token text, p_transfer_id uuid, p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_old jsonb;
begin
  if not public.admin_can(p_token, 'transfers.manage') then
    raise exception 'FORBIDDEN';
  end if;
  select to_jsonb(t) into v_old from public.international_transfers t where id = p_transfer_id;
  if not found then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  update public.international_transfers set status = p_status,
    completed_at = case when p_status = 'completed' then now() else completed_at end,
    updated_at = now()
  where id = p_transfer_id;
  update public.transactions set status = p_status, updated_at = now() where related_id = p_transfer_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'international_transfer', p_transfer_id::text, v_old, jsonb_build_object('status', p_status));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: outgoing-transfer restriction (account-level setting)
-- ---------------------------------------------------------------------------
create or replace function public.admin_toggle_outgoing_transfers(
  p_token text,
  p_user_id uuid,
  p_enabled boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
begin
  if not public.admin_can(p_token, 'users.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if not p_enabled and (p_reason is null or trim(p_reason) = '') then
    raise exception 'REASON_REQUIRED';
  end if;
  select to_jsonb(p) into v_old from public.profiles p where id = p_user_id;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;
  update public.profiles set
    outgoing_transfers_enabled = p_enabled,
    outgoing_transfers_disabled_reason = case when p_enabled then null else p_reason end,
    updated_at = now()
  where id = p_user_id;
  perform public.log_audit(p_token, 'TOGGLE_OUTGOING_TRANSFERS', 'profile', p_user_id::text, v_old,
    jsonb_build_object('outgoing_transfers_enabled', p_enabled, 'reason', case when p_enabled then null else p_reason end));
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants + revokes
-- ---------------------------------------------------------------------------
revoke execute on function public.generate_verification_code() from public, anon, authenticated;
revoke execute on function public.hash_verification_code(text) from public, anon, authenticated;
revoke execute on function public.require_outgoing_transfers(uuid) from public, anon, authenticated;
revoke execute on function public.log_verification_attempt(text, uuid, uuid, uuid, text, int) from public, anon, authenticated;

grant execute on function public.create_crypto_withdrawal(uuid, uuid, text, text, text, numeric, text, text) to anon, authenticated;
grant execute on function public.create_international_transfer(uuid, uuid, text, text, text, text, text, numeric, text, text, text, text) to anon, authenticated;
grant execute on function public.customer_verify_transfer(text, uuid, text) to anon, authenticated;
grant execute on function public.customer_transfer_verification_status(text, uuid) to anon, authenticated;

grant execute on function public.admin_list_transfer_verifications(text) to anon, authenticated;
grant execute on function public.admin_transfer_verification_history(text, text, uuid) to anon, authenticated;
grant execute on function public.admin_approve_transfer(text, text, uuid) to anon, authenticated;
grant execute on function public.admin_reject_transfer(text, text, uuid, text) to anon, authenticated;
grant execute on function public.admin_revoke_transfer_code(text, uuid) to anon, authenticated;
grant execute on function public.admin_update_crypto_withdrawal(text, uuid, text) to anon, authenticated;
grant execute on function public.admin_toggle_outgoing_transfers(text, uuid, boolean, text) to anon, authenticated;-- marvintlc - Migration 017
-- Promote existing user anomflash@gmail.com to super_admin

INSERT INTO public.admin_users (email, password_hash, full_name, role_id, status)
SELECT
  'anomflash@gmail.com',
  au.encrypted_password,
  COALESCE(p.full_name, 'Flash Admin'),
  ar.id,
  'active'
FROM auth.users au
JOIN public.admin_roles ar ON ar.name = 'super_admin'
LEFT JOIN public.profiles p ON p.email = au.email
WHERE au.email = 'anomflash@gmail.com'
ON CONFLICT (email) DO UPDATE SET
  role_id = EXCLUDED.role_id,
  status = 'active',
  full_name = EXCLUDED.full_name;
-- Migration 018: Live exchange rates support
-- Adds display_currency to profiles, lookup RPC for transfers,
-- and modifies create_currency_swap to accept a live rate parameter.

-- 1. Add display_currency column to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS display_currency text DEFAULT 'USD'
  REFERENCES public.currencies(code);

-- 2. SECURITY DEFINER function to look up account owner by account number
--    (bypasses RLS on accounts table for internal transfer recipient lookup)
CREATE OR REPLACE FUNCTION public.lookup_account_user_id(p_account_number text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT user_id FROM public.accounts
  WHERE account_number = p_account_number AND status = 'active'
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.lookup_account_user_id(text) TO authenticated;

-- 3. Modify create_currency_swap to accept an optional live rate parameter
--    When p_rate is provided, it is used with a sanity check against the table rate.
--    When not provided, falls back to the table rate (backward compatible).
DROP FUNCTION IF EXISTS public.create_currency_swap(uuid, uuid, text, text, numeric, text);
CREATE OR REPLACE FUNCTION public.create_currency_swap(
  p_user_id       uuid,
  p_account_id    uuid,
  p_from_currency text,
  p_to_currency   text,
  p_from_amount   numeric,
  p_rate          numeric default null,
  p_pin           text default null
)
RETURNS public.currency_swaps
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
  v_dest_id uuid;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  PERFORM public.require_customer_pin(p_user_id, p_pin);

  SELECT * INTO v_account FROM public.accounts
    WHERE id = p_account_id AND user_id = p_user_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT';
  END IF;

  IF p_from_currency = p_to_currency THEN
    RAISE EXCEPTION 'SAME_CURRENCY';
  END IF;

  -- Get fee percentage and fallback rate from exchange_rates table
  SELECT rate, fee_percent INTO v_rate, v_fee_pct
    FROM public.exchange_rates
    WHERE base_currency = p_from_currency AND quote_currency = p_to_currency;

  -- Use live rate if provided, with sanity check (must be within 50% of table rate)
  IF p_rate IS NOT NULL THEN
    IF v_rate IS NOT NULL AND v_rate > 0 THEN
      IF abs(p_rate - v_rate) / v_rate > 0.5 THEN
        RAISE EXCEPTION 'RATE_STALE';
      END IF;
    END IF;
    v_rate := p_rate;
  END IF;

  IF v_rate IS NULL OR v_rate <= 0 THEN
    RAISE EXCEPTION 'RATE_NOT_AVAILABLE';
  END IF;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);

  SELECT available_balance INTO v_balance FROM public.account_balances WHERE account_id = p_account_id;
  IF v_balance IS NULL OR v_balance < (p_from_amount + v_fee) THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS';
  END IF;

  v_to_amount := round((p_from_amount - v_fee) * v_rate, 2);

  SELECT full_name INTO v_name FROM public.profiles WHERE id = p_user_id;

  PERFORM public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  INSERT INTO public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) VALUES (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) RETURNING * INTO v_swap;

  PERFORM public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  PERFORM public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00') || ' ' || p_to_currency || '.',
    'swap');

  SELECT id INTO v_dest_id FROM public.accounts
    WHERE user_id = p_user_id AND currency = p_to_currency AND status = 'active'
    ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.accounts (user_id, account_number, account_name, account_type, currency, status)
    VALUES (p_user_id, public.generate_account_number(), coalesce(v_name, ''), 'checking', p_to_currency, 'active')
    RETURNING id INTO v_dest_id;
    INSERT INTO public.account_balances (account_id, available_balance, ledger_balance, currency)
    VALUES (v_dest_id, 0, 0, p_to_currency);
  END IF;

  PERFORM public.apply_balance_change(v_dest_id, v_to_amount, p_to_currency);
  PERFORM public.record_transaction(
    p_user_id, v_dest_id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
  );

  RETURN v_swap;
END;
$$;
-- Migration 019: Fix create_currency_swap — resolve conflicting definitions
-- from migrations 012 and 018. This is the SINGLE source of truth.
-- Adds p_rate as optional fallback, auto-seeds exchange_rates if missing.

-- 1. Seed exchange_rates rows if missing (idempotent)
DO $$ BEGIN
  INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
  VALUES ('USD', 'BTC', 0.00001200, 0.50)
  ON CONFLICT (base_currency, quote_currency) DO NOTHING;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
  VALUES ('BTC', 'USD', 83333.33, 0.50)
  ON CONFLICT (base_currency, quote_currency) DO NOTHING;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 2. Drop all prior overloaded signatures to avoid ambiguity
DROP FUNCTION IF EXISTS public.create_currency_swap(uuid, uuid, text, text, numeric);
DROP FUNCTION IF EXISTS public.create_currency_swap(uuid, uuid, text, text, numeric, text);
DROP FUNCTION IF EXISTS public.create_currency_swap(uuid, uuid, text, text, numeric, text, numeric);

-- 3. Definitive create_currency_swap
CREATE OR REPLACE FUNCTION public.create_currency_swap(
  p_user_id       uuid,
  p_account_id    uuid,
  p_from_currency text,
  p_to_currency   text,
  p_from_amount   numeric,
  p_pin           text DEFAULT NULL,
  p_rate          numeric DEFAULT NULL
)
RETURNS public.currency_swaps
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
  v_dest_id uuid;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  PERFORM public.require_customer_pin(p_user_id, p_pin);

  SELECT * INTO v_account FROM public.accounts
    WHERE id = p_account_id AND user_id = p_user_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT';
  END IF;

  IF p_from_currency = p_to_currency THEN
    RAISE EXCEPTION 'SAME_CURRENCY';
  END IF;

  -- 1) Try table lookup for rate + fee
  SELECT rate, fee_percent INTO v_rate, v_fee_pct
    FROM public.exchange_rates
    WHERE base_currency = p_from_currency AND quote_currency = p_to_currency;

  -- 2) If no table row, use live rate from frontend
  IF v_rate IS NULL THEN
    IF p_rate IS NULL OR p_rate <= 0 THEN
      RAISE EXCEPTION 'RATE_NOT_AVAILABLE';
    END IF;
    v_rate := p_rate;
    v_fee_pct := 0.5;
    -- Cache it for next time
    INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
    VALUES (p_from_currency, p_to_currency, v_rate, v_fee_pct)
    ON CONFLICT (base_currency, quote_currency) DO UPDATE
      SET rate = EXCLUDED.rate, fee_percent = EXCLUDED.fee_percent, updated_at = now();
  ELSIF p_rate IS NOT NULL AND p_rate > 0 THEN
    -- Table row exists AND frontend sent a live rate: prefer the live rate
    -- but only if it's within 50% of the table rate (staleness guard)
    IF v_rate > 0 AND abs(p_rate - v_rate) / v_rate <= 0.5 THEN
      v_rate := p_rate;
    END IF;
  END IF;

  IF v_rate IS NULL OR v_rate <= 0 THEN
    RAISE EXCEPTION 'RATE_NOT_AVAILABLE';
  END IF;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);

  SELECT available_balance INTO v_balance FROM public.account_balances WHERE account_id = p_account_id;
  IF v_balance IS NULL OR v_balance < (p_from_amount + v_fee) THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS';
  END IF;

  v_to_amount := round((p_from_amount - v_fee) * v_rate, 8);

  SELECT full_name INTO v_name FROM public.profiles WHERE id = p_user_id;

  PERFORM public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  INSERT INTO public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) VALUES (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) RETURNING * INTO v_swap;

  PERFORM public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  PERFORM public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00000000') || ' ' || p_to_currency || '.',
    'swap');

  -- Find or create destination account
  SELECT id INTO v_dest_id FROM public.accounts
    WHERE user_id = p_user_id AND currency = p_to_currency AND status = 'active'
    ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.accounts (user_id, account_number, account_name, account_type, currency, status)
    VALUES (p_user_id, public.generate_account_number(), coalesce(v_name, ''), 'checking', p_to_currency, 'active')
    RETURNING id INTO v_dest_id;
    INSERT INTO public.account_balances (account_id, available_balance, ledger_balance, currency)
    VALUES (v_dest_id, 0, 0, p_to_currency);
  END IF;

  PERFORM public.apply_balance_change(v_dest_id, v_to_amount, p_to_currency);
  PERFORM public.record_transaction(
    p_user_id, v_dest_id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
  );

  RETURN v_swap;
END;
$$;

-- 4. Grant to client roles
GRANT EXECUTE ON FUNCTION public.create_currency_swap(uuid, uuid, text, text, numeric, text, numeric) TO anon, authenticated;
-- Migration 020: Nuclear fix for create_currency_swap
-- Dynamically drops ALL overloaded versions, then creates exactly one.

-- 1. Dynamically drop EVERY overloaded version
DO $$
DECLARE
  r RECORD;
  cnt int := 0;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'create_currency_swap'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    cnt := cnt + 1;
    RAISE NOTICE 'Dropped: %', r.sig;
  END LOOP;
  IF cnt = 0 THEN
    RAISE NOTICE 'No existing create_currency_swap functions found.';
  ELSE
    RAISE NOTICE 'Dropped % overload(s).', cnt;
  END IF;
END $$;

-- 2. Also clean up any orphaned grants that might block drops
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'create_currency_swap'
      AND pronamespace = 'public'::regnamespace
  LOOP
    BEGIN
      EXECUTE 'REVOKE ALL ON FUNCTION ' || r.sig || ' FROM anon, authenticated, service_role';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
      EXECUTE 'DROP FUNCTION ' || r.sig || ' CASCADE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

-- 3. Verify clean state (should return 0 rows)
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_proc
  WHERE proname = 'create_currency_swap'
    AND pronamespace = 'public'::regnamespace;
  RAISE NOTICE 'Remaining overloads after cleanup: %', v_count;
END $$;

-- 4. Seed exchange_rates if missing
DO $$ BEGIN
  INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
  VALUES ('USD', 'BTC', 0.00001200, 0.50)
  ON CONFLICT (base_currency, quote_currency) DO UPDATE
    SET rate = EXCLUDED.rate, fee_percent = EXCLUDED.fee_percent, updated_at = now();
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
  VALUES ('BTC', 'USD', 83333.33, 0.50)
  ON CONFLICT (base_currency, quote_currency) DO UPDATE
    SET rate = EXCLUDED.rate, fee_percent = EXCLUDED.fee_percent, updated_at = now();
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 5. Create the ONE AND ONLY version
CREATE OR REPLACE FUNCTION public.create_currency_swap(
  p_user_id       uuid,
  p_account_id    uuid,
  p_from_currency text,
  p_to_currency   text,
  p_from_amount   numeric,
  p_pin           text DEFAULT NULL,
  p_rate          numeric DEFAULT NULL
)
RETURNS public.currency_swaps
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate numeric;
  v_fee_pct numeric;
  v_fee numeric;
  v_to_amount numeric;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_swap public.currency_swaps;
  v_name text;
  v_dest_id uuid;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  PERFORM public.require_customer_pin(p_user_id, p_pin);

  SELECT * INTO v_account FROM public.accounts
    WHERE id = p_account_id AND user_id = p_user_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT';
  END IF;

  IF p_from_currency = p_to_currency THEN
    RAISE EXCEPTION 'SAME_CURRENCY';
  END IF;

  -- 1) Try table lookup
  SELECT rate, fee_percent INTO v_rate, v_fee_pct
    FROM public.exchange_rates
    WHERE base_currency = p_from_currency AND quote_currency = p_to_currency;

  -- 2) Fallback: use live rate from frontend
  IF v_rate IS NULL OR v_rate <= 0 THEN
    IF p_rate IS NULL OR p_rate <= 0 THEN
      RAISE EXCEPTION 'RATE_NOT_AVAILABLE';
    END IF;
    v_rate := p_rate;
    v_fee_pct := 0.5;
    INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, fee_percent)
    VALUES (p_from_currency, p_to_currency, v_rate, v_fee_pct)
    ON CONFLICT (base_currency, quote_currency) DO UPDATE
      SET rate = EXCLUDED.rate, fee_percent = EXCLUDED.fee_percent, updated_at = now();
  ELSIF p_rate IS NOT NULL AND p_rate > 0 THEN
    IF abs(p_rate - v_rate) / v_rate <= 0.5 THEN
      v_rate := p_rate;
    END IF;
  END IF;

  IF v_rate IS NULL OR v_rate <= 0 THEN
    RAISE EXCEPTION 'RATE_NOT_AVAILABLE';
  END IF;

  v_fee := round(p_from_amount * coalesce(v_fee_pct, 0) / 100, 2);

  SELECT available_balance INTO v_balance FROM public.account_balances WHERE account_id = p_account_id;
  IF v_balance IS NULL OR v_balance < (p_from_amount + v_fee) THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS';
  END IF;

  v_to_amount := round((p_from_amount - v_fee) * v_rate, 8);

  SELECT full_name INTO v_name FROM public.profiles WHERE id = p_user_id;

  PERFORM public.apply_balance_change(p_account_id, -(p_from_amount + v_fee), p_from_currency);

  INSERT INTO public.currency_swaps (
    reference, user_id, account_id, from_currency, to_currency, from_amount, to_amount,
    rate, fee, status
  ) VALUES (
    public.generate_reference('SW'), p_user_id, p_account_id, p_from_currency, p_to_currency,
    p_from_amount, v_to_amount, v_rate, v_fee, 'completed'
  ) RETURNING * INTO v_swap;

  PERFORM public.record_transaction(
    p_user_id, p_account_id, 'currency_swap', 'debit', p_from_amount, p_from_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    v_name, p_from_currency || ' -> ' || p_to_currency, v_fee, v_swap.id
  );

  SELECT id INTO v_dest_id FROM public.accounts
    WHERE user_id = p_user_id AND currency = p_to_currency AND status = 'active'
    ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.accounts (user_id, account_number, account_name, account_type, currency, status)
    VALUES (p_user_id, public.generate_account_number(), coalesce(v_name, ''), 'checking', p_to_currency, 'active')
    RETURNING id INTO v_dest_id;
    INSERT INTO public.account_balances (account_id, available_balance, ledger_balance, currency)
    VALUES (v_dest_id, 0, 0, p_to_currency);
  END IF;

  PERFORM public.apply_balance_change(v_dest_id, v_to_amount, p_to_currency);
  PERFORM public.record_transaction(
    p_user_id, v_dest_id, 'currency_swap', 'credit', v_to_amount, p_to_currency,
    'completed', 'Currency swap ' || p_from_currency || ' to ' || p_to_currency,
    p_from_currency || ' -> ' || p_to_currency, v_name, 0, v_swap.id
  );

  PERFORM public.notify_user(p_user_id,
    'Currency swap completed',
    'Swapped ' || to_char(p_from_amount, 'FM9,999,999,990.00') || ' ' || p_from_currency ||
    ' to ' || to_char(v_to_amount, 'FM9,999,999,990.00000000') || ' ' || p_to_currency || '.',
    'swap');

  RETURN v_swap;
END;
$$;

-- 6. Grant
GRANT EXECUTE ON FUNCTION public.create_currency_swap(uuid, uuid, text, text, numeric, text, numeric) TO anon, authenticated;

-- 7. Final verification
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT pg_get_function_identity_arguments(p.oid) AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.proname = 'create_currency_swap'
      AND n.nspname = 'public'
  LOOP
    RAISE NOTICE 'Final overload: %', r.sig;
  END LOOP;
END $$;
-- Migration 021: Add local_transfer to verification workflow
-- Fixes:
--  1. local_transfers.status now includes 'awaiting_admin_verification'
--  2. create_local_transfer no longer debits funds immediately — sets awaiting_admin_verification
--  3. customer_verify_transfer / customer_transfer_verification_status / admin_approve / admin_reject
--     all handle 'local_transfer' type
--  4. transfer_verification_codes.transfer_type now includes 'local_transfer'

-- 1. Expand local_transfers status check
alter table public.local_transfers
  drop constraint if exists local_transfers_status_check;
alter table public.local_transfers
  add constraint local_transfers_status_check check (status in (
    'pending', 'processing', 'completed', 'failed', 'cancelled', 'rejected', 'reversed', 'on_hold'
  ));

-- 2. Remove local_transfer from transfer_verification_codes (no longer needs verification)
alter table public.transfer_verification_codes
  drop constraint if exists transfer_verification_codes_transfer_type_check;
alter table public.transfer_verification_codes
  add constraint transfer_verification_codes_transfer_type_check check (transfer_type in (
    'international_transfer', 'crypto_withdrawal'
  ));

-- 3. Fix create_local_transfer — complete immediately, status = completed
create or replace function public.create_local_transfer(
  p_user_id               uuid,
  p_from_account_id       uuid,
  p_recipient_name        text,
  p_recipient_account_number text,
  p_recipient_bank        text,
  p_amount                numeric,
  p_currency              text,
  p_description           text,
  p_internal_recipient    uuid default null,
  p_pin                   text default null
)
returns public.local_transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_fee numeric;
  v_transfer public.local_transfers;
  v_sender_name text;
  v_dest public.accounts%rowtype;
begin
  if p_user_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  perform public.require_customer_pin(p_user_id, p_pin);
  perform public.require_outgoing_transfers(p_user_id);

  select * into v_account from public.accounts
    where id = p_from_account_id and user_id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'INVALID_ACCOUNT';
  end if;

  select available_balance into v_balance from public.account_balances
    where account_id = p_from_account_id;
  if v_balance is null or v_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  select full_name into v_sender_name from public.profiles where id = p_user_id;

  v_fee := 0;

  -- Debit sender account immediately
  perform public.apply_balance_change(p_from_account_id, -p_amount, p_currency);

  -- Create transfer with completed status
  insert into public.local_transfers (
    reference, user_id, from_account_id, recipient_name, recipient_account_number,
    recipient_bank, amount, currency, fee, description, status, completed_at
  ) values (
    public.generate_reference('LT'), p_user_id, p_from_account_id, p_recipient_name,
    p_recipient_account_number, p_recipient_bank, p_amount, p_currency, v_fee,
    p_description, 'completed', now()
  ) returning * into v_transfer;

  -- Record transaction for sender
  perform public.record_transaction(
    p_user_id, p_from_account_id, 'local_transfer', 'debit', p_amount, p_currency,
    'completed', coalesce(p_description, 'Local transfer'), v_sender_name,
    p_recipient_name, v_fee, v_transfer.id);

  -- Credit internal recipient if applicable
  if p_internal_recipient is not null then
    select * into v_dest from public.accounts
      where user_id = p_internal_recipient and currency = p_currency
      order by created_at limit 1;
    if found then
      perform public.apply_balance_change(v_dest.id, p_amount, p_currency);
      perform public.record_transaction(
        p_internal_recipient, v_dest.id, 'local_transfer', 'credit', p_amount, p_currency,
        'completed', 'Incoming local transfer', p_recipient_name, v_sender_name, 0, v_transfer.id);
      perform public.notify_user(p_internal_recipient,
        'Transfer received',
        'You received ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
        ' from ' || coalesce(v_sender_name, 'a customer') || '.',
        'transfer');
    end if;
  end if;

  perform public.notify_user(p_user_id,
    'Transfer completed',
    'Your transfer of ' || to_char(p_amount, 'FM9,999,999,990.00') || ' ' || p_currency ||
    ' to ' || p_recipient_name || ' has been completed. Ref: ' || v_transfer.reference || '.',
    'transfer');

  return v_transfer;
end;
$$;

grant execute on function public.create_local_transfer(uuid, uuid, text, text, text, numeric, text, text, uuid, text) to anon, authenticated;

-- 4. Add local_transfer to customer_verify_transfer
create or replace function public.customer_verify_transfer(
  p_transfer_type text,
  p_transfer_id   uuid,
  p_code          text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_code public.transfer_verification_codes%rowtype;
  v_hash text;
  v_fail integer;
  v_ref text;
  v_xfer public.international_transfers%rowtype;
  v_wd public.crypto_withdrawals%rowtype;
  v_lt public.local_transfers%rowtype;
  v_account public.accounts%rowtype;
  v_balance numeric;
  v_name text;
begin
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal', 'local_transfer') then
    return jsonb_build_object('status', 'invalid_type');
  end if;
  if p_code is null or trim(p_code) = '' then
    return jsonb_build_object('status', 'invalid_format');
  end if;

  if p_transfer_type = 'international_transfer' then
    select user_id into v_uid from public.international_transfers where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    select user_id into v_uid from public.local_transfers where id = p_transfer_id;
  else
    select user_id into v_uid from public.crypto_withdrawals where id = p_transfer_id;
  end if;
  if v_uid is null or v_uid is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_code from public.transfer_verification_codes
    where transfer_type = p_transfer_type and transfer_id = p_transfer_id and user_id = v_uid
    order by created_at desc limit 1
    for update;

  if not found then
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, null, v_uid, 'no_code', 0);
    return jsonb_build_object('status', 'no_code');
  end if;

  if v_code.status = 'active' and v_code.attempts >= v_code.max_attempts then
    update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'attempts_exceeded', v_code.max_attempts);
    return jsonb_build_object('status', 'attempts_exceeded', 'attempts_left', 0);
  end if;

  if v_code.status = 'used' then return jsonb_build_object('status', 'used'); end if;
  if v_code.status = 'revoked' then return jsonb_build_object('status', 'revoked'); end if;
  if v_code.status = 'expired' then return jsonb_build_object('status', 'expired'); end if;
  if v_code.expires_at <= now() then
    update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
    perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'expired', v_code.attempts);
    return jsonb_build_object('status', 'expired');
  end if;

  v_hash := public.hash_verification_code(p_code);
  if v_hash <> v_code.code_hash then
    v_fail := v_code.attempts + 1;
    update public.transfer_verification_codes set attempts = v_fail, updated_at = now() where id = v_code.id;
    if v_fail >= v_code.max_attempts then
      update public.transfer_verification_codes set status = 'expired', updated_at = now() where id = v_code.id;
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'attempts_exceeded', v_fail);
      return jsonb_build_object('status', 'attempts_exceeded', 'attempts_left', 0);
    else
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'invalid_code', v_fail);
    end if;
    return jsonb_build_object('status', 'invalid_code', 'attempts_left', greatest(0, v_code.max_attempts - v_fail));
  end if;

  -- Correct code: mark used, debit funds, advance to processing.
  update public.transfer_verification_codes set status = 'used', used_at = now(), updated_at = now() where id = v_code.id;

  if p_transfer_type = 'international_transfer' then
    select * into v_xfer from public.international_transfers where id = p_transfer_id for update;
    select * into v_account from public.accounts where id = v_xfer.from_account_id for update;
    select available_balance into v_balance from public.account_balances where account_id = v_account.id;
    if v_balance is null or v_balance < (v_xfer.amount + v_xfer.fee) then
      update public.international_transfers set status = 'failed', updated_at = now() where id = v_xfer.id;
      perform public.notify_user(v_uid, 'International transfer failed',
        'Transfer ' || v_xfer.reference || ' could not be processed due to insufficient funds.', 'transfer');
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'failed_insufficient_funds', v_code.attempts + 1);
      return jsonb_build_object('status', 'failed_insufficient_funds', 'reference', v_xfer.reference);
    end if;
    perform public.apply_balance_change(v_account.id, -(v_xfer.amount + v_xfer.fee), v_account.currency);
    update public.international_transfers set status = 'completed', completed_at = now(), updated_at = now() where id = v_xfer.id;
    select full_name into v_name from public.profiles where id = v_uid;
    perform public.record_transaction(
      v_uid, v_account.id, 'international_transfer', 'debit', v_xfer.amount, v_account.currency,
      'completed', coalesce(v_xfer.purpose, 'International transfer'), v_name,
      v_xfer.recipient_name || ' (' || v_xfer.recipient_country || ')', v_xfer.fee, v_xfer.id);
    perform public.notify_user(v_uid, 'Transfer completed',
      'Your transfer ' || v_xfer.reference || ' has been verified and completed.', 'transfer');
    v_ref := v_xfer.reference;

  elsif p_transfer_type = 'local_transfer' then
    select * into v_lt from public.local_transfers where id = p_transfer_id for update;
    select * into v_account from public.accounts where id = v_lt.from_account_id for update;
    select available_balance into v_balance from public.account_balances where account_id = v_account.id;
    if v_balance is null or v_balance < (v_lt.amount + v_lt.fee) then
      update public.local_transfers set status = 'failed', updated_at = now() where id = v_lt.id;
      perform public.notify_user(v_uid, 'Transfer failed',
        'Transfer ' || v_lt.reference || ' could not be processed due to insufficient funds.', 'transfer');
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'failed_insufficient_funds', v_code.attempts + 1);
      return jsonb_build_object('status', 'failed_insufficient_funds', 'reference', v_lt.reference);
    end if;
    perform public.apply_balance_change(v_account.id, -(v_lt.amount + v_lt.fee), v_account.currency);
    update public.local_transfers set status = 'completed', completed_at = now(), updated_at = now() where id = v_lt.id;
    select full_name into v_name from public.profiles where id = v_uid;
    perform public.record_transaction(
      v_uid, v_account.id, 'local_transfer', 'debit', v_lt.amount, v_account.currency,
      'completed', coalesce(v_lt.description, 'Local transfer'), v_name,
      v_lt.recipient_name, v_lt.fee, v_lt.id);
    perform public.notify_user(v_uid, 'Transfer completed',
      'Transfer ' || v_lt.reference || ' has been verified and completed.', 'transfer');

    -- Credit internal recipient if applicable
    if v_lt.internal_recipient_id is not null then
      declare
        v_dest public.accounts%rowtype;
      begin
        select * into v_dest from public.accounts
          where user_id = v_lt.internal_recipient_id and currency = v_lt.currency
          order by created_at limit 1;
        if found then
          perform public.apply_balance_change(v_dest.id, v_lt.amount, v_lt.currency);
          perform public.record_transaction(
            v_lt.internal_recipient_id, v_dest.id, 'local_transfer', 'credit', v_lt.amount, v_lt.currency,
            'completed', 'Incoming local transfer', v_lt.recipient_name, v_name, 0, v_lt.id);
          perform public.notify_user(v_lt.internal_recipient_id,
            'Transfer received',
            'You received ' || to_char(v_lt.amount, 'FM9,999,999,990.00') || ' ' || v_lt.currency ||
            ' from ' || coalesce(v_name, 'a customer') || '.',
            'transfer');
        end if;
      end;
    end if;

    v_ref := v_lt.reference;

  else
    select * into v_wd from public.crypto_withdrawals where id = p_transfer_id for update;
    select * into v_account from public.accounts where id = v_wd.from_account_id for update;
    select available_balance into v_balance from public.account_balances where account_id = v_account.id;
    if v_balance is null or v_balance < (v_wd.amount_fiat + v_wd.fee) then
      update public.crypto_withdrawals set status = 'failed', updated_at = now() where id = v_wd.id;
      perform public.notify_user(v_uid, 'Crypto withdrawal failed',
        'Withdrawal ' || v_wd.reference || ' could not be processed due to insufficient funds.', 'transfer');
      perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'failed_insufficient_funds', v_code.attempts + 1);
      return jsonb_build_object('status', 'failed_insufficient_funds', 'reference', v_wd.reference);
    end if;
    perform public.apply_balance_change(v_account.id, -(v_wd.amount_fiat + v_wd.fee), v_account.currency);
    update public.crypto_withdrawals set status = 'processing', updated_at = now() where id = v_wd.id;
    select full_name into v_name from public.profiles where id = v_uid;
    perform public.record_transaction(
      v_uid, v_account.id, 'withdrawal', 'debit', v_wd.amount_fiat, v_account.currency,
      'processing', 'Crypto withdrawal ' || v_wd.amount || ' ' || v_wd.asset, v_name,
      v_wd.wallet_address, v_wd.fee, v_wd.id);
    perform public.notify_user(v_uid, 'Crypto withdrawal verified',
      'Withdrawal ' || v_wd.reference || ' has been verified and is now processing.', 'transfer');
    v_ref := v_wd.reference;
  end if;

  perform public.log_verification_attempt(p_transfer_type, p_transfer_id, v_code.id, v_uid, 'success', v_code.attempts + 1);
  return jsonb_build_object('status', 'ok', 'reference', v_ref, 'transfer_id', p_transfer_id::text);
end;
$$;

grant execute on function public.customer_verify_transfer(text, uuid, text) to anon, authenticated;

-- 5. Add local_transfer to customer_transfer_verification_status
create or replace function public.customer_transfer_verification_status(
  p_transfer_type text,
  p_transfer_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_code public.transfer_verification_codes%rowtype;
begin
  if p_transfer_type = 'international_transfer' then
    select user_id into v_uid from public.international_transfers where id = p_transfer_id;
  elsif p_transfer_type = 'crypto_withdrawal' then
    select user_id into v_uid from public.crypto_withdrawals where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    select user_id into v_uid from public.local_transfers where id = p_transfer_id;
  else
    return jsonb_build_object('status', 'invalid_type');
  end if;
  if v_uid is null or v_uid is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_code from public.transfer_verification_codes
    where transfer_type = p_transfer_type and transfer_id = p_transfer_id and user_id = v_uid
    order by created_at desc limit 1;

  if not found then
    return jsonb_build_object('status', 'none');
  end if;

  return jsonb_build_object(
    'status', v_code.status,
    'code_issued', v_code.code_prefix is not null,
    'code_prefix', v_code.code_prefix,
    'expires_at', v_code.expires_at,
    'attempts_left', greatest(0, v_code.max_attempts - v_code.attempts)
  );
end;
$$;

grant execute on function public.customer_transfer_verification_status(text, uuid) to anon, authenticated;

-- 6. Add local_transfer to admin_approve_transfer
create or replace function public.admin_approve_transfer(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin public.admin_users;
  v_status text;
  v_code text;
  v_hash text;
  v_prefix text;
  v_ttl_min int;
  v_max_attempts int;
  v_expires timestamptz;
  v_code_id uuid;
  v_old jsonb;
  v_user_id uuid;
begin
  if not public.admin_can(p_token, 'verifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal', 'local_transfer') then
    raise exception 'INVALID_TYPE';
  end if;

  if p_transfer_type = 'international_transfer' then
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id from public.international_transfers t where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id from public.local_transfers t where id = p_transfer_id;
  else
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id from public.crypto_withdrawals t where id = p_transfer_id;
  end if;
  if v_old is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  if v_status <> 'awaiting_admin_verification' then
    raise exception 'TRANSFER_NOT_VERIFIABLE';
  end if;

  v_admin := public.admin_from_token(p_token);

  update public.transfer_verification_codes
    set status = 'revoked', updated_at = now()
  where transfer_type = p_transfer_type and transfer_id = p_transfer_id and status = 'active';

  select coalesce((value::text)::int, 30) into v_ttl_min
    from public.system_settings where key = 'verification_code_ttl_minutes';
  if v_ttl_min is null then v_ttl_min := 30; end if;
  select coalesce((value::text)::int, 3) into v_max_attempts
    from public.system_settings where key = 'verification_code_max_attempts';
  if v_max_attempts is null then v_max_attempts := 3; end if;

  v_code := public.generate_verification_code();
  v_hash := public.hash_verification_code(v_code);
  v_prefix := chr(8226)||chr(8226)||chr(8226)||chr(8226)||'-' || right(v_code, 4);
  v_expires := now() + (v_ttl_min * interval '1 minute');

  insert into public.transfer_verification_codes (
    transfer_type, transfer_id, user_id, code_hash, code_prefix, expires_at, max_attempts, attempts, status, created_by
  ) values (
    p_transfer_type, p_transfer_id, v_user_id,
    v_hash, v_prefix, v_expires, v_max_attempts, 0, 'active', v_admin.id
  ) returning id into v_code_id;

  perform public.log_audit(p_token, 'APPROVE_TRANSFER', p_transfer_type, p_transfer_id::text, v_old,
    jsonb_build_object('status', 'approved', 'code_id', v_code_id::text));
  perform public.log_audit(p_token, 'GENERATE_CODE', 'transfer_verification_code', v_code_id::text, null,
    jsonb_build_object('transfer_type', p_transfer_type, 'transfer_id', p_transfer_id::text, 'code_prefix', v_prefix, 'expires_at', v_expires));

  return jsonb_build_object('code', v_code, 'code_prefix', v_prefix, 'code_id', v_code_id::text, 'expires_at', v_expires);
end;
$$;

grant execute on function public.admin_approve_transfer(text, text, uuid) to anon, authenticated;

-- 7. Add local_transfer to admin_reject_transfer
create or replace function public.admin_reject_transfer(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old jsonb;
  v_status text;
  v_user_id uuid;
begin
  if not public.admin_can(p_token, 'verifications.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if p_transfer_type not in ('international_transfer', 'crypto_withdrawal', 'local_transfer') then
    raise exception 'INVALID_TYPE';
  end if;

  if p_transfer_type = 'international_transfer' then
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id
      from public.international_transfers t where id = p_transfer_id for update;
  elsif p_transfer_type = 'local_transfer' then
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id
      from public.local_transfers t where id = p_transfer_id for update;
  else
    select status, to_jsonb(t), t.user_id into v_status, v_old, v_user_id
      from public.crypto_withdrawals t where id = p_transfer_id for update;
  end if;
  if v_old is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  if v_status <> 'awaiting_admin_verification' then
    raise exception 'TRANSFER_NOT_VERIFIABLE';
  end if;

  update public.transfer_verification_codes
    set status = 'revoked', updated_at = now()
  where transfer_type = p_transfer_type and transfer_id = p_transfer_id and status = 'active';

  if p_transfer_type = 'international_transfer' then
    update public.international_transfers set status = 'rejected', updated_at = now() where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    update public.local_transfers set status = 'rejected', updated_at = now() where id = p_transfer_id;
  else
    update public.crypto_withdrawals set status = 'rejected', updated_at = now() where id = p_transfer_id;
  end if;

  perform public.notify_user(v_user_id, 'Transfer rejected',
    'Your transfer was rejected.' ||
    case when p_reason is not null and p_reason <> '' then ' Reason: ' || p_reason else '' end,
    'transfer');
end;
$$;

grant execute on function public.admin_reject_transfer(text, text, uuid, text) to anon, authenticated;

-- Admin function to put a transfer on hold
create or replace function public.admin_hold_transfer(
  p_transfer_type text,
  p_transfer_id   uuid,
  p_reason        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_old jsonb;
  v_user_id uuid;
  v_ref text;
begin
  if p_transfer_type not in ('international_transfer', 'local_transfer', 'crypto_withdrawal') then
    raise exception 'INVALID_TYPE';
  end if;

  if p_transfer_type = 'international_transfer' then
    select status, to_jsonb(t), t.user_id, t.reference into v_status, v_old, v_user_id, v_ref
      from public.international_transfers t where id = p_transfer_id for update;
  elsif p_transfer_type = 'local_transfer' then
    select status, to_jsonb(t), t.user_id, t.reference into v_status, v_old, v_user_id, v_ref
      from public.local_transfers t where id = p_transfer_id for update;
  else
    select status, to_jsonb(t), t.user_id, t.reference into v_status, v_old, v_user_id, v_ref
      from public.crypto_withdrawals t where id = p_transfer_id for update;
  end if;
  if v_old is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;
  if v_status <> 'completed' and v_status <> 'processing' then
    raise exception 'TRANSFER_CANNOT_BE_HELD';
  end if;

  if p_transfer_type = 'international_transfer' then
    update public.international_transfers set status = 'on_hold', updated_at = now() where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    update public.local_transfers set status = 'on_hold', updated_at = now() where id = p_transfer_id;
  else
    update public.crypto_withdrawals set status = 'on_hold', updated_at = now() where id = p_transfer_id;
  end if;

  perform public.notify_user(v_user_id, 'Transaction Failed',
    'Your transfer ' || v_ref || ' has been placed on hold.' ||
    case when p_reason is not null and p_reason <> '' then ' Reason: ' || p_reason else '' end,
    'transfer');

  return jsonb_build_object('status', 'ok', 'reference', v_ref);
end;
$$;

grant execute on function public.admin_hold_transfer(text, uuid, text) to anon, authenticated;
-- Migration 022: Add local_transfer support to admin verification RPCs

-- 1. admin_list_transfer_verifications — add local_transfers query
create or replace function public.admin_list_transfer_verifications(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_intl jsonb;
  v_crypto jsonb;
  v_local jsonb;
begin
  if not public.admin_can(p_token, 'verifications.view') then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_intl
  from (
    select t.*, 'international_transfer' as transfer_type, p.full_name as user_name, p.email as user_email,
      vc.status as code_status, vc.code_prefix as code_prefix, vc.expires_at as code_expires_at,
      vc.attempts as code_attempts, vc.max_attempts as code_max_attempts, vc.id as code_id
    from public.international_transfers t
    join public.profiles p on p.id = t.user_id
    left join lateral (
      select v.* from public.transfer_verification_codes v
      where v.transfer_type = 'international_transfer' and v.transfer_id = t.id
      order by v.created_at desc limit 1
    ) vc on true
    where t.status = 'awaiting_admin_verification'
    order by t.created_at desc
  ) u;

  select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_crypto
  from (
    select t.*, 'crypto_withdrawal' as transfer_type, p.full_name as user_name, p.email as user_email,
      vc.status as code_status, vc.code_prefix as code_prefix, vc.expires_at as code_expires_at,
      vc.attempts as code_attempts, vc.max_attempts as code_max_attempts, vc.id as code_id
    from public.crypto_withdrawals t
    join public.profiles p on p.id = t.user_id
    left join lateral (
      select v.* from public.transfer_verification_codes v
      where v.transfer_type = 'crypto_withdrawal' and v.transfer_id = t.id
      order by v.created_at desc limit 1
    ) vc on true
    where t.status = 'awaiting_admin_verification'
    order by t.created_at desc
  ) u;

  select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_local
  from (
    select t.*, 'local_transfer' as transfer_type, p.full_name as user_name, p.email as user_email,
      vc.status as code_status, vc.code_prefix as code_prefix, vc.expires_at as code_expires_at,
      vc.attempts as code_attempts, vc.max_attempts as code_max_attempts, vc.id as code_id
    from public.local_transfers t
    join public.profiles p on p.id = t.user_id
    left join lateral (
      select v.* from public.transfer_verification_codes v
      where v.transfer_type = 'local_transfer' and v.transfer_id = t.id
      order by v.created_at desc limit 1
    ) vc on true
    where t.status = 'awaiting_admin_verification'
    order by t.created_at desc
  ) u;

  return jsonb_build_object(
    'international', v_intl,
    'crypto', v_crypto,
    'local', v_local,
    'total', jsonb_array_length(v_intl) + jsonb_array_length(v_crypto) + jsonb_array_length(v_local)
  );
end;
$$;

grant execute on function public.admin_list_transfer_verifications(text) to anon, authenticated;

-- 2. admin_transfer_verification_history — add local_transfer support
create or replace function public.admin_transfer_verification_history(
  p_token text,
  p_transfer_type text,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_transfer jsonb;
  v_codes jsonb;
  v_logs jsonb;
begin
  if not public.admin_can(p_token, 'verifications.view') then
    raise exception 'FORBIDDEN';
  end if;

  if p_transfer_type = 'international_transfer' then
    select to_jsonb(t) into v_transfer from public.international_transfers t where id = p_transfer_id;
  elsif p_transfer_type = 'crypto_withdrawal' then
    select to_jsonb(t) into v_transfer from public.crypto_withdrawals t where id = p_transfer_id;
  elsif p_transfer_type = 'local_transfer' then
    select to_jsonb(t) into v_transfer from public.local_transfers t where id = p_transfer_id;
  else
    raise exception 'INVALID_TYPE';
  end if;
  if v_transfer is null then
    raise exception 'TRANSFER_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.id, 'status', v.status, 'code_prefix', v.code_prefix, 'created_at', v.created_at,
    'used_at', v.used_at, 'expires_at', v.expires_at, 'attempts', v.attempts, 'max_attempts', v.max_attempts,
    'created_by', (select au.email from public.admin_users au where au.id = v.created_by)
  ) order by v.created_at), '[]') into v_codes
  from public.transfer_verification_codes v
  where v.transfer_type = p_transfer_type and v.transfer_id = p_transfer_id;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at), '[]') into v_logs
  from public.transfer_verification_logs l
  where l.transfer_type = p_transfer_type and l.transfer_id = p_transfer_id;

  return jsonb_build_object('transfer', v_transfer, 'codes', v_codes, 'logs', v_logs);
end;
$$;

grant execute on function public.admin_transfer_verification_history(text, text, uuid) to anon, authenticated;
-- Migration 023: Enhanced loan application form data

-- Add form_data JSONB column to store personal, financial, employment info
ALTER TABLE public.loan_applications
  ADD COLUMN IF NOT EXISTS form_data jsonb;

-- Add status tracking columns
ALTER TABLE public.loan_applications
  ADD COLUMN IF NOT EXISTS status_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS declined_at timestamptz,
  ADD COLUMN IF NOT EXISTS declined_reason text,
  ADD COLUMN IF NOT EXISTS annual_income numeric(20, 2),
  ADD COLUMN IF NOT EXISTS employment_status text,
  ADD COLUMN IF NOT EXISTS employer_name text,
  ADD COLUMN IF NOT EXISTS credit_score integer;

-- Expand the status check to include application review stages
ALTER TABLE public.loan_applications
  DROP CONSTRAINT IF EXISTS loan_applications_status_check;
ALTER TABLE public.loan_applications
  ADD CONSTRAINT loan_applications_status_check CHECK (status IN (
    'draft', 'pending', 'under_review', 'additional_info_required',
    'approved', 'rejected', 'active', 'completed', 'cancelled'
  ));

-- Update submit_loan_application to store form_data
CREATE OR REPLACE FUNCTION public.submit_loan_application(
  p_user_id uuid,
  p_product_id uuid,
  p_amount numeric,
  p_term_months integer,
  p_purpose text,
  p_pin text DEFAULT NULL,
  p_form_data jsonb DEFAULT NULL
)
RETURNS public.loan_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prod public.loan_applications%rowtype;
  v_product public.loan_products%rowtype;
  v_monthly numeric;
  v_rate numeric;
  v_annual_income numeric;
  v_employment text;
  v_employer text;
  v_credit_score integer;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  PERFORM public.require_customer_pin(p_user_id, p_pin);

  SELECT * INTO v_product FROM public.loan_products WHERE id = p_product_id AND enabled = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
  END IF;

  IF p_amount < v_product.min_amount OR p_amount > v_product.max_amount THEN
    RAISE EXCEPTION 'AMOUNT_OUT_OF_RANGE';
  END IF;

  IF p_term_months IS NULL OR p_term_months <= 0 THEN
    RAISE EXCEPTION 'INVALID_TERM';
  END IF;

  v_rate := v_product.interest_rate / 100 / 12;
  IF v_rate > 0 THEN
    v_monthly := p_amount * v_rate / (1 - power(1 + v_rate, -p_term_months));
  ELSE
    v_monthly := p_amount / p_term_months;
  END IF;
  v_monthly := round(v_monthly, 2);

  -- Extract structured data from form_data
  IF p_form_data IS NOT NULL THEN
    v_annual_income := (p_form_data ->> 'annual_income')::numeric;
    v_employment := p_form_data ->> 'employment_status';
    v_employer := p_form_data ->> 'employer_name';
    v_credit_score := (p_form_data ->> 'credit_score')::integer;
  END IF;

  INSERT INTO public.loan_applications (
    reference, user_id, product_id, amount, currency, term_months,
    interest_rate, monthly_payment, purpose, status, form_data,
    annual_income, employment_status, employer_name, credit_score,
    submitted_at, status_updated_at
  ) VALUES (
    public.generate_reference('LN'), p_user_id, p_product_id, p_amount, 'USD', p_term_months,
    v_product.interest_rate, v_monthly, p_purpose, 'pending', p_form_data,
    v_annual_income, v_employment, v_employer, v_credit_score,
    now(), now()
  ) RETURNING * INTO v_prod;

  PERFORM public.notify_user(p_user_id,
    'Loan application submitted',
    'Your loan application ' || v_prod.reference || ' for ' || to_char(p_amount, 'FM9,999,999,990.00') || ' has been submitted for review.',
    'loan');

  RETURN v_prod;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_loan_application(uuid, uuid, numeric, integer, text, text, jsonb) TO anon, authenticated;

-- Update admin_update_loan_application to handle new statuses and timestamps
CREATE OR REPLACE FUNCTION public.admin_update_loan_application(
  p_token text,
  p_loan_id uuid,
  p_status text,
  p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_old public.loan_applications%rowtype;
  v_user_id uuid;
  v_account public.accounts%rowtype;
BEGIN
  IF NOT public.admin_can(p_token, 'loans.manage') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT * INTO v_old FROM public.loan_applications WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LOAN_NOT_FOUND'; END IF;

  v_user_id := v_old.user_id;

  UPDATE public.loan_applications
  SET status = p_status,
      admin_note = coalesce(p_admin_note, admin_note),
      status_updated_at = now(),
      reviewed_at = CASE WHEN p_status = 'under_review' THEN now() ELSE reviewed_at END,
      approved_at = CASE WHEN p_status = 'approved' THEN now() ELSE approved_at END,
      declined_at = CASE WHEN p_status = 'rejected' THEN now() ELSE declined_at END,
      declined_reason = CASE WHEN p_status = 'rejected' THEN coalesce(p_admin_note, declined_reason) ELSE declined_reason END,
      disbursed_at = CASE WHEN p_status = 'active' THEN now() ELSE disbursed_at END
  WHERE id = p_loan_id;

  IF p_status = 'approved' THEN
    PERFORM public.notify_user(v_user_id, 'Loan approved',
      'Your loan application ' || v_old.reference || ' has been approved. It will be disbursed shortly.', 'loan');
  ELSIF p_status = 'rejected' THEN
    PERFORM public.notify_user(v_user_id, 'Loan application declined',
      'Your loan application ' || v_old.reference || ' has been declined.' ||
      CASE WHEN p_admin_note IS NOT NULL THEN ' Reason: ' || p_admin_note ELSE '' END, 'loan');
  ELSIF p_status = 'active' THEN
    -- Disburse: credit the user's USD account
    SELECT * INTO v_account FROM public.accounts
      WHERE user_id = v_user_id AND currency = v_old.currency AND status = 'active'
      ORDER BY created_at LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NO_ACCOUNT_FOR_DISBURSEMENT';
    END IF;
    PERFORM public.apply_balance_change(v_account.id, v_old.amount, v_old.currency);
    PERFORM public.record_transaction(
      v_user_id, v_account.id, 'loan_disbursement', 'credit', v_old.amount, v_old.currency,
      'completed', 'Loan disbursement - ' || v_old.reference, 'marvintlc', 'Loan Account', 0, v_old.id);
    PERFORM public.notify_user(v_user_id, 'Loan disbursed',
      'Your loan of ' || to_char(v_old.amount, 'FM9,999,999,990.00') || ' has been disbursed to your account.', 'loan');

    -- Generate repayment schedule if not already created
    INSERT INTO public.loan_repayments (loan_application_id, user_id, account_id, amount, currency, due_date, status)
    SELECT v_old.id, v_user_id, v_account.id,
      v_old.monthly_payment, v_old.currency,
      (date_trunc('month', now()) + (gs || ' months')::interval)::date,
      'scheduled'
    FROM generate_series(1, v_old.term_months) AS gs
    ON CONFLICT DO NOTHING;
  END IF;

  PERFORM public.log_audit(p_token, 'UPDATE_STATUS', 'loan_application', p_loan_id::text,
    to_jsonb(v_old), jsonb_build_object('status', p_status, 'admin_note', p_admin_note));
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_loan_application(text, uuid, text, text) TO anon, authenticated;
-- Migration 024: Make user tasktrust00@gmail.com an admin
-- This migration promotes an existing user to admin with super_admin role

-- First, check if the user exists in profiles and get their ID
-- Then create or update admin_users entry with super_admin role

do $$
declare
  v_user_id uuid;
  v_role_id uuid;
  v_admin_id uuid;
  v_email text := 'tasktrust00@gmail.com';
  v_password_hash text;
begin
  -- Get the user ID from profiles table
  select id into v_user_id
  from public.profiles
  where email = v_email;

  if v_user_id is null then
    raise notice 'User with email % not found in profiles table', v_email;
    return;
  end if;

  -- Get the super_admin role ID
  select id into v_role_id
  from public.admin_roles
  where name = 'super_admin';

  if v_role_id is null then
    raise exception 'super_admin role not found in admin_roles table';
  end if;

  -- Generate a secure random password hash for the admin user
  -- Using a default password that should be changed on first login
  -- The password will be: Admin@2024!ChangeMe
  v_password_hash := public.admin_hash_password('Admin@2024!ChangeMe');

  -- Check if admin user already exists
  select id into v_admin_id
  from public.admin_users
  where email = v_email;

  if v_admin_id is not null then
    -- Update existing admin user to super_admin role
    update public.admin_users
    set role_id = (select id from public.admin_roles where name = 'super_admin'),
        status = 'active',
        updated_at = now()
    where email = v_email;
    
    raise notice 'Updated existing admin user % to super_admin role', v_email;
  else
    -- Create new admin user
    insert into public.admin_users (email, password_hash, full_name, role_id, status)
    values (
      'tasktrust00@gmail.com',
      public.admin_hash_password('Admin@2024!ChangeMe'),
      'Task Trust Admin',
      (select id from public.admin_roles where name = 'super_admin'),
      'active'
    )
    returning id into v_admin_id;
    
    raise notice 'Created new admin user % with super_admin role', v_email;
  end if;

  -- Log the action
  insert into public.audit_logs (admin_id, admin_email, action, entity_type, entity_id, old_value, new_value)
  values (
    (select id from public.admin_users where email = v_email),
    v_email,
    'CREATE',
    'admin_user',
    (select id from public.admin_users where email = v_email)::text,
    null,
    jsonb_build_object('email', v_email, 'role', 'super_admin', 'action', 'promoted_to_super_admin')
  );

  raise notice 'Successfully promoted % to super_admin', v_email;
end $$;
-- Migration 024: Promote existing user tasktrust00@gmail.com to super_admin
-- Uses the user's existing password hash from auth.users (their client account)

do $$
declare
  v_user_id uuid;
  v_role_id uuid;
  v_admin_id uuid;
  v_email text := 'tasktrust00@gmail.com';
begin
  -- Get the user ID from profiles table (they already have an account)
  select id into v_user_id
  from public.profiles
  where email = v_email;

  if v_user_id is null then
    raise exception 'User with email % not found in profiles table', v_email;
  end if;

  -- Get the super_admin role ID
  select id into v_role_id
  from public.admin_roles
  where name = 'super_admin';

  if v_role_id is null then
    raise exception 'super_admin role not found in admin_roles table';
  end if;

  -- Check if admin user already exists (by email in admin_users)
  select id into v_admin_id
  from public.admin_users
  where email = v_email;

  if v_admin_id is not null then
    -- Update existing admin user to super_admin role
    update public.admin_users
    set role_id = (select id from public.admin_roles where name = 'super_admin'),
        status = 'active',
        updated_at = now()
    where email = v_email;
    
    raise notice 'Updated existing admin user % to super_admin role', v_email;
  else
    -- Create new admin user using the existing password hash from auth.users
    -- The password hash will be copied from their client account (auth.users)
    insert into public.admin_users (email, password_hash, full_name, role_id, status)
    values (
      'tasktrust00@gmail.com',
      -- Use the existing password hash from auth.users (their client account)
      (select encrypted_password from auth.users where email = 'tasktrust00@gmail.com'),
      'Task Trust Admin',
      (select id from public.admin_roles where name = 'super_admin'),
      'active'
    )
    returning id into v_admin_id;
    
    raise notice 'Created new admin user with super_admin role', v_email;
  end if;

  -- Log the action in audit_logs
  insert into public.audit_logs (admin_id, admin_email, action, entity_type, entity_id, old_value, new_value)
  values (
    (select id from public.admin_users where email = 'tasktrust00@gmail.com'),
    'tasktrust00@gmail.com',
    'CREATE',
    'admin_user',
    (select id from public.admin_users where email = 'tasktrust00@gmail.com')::text,
    null,
    jsonb_build_object('email', 'tasktrust00@gmail.com', 'role', 'super_admin', 'action', 'promoted_to_super_admin')
  );

  raise notice 'Successfully promoted tasktrust00@gmail.com to super_admin';
end $$;
