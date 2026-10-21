-- 0011_admin_panel.sql: everything the /admin panel needs. Safe to run once on a project that has 0001 to 0010.
-- Run it BEFORE deploying the matching app version. Nothing existing is changed or removed.
--
-- Security model: every privileged operation is a database function that checks, on the server, that the caller is an
-- ACTIVE user with role 'admin' (app_is_admin). The browser never holds a service key. Supervisors, coordinators and school
-- accounts are refused by every function and by row level security, whatever the screen shows.
--   * admin_activity       audit trail of administrative actions (no passwords, tokens or secrets are ever written)
--   * site_content         editable text, plain text only (angle brackets are refused, so no HTML or script can be stored)
--   * site_content_versions history with restore
--   * site_settings        validated settings (title, organization, announcement, landing view, school year, contact)
--   * site_media / site_media_slots / storage bucket "site-media"   images, with usage tracking
--   * app_admin_* functions   user management, password reset, content, settings and media

create or replace function public.app_is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role_of_user()::text = 'admin', false)
$$;
revoke execute on function public.app_is_admin() from public, anon;
grant execute on function public.app_is_admin() to authenticated;

-- ===== audit trail of administrative actions =====
create table public.admin_activity (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  actor_name text,
  action text not null,
  resource text,
  resource_id text,
  outcome text not null default 'success' check (outcome in ('success', 'failure', 'denied')),
  details jsonb not null default '{}'
);
create index on public.admin_activity (at desc);
alter table public.admin_activity enable row level security;
revoke all on public.admin_activity from anon, authenticated;
grant select on public.admin_activity to authenticated;
create policy admin_activity_select on public.admin_activity for select to authenticated using (public.app_is_admin());

create or replace function public.app_admin_log(p_action text, p_resource text, p_resource_id text, p_outcome text, p_details jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.admin_activity (actor, actor_name, action, resource, resource_id, outcome, details)
  values (auth.uid(), (select display_name from public.profiles where id = auth.uid()), p_action, p_resource, p_resource_id,
          coalesce(p_outcome, 'success'), coalesce(p_details, '{}'))
$$;
revoke execute on function public.app_admin_log(text, text, text, text, jsonb) from public, anon, authenticated;

-- Events the admin page reports about itself (sign-in, sign-out, own password change). Admin only.
create or replace function public.app_admin_log_event(p_action text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_action not in ('login', 'logout', 'password_changed_self') then raise exception 'Unknown event.'; end if;
  perform public.app_admin_log('admin.' || p_action, 'session', null, 'success', '{}');
end $$;

-- A signed-in user who is NOT an administrator opened /admin: record it (at most once a minute per user).
create or replace function public.app_admin_log_denied() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  if exists (select 1 from public.admin_activity where actor = auth.uid() and action = 'admin.access_denied' and at > now() - interval '1 minute') then return; end if;
  perform public.app_admin_log('admin.access_denied', 'session', null, 'denied', '{}');
end $$;
revoke execute on function public.app_admin_log_event(text), public.app_admin_log_denied() from public, anon;
grant execute on function public.app_admin_log_event(text), public.app_admin_log_denied() to authenticated;

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

-- ===== website content (plain text) with history =====
create table public.site_content (
  key text primary key check (key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$' and char_length(key) <= 80),
  value text not null check (char_length(value) between 1 and 2000),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create table public.site_content_versions (
  id bigint generated always as identity primary key,
  key text not null,
  old_value text,
  new_value text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
create index on public.site_content_versions (key, changed_at desc);
alter table public.site_content enable row level security;
alter table public.site_content_versions enable row level security;
revoke all on public.site_content, public.site_content_versions from anon, authenticated;
grant select on public.site_content to anon, authenticated;
grant select on public.site_content_versions to authenticated;
create policy site_content_read on public.site_content for select to anon, authenticated using (true);
create policy site_content_versions_read on public.site_content_versions for select to authenticated using (public.app_is_admin());

create or replace function public.app_admin_save_content(p_key text, p_value text) returns void
language plpgsql security definer set search_path = '' as $$
declare v text := btrim(replace(coalesce(p_value, ''), E'\r', '')); old text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_key is null or p_key !~ '^[a-z0-9]+([._-][a-z0-9]+)*$' or char_length(p_key) > 80 then raise exception 'Unknown content item.'; end if;
  if v = '' then raise exception 'This text cannot be empty. Use "Reset to default" to go back to the original.'; end if;
  if char_length(v) > 2000 then raise exception 'This text is too long (2000 characters at most).'; end if;
  if v ~ '[<>]' then raise exception 'Plain text only: the characters < and > are not allowed.'; end if;
  if v ~ '[\x00-\x08\x0b\x0c\x0e-\x1f]' then raise exception 'The text contains characters that are not allowed.'; end if;
  select value into old from public.site_content where key = p_key;
  if old is not distinct from v then return; end if;
  insert into public.site_content_versions (key, old_value, new_value, changed_by) values (p_key, old, v, auth.uid());
  insert into public.site_content (key, value, updated_by, updated_at) values (p_key, v, auth.uid(), now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform public.app_admin_log('content.update', 'content', p_key, 'success', jsonb_build_object('key', p_key, 'length', char_length(v)));
end $$;

create or replace function public.app_admin_reset_content(p_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare old text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select value into old from public.site_content where key = p_key;
  if old is null then return; end if;
  insert into public.site_content_versions (key, old_value, new_value, changed_by) values (p_key, old, null, auth.uid());
  delete from public.site_content where key = p_key;
  perform public.app_admin_log('content.reset', 'content', p_key, 'success', jsonb_build_object('key', p_key));
end $$;

-- put back the text a version replaced (the old text of that version, or the default when it was the first edit)
create or replace function public.app_admin_restore_content(p_version_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare ver record;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select * into ver from public.site_content_versions where id = p_version_id;
  if not found then raise exception 'Version not found.'; end if;
  if ver.old_value is null then perform public.app_admin_reset_content(ver.key); else perform public.app_admin_save_content(ver.key, ver.old_value); end if;
  perform public.app_admin_log('content.restore', 'content', ver.key, 'success', jsonb_build_object('key', ver.key, 'version', p_version_id));
end $$;

-- ===== website settings (validated) =====
create table public.site_settings (
  key text primary key check (key in ('site.title', 'org.name', 'announcement', 'default_view', 'default_sy', 'contact')),
  value jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;
revoke all on public.site_settings from anon, authenticated;
grant select on public.site_settings to anon, authenticated;
create policy site_settings_read on public.site_settings for select to anon, authenticated using (true);

create or replace function public.app_admin_save_setting(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare t text; txt text; lvl text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_key in ('site.title', 'org.name') then
    if jsonb_typeof(p_value) <> 'string' then raise exception 'Enter text.'; end if;
    t := btrim(p_value #>> '{}');
    if char_length(t) < 3 or char_length(t) > 120 then raise exception 'Use 3 to 120 characters.'; end if;
    if t ~ '[<>]' then raise exception 'Plain text only: the characters < and > are not allowed.'; end if;
    p_value := to_jsonb(t);
  elsif p_key = 'announcement' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'Invalid announcement.'; end if;
    txt := btrim(coalesce(p_value ->> 'text', '')); lvl := coalesce(p_value ->> 'level', 'info');
    if lvl not in ('info', 'warning') then raise exception 'Choose Information or Warning.'; end if;
    if char_length(txt) > 300 or txt ~ '[<>]' then raise exception 'The announcement must be plain text of 300 characters at most.'; end if;
    if coalesce((p_value ->> 'enabled')::boolean, false) and txt = '' then raise exception 'Enter the announcement text before turning it on.'; end if;
    p_value := jsonb_build_object('enabled', coalesce((p_value ->> 'enabled')::boolean, false), 'text', txt, 'level', lvl);
  elsif p_key = 'default_view' then
    if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') not in ('division', 'dashboard', 'district-view', 'comparative', 'grade-view', 'least-learned', 'data-input', 'manage-records') then
      raise exception 'Choose one of the listed screens.'; end if;
  elsif p_key = 'default_sy' then
    if jsonb_typeof(p_value) <> 'string' or ((p_value #>> '{}') <> 'ALL' and (p_value #>> '{}') !~ '^[0-9]{4}-[0-9]{4}$') then raise exception 'Choose All school years or a school year like 2025-2026.'; end if;
  elsif p_key = 'contact' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'Invalid contact details.'; end if;
    p_value := jsonb_build_object('email', btrim(coalesce(p_value ->> 'email', '')), 'phone', btrim(coalesce(p_value ->> 'phone', '')), 'address', btrim(coalesce(p_value ->> 'address', '')));
    if (p_value ->> 'email') <> '' and (p_value ->> 'email') !~ '^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$' then raise exception 'Enter a valid email address.'; end if;
    if char_length(p_value ->> 'phone') > 40 or (p_value ->> 'phone') ~ '[<>]' or char_length(p_value ->> 'address') > 200 or (p_value ->> 'address') ~ '[<>]' then raise exception 'The phone (40) or address (200) is too long or contains characters that are not allowed.'; end if;
  else
    raise exception 'Unknown setting.';
  end if;
  insert into public.site_settings (key, value, updated_by, updated_at) values (p_key, p_value, auth.uid(), now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform public.app_admin_log('settings.update', 'setting', p_key, 'success', jsonb_build_object('key', p_key));
end $$;

-- back to the built-in value: removes the override
create or replace function public.app_admin_clear_setting(p_key text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  delete from public.site_settings where key = p_key;
  if found then perform public.app_admin_log('settings.clear', 'setting', p_key, 'success', jsonb_build_object('key', p_key)); end if;
end $$;

-- ===== images and media =====
create table public.site_media (
  id uuid primary key default gen_random_uuid(),
  path text not null unique check (path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'),
  original_name text not null check (char_length(original_name) between 1 and 200),
  mime text not null check (mime in ('image/png', 'image/jpeg', 'image/webp')),
  size_bytes integer not null check (size_bytes between 1 and 2097152),
  alt_text text not null default '' check (char_length(alt_text) <= 200),
  uploaded_by uuid,
  uploaded_at timestamptz not null default now()
);
create table public.site_media_slots (
  slot text primary key check (slot in ('brand.logo', 'print.header_logo', 'print.footer_logo_1', 'print.footer_logo_2', 'print.footer_logo_3')),
  media_id uuid not null references public.site_media(id) on delete restrict,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.site_media enable row level security;
alter table public.site_media_slots enable row level security;
revoke all on public.site_media, public.site_media_slots from anon, authenticated;
grant select on public.site_media, public.site_media_slots to anon, authenticated;
create policy site_media_read on public.site_media for select to anon, authenticated using (true);
create policy site_media_slots_read on public.site_media_slots for select to anon, authenticated using (true);

create or replace function public.app_admin_register_media(p_path text, p_name text, p_mime text, p_size integer, p_alt text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_mime not in ('image/png', 'image/jpeg', 'image/webp') then raise exception 'Only PNG, JPEG or WebP images are allowed.'; end if;
  if p_size is null or p_size < 1 or p_size > 2097152 then raise exception 'The image must be 2 MB or smaller.'; end if;
  if p_path is null or p_path !~ ('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.' || case p_mime when 'image/png' then 'png' when 'image/jpeg' then 'jpg' else 'webp' end || '$') then
    raise exception 'The file name does not match its type.';
  end if;
  if btrim(coalesce(p_alt, '')) ~ '[<>]' then raise exception 'Plain text only for the description.'; end if;
  insert into public.site_media (path, original_name, mime, size_bytes, alt_text, uploaded_by)
    values (p_path, left(regexp_replace(btrim(coalesce(p_name, 'image')), '[<>"\\/]', '_', 'g'), 200), p_mime, p_size, left(btrim(coalesce(p_alt, '')), 200), auth.uid()) returning id into v_id;
  perform public.app_admin_log('media.upload', 'media', v_id::text, 'success', jsonb_build_object('name', left(coalesce(p_name, ''), 80), 'size', p_size, 'mime', p_mime));
  return v_id;
end $$;

create or replace function public.app_admin_update_media(p_id uuid, p_alt text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if btrim(coalesce(p_alt, '')) ~ '[<>]' or char_length(btrim(coalesce(p_alt, ''))) > 200 then raise exception 'Plain text only, 200 characters at most.'; end if;
  update public.site_media set alt_text = btrim(coalesce(p_alt, '')) where id = p_id;
  if not found then raise exception 'Image not found.'; end if;
  perform public.app_admin_log('media.update', 'media', p_id::text, 'success', '{}');
end $$;

create or replace function public.app_admin_assign_media(p_slot text, p_media_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_slot not in ('brand.logo', 'print.header_logo', 'print.footer_logo_1', 'print.footer_logo_2', 'print.footer_logo_3') then raise exception 'Unknown image position.'; end if;
  if p_media_id is null then
    delete from public.site_media_slots where slot = p_slot;
  else
    if not exists (select 1 from public.site_media where id = p_media_id) then raise exception 'Image not found.'; end if;
    insert into public.site_media_slots (slot, media_id, updated_by, updated_at) values (p_slot, p_media_id, auth.uid(), now())
      on conflict (slot) do update set media_id = excluded.media_id, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
  perform public.app_admin_log('media.assign', 'media', p_slot, 'success', jsonb_build_object('slot', p_slot, 'media', p_media_id));
end $$;

-- Removes an image record that is not in use; returns its storage path so the page can delete the file too.
create or replace function public.app_admin_delete_media(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_path text; used text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select string_agg(slot, ', ') into used from public.site_media_slots where media_id = p_id;
  if used is not null then raise exception 'This image is still in use (%). Replace or clear those positions first.', used; end if;
  delete from public.site_media where id = p_id returning path into v_path;
  if v_path is null then raise exception 'Image not found.'; end if;
  perform public.app_admin_log('media.delete', 'media', p_id::text, 'success', '{}');
  return v_path;
end $$;

revoke execute on function public.app_admin_list_users(text, text, smallint, bigint, text, text, integer, integer), public.app_admin_user_stats(),
  public.app_admin_create_user(text, text, text, smallint, text, bigint, text), public.app_admin_update_user(uuid, text, text, text, smallint, text, bigint, boolean),
  public.app_admin_set_password(uuid, text), public.app_admin_activity(text, text, integer, integer), public.app_admin_data_changes(integer, integer),
  public.app_admin_save_content(text, text), public.app_admin_reset_content(text), public.app_admin_restore_content(bigint),
  public.app_admin_save_setting(text, jsonb), public.app_admin_clear_setting(text), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
  public.app_admin_assign_media(text, uuid), public.app_admin_delete_media(uuid) from public, anon;
grant execute on function public.app_admin_list_users(text, text, smallint, bigint, text, text, integer, integer), public.app_admin_user_stats(),
  public.app_admin_create_user(text, text, text, smallint, text, bigint, text), public.app_admin_update_user(uuid, text, text, text, smallint, text, bigint, boolean),
  public.app_admin_set_password(uuid, text), public.app_admin_activity(text, text, integer, integer), public.app_admin_data_changes(integer, integer),
  public.app_admin_save_content(text, text), public.app_admin_reset_content(text), public.app_admin_restore_content(bigint),
  public.app_admin_save_setting(text, jsonb), public.app_admin_clear_setting(text), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
  public.app_admin_assign_media(text, uuid), public.app_admin_delete_media(uuid) to authenticated;

-- ===== storage: a public bucket for site images; only an administrator can write to it =====
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      values ('site-media', 'site-media', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
      on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];
    execute 'drop policy if exists site_media_admin_insert on storage.objects';
    execute 'drop policy if exists site_media_admin_update on storage.objects';
    execute 'drop policy if exists site_media_admin_delete on storage.objects';
    execute $p$create policy site_media_admin_insert on storage.objects for insert to authenticated with check (bucket_id = 'site-media' and public.app_is_admin())$p$;
    execute $p$create policy site_media_admin_update on storage.objects for update to authenticated using (bucket_id = 'site-media' and public.app_is_admin()) with check (bucket_id = 'site-media' and public.app_is_admin())$p$;
    execute $p$create policy site_media_admin_delete on storage.objects for delete to authenticated using (bucket_id = 'site-media' and public.app_is_admin())$p$;
  end if;
end $$;

create trigger audit_site_content after insert or update or delete on public.site_content for each row execute function public.app_audit();
