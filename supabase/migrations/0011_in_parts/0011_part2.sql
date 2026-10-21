-- 0011_admin_panel.sql, part 2 of 4. For pasting into the Supabase SQL editor when the whole file is too long to paste.
-- Run the four parts in order, each as its own run. Together they equal 0011_admin_panel.sql.

-- ===== user management =====
create or replace function public.app_admin_list_users(p_search text default null, p_role text default null, p_district_id smallint default null,
  p_school_id bigint default null, p_program text default null, p_status text default null, p_limit integer default 25, p_offset integer default 0)
returns table (total bigint, id uuid, username text, display_name text, email text, role text, district_id smallint, district_name text,
  education_level text, school_id bigint, school_name text, programs text[], active boolean, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  return query
  with base as (
    select p.id, p.username, p.display_name, u.email::text as email, p.role::text as role, p.district_id, d.name as district_name,
           p.education_level, p.school_id, s.name as school_name,
           coalesce((select array_agg(sp.program order by sp.program) from public.school_programs sp where sp.school_id = p.school_id), '{}') as programs,
           p.active, u.created_at, u.last_sign_in_at
    from public.profiles p
    left join auth.users u on u.id = p.id
    left join public.districts d on d.id = p.district_id
    left join public.schools s on s.id = p.school_id
    where (p_search is null or btrim(p_search) = '' or p.username ilike '%' || btrim(p_search) || '%' or p.display_name ilike '%' || btrim(p_search) || '%'
           or u.email ilike '%' || btrim(p_search) || '%' or s.name ilike '%' || btrim(p_search) || '%')
      and (p_role is null or p_role = '' or p.role::text = p_role)
      and (p_district_id is null or p.district_id = p_district_id)
      and (p_school_id is null or p.school_id = p_school_id)
      and (p_status is null or p_status = '' or (p_status = 'active' and p.active) or (p_status = 'disabled' and not p.active))
  )
  select count(*) over () as total, b.id, b.username, b.display_name, b.email, b.role, b.district_id, b.district_name, b.education_level,
         b.school_id, b.school_name, b.programs, b.active, b.created_at, b.last_sign_in_at
  from base b
  where p_program is null or p_program = '' or p_program = any (b.programs)
  order by b.created_at desc nulls last, b.username
  limit greatest(1, least(coalesce(p_limit, 25), 200)) offset greatest(0, coalesce(p_offset, 0));
end $$;

create or replace function public.app_admin_user_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'total', count(*), 'active', count(*) filter (where active), 'disabled', count(*) filter (where not active),
    'by_role', coalesce((select jsonb_object_agg(role, n) from (select role::text as role, count(*) as n from public.profiles group by 1) t), '{}'),
    'schools', (select count(*) from public.schools where active), 'schools_total', (select count(*) from public.schools))
  into r from public.profiles;
  return r;
end $$;

-- shared validation of a role and its assignments; returns the profile columns to store
create or replace function public.app_admin_check_assignment(p_role text, p_district_id smallint, p_education_level text, p_school_id bigint)
returns table (district_id smallint, education_level text, school_id bigint)
language plpgsql stable security definer set search_path = '' as $$
declare sch record;
begin
  if p_role not in ('admin', 'supervisor', 'district_coordinator', 'school') then raise exception 'Choose a valid role.'; end if;
  if p_role in ('admin', 'supervisor') then
    if p_district_id is not null or p_education_level is not null or p_school_id is not null then
      raise exception 'An % has no district, education level or school.', p_role;
    end if;
    return query select null::smallint, null::text, null::bigint;
  elsif p_role = 'district_coordinator' then
    if p_school_id is not null then raise exception 'A district coordinator is not assigned to a school.'; end if;
    if p_district_id is null or not exists (select 1 from public.districts d where d.id = p_district_id) then raise exception 'Choose the coordinator''s district.'; end if;
    if p_education_level is null or p_education_level not in ('elementary', 'secondary') then raise exception 'Choose Elementary or Secondary for a district coordinator.'; end if;
    return query select p_district_id, p_education_level, null::bigint;
  else
    if p_education_level is not null then raise exception 'A school account has no education level; its school decides what it sees.'; end if;
    select s.id, s.district_id, s.active into sch from public.schools s where s.id = p_school_id;
    if not found then raise exception 'Choose the school for a school account.'; end if;
    if p_district_id is not null and p_district_id <> sch.district_id then raise exception 'That school belongs to a different district.'; end if;
    if not sch.active then raise exception 'That school is inactive.'; end if;
    if not exists (select 1 from public.school_programs sp where sp.school_id = sch.id) then raise exception 'Classify the school as Special Programs or IPED first.'; end if;
    return query select sch.district_id, null::text, sch.id;
  end if;
end $$;
revoke execute on function public.app_admin_check_assignment(text, smallint, text, bigint) from public, anon, authenticated;

create or replace function public.app_admin_create_user(p_username text, p_display_name text, p_role text, p_district_id smallint,
  p_education_level text, p_school_id bigint, p_password text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uname text := lower(btrim(coalesce(p_username, ''))); dname text := btrim(coalesce(p_display_name, ''));
  a record; v_id uuid; v_email text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if uname !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then raise exception 'Username must be 3 to 40 characters: lowercase letters, numbers, dot, dash or underscore.'; end if;
  if dname = '' or char_length(dname) > 120 then raise exception 'Enter a display name (120 characters at most).'; end if;
  if char_length(coalesce(p_password, '')) < 8 or char_length(p_password) > 72 then raise exception 'The password must be 8 to 72 characters.'; end if;
  select * into a from public.app_admin_check_assignment(p_role, p_district_id, p_education_level, p_school_id);
  if p_role = 'school' and exists (select 1 from public.profiles where profiles.school_id = a.school_id and active) then raise exception 'This school already has an active account.'; end if;
  v_email := uname || '@users.mapehdavnor.altasme.app';
  if exists (select 1 from public.profiles where lower(username) = uname) or exists (select 1 from auth.users where lower(email) = v_email) then raise exception 'That username is already taken.'; end if;
  v_id := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false), 'email', now(), now(), now());
  insert into public.profiles (id, username, display_name, role, district_id, education_level, school_id, active, must_change_password)
    values (v_id, uname, dname, p_role::public.app_role, a.district_id, a.education_level, a.school_id, true, false);
  perform public.app_admin_log('user.create', 'user', v_id::text, 'success', jsonb_build_object('username', uname, 'role', p_role, 'district_id', a.district_id, 'education_level', a.education_level, 'school_id', a.school_id));
  return v_id;
end $$;

create or replace function public.app_admin_update_user(p_id uuid, p_username text, p_display_name text, p_role text, p_district_id smallint,
  p_education_level text, p_school_id bigint, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  cur record; a record; uname text := lower(btrim(coalesce(p_username, ''))); dname text := btrim(coalesce(p_display_name, '')); v_email text; changes jsonb := '{}';
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select p.*, p.role::text as role_text into cur from public.profiles p where p.id = p_id;
  if not found then raise exception 'User not found.'; end if;
  if uname !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then raise exception 'Username must be 3 to 40 characters: lowercase letters, numbers, dot, dash or underscore.'; end if;
  if dname = '' or char_length(dname) > 120 then raise exception 'Enter a display name (120 characters at most).'; end if;
  select * into a from public.app_admin_check_assignment(p_role, p_district_id, p_education_level, p_school_id);
  -- never lock the system out of administration
  if cur.role_text = 'admin' and cur.active and (p_role <> 'admin' or not p_active)
     and not exists (select 1 from public.profiles o where o.id <> p_id and o.role::text = 'admin' and o.active) then
    raise exception 'This is the last active administrator. Create or enable another administrator first.';
  end if;
  if p_id = auth.uid() and not p_active then raise exception 'You cannot disable your own account.'; end if;
  if p_role = 'school' and p_active and exists (select 1 from public.profiles o where o.school_id = a.school_id and o.active and o.id <> p_id) then
    raise exception 'This school already has an active account.';
  end if;
  if uname <> lower(cur.username) then
    v_email := uname || '@users.mapehdavnor.altasme.app';
    if exists (select 1 from public.profiles o where lower(o.username) = uname and o.id <> p_id) or exists (select 1 from auth.users u where lower(u.email) = v_email and u.id <> p_id) then
      raise exception 'That username is already taken.';
    end if;
    update auth.users set email = v_email, updated_at = now() where id = p_id;
    update auth.identities set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email)) where user_id = p_id;
    changes := changes || jsonb_build_object('username', jsonb_build_object('from', cur.username, 'to', uname));
  end if;
  if cur.role_text <> p_role then changes := changes || jsonb_build_object('role', jsonb_build_object('from', cur.role_text, 'to', p_role)); end if;
  if cur.active <> p_active then changes := changes || jsonb_build_object('active', jsonb_build_object('from', cur.active, 'to', p_active)); end if;
  if cur.district_id is distinct from a.district_id then changes := changes || jsonb_build_object('district_id', jsonb_build_object('from', cur.district_id, 'to', a.district_id)); end if;
  if cur.education_level is distinct from a.education_level then changes := changes || jsonb_build_object('education_level', jsonb_build_object('from', cur.education_level, 'to', a.education_level)); end if;
  if cur.school_id is distinct from a.school_id then changes := changes || jsonb_build_object('school_id', jsonb_build_object('from', cur.school_id, 'to', a.school_id)); end if;
  if cur.display_name <> dname then changes := changes || jsonb_build_object('display_name', true); end if;
  update public.profiles set username = uname, display_name = dname, role = p_role::public.app_role, district_id = a.district_id,
    education_level = a.education_level, school_id = a.school_id, active = p_active where id = p_id;
  update auth.users set banned_until = case when p_active then null else now() + interval '100 years' end where id = p_id;
  perform public.app_admin_log('user.update', 'user', p_id::text, 'success', jsonb_build_object('username', uname, 'changes', changes));
end $$;

-- Sets a new password (hashed; never stored or shown in plain text). The previous password cannot be read by anyone.
create or replace function public.app_admin_set_password(p_id uuid, p_password text) returns void
language plpgsql security definer set search_path = '' as $$
declare uname text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if char_length(coalesce(p_password, '')) < 8 or char_length(p_password) > 72 then raise exception 'The password must be 8 to 72 characters.'; end if;
  select username into uname from public.profiles where id = p_id;
  if uname is null then raise exception 'User not found.'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = p_id;
  perform public.app_admin_log('user.password_reset', 'user', p_id::text, 'success', jsonb_build_object('username', uname));
end $$;

-- ===== activity and data-change logs (summary columns only) =====
create or replace function public.app_admin_activity(p_action text default null, p_outcome text default null, p_limit integer default 25, p_offset integer default 0)
returns table (total bigint, id bigint, at timestamptz, actor_name text, action text, resource text, resource_id text, outcome text, details jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  return query select count(*) over (), a.id, a.at, a.actor_name, a.action, a.resource, a.resource_id, a.outcome, a.details
    from public.admin_activity a
    where (p_action is null or p_action = '' or a.action like p_action || '%') and (p_outcome is null or p_outcome = '' or a.outcome = p_outcome)
    order by a.at desc, a.id desc limit greatest(1, least(coalesce(p_limit, 25), 200)) offset greatest(0, coalesce(p_offset, 0));
end $$;

create or replace function public.app_admin_data_changes(p_limit integer default 25, p_offset integer default 0)
returns table (total bigint, id bigint, at timestamptz, actor_name text, table_name text, action text, row_id text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  return query select count(*) over (), l.id, l.at, (select p.display_name from public.profiles p where p.id = l.actor), l.table_name, l.action, l.row_id
    from public.audit_log l order by l.at desc, l.id desc limit greatest(1, least(coalesce(p_limit, 25), 200)) offset greatest(0, coalesce(p_offset, 0));
end $$;

