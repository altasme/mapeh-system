-- setup_all.sql: paste into the Supabase SQL editor and run once, on a NEW project.
-- Order: schema, access rules, audit log, districts, settings. Sample records are loaded later by tools/load-demo-records.mjs.

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
