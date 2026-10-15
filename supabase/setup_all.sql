-- setup_all.sql: paste into the Supabase SQL editor and run once, on a NEW project (schema, access rules, audit log,
-- education levels, MAPEH rules and record controls, coordinators by level, districts, settings). An existing project that already ran 0001 to 0003 needs only 0004 to 0007.
-- Sample records are loaded later by tools/load-demo-records.mjs.

-- ===== supabase/migrations/0001_schema.sql =====
-- 0001_schema.sql: tables, types, indexes, triggers (CLAUDE.md section 7)

create type public.app_role as enum ('admin', 'supervisor', 'district_coordinator');

create table public.districts (
  id smallint generated always as identity primary key,
  name text not null unique,
  coordinator_name text not null default '',
  coordinator_position text not null default '',
  sort_order smallint not null
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  role public.app_role not null,
  district_id smallint references public.districts(id),
  constraint coordinator_needs_district
    check (role <> 'district_coordinator' or district_id is not null)
);

create table public.assessment_records (
  id bigint generated always as identity primary key,
  sy text not null check (sy ~ '^[0-9]{4}-[0-9]{4}$'),
  term text not null check (term in ('Term 1', 'Term 2', 'Term 3')),
  district_id smallint not null references public.districts(id),
  school text not null default '',
  key_stage text not null,
  grade_level text not null,
  learning_area text not null,
  baseline_mps numeric(5,2) not null check (baseline_mps between 0 and 100),
  mps numeric(5,2) not null check (mps between 0 and 100),
  pct75 numeric(5,2) not null check (pct75 between 0 and 100),
  proficiency_level text not null,
  least_learned jsonb not null default '[]',
  is_demo boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.assessment_records (district_id, sy, term);
create index on public.assessment_records (learning_area);

create table public.comparative_notes (
  id bigint generated always as identity primary key,
  sy text not null,
  district_scope text not null,
  subject text not null,
  term text not null,
  analysis text not null default '',
  interventions text not null default '',
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (sy, district_scope, subject, term)
);

create table public.app_settings (
  id smallint primary key default 1 check (id = 1),
  data jsonb not null,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);

-- updated_at touch
create or replace function public.app_touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger touch_assessment_records before update on public.assessment_records
  for each row execute function public.app_touch_updated_at();
create trigger touch_comparative_notes before update on public.comparative_notes
  for each row execute function public.app_touch_updated_at();
create trigger touch_app_settings before update on public.app_settings
  for each row execute function public.app_touch_updated_at();

-- created_by cannot be spoofed by a signed-in client. When there is no JWT user
-- (SQL editor seed run), the supplied value is kept.
create or replace function public.app_force_created_by() returns trigger
language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end $$;

create trigger force_created_by before insert on public.assessment_records
  for each row execute function public.app_force_created_by();

-- ===== supabase/migrations/0002_rls.sql =====
-- 0002_rls.sql: helper functions and policies (CLAUDE.md section 8)

create or replace function public.app_role_of_user() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.app_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select district_id from public.profiles where id = auth.uid()
$$;

create or replace function public.app_is_division_user() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role_of_user() in ('admin', 'supervisor'), false)
$$;

create or replace function public.app_district_name_of_user() returns text
language sql stable security definer set search_path = '' as $$
  select d.name from public.districts d where d.id = public.app_district_of_user()
$$;

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.assessment_records to authenticated;
grant select, insert, update on public.comparative_notes to authenticated;
grant select, update on public.districts to authenticated;
grant select, update on public.app_settings to authenticated;
grant select on public.profiles to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.app_role_of_user(), public.app_district_of_user(),
  public.app_is_division_user(), public.app_district_name_of_user() to authenticated;

alter table public.assessment_records enable row level security;
alter table public.comparative_notes enable row level security;
alter table public.districts enable row level security;
alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;

-- assessment_records
create policy records_select on public.assessment_records for select to authenticated
  using (public.app_is_division_user() or district_id = public.app_district_of_user());
create policy records_insert on public.assessment_records for insert to authenticated
  with check (public.app_is_division_user() or district_id = public.app_district_of_user());
create policy records_update on public.assessment_records for update to authenticated
  using (public.app_is_division_user() or district_id = public.app_district_of_user())
  with check (public.app_is_division_user() or district_id = public.app_district_of_user());
create policy records_delete on public.assessment_records for delete to authenticated
  using (public.app_is_division_user());

-- comparative_notes
create policy notes_select on public.comparative_notes for select to authenticated
  using (public.app_is_division_user() or district_scope = public.app_district_name_of_user());
create policy notes_insert on public.comparative_notes for insert to authenticated
  with check (public.app_is_division_user() or district_scope = public.app_district_name_of_user());
create policy notes_update on public.comparative_notes for update to authenticated
  using (public.app_is_division_user() or district_scope = public.app_district_name_of_user())
  with check (public.app_is_division_user() or district_scope = public.app_district_name_of_user());

-- districts
create policy districts_select on public.districts for select to authenticated using (true);
create policy districts_update on public.districts for update to authenticated
  using (public.app_is_division_user()) with check (public.app_is_division_user());

-- app_settings
create policy settings_select on public.app_settings for select to authenticated using (true);
create policy settings_update on public.app_settings for update to authenticated
  using (public.app_is_division_user()) with check (public.app_is_division_user());

-- profiles: own row only, no writes
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid());

-- ===== supabase/migrations/0003_audit.sql =====
-- 0003_audit.sql: audit_log filled by triggers (CLAUDE.md section 11)

create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  table_name text not null,
  action text not null,
  row_id text,
  old jsonb,
  new jsonb
);

alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
create policy audit_select on public.audit_log for select to authenticated
  using (public.app_role_of_user() = 'admin');

create or replace function public.app_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  rid text;
begin
  if tg_op = 'DELETE' then
    rid := to_jsonb(old)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, old)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(old));
    return old;
  elsif tg_op = 'UPDATE' then
    rid := to_jsonb(new)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, old, new)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(old), to_jsonb(new));
    return new;
  else
    rid := to_jsonb(new)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, new)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(new));
    return new;
  end if;
end $$;

create trigger audit_assessment_records after insert or update or delete on public.assessment_records
  for each row execute function public.app_audit();
create trigger audit_comparative_notes after insert or update or delete on public.comparative_notes
  for each row execute function public.app_audit();
create trigger audit_districts after insert or update or delete on public.districts
  for each row execute function public.app_audit();
create trigger audit_app_settings after insert or update or delete on public.app_settings
  for each row execute function public.app_audit();

-- ===== supabase/migrations/0004_education_levels.sql =====
-- 0004_education_levels.sql: separate Elementary and Secondary coordinators.
-- Safe to run once on a project that already has 0001 to 0003. Run it BEFORE deploying the matching app version.
--
-- Model:
--   * Every assessment record has an education_level ('elementary' or 'secondary'), derived from its grade level
--     (Grade 1-6 elementary, Grade 7-12 secondary) as a generated column, so it can never disagree with the grade.
--   * Coordinator profiles carry a district AND an education level. Admin and Supervisor carry neither.
--   * Row Level Security checks district AND level on every read, insert and update of records and notes.
--   * profiles.active retires an account without deleting it. profiles.must_change_password gates ALL data access
--     until the user sets a new password (cleared by a trigger when the Auth password actually changes).

-- ===== A. Education level on records =====
create or replace function public.app_education_level(g text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when g in ('Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6') then 'elementary'
    when g in ('Grade 7','Grade 8','Grade 9','Grade 10','Grade 11','Grade 12') then 'secondary'
  end
$$;

alter table public.assessment_records
  add column education_level text generated always as (public.app_education_level(grade_level)) stored not null;
alter table public.assessment_records
  add constraint assessment_records_education_level_check check (education_level in ('elementary', 'secondary'));
create index on public.assessment_records (district_id, education_level, sy, term);

-- ===== B. Profiles: level, active, forced password change =====
alter table public.profiles
  add column education_level text check (education_level in ('elementary', 'secondary')),
  add column active boolean not null default true,
  add column must_change_password boolean not null default false;

-- The original district-wide coordinators could see both levels. Retire them (reversible: set active = true again).
update public.profiles set active = false where role = 'district_coordinator' and education_level is null;

alter table public.profiles drop constraint coordinator_needs_district;
alter table public.profiles add constraint coordinator_scope check (
  role <> 'district_coordinator' or (district_id is not null and (education_level is not null or not active)));
alter table public.profiles add constraint division_has_no_level check (role = 'district_coordinator' or education_level is null);

-- ===== C. Helper functions (the single place access is decided) =====
-- A session is usable only when the profile exists, is active, and the password is no longer an initial one.
create or replace function public.app_session_ok() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select active and not must_change_password from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.app_role_of_user() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid() and active and not must_change_password
$$;

create or replace function public.app_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select district_id from public.profiles where id = auth.uid() and active and not must_change_password
$$;

create or replace function public.app_education_level_of_user() returns text
language sql stable security definer set search_path = '' as $$
  select education_level from public.profiles where id = auth.uid() and active and not must_change_password
$$;

-- Division users see everything. A coordinator sees a record only in their own district AND their own level.
create or replace function public.app_can_access_record(d smallint, g text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.app_is_division_user() or (
    public.app_role_of_user() = 'district_coordinator'
    and d is not null and d = public.app_district_of_user()
    and public.app_education_level(g) is not null
    and public.app_education_level(g) = public.app_education_level_of_user())
$$;

-- Same rule for notes, which are keyed by district name and level ('all' is reserved for division users)
create or replace function public.app_can_access_note(scope text, lvl text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.app_is_division_user() or (
    public.app_role_of_user() = 'district_coordinator'
    and scope = public.app_district_name_of_user()
    and lvl = public.app_education_level_of_user())
$$;

revoke execute on function public.app_session_ok(), public.app_education_level_of_user(),
  public.app_can_access_record(smallint, text), public.app_can_access_note(text, text), public.app_education_level(text) from anon;
grant execute on function public.app_session_ok(), public.app_education_level_of_user(),
  public.app_can_access_record(smallint, text), public.app_can_access_note(text, text), public.app_education_level(text) to authenticated;

-- ===== D. Policies: records =====
drop policy records_select on public.assessment_records;
drop policy records_insert on public.assessment_records;
drop policy records_update on public.assessment_records;
drop policy records_delete on public.assessment_records;
create policy records_select on public.assessment_records for select to authenticated
  using (public.app_can_access_record(district_id, grade_level));
create policy records_insert on public.assessment_records for insert to authenticated
  with check (public.app_can_access_record(district_id, grade_level));
create policy records_update on public.assessment_records for update to authenticated
  using (public.app_can_access_record(district_id, grade_level))
  with check (public.app_can_access_record(district_id, grade_level));
create policy records_delete on public.assessment_records for delete to authenticated
  using (public.app_is_division_user());

-- ===== E. Notes: one set per district AND level =====
alter table public.comparative_notes
  add column education_level text not null default 'all' check (education_level in ('all', 'elementary', 'secondary'));
alter table public.comparative_notes drop constraint comparative_notes_sy_district_scope_subject_term_key;
alter table public.comparative_notes add constraint comparative_notes_scope_key unique (sy, district_scope, education_level, subject, term);
drop policy notes_select on public.comparative_notes;
drop policy notes_insert on public.comparative_notes;
drop policy notes_update on public.comparative_notes;
create policy notes_select on public.comparative_notes for select to authenticated
  using (public.app_can_access_note(district_scope, education_level));
create policy notes_insert on public.comparative_notes for insert to authenticated
  with check (public.app_can_access_note(district_scope, education_level));
create policy notes_update on public.comparative_notes for update to authenticated
  using (public.app_can_access_note(district_scope, education_level))
  with check (public.app_can_access_note(district_scope, education_level));

-- ===== F. Clear the forced-change flag when the Auth password really changes =====
-- GoTrue updates auth.users.encrypted_password when a user sets a new password (and when an admin resets one).
-- tools/reset-password.mjs sets the flag again after an administrative reset.
create or replace function public.app_password_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles set must_change_password = false where id = new.id and must_change_password;
  return new;
end $$;

drop trigger if exists app_password_changed on auth.users;
create trigger app_password_changed after update of encrypted_password on auth.users
  for each row when (old.encrypted_password is distinct from new.encrypted_password)
  execute function public.app_password_changed();

-- ===== supabase/migrations/0005_mapeh_components_and_record_controls.sql =====
-- 0005_mapeh_components_and_record_controls.sql: MAPEH component structure, grade rules, and edit / soft delete of records.
-- Safe to run once on a project that already has 0001 to 0004. Run it BEFORE deploying the matching app version
-- (the new column privileges refuse the previous app's insert path, which sent is_demo).
--
-- Model:
--   * Learning areas. Overall MAPEH is its own official record ("MAPEH - Overall"), never computed from the parts.
--     Components: "MAPEH - Music", "MAPEH - Arts", "MAPEH - PE", "MAPEH - Health".
--     Legacy combined areas ("MAPEH - Music & Arts", "MAPEH - PE & Health") stay readable and editable.
--   * Grade rules (checked by a trigger, so they hold for the app, Excel imports and direct API calls alike):
--       Grade 1 to 3   : "MAPEH - Overall" only (no components, no legacy combined areas)
--       Grade 4 to 10  : Overall plus the four components (no legacy combined areas on new or changed rows)
--       Grade 11 to 12 : no MAPEH-family areas
--     IPED, SPA, SPS, SPFL and every other area are not touched. Existing rows that already break a rule are kept
--     and flagged in the app; the rule is enforced when a row is created or its grade or learning area changes.
--   * proficiency_level is computed by the database from mps (same 90 / 85 / 80 / 75 scale as the app's getPL).
--   * Editing: coordinators edit inside their district and level, Admin and Supervisor everywhere. Only the
--     business columns can be written; ownership, deletion and audit columns cannot.
--   * Deleting is soft. Rows are hidden, never destroyed, and only division users can see and restore them.
--     Direct DELETE on assessment_records is revoked for everyone but the database owner.

-- ===== A. Columns =====
alter table public.assessment_records
  add column updated_by uuid references auth.users(id),
  add column deleted_at timestamptz,
  add column deleted_by uuid references auth.users(id),
  add column delete_reason text;
create index on public.assessment_records (deleted_at) where deleted_at is not null;

-- ===== B. MAPEH rules =====
create or replace function public.app_mapeh_rule_problem(g text, area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when area not in ('MAPEH - Overall','MAPEH - Music','MAPEH - Arts','MAPEH - PE','MAPEH - Health',
                      'MAPEH - Music & Arts','MAPEH - PE & Health') then null
    when g in ('Grade 1','Grade 2','Grade 3') and area <> 'MAPEH - Overall'
      then 'Grades 1 to 3 are recorded as overall MAPEH only. Music, Arts, PE and Health are not recorded separately for these grades.'
    when g in ('Grade 4','Grade 5','Grade 6','Grade 7','Grade 8','Grade 9','Grade 10')
         and area in ('MAPEH - Music & Arts','MAPEH - PE & Health')
      then 'Grades 4 to 10 are recorded as overall MAPEH plus Music, Arts, PE and Health. The combined Music & Arts and PE & Health areas are no longer used.'
    when g in ('Grade 11','Grade 12')
      then 'MAPEH is not assessed in Grades 11 and 12.'
    else null
  end
$$;

create or replace function public.app_proficiency_level(m numeric) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when m >= 90 then 'Advanced' when m >= 85 then 'Proficient' when m >= 80 then 'Approaching Proficiency'
              when m >= 75 then 'Developing' else 'Beginning' end
$$;

-- One guard trigger: MAPEH rules (on create, or when grade / area change), computed proficiency, editor stamp.
create or replace function public.app_records_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  problem text;
begin
  if tg_op = 'INSERT' or new.grade_level is distinct from old.grade_level or new.learning_area is distinct from old.learning_area then
    problem := public.app_mapeh_rule_problem(new.grade_level, new.learning_area);
    if problem is not null then
      raise exception '%', problem using errcode = '23514', constraint = 'mapeh_grade_rule';
    end if;
  end if;
  new.proficiency_level := public.app_proficiency_level(new.mps);
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

create trigger records_guard before insert or update on public.assessment_records
  for each row execute function public.app_records_guard();

-- ===== C. Who can write what (column privileges) =====
-- authenticated may no longer delete, and may write only the business columns. is_demo, created_*, deleted_*,
-- updated_* and the generated education_level are not writable through the API.
revoke insert, update, delete on public.assessment_records from authenticated;
grant insert (sy, term, district_id, school, key_stage, grade_level, learning_area, baseline_mps, mps, pct75, proficiency_level, least_learned)
  on public.assessment_records to authenticated;
grant update (sy, term, district_id, school, key_stage, grade_level, learning_area, baseline_mps, mps, pct75, proficiency_level, least_learned)
  on public.assessment_records to authenticated;

-- ===== D. Policies: deleted rows are visible to division users only, and never editable =====
drop policy records_select on public.assessment_records;
drop policy records_update on public.assessment_records;
drop policy records_delete on public.assessment_records;
create policy records_select on public.assessment_records for select to authenticated
  using (public.app_can_access_record(district_id, grade_level) and (deleted_at is null or public.app_is_division_user()));
create policy records_update on public.assessment_records for update to authenticated
  using (public.app_can_access_record(district_id, grade_level) and deleted_at is null)
  with check (public.app_can_access_record(district_id, grade_level) and deleted_at is null);

-- ===== E. Soft delete and restore (the only way to delete) =====
-- Atomic: if any requested row is outside the caller's scope, nothing changes and 42501 is raised.
create or replace function public.app_delete_records(p_ids bigint[], p_reason text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  ids bigint[];
  n integer;
begin
  if not public.app_session_ok() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  select coalesce(array_agg(distinct x), '{}') into ids from unnest(p_ids) x;
  if cardinality(ids) = 0 then return 0; end if;
  if cardinality(ids) > 1000 then
    raise exception 'Too many records in one request.' using errcode = '22023';
  end if;
  if exists (select 1 from public.assessment_records r
             where r.id = any(ids) and r.deleted_at is null and not public.app_can_access_record(r.district_id, r.grade_level)) then
    raise exception 'You do not have access to one or more of these records.' using errcode = '42501';
  end if;
  update public.assessment_records set deleted_at = now(), deleted_by = auth.uid(), delete_reason = nullif(btrim(p_reason), '')
    where id = any(ids) and deleted_at is null;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.app_restore_records(p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if not public.app_is_division_user() then
    raise exception 'Only the division team can restore records.' using errcode = '42501';
  end if;
  update public.assessment_records set deleted_at = null, deleted_by = null, delete_reason = null
    where id = any(p_ids) and deleted_at is not null;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.app_delete_records_by_sy(p_sy text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if not public.app_is_division_user() then
    raise exception 'Only the division team can delete in bulk.' using errcode = '42501';
  end if;
  update public.assessment_records set deleted_at = now(), deleted_by = auth.uid(), delete_reason = 'Bulk delete: school year ' || p_sy
    where sy = p_sy and deleted_at is null;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.app_delete_all_records() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if not public.app_is_division_user() then
    raise exception 'Only the division team can delete in bulk.' using errcode = '42501';
  end if;
  update public.assessment_records set deleted_at = now(), deleted_by = auth.uid(), delete_reason = 'Bulk delete: all records'
    where deleted_at is null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.app_delete_records(bigint[], text), public.app_restore_records(bigint[]),
  public.app_delete_records_by_sy(text), public.app_delete_all_records(),
  public.app_mapeh_rule_problem(text, text), public.app_proficiency_level(numeric) from public, anon;
grant execute on function public.app_delete_records(bigint[], text), public.app_restore_records(bigint[]),
  public.app_delete_records_by_sy(text), public.app_delete_all_records(),
  public.app_mapeh_rule_problem(text, text), public.app_proficiency_level(numeric) to authenticated;

-- ===== F. Audit: name soft deletes and restores =====
create or replace function public.app_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  rid text;
  act text := tg_op;
begin
  if tg_op = 'DELETE' then
    rid := to_jsonb(old)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, old)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(old));
    return old;
  elsif tg_op = 'UPDATE' then
    rid := to_jsonb(new)->>'id';
    if tg_table_name = 'assessment_records' then
      if old.deleted_at is null and new.deleted_at is not null then act := 'SOFT_DELETE';
      elsif old.deleted_at is not null and new.deleted_at is null then act := 'RESTORE';
      end if;
    end if;
    insert into public.audit_log (actor, table_name, action, row_id, old, new)
      values (auth.uid(), tg_table_name, act, rid, to_jsonb(old), to_jsonb(new));
    return new;
  else
    rid := to_jsonb(new)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, new)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(new));
    return new;
  end if;
end $$;

-- ===== supabase/migrations/0006_coordinators_by_level.sql =====
-- 0006_coordinators_by_level.sql: one Elementary and one Secondary coordinator (name and position) per district.
-- Safe to run once on a project that already has 0001 to 0005. Run it BEFORE deploying the matching app version
-- (the previous app version keeps working, it reads the old columns).
--
-- Each level's details are stored separately. Existing coordinator information is preserved: both levels start with
-- the district's current name and position, which an Admin or Supervisor can then edit per level in Settings.
-- The original columns (coordinator_name, coordinator_position) are kept untouched and are no longer read by the app.
-- Who may change them is unchanged: districts are updatable by Admin and Supervisor only (policy from 0002).
alter table public.districts
  add column elem_coordinator_name text not null default '',
  add column elem_coordinator_position text not null default '',
  add column sec_coordinator_name text not null default '',
  add column sec_coordinator_position text not null default '';

update public.districts set
  elem_coordinator_name = coordinator_name, elem_coordinator_position = coordinator_position,
  sec_coordinator_name = coordinator_name, sec_coordinator_position = coordinator_position;

comment on column public.districts.coordinator_name is 'Legacy, superseded by elem_/sec_coordinator_name (0006). Not read by the app.';
comment on column public.districts.coordinator_position is 'Legacy, superseded by elem_/sec_coordinator_position (0006). Not read by the app.';

-- ===== supabase/migrations/0007_edit_competency.sql =====
-- 0007_edit_competency.sql: correct one least-learned competency entry in place.
-- Safe to run once on a project that already has 0001 to 0006. Run it BEFORE deploying the matching app version.
--
-- A competency entry lives in assessment_records.least_learned (a JSON array on its record). Editing replaces ONE element
-- of that array on the existing record: no row is created, so nothing is duplicated, and the record keeps its district,
-- education level, program, grade level, school year and term.
-- The function is SECURITY INVOKER on purpose: row level security and the column privileges of the caller apply exactly
-- as for a direct update. A coordinator can therefore only edit entries on records in their own district and level, and
-- Admin and Supervisor anywhere, with no extra rules to keep in sync. Deleted records cannot be edited.
-- The caller sends the description it believes it is replacing; if the entry changed meanwhile, nothing is saved.

create or replace function public.app_edit_competency(p_id bigint, p_index integer, p_old_desc text, p_code text, p_desc text) returns integer
language plpgsql security invoker set search_path = '' as $$
declare
  cur jsonb; el jsonb; cur_desc text; n integer;
begin
  p_code := btrim(coalesce(p_code, ''));
  p_desc := btrim(coalesce(p_desc, ''));
  if p_desc = '' then raise exception 'The competency description cannot be empty.'; end if;
  if char_length(p_desc) > 500 then raise exception 'The competency description is too long (500 characters at most).'; end if;
  if p_code = '' then raise exception 'Enter a competency code.'; end if;
  if char_length(p_code) > 40 then raise exception 'The competency code is too long (40 characters at most).'; end if;

  select least_learned into cur from public.assessment_records where id = p_id and deleted_at is null;
  if cur is null or jsonb_typeof(cur) <> 'array' or p_index < 0 or p_index >= jsonb_array_length(cur) then
    raise exception 'That competency could not be found. Reload the page and try again.';
  end if;
  el := cur -> p_index;
  cur_desc := case when jsonb_typeof(el) = 'string' then el #>> '{}'
                   else coalesce(el ->> 'desc', el ->> 'description', el ->> 'competency', '') end;
  if btrim(cur_desc) <> btrim(coalesce(p_old_desc, '')) then
    raise exception 'This competency was changed by someone else. Reload the page and try again.';
  end if;

  update public.assessment_records
    set least_learned = jsonb_set(least_learned, array[p_index::text], jsonb_build_object('code', p_code, 'desc', p_desc))
    where id = p_id and deleted_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'You do not have access to that record.' using errcode = '42501'; end if;
  return n;
end $$;

revoke execute on function public.app_edit_competency(bigint, integer, text, text, text) from public, anon;
grant execute on function public.app_edit_competency(bigint, integer, text, text, text) to authenticated;

-- least_learned must stay a JSON array (the app and every report read it as a list).
create or replace function public.app_records_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  problem text;
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
  new.proficiency_level := public.app_proficiency_level(new.mps);
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

-- ===== supabase/seed/districts.sql =====
-- districts.sql: 11 districts and the client's existing coordinator defaults, verbatim (stars 5 and 6)
insert into public.districts (name, coordinator_name, coordinator_position, sort_order) values
  ('Asuncion',        'Dr. Juan Dela Cruz',        'Public Schools District Supervisor', 1),
  ('B.E. Dujali',     'Maria Clara Santos',        'District Assessment Coordinator',    2),
  ('Carmen',          'Pedro Penduko',             'Principal In-Charge',                3),
  ('Kapalong East',   'Ana Rosa Reyes',            'Public Schools District Supervisor', 4),
  ('Kapalong West',   'Roberto Garcia',            'District Assessment Coordinator',    5),
  ('New Corella',     'Elena Torralba',            'Public Schools District Supervisor', 6),
  ('San Isidro',      'Gabriel Fernandez',         'Principal In-Charge',                7),
  ('Sto. Tomas East', 'Corazon Aquino-Dela Cruz',  'Public Schools District Supervisor', 8),
  ('Sto. Tomas West', 'Ramon Magsaysay Jr.',       'District Assessment Coordinator',    9),
  ('Talaingod',       'Bayanihan Datu',            'Principal In-Charge',                10),
  ('Langilan',        'Luzviminda Salcedo',        'Public Schools District Supervisor', 11);

-- When migration 0006 (coordinators by level) is already applied, give both levels the same starting details.
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'districts' and column_name = 'elem_coordinator_name') then
    update public.districts set
      elem_coordinator_name = coordinator_name, elem_coordinator_position = coordinator_position,
      sec_coordinator_name = coordinator_name, sec_coordinator_position = coordinator_position
    where elem_coordinator_name = '' and sec_coordinator_name = '';
  end if;
end $$;


-- ===== supabase/seed/settings.sql =====
-- settings.sql: app_settings row from the client's current defaults
insert into public.app_settings (id, data) values (1, '{
  "sy": "",
  "sigPrepName": "JUAN DELA CRUZ", "sigPrepPos": "District Coordinator",
  "sigCheckName": "MARIA SANTOS", "sigCheckPos": "Education Program Supervisor",
  "sigNoteName": "DR. ALBERTO R. REYES", "sigNotePos": "Schools Division Superintendent",
  "headerLogo": "", "headerL1": "Republic of the Philippines", "headerL2": "Department of Education",
  "headerL3": "REGION XI", "headerL4": "SCHOOLS DIVISION OF DAVAO DEL NORTE",
  "footerLogo1": "", "footerLogo2": "", "footerLogo3": "",
  "footerAddress": "Mankilam, Tagum City, Davao del Norte", "footerPhone": "(084) 823 5170",
  "footerEmail": "depeddavnor.sdo@deped.gov.ph", "footerWebsite": "www.depeddavnor.ph",
  "footerFacebook": "DepEd Davao del Norte"
}'::jsonb);
