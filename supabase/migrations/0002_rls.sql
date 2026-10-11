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
