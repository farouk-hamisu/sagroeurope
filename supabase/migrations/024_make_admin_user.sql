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
  insert into public.audit_logs (admin_id, admin_email, action, resource, resource_id, previous_value, new_value)
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
