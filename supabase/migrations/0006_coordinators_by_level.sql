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
