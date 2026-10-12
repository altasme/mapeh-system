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
