-- Migration 025: Fix admin user password for tasktrust00@gmail.com
-- The admin login uses PostgreSQL's crypt() function which requires a specific hash format.
-- Supabase Auth uses a different password hashing format, so we need to set a proper hash.

do $$
declare
  v_email text := 'tasktrust00@gmail.com';
  v_admin_id uuid;
  v_role_id uuid;
  v_user_id uuid;
begin
  -- Get the user ID from profiles table
  select id into v_user_id
  from public.profiles
  where email = 'tasktrust00@gmail.com';

  if v_user_id is null then
    raise notice 'User with email tasktrust00@gmail.com not found in profiles table';
    return;
  end if;

  -- Get the super_admin role ID
  select id into v_role_id
  from public.admin_roles
  where name = 'super_admin';

  if v_role_id is null then
    raise exception 'super_admin role not found in admin_roles table';
  end if;

  -- Check if admin user already exists
  select id into v_admin_id
  from public.admin_users
  where email = 'tasktrust00@gmail.com';

  if v_admin_id is not null then
    -- Update existing admin user to super_admin role with a known password hash
    -- Set a known password: "Admin@2024!SecurePass"
    -- The hash is generated using admin_hash_password function (PostgreSQL crypt with bcrypt)
    update public.admin_users
    set 
      role_id = (select id from public.admin_roles where name = 'super_admin'),
      status = 'active',
      password_hash = public.admin_hash_password('Admin@2024!SecurePass'),
      updated_at = now()
    where email = 'tasktrust00@gmail.com';
    
    raise notice 'Updated existing admin user to super_admin with known password';
  else
    -- Create new admin user with a known password
    insert into public.admin_users (email, password_hash, full_name, role_id, status)
    values (
      'tasktrust00@gmail.com',
      public.admin_hash_password('Admin@2024!SecurePass'),
      'Task Trust Admin',
      (select id from public.admin_roles where name = 'super_admin'),
      'active'
    )
    returning id into v_admin_id;
    
    raise notice 'Created new admin user with super_admin role';
  end if;

  -- Log the action
  insert into public.audit_logs (admin_id, admin_email, action, entity_type, entity_id, old_value, new_value)
  values (
    (select id from public.admin_users where email = 'tasktrust00@gmail.com'),
    'tasktrust00@gmail.com',
    'UPDATE',
    'admin_user',
    (select id from public.admin_users where email = 'tasktrust00@gmail.com')::text,
    null,
    jsonb_build_object('email', 'tasktrust00@gmail.com', 'role', 'super_admin', 'action', 'password_reset_for_login')
  );

  raise notice 'Successfully configured admin user tasktrust00@gmail.com with known password';
end $$;
