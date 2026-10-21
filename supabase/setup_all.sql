-- setup_all.sql: paste into the Supabase SQL editor and run once, on a NEW project (schema, access rules, audit log,
-- education levels, MAPEH rules and record controls, coordinators by level, districts, settings). An existing project that already ran 0001 to 0003 needs only 0004 to 0011.
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

-- ===== supabase/migrations/0008_no_password_gate.sql =====
-- 0008_no_password_gate.sql: client decision for the testing phase: accounts keep their initial passwords and there is
-- no forced or voluntary password change. The "must change password" lock from 0004 is switched off:
--   * every account's flag is cleared, and
--   * the access helper functions no longer look at it, so no account can be locked out by it.
-- The column and the trigger stay in place (harmless), so the lock can be switched back on later by restoring the
-- four helper functions as written in 0004 (see HANDOVER section 15). Safe to run more than once.
update public.profiles set must_change_password = false where must_change_password;

create or replace function public.app_session_ok() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select active from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.app_role_of_user() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.app_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select district_id from public.profiles where id = auth.uid() and active
$$;

create or replace function public.app_education_level_of_user() returns text
language sql stable security definer set search_path = '' as $$
  select education_level from public.profiles where id = auth.uid() and active
$$;

-- ===== supabase/migrations/0009_coordinator_title.sql =====
-- 0009_coordinator_title.sql: "Designated Position" and "Title" become separate fields for each district coordinator.
-- Safe to run once on a project that already has 0001 to 0008. Run it BEFORE deploying the matching app version.
-- Existing values stay in the position columns; the new title columns start empty, so existing reports do not change
-- until a title is entered. Who may edit them is unchanged (Admin and Supervisor, policy from 0002).
alter table public.districts
  add column elem_coordinator_title text not null default '',
  add column sec_coordinator_title text not null default '';

-- ===== supabase/migrations/0010_schools_programs_school_accounts.sql =====
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

-- ===== supabase/migrations/0011_admin_panel.sql =====
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
  public.app_admin_save_setting(text, jsonb), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
  public.app_admin_assign_media(text, uuid), public.app_admin_delete_media(uuid) from public, anon;
grant execute on function public.app_admin_list_users(text, text, smallint, bigint, text, text, integer, integer), public.app_admin_user_stats(),
  public.app_admin_create_user(text, text, text, smallint, text, bigint, text), public.app_admin_update_user(uuid, text, text, text, smallint, text, bigint, boolean),
  public.app_admin_set_password(uuid, text), public.app_admin_activity(text, text, integer, integer), public.app_admin_data_changes(integer, integer),
  public.app_admin_save_content(text, text), public.app_admin_reset_content(text), public.app_admin_restore_content(bigint),
  public.app_admin_save_setting(text, jsonb), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
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
