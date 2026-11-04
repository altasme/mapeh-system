-- 0015_key_stage_1_regular_and_signatories.sql: client updates of November 2026. Safe to run once after 0001 to 0014.
--
--   1. Key Stage 1 (Grades 1 to 3) is entered as "MAPEH - Overall" (the regular MAPEH) ONLY. Music and Arts, P.E. and Health
--      and the four separate components are refused on new or changed records. This replaces the 0014 rule that refused Overall
--      in Key Stage 1. Records already saved (including any Music and Arts / P.E. and Health entered for Grades 1 to 3
--      meanwhile) are not touched and stay editable.
--   2. District and school signatories: one saved set of "Prepared by / Checked by / Noted by" (name and position) per district
--      and education level, and one per school. A coordinator saves only their own district and level; a school account only its
--      own school; the Supervisor and Admin can save any. Nothing is pre-filled: the sets start empty.

-- ===== 1. Key Stage 1 =====
create or replace function public.app_mapeh_rule_problem(g text, area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when area in ('SHS - Life and Career Skills', 'SHS - Sports/Health/Wellness') then
      case when g in ('Grade 11', 'Grade 12') then null
           else 'Life and Career Skills and Sports/Health/Wellness are Key Stage 4 subjects: enter them for Grades 11 and 12 only.' end
    when area not in ('MAPEH - Overall','MAPEH - Music','MAPEH - Arts','MAPEH - PE','MAPEH - Health',
                      'MAPEH - Music & Arts','MAPEH - PE & Health') then null
    when g in ('Grade 1','Grade 2','Grade 3') and area <> 'MAPEH - Overall'
      then 'Key Stage 1 (Grades 1 to 3) is entered as MAPEH - Overall only. Music and Arts, P.E. and Health and the separate components are not entered for these grades.'
    when g in ('Grade 11','Grade 12')
      then 'MAPEH is not assessed in Grades 11 and 12.'
    else null
  end
$$;

-- ===== 2. District and school signatories =====
create table public.report_signatories (
  id bigint generated always as identity primary key,
  district_id smallint not null references public.districts(id),
  education_level text check (education_level in ('elementary', 'secondary')),
  school_id bigint references public.schools(id),
  prepared_name text not null default '' check (char_length(prepared_name) <= 120),
  prepared_pos text not null default '' check (char_length(prepared_pos) <= 160),
  checked_name text not null default '' check (char_length(checked_name) <= 120),
  checked_pos text not null default '' check (char_length(checked_pos) <= 160),
  noted_name text not null default '' check (char_length(noted_name) <= 120),
  noted_pos text not null default '' check (char_length(noted_pos) <= 160),
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  constraint signatory_scope check ((school_id is null and education_level is not null) or (school_id is not null and education_level is null))
);
create unique index report_signatories_district_key on public.report_signatories (district_id, education_level) where school_id is null;
create unique index report_signatories_school_key on public.report_signatories (school_id) where school_id is not null;
create trigger touch_report_signatories before update on public.report_signatories for each row execute function public.app_touch_updated_at();
create trigger audit_report_signatories after insert or update or delete on public.report_signatories for each row execute function public.app_audit();

alter table public.report_signatories enable row level security;
revoke all on public.report_signatories from anon, authenticated;
grant select on public.report_signatories to authenticated;
-- division users read all; a coordinator the set of their own district and level; a school account its own school
create policy report_signatories_select on public.report_signatories for select to authenticated
  using (public.app_is_division_user()
         or (public.app_role_of_user()::text = 'district_coordinator' and school_id is null
             and district_id = public.app_district_of_user() and education_level = public.app_education_level_of_user())
         or (school_id is not null and school_id = public.app_school_of_user()));

create or replace function public.app_save_signatories(p_prepared_name text, p_prepared_pos text, p_checked_name text, p_checked_pos text,
                                                       p_noted_name text, p_noted_pos text,
                                                       p_district_id smallint default null, p_education_level text default null, p_school_id bigint default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  role text := public.app_role_of_user()::text; d smallint; lvl text; sid bigint; rid bigint;
  pn text := btrim(coalesce(p_prepared_name, '')); pp text := btrim(coalesce(p_prepared_pos, ''));
  cn text := btrim(coalesce(p_checked_name, '')); cp text := btrim(coalesce(p_checked_pos, ''));
  nn text := btrim(coalesce(p_noted_name, '')); np text := btrim(coalesce(p_noted_pos, ''));
begin
  if role is null then raise exception 'Not allowed.' using errcode = '42501'; end if;
  if char_length(pn) > 120 or char_length(cn) > 120 or char_length(nn) > 120 then raise exception 'A name can have at most 120 characters.'; end if;
  if char_length(pp) > 160 or char_length(cp) > 160 or char_length(np) > 160 then raise exception 'A position can have at most 160 characters.'; end if;
  if role = 'school' then
    sid := public.app_school_of_user();
    if sid is null then raise exception 'Not allowed.' using errcode = '42501'; end if;
    select s.district_id into d from public.schools s where s.id = sid;
  elsif role = 'district_coordinator' then
    d := public.app_district_of_user(); lvl := public.app_education_level_of_user();
    if d is null or lvl is null then raise exception 'Not allowed.' using errcode = '42501'; end if;
  elsif role in ('admin', 'supervisor') then
    if p_school_id is not null then
      select s.district_id into d from public.schools s where s.id = p_school_id;
      if d is null then raise exception 'School not found.'; end if;
      sid := p_school_id;
    else
      d := p_district_id; lvl := p_education_level;
      if d is null or lvl not in ('elementary', 'secondary') then raise exception 'Choose a district and an education level, or a school.'; end if;
      if not exists (select 1 from public.districts where id = d) then raise exception 'Choose a district.'; end if;
    end if;
  else
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if sid is not null then
    insert into public.report_signatories (district_id, school_id, prepared_name, prepared_pos, checked_name, checked_pos, noted_name, noted_pos)
      values (d, sid, pn, pp, cn, cp, nn, np)
      on conflict (school_id) where school_id is not null do update
        set prepared_name = excluded.prepared_name, prepared_pos = excluded.prepared_pos, checked_name = excluded.checked_name,
            checked_pos = excluded.checked_pos, noted_name = excluded.noted_name, noted_pos = excluded.noted_pos
      returning id into rid;
  else
    insert into public.report_signatories (district_id, education_level, prepared_name, prepared_pos, checked_name, checked_pos, noted_name, noted_pos)
      values (d, lvl, pn, pp, cn, cp, nn, np)
      on conflict (district_id, education_level) where school_id is null do update
        set prepared_name = excluded.prepared_name, prepared_pos = excluded.prepared_pos, checked_name = excluded.checked_name,
            checked_pos = excluded.checked_pos, noted_name = excluded.noted_name, noted_pos = excluded.noted_pos
      returning id into rid;
  end if;
  return rid;
end $$;
revoke execute on function public.app_save_signatories(text, text, text, text, text, text, smallint, text, bigint) from public, anon;
grant execute on function public.app_save_signatories(text, text, text, text, text, text, smallint, text, bigint) to authenticated;
