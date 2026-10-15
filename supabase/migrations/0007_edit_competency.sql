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
