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
  v_admin public.admin_users;
  v_where text := '';
  v_params text[] := array[];
  v_query text;
  v_count_query text;
  v_total int;
  v_rows jsonb;
begin
  if not public.admin_can(p_token, 'deposits.view') then
    raise exception 'FORBIDDEN';
  end if;

  v_admin := public.admin_from_token(p_token);

  -- Build dynamic query
  v_where := 'where 1=1';
  v_params := array[];

  if p_search is not null and p_search <> '' then
    v_where := v_where || ' and (d.reference ilike $' || array_length(v_params, 1) + 1 || ' or u.email ilike $' || array_length(v_params, 1) + 1 || ' or u.full_name ilike $' || array_length(v_params, 1) + 1 || ')';
    v_params := v_params || '%' || p_search || '%';
  end if;

  if p_status is not null and p_status <> '' then
    v_where := v_where || ' and d.status = $' || array_length(v_params, 1) + 1;
    v_params := v_params || p_status;
  end if;

  if p_type is not null and p_type <> '' then
    if p_type = 'fiat' then
      v_where := v_where || ' and d.type is distinct from ''crypto''';
    elsif p_type = 'crypto' then
      v_where := v_where || ' and d.type = ''crypto''';
    end if;
  end if;

  if p_asset is not null and p_asset <> '' then
    v_where := v_where || ' and (d.asset = $' || array_length(v_params, 1) + 1 || ' or d.currency = $' || array_length(v_params, 1) + 1 || ')';
    v_params := v_params || p_asset;
  end if;

  -- Count total
  v_count_query := 'select count(*) from (select d.*, u.email as user_email, u.full_name as user_name from public.deposits d join public.profiles u on u.id = d.user_id ' || v_where || ') q';
  execute format(v_count_query) using v_params into v_total;

  -- Fetch rows
  v_query := 'select d.*, u.email as user_email, u.full_name as user_name from public.deposits d join public.profiles u on u.id = d.user_id ' || v_where || ' order by d.created_at desc limit $' || array_length(v_params, 1) + 1 || ' offset $' || array_length(v_params, 1) + 2;
  v_params := v_params || array[12, 0]::int[]; -- placeholder for limit/offset

  execute format(v_query) using v_params into v_rows;

  return jsonb_build_object(
    'rows', v_rows,
    'total', v_total
  );
end;
$$;

grant execute on function public.admin_list_deposits(text, text, text, text, int, int) to anon, authenticated;

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
