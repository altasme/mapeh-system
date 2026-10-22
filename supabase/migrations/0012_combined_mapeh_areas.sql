-- 0012_combined_mapeh_areas.sql: the two combined MAPEH areas become enterable again in Grades 4 to 10.
--
-- Why: migration 0005 made "MAPEH - Music & Arts" and "MAPEH - PE & Health" legacy: readable and editable, but refused on
-- new or changed rows. The Fast Data Entry list therefore stopped offering them. The client wants both back, so they
-- are accepted again alongside Overall MAPEH, Music, Arts, PE and Health.
--
-- Rules after this migration (checked by the existing records_guard trigger, so they hold for the app, Excel imports and
-- direct API calls alike):
--   Grade 1 to 3   : "MAPEH - Overall" only                                  (unchanged)
--   Grade 4 to 10  : Overall, Music, Arts, PE, Health, Music & Arts, PE & Health   (the two combined areas are new here)
--   Grade 11 to 12 : no MAPEH-family areas                                   (unchanged)
-- Only the rule function changes. No table, column, policy or row is touched; no data is migrated, deleted or rewritten.
-- Safe to run more than once.

create or replace function public.app_mapeh_rule_problem(g text, area text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when area not in ('MAPEH - Overall','MAPEH - Music','MAPEH - Arts','MAPEH - PE','MAPEH - Health',
                      'MAPEH - Music & Arts','MAPEH - PE & Health') then null
    when g in ('Grade 1','Grade 2','Grade 3') and area <> 'MAPEH - Overall'
      then 'Grades 1 to 3 are recorded as overall MAPEH only. Music, Arts, PE, Health and the combined Music & Arts and PE & Health areas are not recorded separately for these grades.'
    when g in ('Grade 11','Grade 12')
      then 'MAPEH is not assessed in Grades 11 and 12.'
    else null
  end
$$;
