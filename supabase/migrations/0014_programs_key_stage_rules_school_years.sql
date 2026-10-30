-- 0014_programs_key_stage_rules_school_years.sql: client revision of October 2026 (second round).
-- Safe to run once on a project that has 0001 to 0013. No assessment record is changed, moved or deleted.
--
--   1. MAPEH becomes a school program next to Special Programs and IPED. A school can hold any combination
--      (school_programs is already one row per school per program, so nothing is duplicated). Every existing school is
--      tagged MAPEH once, because every school teaches MAPEH; nothing is tagged Special Programs or IPED by this migration.
--      The records guard now requires a school to be tagged MAPEH for MAPEH records, as it already does for SP and IPED.
--   2. Entry rules: Key Stage 1 (Grades 1 to 3) takes Music and Arts and P.E. and Health and no longer takes MAPEH - Overall
--      on new or changed rows (existing rows stay editable). Two Key Stage 4 subjects are added (SHS - Life and Career Skills,
--      SHS - Sports/Health/Wellness) and may only be entered for Grades 11 and 12. They belong to the MAPEH program (to confirm).
--   3. School years: public.school_years is the single list of years that can be entered (enabled / disabled). Only the System
--      Administrator can change it (app_set_school_year_enabled). The records guard refuses NEW records, or a change of school
--      year, in a disabled year. Existing records are never touched and stay in every report.
-- The Overall MAPEH formula ((Music and Arts + P.E. and Health) / 2) is a reporting calculation done in the app; no stored value changes.

-- ===== 1. MAPEH program =====
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid = 'public.school_programs'::regclass and contype = 'c' loop
    execute format('alter table public.school_programs drop constraint %I', c);
  end loop;
end $$;
alter table public.school_programs add constraint school_programs_program_check check (program in ('special_programs', 'iped', 'mapeh'));

create or replace function public.app_area_program(area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when area like 'SPA - %' or area like 'SPS - %' or area like 'SPFL - %' then 'special_programs'
              when area like 'IPED - %' then 'iped'
              when area like 'MAPEH - %' or area like 'SHS - %' then 'mapeh' end
$$;

insert into public.school_programs (school_id, program) select id, 'mapeh' from public.schools on conflict do nothing;

drop function if exists public.app_save_school(bigint, text, smallint, text[], boolean, text, integer);
create or replace function public.app_save_school(p_id bigint, p_name text, p_district_id smallint, p_programs text[], p_active boolean default true,
                                                  p_education_level text default null, p_deped_id integer default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  nm text := btrim(coalesce(p_name, '')); progs text[]; sid bigint; cur record;
begin
  if not public.app_is_division_user() then raise exception 'Only a Supervisor or Admin can manage schools.' using errcode = '42501'; end if;
  if nm = '' or char_length(nm) > 200 then raise exception 'Enter the school name (200 characters at most).'; end if;
  if not exists (select 1 from public.districts where id = p_district_id) then raise exception 'Choose a district.'; end if;
  if p_education_level is not null and p_education_level not in ('elementary', 'secondary') then raise exception 'Education level must be Elementary or Secondary.'; end if;
  select coalesce(array_agg(distinct x), '{}') into progs from unnest(coalesce(p_programs, '{}')) x;
  if exists (select 1 from unnest(progs) x where x not in ('mapeh', 'special_programs', 'iped')) then
    raise exception 'Programs can only be MAPEH, Special Programs or IPED.';
  end if;
  if p_id is null then
    begin
      insert into public.schools (name, district_id, active, education_level, deped_school_id)
        values (nm, p_district_id, coalesce(p_active, true), p_education_level, p_deped_id) returning id into sid;
    exception when unique_violation then
      raise exception 'A school with that name or DepEd ID already exists in this district. Open it and change it there instead.';
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
      update public.schools set name = nm, district_id = p_district_id, active = coalesce(p_active, active),
             education_level = coalesce(p_education_level, education_level), deped_school_id = coalesce(p_deped_id, deped_school_id) where id = sid;
    exception when unique_violation then
      raise exception 'A school with that name or DepEd ID already exists in this district.';
    end;
  end if;
  delete from public.school_programs where school_id = sid and program <> all (progs);
  insert into public.school_programs (school_id, program) select sid, x from unnest(progs) x on conflict do nothing;
  return sid;
end $$;
revoke execute on function public.app_save_school(bigint, text, smallint, text[], boolean, text, integer) from public, anon;
grant execute on function public.app_save_school(bigint, text, smallint, text[], boolean, text, integer) to authenticated;

-- ===== 2. entry rules by grade =====
create or replace function public.app_mapeh_rule_problem(g text, area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when area in ('SHS - Life and Career Skills', 'SHS - Sports/Health/Wellness') then
      case when g in ('Grade 11', 'Grade 12') then null
           else 'Life and Career Skills and Sports/Health/Wellness are Key Stage 4 subjects: enter them for Grades 11 and 12 only.' end
    when area not in ('MAPEH - Overall','MAPEH - Music','MAPEH - Arts','MAPEH - PE','MAPEH - Health',
                      'MAPEH - Music & Arts','MAPEH - PE & Health') then null
    when g in ('Grade 1','Grade 2','Grade 3') and area = 'MAPEH - Overall'
      then 'MAPEH - Overall is not entered for Key Stage 1 (Grades 1 to 3). Enter Music and Arts and P.E. and Health instead.'
    when g in ('Grade 1','Grade 2','Grade 3') and area not in ('MAPEH - Music & Arts', 'MAPEH - PE & Health')
      then 'Grades 1 to 3 are entered as Music and Arts and P.E. and Health. Music, Arts, PE and Health are not entered separately for these grades.'
    when g in ('Grade 11','Grade 12')
      then 'MAPEH is not assessed in Grades 11 and 12.'
    else null
  end
$$;

-- ===== 3. school years =====
create table public.school_years (
  sy text primary key check (sy ~ '^[0-9]{4}-[0-9]{4}$'),
  enabled boolean not null default true,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);
insert into public.school_years (sy)
  select g || '-' || (g + 1) from generate_series(2025, 2034) g on conflict do nothing;
alter table public.school_years enable row level security;
revoke all on public.school_years from anon, authenticated;
grant select on public.school_years to authenticated;
create policy school_years_select on public.school_years for select to authenticated using (true);
create trigger touch_school_years before update on public.school_years for each row execute function public.app_touch_updated_at();
create trigger audit_school_years after insert or update or delete on public.school_years for each row execute function public.app_audit();

create or replace function public.app_set_school_year_enabled(p_sy text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only the System Administrator can change school year availability.' using errcode = '42501'; end if;
  if p_sy is null or p_sy !~ '^[0-9]{4}-[0-9]{4}$' then raise exception 'Choose a school year.'; end if;
  if p_enabled is null then raise exception 'Choose enabled or disabled.'; end if;
  if not p_enabled and not exists (select 1 from public.school_years where enabled and sy <> p_sy) then
    raise exception 'At least one school year must stay enabled.';
  end if;
  insert into public.school_years (sy, enabled) values (p_sy, p_enabled)
    on conflict (sy) do update set enabled = excluded.enabled;
end $$;
revoke execute on function public.app_set_school_year_enabled(text, boolean) from public, anon;
grant execute on function public.app_set_school_year_enabled(text, boolean) to authenticated;

-- ===== records guard: rules, school year, school, level, program =====
create or replace function public.app_records_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  problem text; sname text; sdist smallint; sactive boolean; slevel text; prog text;
begin
  if (tg_op = 'INSERT' or new.sy is distinct from old.sy)
     and exists (select 1 from public.school_years y where y.sy = new.sy and not y.enabled) then
    raise exception 'School year % is not open for data entry.', new.sy using errcode = '23514', constraint = 'school_year_enabled';
  end if;
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
    select s.name, s.district_id, s.active, s.education_level into sname, sdist, sactive, slevel from public.schools s where s.id = new.school_id;
    if sname is null then raise exception 'That school was not found.'; end if;
    if sdist <> new.district_id then raise exception 'That school belongs to a different district.'; end if;
    if (tg_op = 'INSERT' or new.school_id is distinct from old.school_id) and not sactive then
      raise exception 'That school is inactive.';
    end if;
    if slevel is not null and (tg_op = 'INSERT' or new.school_id is distinct from old.school_id or new.grade_level is distinct from old.grade_level)
       and slevel is distinct from public.app_education_level(new.grade_level) then
      raise exception 'That is a % school, so it cannot take % records.', slevel, coalesce(public.app_education_level(new.grade_level), 'this grade level')
        using errcode = '23514', constraint = 'school_level_rule';
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
