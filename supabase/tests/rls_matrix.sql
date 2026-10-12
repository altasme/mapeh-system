-- rls_matrix.sql: access rules after 0004 (Elementary / Secondary coordinators). Run in the Supabase SQL editor
-- AFTER migrations 0001 to 0004 and seed/districts.sql. One transaction, rolled back: it creates throwaway users and
-- never touches real accounts. A failed check raises an exception; passes print NOTICE lines.
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_admin@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_sup@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_asu_elem@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_asu_sec@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000b3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_car_elem@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000b4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_car_sec@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_legacy@test.invalid','h'),
  ('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_gated@test.invalid','h');

insert into public.profiles (id, username, display_name, role, district_id, education_level, active, must_change_password) values
  ('00000000-0000-0000-0000-0000000000a1','t_admin','T Admin','admin',null,null,true,false),
  ('00000000-0000-0000-0000-0000000000a2','t_sup','T Sup','supervisor',null,null,true,false),
  ('00000000-0000-0000-0000-0000000000b1','t_asu_elem','T Asu Elem','district_coordinator',(select id from public.districts where name='Asuncion'),'elementary',true,false),
  ('00000000-0000-0000-0000-0000000000b2','t_asu_sec','T Asu Sec','district_coordinator',(select id from public.districts where name='Asuncion'),'secondary',true,false),
  ('00000000-0000-0000-0000-0000000000b3','t_car_elem','T Car Elem','district_coordinator',(select id from public.districts where name='Carmen'),'elementary',true,false),
  ('00000000-0000-0000-0000-0000000000b4','t_car_sec','T Car Sec','district_coordinator',(select id from public.districts where name='Carmen'),'secondary',true,false),
  ('00000000-0000-0000-0000-0000000000c1','t_legacy','T Legacy','district_coordinator',(select id from public.districts where name='Asuncion'),null,false,false),
  ('00000000-0000-0000-0000-0000000000c2','t_gated','T Gated','district_coordinator',(select id from public.districts where name='Asuncion'),'elementary',true,true);

insert into public.app_settings (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

-- two records per district: one elementary (Grade 1), one secondary (Grade 8)
insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by,is_demo)
select '2025-2026','Term 1', d.id, g.ks, g.gl,'MAPEH - Music & Arts',65,80,70,'Approaching Proficiency','00000000-0000-0000-0000-0000000000a1',true
from public.districts d, (values ('Key Stage 1','Grade 1'),('Key Stage 3','Grade 8')) g(ks, gl) where d.name in ('Asuncion','Carmen');

insert into public.comparative_notes (sy,district_scope,education_level,subject,term,analysis,interventions,updated_by)
values ('2025-2026','Asuncion','elementary','ALL','ALL','e','e','00000000-0000-0000-0000-0000000000a1'),
       ('2025-2026','Asuncion','secondary','ALL','ALL','s','s','00000000-0000-0000-0000-0000000000a1'),
       ('2025-2026','Carmen','elementary','ALL','ALL','c','c','00000000-0000-0000-0000-0000000000a1'),
       ('2025-2026','Asuncion','all','ALL','ALL','a','a','00000000-0000-0000-0000-0000000000a1');

do $$
declare
  n int; asu smallint; car smallint; denied boolean; rid bigint; code text; total_recs int; total_notes int; exp_own int;
begin
  select count(*) into total_recs from public.assessment_records;
  select count(*) into total_notes from public.comparative_notes;
  select id into asu from public.districts where name='Asuncion';
  select id into car from public.districts where name='Carmen';

  -- generated level is correct, and an unknown grade is refused outright
  perform 1 from public.assessment_records where grade_level='Grade 1' and education_level='elementary'; assert found, 'grade 1 is elementary';
  perform 1 from public.assessment_records where grade_level='Grade 8' and education_level='secondary'; assert found, 'grade 8 is secondary';
  assert public.app_education_level('Grade 6') = 'elementary' and public.app_education_level('Grade 7') = 'secondary', 'boundary grades 6 and 7';
  assert public.app_education_level('Grade 13') is null and public.app_education_level('') is null, 'unknown grades have no level';
  denied := false;
  begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
    values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 13','X',65,80,70,'x','00000000-0000-0000-0000-0000000000a1');
  exception when not_null_violation then denied := true; end;
  assert denied, 'unknown grade is rejected (education level cannot be determined)';
  raise notice 'PASS education level derivation';

  -- ===== Admin and Supervisor: both levels, everywhere =====
  foreach code in array array['a1','a2'] loop
    perform set_config('request.jwt.claims', format('{"sub":"00000000-0000-0000-0000-0000000000%s","role":"authenticated"}', code), true);
    set local role authenticated;
    select count(*) into n from public.assessment_records; assert n = total_recs, code || ' reads every record (' || total_recs || ')';
    select count(*) into n from public.comparative_notes; assert n = total_notes, code || ' reads all notes';
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
      values ('2025-2026','Term 2',car,'Key Stage 3','Grade 9','X',65,80,70,'x') returning id into rid;
    update public.assessment_records set grade_level = 'Grade 2', district_id = asu where id = rid; get diagnostics n = row_count; assert n = 1, code || ' can move a record across level and district';
    delete from public.assessment_records where id = rid; get diagnostics n = row_count; assert n = 1, code || ' deletes';
    reset role;
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
  set local role authenticated; select count(*) into n from public.audit_log; assert n > 0, 'admin reads audit log'; reset role;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
  set local role authenticated; select count(*) into n from public.audit_log; assert n = 0, 'supervisor cannot read audit log'; reset role;
  raise notice 'PASS admin and supervisor';

  -- ===== The four coordinators: own district AND own level only =====
  -- b1 Asuncion elementary, b2 Asuncion secondary, b3 Carmen elementary, b4 Carmen secondary
  declare
    who text; dist smallint; lvl text; otherlvl text; owngrade text; othergrade text; otherdist smallint;
  begin
    for who, dist, lvl, otherlvl, owngrade, othergrade, otherdist in
      select * from (values ('b1', asu, 'elementary', 'secondary', 'Grade 3', 'Grade 9', car),
                            ('b2', asu, 'secondary', 'elementary', 'Grade 9', 'Grade 3', car),
                            ('b3', car, 'elementary', 'secondary', 'Grade 3', 'Grade 9', asu),
                            ('b4', car, 'secondary', 'elementary', 'Grade 9', 'Grade 3', asu)) v
    loop
      perform set_config('request.jwt.claims', format('{"sub":"00000000-0000-0000-0000-0000000000%s","role":"authenticated"}', who), true);
      set local role authenticated;
      reset role; select count(*) into exp_own from public.assessment_records where district_id = dist and education_level = lvl; assert exp_own >= 1, 'fixture has own-scope rows'; set local role authenticated;
      select count(*) into n from public.assessment_records; assert n = exp_own, who || ' sees exactly their own district and level (' || exp_own || ' rows)';
      select count(*) into n from public.assessment_records where education_level = otherlvl; assert n = 0, who || ' sees no ' || otherlvl || ' records, even in the same district';
      select count(*) into n from public.assessment_records where district_id = otherdist; assert n = 0, who || ' sees no other district';
      -- create
      insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
        values ('2025-2026','Term 2',dist,'Key Stage 1',owngrade,'X',65,80,70,'x') returning id into rid;
      denied := false;
      begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
        values ('2025-2026','Term 2',dist,'Key Stage 1',othergrade,'X',65,80,70,'x'); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot create a ' || otherlvl || ' record in the same district';
      denied := false;
      begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
        values ('2025-2026','Term 2',otherdist,'Key Stage 1',owngrade,'X',65,80,70,'x'); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot create a record in another district';
      -- update
      denied := false;
      begin update public.assessment_records set grade_level = othergrade where id = rid; exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot move a record to the other level';
      denied := false;
      begin update public.assessment_records set district_id = otherdist where id = rid; exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot move a record to another district';
      update public.assessment_records set mps = 90 where id = rid; get diagnostics n = row_count; assert n = 1, who || ' can edit own-scope records';
      update public.assessment_records set mps = 1 where education_level = otherlvl; get diagnostics n = row_count; assert n = 0, who || ' cannot edit other-level records';
      -- delete
      delete from public.assessment_records where id = rid; get diagnostics n = row_count; assert n = 0, who || ' cannot delete';
      -- notes
      select count(*) into n from public.comparative_notes; assert n <= 1, who || ' sees at most their own note';
      select count(*) into n from public.comparative_notes where education_level in ('all', otherlvl); assert n = 0, who || ' sees no other-level or division notes';
      denied := false;
      begin insert into public.comparative_notes (sy,district_scope,education_level,subject,term,analysis,interventions)
        values ('2025-2026', (select name from public.districts where id = dist), otherlvl, 'ALL','T9','x','x'); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot write a note for the other level';
      denied := false;
      begin insert into public.comparative_notes (sy,district_scope,education_level,subject,term,analysis,interventions)
        values ('2025-2026', (select name from public.districts where id = dist), 'all', 'ALL','T9','x','x'); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot write a division-wide note';
      insert into public.comparative_notes (sy,district_scope,education_level,subject,term,analysis,interventions)
        values ('2025-2026', (select name from public.districts where id = dist), lvl, 'ALL','T9','x','x');
      -- everything else
      update public.districts set coordinator_name = 'x' where id = dist; get diagnostics n = row_count; assert n = 0, who || ' cannot update districts';
      update public.app_settings set data = data; get diagnostics n = row_count; assert n = 0, who || ' cannot update settings';
      select count(*) into n from public.audit_log; assert n = 0, who || ' cannot read audit log';
      select count(*) into n from public.profiles; assert n = 1, who || ' sees only their own profile';
      denied := false;
      begin update public.profiles set education_level = otherlvl where id = auth.uid(); get diagnostics n = row_count; denied := (n = 0);
      exception when others then denied := true; end;
      assert denied, who || ' cannot change their own level';
      denied := false;
      begin update public.profiles set must_change_password = false, active = true where id = auth.uid(); get diagnostics n = row_count; denied := (n = 0);
      exception when others then denied := true; end;
      assert denied, who || ' cannot edit the security flags on their own profile';
      reset role;
    end loop;
  end;
  raise notice 'PASS four coordinators (own district and level only)';

  -- ===== Retired account and forced password change =====
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n = 0, 'retired coordinator sees nothing';
  denied := false;
  begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 1','Grade 3','X',65,80,70,'x'); exception when insufficient_privilege then denied := true; end;
  assert denied, 'retired coordinator cannot write';
  reset role;
  raise notice 'PASS retired account';

  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n = 0, 'initial-password account sees no records';
  select count(*) into n from public.comparative_notes; assert n = 0, 'initial-password account sees no notes';
  select count(*) into n from public.profiles where must_change_password; assert n = 1, 'the account can still read its own profile to learn it must change the password';
  denied := false;
  begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 1','Grade 3','X',65,80,70,'x'); exception when insufficient_privilege then denied := true; end;
  assert denied, 'initial-password account cannot write';
  reset role;
  -- the real password change (GoTrue updates encrypted_password) clears the flag
  update auth.users set encrypted_password = 'new-hash' where id = '00000000-0000-0000-0000-0000000000c2';
  assert (select not must_change_password from public.profiles where username = 't_gated'), 'trigger clears the flag after a real password change';
  set local role authenticated;
  select count(*) into n from public.assessment_records; assert n >= 1 and n = (select count(*) from public.assessment_records where district_id = asu and education_level = 'elementary'), 'after the password change the account sees exactly its own scope (Asuncion elementary)';
  reset role;
  raise notice 'PASS forced password change';

  -- ===== Signed out =====
  set local role anon;
  denied := false; begin perform 1 from public.assessment_records limit 1; exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on assessment_records';
  denied := false; begin perform 1 from public.profiles limit 1; exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on profiles';
  reset role;
  raise notice 'PASS signed out';
end $$;

rollback;
