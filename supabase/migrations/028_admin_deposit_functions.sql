-- Migration 028: Admin deposit verification functions
-- Adds admin RPCs for deposit verification and management

-- Admin: list deposits with filters
create or replace function public.admin_list_deposits(
  p_token text,
  p_search text default null,
  p_status text default null,
  p_type text default null,      -- 'fiat', 'crypto'
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

  return jsonb_build_object(
    'rows', v_rows,
    'total', v_total
  );
end;
$$;

grant execute on function public.admin_list_deposits(text, text, text, text, text, int, int) to anon, authenticated;

-- Admin: update deposit status
create or replace function public.admin_update_deposit_status(
  p_token text,
  p_deposit_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deposit public.deposits%rowtype;
begin
  if not public.admin_can(p_token, 'deposits.manage') then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_deposit from public.deposits where id = p_deposit_id for update;
  if not found then
    raise exception 'DEPOSIT_NOT_FOUND';
  end if;

  update public.deposits set status = p_status, updated_at = now() where id = p_deposit_id;
  perform public.log_audit(p_token, 'UPDATE_STATUS', 'deposit', p_deposit_id::text, to_jsonb(v_deposit),
    jsonb_build_object('status', p_status));
end;
$$;

grant execute on function public.admin_update_deposit_status(text, uuid, text) to anon, authenticated;
