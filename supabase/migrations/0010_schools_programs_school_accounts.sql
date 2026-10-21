-- 0010_schools_programs_school_accounts.sql
--   1. Baseline school year on each record (records.baseline_sy).
--   2. A schools list with Special Programs / IPED classification (a school can be in one or both, never duplicated).
--   3. School-level accounts: role 'school', tied to ONE school. Created only by a Supervisor or Admin, through a
--      database function that runs on the server with a built-in permission check (no service key in the browser).
-- Safe to run once on a project that already has 0001 to 0009. Run it BEFORE deploying the matching app version.
-- Nothing is bulk-modified: existing records keep their free-text school, baseline_sy stays empty for existing rows
-- (shown as "SY not recorded"), and no accounts are created.

-- ===== 1. Baseline school year =====
alter table public.assessment_records
  add column baseline_sy text check (baseline_sy ~ '^[0-9]{4}-[0-9]{4}$');

-- ===== 2. Schools and program classification =====
create table public.schools (
  id bigint generated always as identity primary key,
  name text not null check (btrim(name) <> '' and char_length(name) <= 200),
  district_id smallint not null references public.districts(id),
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- one row per school per district (case and spacing ignored): assigning a program never creates a second school
create unique index schools_district_name_key on public.schools (district_id, lower(btrim(name)));

create table public.school_programs (
  school_id bigint not null references public.schools(id) on delete restrict,
  program text not null check (program in ('special_programs', 'iped')),
  primary key (school_id, program)
);
create index on public.school_programs (program);

alter table public.assessment_records
  add column school_id bigint references public.schools(id);
create index on public.assessment_records (school_id) where school_id is not null;

create trigger touch_schools before update on public.schools
  for each row execute function public.app_touch_updated_at();

-- ===== 3. School accounts: profile columns =====
alter type public.app_role add value if not exists 'school';
alter table public.profiles add column school_id bigint references public.schools(id);
-- (role is compared as text so this file also works when run in a single transaction)
alter table public.profiles add constraint school_scope check (
  (role::text = 'school') = (school_id is not null) and (role::text <> 'school' or (district_id is not null and education_level is null)));
-- one ACTIVE account per school
create unique index profiles_one_active_account_per_school on public.profiles (school_id) where school_id is not null and active;

-- ===== helper functions =====
create or replace function public.app_school_of_user() returns bigint
language sql stable security definer set search_path = '' as $$
  select school_id from public.profiles where id = auth.uid() and active and school_id is not null
$$;

create or replace function public.app_school_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select s.district_id from public.schools s where s.id = public.app_school_of_user() and s.active
$$;

-- the program a learning area belongs to (MAPEH and anything else: none)
create or replace function public.app_area_program(area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when area like 'SPA - %' or area like 'SPS - %' or area like 'SPFL - %' then 'special_programs'
              when area like 'IPED - %' then 'iped' end
$$;

create or replace function public.app_school_allows_area(sid bigint, area text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.school_programs p where p.school_id = sid and p.program = public.app_area_program(area))
$$;

revoke execute on function public.app_school_of_user(), public.app_school_district_of_user(), public.app_area_program(text),
  public.app_school_allows_area(bigint, text) from public, anon;
grant execute on function public.app_school_of_user(), public.app_school_district_of_user(), public.app_area_program(text),
  public.app_school_allows_area(bigint, text) to authenticated;

-- ===== RLS: schools and classifications are read-only through the API =====
alter table public.schools enable row level security;
alter table public.school_programs enable row level security;
revoke all on public.schools, public.school_programs from anon, authenticated;
grant select on public.schools, public.school_programs to authenticated;

-- Division users see every school; a coordinator the schools of their own district; a school account only its own school.
create policy schools_select on public.schools for select to authenticated
  using (public.app_is_division_user()
         or (public.app_role_of_user()::text = 'district_coordinator' and district_id = public.app_district_of_user())
         or id = public.app_school_of_user());
create policy school_programs_select on public.school_programs for select to authenticated
  using (exists (select 1 from public.schools s where s.id = school_programs.school_id));

-- ===== RLS: records of a school account =====
-- Added next to the existing policies (policies combine with OR), so division and coordinator access is untouched.
-- A school account sees and writes only records of ITS school, only in the learning areas of ITS program(s),
-- only in its school's district, and never deleted rows. It cannot move a record to another school.
create policy records_school_select on public.assessment_records for select to authenticated
  using (school_id is not null and school_id = public.app_school_of_user() and deleted_at is null
         and public.app_school_allows_area(school_id, learning_area));
create policy records_school_insert on public.assessment_records for insert to authenticated
  with check (school_id is not null and school_id = public.app_school_of_user() and deleted_at is null
              and district_id = public.app_school_district_of_user() and public.app_school_allows_area(school_id, learning_area));
create policy records_school_update on public.assessment_records for update to authenticated
  using (school_id is not null and school_id = public.app_school_of_user() and deleted_at is null
         and public.app_school_allows_area(school_id, learning_area))
  with check (school_id is not null and school_id = public.app_school_of_user() and deleted_at is null
              and district_id = public.app_school_district_of_user() and public.app_school_allows_area(school_id, learning_area));
-- (no delete policy and the delete function refuses school accounts: school accounts cannot delete)

grant insert (school_id, baseline_sy) on public.assessment_records to authenticated;
grant update (school_id, baseline_sy) on public.assessment_records to authenticated;

-- ===== records guard: school link must be consistent =====
create or replace function public.app_records_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  problem text; sname text; sdist smallint; sactive boolean; prog text;
begin
  if tg_op = 'INSERT' or new.grade_level is distinct from old.grade_level or new.learning_area is distinct from old.learning_area then
    problem := public.app_mapeh_rule_problem(new.grade_level, new.learning_area);
    if problem is not null then
      raise exception '%', problem using errcode = '23514', constraint = 'mapeh_grade_rule';
    end if;
  end if;
  if jsonb_typeof(new.least_learned) is distinct from 'array' then
    raise exception 'Least learned competencies must be a list.' using errcode = '23514';
  end if;
  if new.school_id is not null then
    select s.name, s.district_id, s.active into sname, sdist, sactive from public.schools s where s.id = new.school_id;
    if sname is null then raise exception 'That school was not found.'; end if;
    if sdist <> new.district_id then raise exception 'That school belongs to a different district.'; end if;
    if (tg_op = 'INSERT' or new.school_id is distinct from old.school_id) and not sactive then
      raise exception 'That school is inactive.';
    end if;
    prog := public.app_area_program(new.learning_area);
    if prog is not null and (tg_op = 'INSERT' or new.school_id is distinct from old.school_id or new.learning_area is distinct from old.learning_area)
       and not exists (select 1 from public.school_programs p where p.school_id = new.school_id and p.program = prog) then
      raise exception 'That school is not classified under the program of this learning area.';
    end if;
    new.school := sname;   -- the printed school name always matches the school record
  end if;
  new.proficiency_level := public.app_proficiency_level(new.mps);
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

-- ===== school list management (Supervisor or Admin) =====
create or replace function public.app_save_school(p_id bigint, p_name text, p_district_id smallint, p_programs text[], p_active boolean default true) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  nm text := btrim(coalesce(p_name, '')); progs text[]; sid bigint; cur record;
begin
  if not public.app_is_division_user() then raise exception 'Only a Supervisor or Admin can manage schools.' using errcode = '42501'; end if;
  if nm = '' or char_length(nm) > 200 then raise exception 'Enter the school name (200 characters at most).'; end if;
  if not exists (select 1 from public.districts where id = p_district_id) then raise exception 'Choose a district.'; end if;
  select coalesce(array_agg(distinct x), '{}') into progs from unnest(coalesce(p_programs, '{}')) x;
  if cardinality(progs) = 0 or exists (select 1 from unnest(progs) x where x not in ('special_programs', 'iped')) then
    raise exception 'Choose Special Programs, IPED, or both.';
  end if;
  if p_id is null then
    begin
      insert into public.schools (name, district_id, active) values (nm, p_district_id, coalesce(p_active, true)) returning id into sid;
    exception when unique_violation then
      raise exception 'A school with that name already exists in this district. Open it and add the program there instead.';
    end;
  else
    select * into cur from public.schools where id = p_id;
    if not found then raise exception 'School not found.'; end if;
    sid := p_id;
    if cur.district_id <> p_district_id and exists (select 1 from public.assessment_records where school_id = sid) then
      raise exception 'This school has linked records, so it cannot be moved to another district.';
    end if;
    if exists (select 1 from public.school_programs sp
               where sp.school_id = sid and sp.program <> all (progs)
                 and exists (select 1 from public.assessment_records r where r.school_id = sid and r.deleted_at is null and public.app_area_program(r.learning_area) = sp.program)) then
      raise exception 'Cannot remove a program that this school already has records for.';
    end if;
    begin
      update public.schools set name = nm, district_id = p_district_id, active = coalesce(p_active, active) where id = sid;
    exception when unique_violation then
      raise exception 'A school with that name already exists in this district.';
    end;
  end if;
  delete from public.school_programs where school_id = sid and program <> all (progs);
  insert into public.school_programs (school_id, program) select sid, x from unnest(progs) x on conflict do nothing;
  return sid;
end $$;

-- Import many schools at once, all or nothing. A school that already exists (same district and name) gets the extra
-- program added instead of a duplicate row. p_rows: [{"name":"...","district":"...","programs":["iped"]}]
create or replace function public.app_import_schools(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb; i int := 0; created int := 0; updated int := 0; did smallint; nm text; progs text[]; sid bigint; bad text[] := '{}';
begin
  if not public.app_is_division_user() then raise exception 'Only a Supervisor or Admin can manage schools.' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'There are no schools to import.'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'Import at most 1000 schools at a time.'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    nm := btrim(coalesce(r ->> 'name', ''));
    select id into did from public.districts where lower(name) = lower(btrim(coalesce(r ->> 'district', '')));
    select coalesce(array_agg(distinct x), '{}') into progs from jsonb_array_elements_text(coalesce(r -> 'programs', '[]')) x;
    if nm = '' or char_length(nm) > 200 then bad := bad || ('row ' || (i + 1) || ': school name'); continue; end if;
    if did is null then bad := bad || ('row ' || (i + 1) || ': unknown district "' || coalesce(r ->> 'district', '') || '"'); continue; end if;
    if cardinality(progs) = 0 or exists (select 1 from unnest(progs) x where x not in ('special_programs', 'iped')) then
      bad := bad || ('row ' || (i + 1) || ': program must be Special Programs, IPED or Both'); continue;
    end if;
    select id into sid from public.schools where district_id = did and lower(btrim(name)) = lower(nm);
    if sid is null then
      insert into public.schools (name, district_id) values (nm, did) returning id into sid; created := created + 1;
    else updated := updated + 1; end if;
    insert into public.school_programs (school_id, program) select sid, x from unnest(progs) x on conflict do nothing;
  end loop;
  if cardinality(bad) > 0 then
    raise exception 'Nothing was imported. % row(s) have problems: %', cardinality(bad), array_to_string(bad[1:5], '; ');
  end if;
  return jsonb_build_object('created', created, 'updated', updated);
end $$;

-- Records that carry this school's name as free text but are not linked yet (candidates for linking).
create or replace function public.app_count_linkable_records(p_school_id bigint) returns integer
language sql stable security definer set search_path = '' as $$
  select case when public.app_is_division_user() then (
    select count(*)::integer from public.assessment_records r join public.schools s on s.id = p_school_id
    where r.school_id is null and r.deleted_at is null and r.district_id = s.district_id
      and lower(btrim(r.school)) = lower(btrim(s.name)) and public.app_school_allows_area(s.id, r.learning_area)) else 0 end
$$;

-- Explicit, one school at a time: link those records to the school (same district, same name, program matches).
create or replace function public.app_link_school_records(p_school_id bigint) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if not public.app_is_division_user() then raise exception 'Only a Supervisor or Admin can link records.' using errcode = '42501'; end if;
  update public.assessment_records r set school_id = s.id
    from public.schools s
    where s.id = p_school_id and r.school_id is null and r.deleted_at is null and r.district_id = s.district_id
      and lower(btrim(r.school)) = lower(btrim(s.name)) and public.app_school_allows_area(s.id, r.learning_area);
  get diagnostics n = row_count;
  return n;
end $$;

-- ===== school accounts =====
create or replace function public.app_create_school_account(p_username text, p_display_name text, p_school_id bigint, p_password text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uname text := lower(btrim(coalesce(p_username, ''))); dname text := btrim(coalesce(p_display_name, ''));
  sch record; v_id uuid; v_email text;
begin
  if not public.app_is_division_user() then
    raise exception 'Only a Supervisor or Admin can create school accounts.' using errcode = '42501';
  end if;
  if uname !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then
    raise exception 'Username must be 3 to 40 characters: lowercase letters, numbers, dot, dash or underscore.';
  end if;
  if dname = '' or char_length(dname) > 120 then raise exception 'Enter a display name (120 characters at most).'; end if;
  if char_length(coalesce(p_password, '')) < 8 then raise exception 'The password must be at least 8 characters.'; end if;
  select s.id, s.name, s.district_id, s.active into sch from public.schools s where s.id = p_school_id;
  if not found then raise exception 'School not found.'; end if;
  if not sch.active then raise exception 'That school is inactive.'; end if;
  if not exists (select 1 from public.school_programs where school_id = p_school_id) then
    raise exception 'Classify the school as Special Programs or IPED first.';
  end if;
  if exists (select 1 from public.profiles where school_id = p_school_id and active) then
    raise exception 'This school already has an active account.';
  end if;
  v_email := uname || '@users.mapehdavnor.altasme.app';
  if exists (select 1 from public.profiles where lower(username) = uname) or exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'That username is already taken.';
  end if;
  -- one transaction: if anything below fails, nothing is left behind
  v_id := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now());
  insert into public.profiles (id, username, display_name, role, district_id, education_level, school_id, active, must_change_password)
    values (v_id, uname, dname, 'school'::public.app_role, sch.district_id, null, sch.id, true, false);
  return v_id;
end $$;

create or replace function public.app_set_school_account_active(p_profile_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare sid bigint;
begin
  if not public.app_is_division_user() then raise exception 'Only a Supervisor or Admin can change school accounts.' using errcode = '42501'; end if;
  select school_id into sid from public.profiles where id = p_profile_id and school_id is not null;
  if sid is null then raise exception 'That is not a school account.'; end if;
  if p_active and exists (select 1 from public.profiles where school_id = sid and active and id <> p_profile_id) then
    raise exception 'This school already has another active account.';
  end if;
  update public.profiles set active = p_active where id = p_profile_id;
  update auth.users set banned_until = case when p_active then null else now() + interval '100 years' end where id = p_profile_id;
end $$;

create or replace function public.app_list_school_accounts() returns table (
  profile_id uuid, username text, display_name text, active boolean, school_id bigint, school_name text, district_name text, programs text[])
language sql stable security definer set search_path = '' as $$
  select p.id, p.username, p.display_name, p.active, s.id, s.name, d.name,
         coalesce((select array_agg(sp.program order by sp.program) from public.school_programs sp where sp.school_id = s.id), '{}')
  from public.profiles p join public.schools s on s.id = p.school_id join public.districts d on d.id = s.district_id
  where public.app_is_division_user()
  order by d.sort_order, s.name, p.username
$$;

revoke execute on function public.app_save_school(bigint, text, smallint, text[], boolean), public.app_import_schools(jsonb),
  public.app_count_linkable_records(bigint), public.app_link_school_records(bigint),
  public.app_create_school_account(text, text, bigint, text), public.app_set_school_account_active(uuid, boolean),
  public.app_list_school_accounts() from public, anon;
grant execute on function public.app_save_school(bigint, text, smallint, text[], boolean), public.app_import_schools(jsonb),
  public.app_count_linkable_records(bigint), public.app_link_school_records(bigint),
  public.app_create_school_account(text, text, bigint, text), public.app_set_school_account_active(uuid, boolean),
  public.app_list_school_accounts() to authenticated;

-- ===== audit =====
create trigger audit_schools after insert or update or delete on public.schools for each row execute function public.app_audit();
create trigger audit_school_programs after insert or update or delete on public.school_programs for each row execute function public.app_audit();
create trigger audit_profiles after insert or update or delete on public.profiles for each row execute function public.app_audit();
