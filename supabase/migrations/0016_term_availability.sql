-- 0016_term_availability.sql: Additional Enhancements 1.1, item 4 (term availability for data entry).
--
--   * public.term_availability: one row per (school year, term) the System Administrator has switched OFF. A term with no row is
--     open, so every existing school year and term stays open after this migration. Each school year is configured on its own.
--   * app_set_term_enabled(sy, term, enabled): System Administrator only (same rule as school year availability).
--   * The records guard refuses a NEW record, or a change of school year or term, in a disabled term. It never touches existing
--     records: they stay readable, editable in their other fields, and in every report. Disabling a term deletes nothing.
--   * Reading is open to every signed-in user so the Fast Data Entry screen can grey the term out and explain why.
--   * Term availability only controls encoding. Reports and filters still list every term that has records.

create table if not exists public.term_availability (
  sy text not null check (sy ~ '^[0-9]{4}-[0-9]{4}$'),
  term text not null check (term in ('Term 1', 'Term 2', 'Term 3')),
  enabled boolean not null default true,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (sy, term)
);
alter table public.term_availability enable row level security;
revoke all on public.term_availability from anon, authenticated;
grant select on public.term_availability to authenticated;
drop policy if exists term_availability_select on public.term_availability;
create policy term_availability_select on public.term_availability for select to authenticated using (true);
drop trigger if exists touch_term_availability on public.term_availability;
create trigger touch_term_availability before update on public.term_availability for each row execute function public.app_touch_updated_at();
drop trigger if exists audit_term_availability on public.term_availability;
create trigger audit_term_availability after insert or update or delete on public.term_availability for each row execute function public.app_audit();

create or replace function public.app_set_term_enabled(p_sy text, p_term text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only the System Administrator can change term availability.' using errcode = '42501'; end if;
  if p_sy is null or p_sy !~ '^[0-9]{4}-[0-9]{4}$' then raise exception 'Choose a school year.'; end if;
  if p_term is null or p_term not in ('Term 1', 'Term 2', 'Term 3') then raise exception 'Choose a term.'; end if;
  if p_enabled is null then raise exception 'Choose enabled or disabled.'; end if;
  if p_enabled then
    delete from public.term_availability where sy = p_sy and term = p_term;   -- no row means open
  else
    insert into public.term_availability (sy, term, enabled) values (p_sy, p_term, false)
      on conflict (sy, term) do update set enabled = false;
  end if;
end $$;
revoke execute on function public.app_set_term_enabled(text, text, boolean) from public, anon;
grant execute on function public.app_set_term_enabled(text, text, boolean) to authenticated;

-- records guard: the 0014 version plus the term check
create or replace function public.app_records_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  problem text; sname text; sdist smallint; sactive boolean; slevel text; prog text;
begin
  if (tg_op = 'INSERT' or new.sy is distinct from old.sy)
     and exists (select 1 from public.school_years y where y.sy = new.sy and not y.enabled) then
    raise exception 'School year % is not open for data entry.', new.sy using errcode = '23514', constraint = 'school_year_enabled';
  end if;
  if (tg_op = 'INSERT' or new.sy is distinct from old.sy or new.term is distinct from old.term)
     and exists (select 1 from public.term_availability t where t.sy = new.sy and t.term = new.term and not t.enabled) then
    raise exception '% of school year % is not open for data entry.', new.term, new.sy using errcode = '23514', constraint = 'term_enabled';
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
