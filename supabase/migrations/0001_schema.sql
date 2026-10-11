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
