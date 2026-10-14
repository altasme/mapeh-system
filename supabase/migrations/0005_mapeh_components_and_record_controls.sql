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
