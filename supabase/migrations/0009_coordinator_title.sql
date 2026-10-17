-- 0009_coordinator_title.sql: "Designated Position" and "Title" become separate fields for each district coordinator.
-- Safe to run once on a project that already has 0001 to 0008. Run it BEFORE deploying the matching app version.
-- Existing values stay in the position columns; the new title columns start empty, so existing reports do not change
-- until a title is entered. Who may edit them is unchanged (Admin and Supervisor, policy from 0002).
alter table public.districts
  add column elem_coordinator_title text not null default '',
  add column sec_coordinator_title text not null default '';
