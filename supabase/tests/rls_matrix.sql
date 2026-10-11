-- rls_matrix.sql: Appendix C checks. Run in the Supabase SQL editor AFTER migrations and seed/districts.sql.
-- Everything runs inside one transaction and is rolled back. It creates throwaway users, so it
-- never touches the real accounts. A failed check raises an exception; passes print NOTICE lines.
begin;

insert into auth.users (id, instance_id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_admin@test.invalid'),
  ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_sup@test.invalid'),
  ('00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_coord_asu@test.invalid'),
  ('00000000-0000-0000-0000-0000000000a4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_coord_car@test.invalid');

insert into public.profiles (id, username, display_name, role, district_id) values
  ('00000000-0000-0000-0000-0000000000a1','t_admin','T Admin','admin',null),
  ('00000000-0000-0000-0000-0000000000a2','t_sup','T Sup','supervisor',null),
  ('00000000-0000-0000-0000-0000000000a3','t_coord_asu','T Asu','district_coordinator',(select id from public.districts where name='Asuncion')),
  ('00000000-0000-0000-0000-0000000000a4','t_coord_car','T Car','district_coordinator',(select id from public.districts where name='Carmen'));

insert into public.app_settings (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by,is_demo)
select '2025-2026','Term 1', d.id,'Key Stage 1','Grade 1','MAPEH - Music & Arts',65,80,70,'Approaching Proficiency','00000000-0000-0000-0000-0000000000a1',true
from public.districts d where d.name in ('Asuncion','Carmen');

insert into public.comparative_notes (sy,district_scope,subject,term,analysis,interventions,updated_by) values
  ('2025-2026','Asuncion','ALL','ALL','a','i','00000000-0000-0000-0000-0000000000a1'),
  ('2025-2026','Carmen','ALL','ALL','a','i','00000000-0000-0000-0000-0000000000a1');

do $$
declare
  n int; asu smallint; car smallint; denied boolean; rid bigint;
  claims text;
begin
  select id into asu from public.districts where name='Asuncion';
  select id into car from public.districts where name='Carmen';

  -- ===== Admin =====
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n = 2, 'admin reads all records';
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',car,'Key Stage 1','Grade 1','X',65,80,70,'Approaching Proficiency') returning id into rid;
  update public.assessment_records set district_id = asu where id = rid; get diagnostics n = row_count; assert n = 1, 'admin moves record';
  select count(*) into n from public.audit_log; assert n > 0, 'admin reads audit_log';
  select count(*) into n from public.profiles; assert n = 1, 'admin sees only own profile';
  delete from public.assessment_records where id = rid; get diagnostics n = row_count; assert n = 1, 'admin deletes';
  update public.districts set coordinator_name = coordinator_name where id = asu; get diagnostics n = row_count; assert n = 1, 'admin updates districts';
  update public.app_settings set data = data; get diagnostics n = row_count; assert n = 1, 'admin updates settings';
  denied := false;
  begin update public.profiles set role = 'admin' where id = auth.uid(); get diagnostics n = row_count; denied := (n = 0);
  exception when others then denied := true; end;
  assert denied, 'admin cannot change own role';
  reset role;
  raise notice 'PASS admin';

  -- ===== Supervisor =====
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n = 2, 'supervisor reads all records';
  select count(*) into n from public.audit_log; assert n = 0, 'supervisor cannot read audit_log';
  update public.districts set coordinator_name = coordinator_name where id = car; get diagnostics n = row_count; assert n = 1, 'supervisor updates districts';
  delete from public.assessment_records where district_id = car; get diagnostics n = row_count; assert n = 1, 'supervisor deletes';
  reset role;
  raise notice 'PASS supervisor';

  -- ===== Coordinator, Asuncion =====
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n = 1, 'coordinator reads own district only';
  select count(*) into n from public.assessment_records where district_id = car; assert n = 0, 'coordinator sees 0 rows of other district';
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 1','Grade 1','X',65,80,70,'Approaching Proficiency') returning id into rid;
  denied := false;
  begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',car,'Key Stage 1','Grade 1','X',65,80,70,'Approaching Proficiency');
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'coordinator cannot insert into other district';
  denied := false;
  begin update public.assessment_records set district_id = car where id = rid;
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'coordinator cannot move a record to another district';
  delete from public.assessment_records where id = rid; get diagnostics n = row_count; assert n = 0, 'coordinator cannot delete';
  select count(*) into n from public.comparative_notes; assert n = 1, 'coordinator reads own-scope notes only';
  update public.districts set coordinator_name = 'x' where id = asu; get diagnostics n = row_count; assert n = 0, 'coordinator cannot update districts';
  update public.app_settings set data = data; get diagnostics n = row_count; assert n = 0, 'coordinator cannot update settings';
  select count(*) into n from public.audit_log; assert n = 0, 'coordinator cannot read audit_log';
  select count(*) into n from public.profiles; assert n = 1, 'coordinator sees only own profile';
  denied := false;
  begin update public.profiles set role = 'admin' where id = auth.uid(); get diagnostics n = row_count; denied := (n = 0);
  exception when others then denied := true; end;
  assert denied, 'coordinator cannot change own role';
  reset role;
  raise notice 'PASS coordinator (own district)';

  -- ===== Coordinator, Carmen: cannot see Asuncion =====
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records where district_id = asu; assert n = 0, 'other coordinator sees 0 Asuncion rows';
  select count(*) into n from public.comparative_notes where district_scope = 'Asuncion'; assert n = 0, 'other coordinator sees 0 Asuncion notes';
  reset role;
  raise notice 'PASS coordinator (other district)';

  -- ===== Signed out =====
  set local role anon;
  denied := false;
  begin perform 1 from public.assessment_records limit 1;
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on assessment_records';
  denied := false;
  begin perform 1 from public.profiles limit 1;
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on profiles';
  reset role;
  raise notice 'PASS signed out';
end $$;

rollback;
