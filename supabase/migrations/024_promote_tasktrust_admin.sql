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
