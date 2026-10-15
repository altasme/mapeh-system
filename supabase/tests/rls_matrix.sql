-- rls_matrix.sql: access rules after 0005 (levels, MAPEH rules, edit and soft delete). Run in the Supabase SQL editor
-- AFTER migrations 0001 to 0007 and seed/districts.sql. One transaction, rolled back: it creates throwaway users and
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
select '2025-2026','Term 1', d.id, g.ks, g.gl,'MAPEH - Overall',65,80,70,'Approaching Proficiency','00000000-0000-0000-0000-0000000000a1',true
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
  select count(*) into total_recs from public.assessment_records where deleted_at is null;
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
    update public.districts set elem_coordinator_name = elem_coordinator_name, sec_coordinator_position = sec_coordinator_position where id = asu; get diagnostics n = row_count; assert n = 1, code || ' can edit the per-level coordinator details';
    assert public.app_delete_records(array[rid], 'test') = 1, code || ' soft deletes';
    select count(*) into n from public.assessment_records where id = rid; assert n = 1, code || ' still sees the deleted row (recoverable)';
    assert public.app_restore_records(array[rid]) = 1, code || ' restores';
    assert public.app_delete_records(array[rid], null) = 1, code || ' deletes again';
    reset role;
    delete from public.assessment_records where id = rid;
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
  set local role authenticated; select count(*) into n from public.audit_log; assert n > 0, 'admin reads audit log'; reset role;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
  set local role authenticated; select count(*) into n from public.audit_log; assert n = 0, 'supervisor cannot read audit log'; reset role;
  raise notice 'PASS admin and supervisor';

  -- ===== The four coordinators: own district AND own level only =====
  -- b1 Asuncion elementary, b2 Asuncion secondary, b3 Carmen elementary, b4 Carmen secondary
  declare
    who text; dist smallint; lvl text; otherlvl text; owngrade text; othergrade text; otherdist smallint; other_rid bigint; far_rid bigint;
  begin
    for who, dist, lvl, otherlvl, owngrade, othergrade, otherdist in
      select * from (values ('b1', asu, 'elementary', 'secondary', 'Grade 3', 'Grade 9', car),
                            ('b2', asu, 'secondary', 'elementary', 'Grade 9', 'Grade 3', car),
                            ('b3', car, 'elementary', 'secondary', 'Grade 3', 'Grade 9', asu),
                            ('b4', car, 'secondary', 'elementary', 'Grade 9', 'Grade 3', asu)) v
    loop
      perform set_config('request.jwt.claims', format('{"sub":"00000000-0000-0000-0000-0000000000%s","role":"authenticated"}', who), true);
      set local role authenticated;
      reset role; select count(*) into exp_own from public.assessment_records where district_id = dist and education_level = lvl and deleted_at is null; assert exp_own >= 1, 'fixture has own-scope rows'; set local role authenticated;
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
      denied := false;
      begin delete from public.assessment_records where id = rid; exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot hard delete through the API';
      denied := false;
      begin update public.assessment_records set deleted_at = now() where id = rid; exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot set deleted_at directly';
      denied := false;
      begin update public.assessment_records set created_by = auth.uid(), is_demo = true where id = rid; exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot rewrite ownership or demo flag';
      denied := false;
      begin perform public.app_delete_records(array[(select id from public.assessment_records where false)::bigint]); exception when others then denied := true; end;
      reset role;
      select id into other_rid from public.assessment_records where education_level = otherlvl and district_id = dist and deleted_at is null limit 1;
      if other_rid is null then insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by) values ('2025-2026','Term 3',dist,'Key Stage 1',othergrade,'X',65,80,70,'x','00000000-0000-0000-0000-0000000000a1') returning id into other_rid; end if;
      select id into far_rid from public.assessment_records where district_id = otherdist and deleted_at is null limit 1;
      set local role authenticated;
      denied := false;
      begin perform public.app_delete_records(array[other_rid]); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot soft delete the other level via RPC';
      denied := false;
      begin perform public.app_delete_records(array[rid, far_rid]); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot soft delete in another district via RPC, and the call is all or nothing';
      select count(*) into n from public.assessment_records where id = rid; assert n = 1, who || ': a refused batch deleted nothing';
      denied := false;
      begin perform public.app_delete_records_by_sy('2025-2026'); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot bulk delete';
      denied := false;
      begin perform public.app_delete_all_records(); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot delete everything';
      assert public.app_delete_records(array[rid], 'cleanup') = 1, who || ' soft deletes own-scope record';
      select count(*) into n from public.assessment_records where id = rid; assert n = 0, who || ' no longer sees a deleted record';
      update public.assessment_records set mps = 5 where id = rid; get diagnostics n = row_count; assert n = 0, who || ' cannot edit a deleted record';
      denied := false;
      begin perform public.app_restore_records(array[rid]); exception when insufficient_privilege then denied := true; end;
      assert denied, who || ' cannot restore';
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
      update public.districts set elem_coordinator_name = 'x', sec_coordinator_name = 'x' where id = dist; get diagnostics n = row_count; assert n = 0, who || ' cannot update the per-level coordinator details';
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
  select count(*) into n from public.assessment_records; assert n >= 1 and n = (select count(*) from public.assessment_records where district_id = asu and education_level = 'elementary' and deleted_at is null), 'after the password change the account sees exactly its own scope (Asuncion elementary)';
  reset role;
  raise notice 'PASS forced password change';

  -- ===== MAPEH grade rules (create, edit, and direct API) =====
  declare
    ok_rows text[][] := array[
      ['Grade 1','MAPEH - Overall'],['Grade 3','MAPEH - Overall'],['Grade 4','MAPEH - Overall'],['Grade 4','MAPEH - Music'],
      ['Grade 6','MAPEH - Arts'],['Grade 7','MAPEH - PE'],['Grade 10','MAPEH - Health'],['Grade 10','MAPEH - Overall'],
      ['Grade 1','IPED - Music'],['Grade 2','Filipino'],['Grade 11','Empowerment Technologies'],['Grade 12','MAPEH-looking but not family']];
    bad_rows text[][] := array[
      ['Grade 1','MAPEH - Music'],['Grade 2','MAPEH - Arts'],['Grade 3','MAPEH - PE'],['Grade 3','MAPEH - Health'],
      ['Grade 2','MAPEH - Music & Arts'],['Grade 1','MAPEH - PE & Health'],
      ['Grade 4','MAPEH - Music & Arts'],['Grade 8','MAPEH - PE & Health'],['Grade 10','MAPEH - Music & Arts'],
      ['Grade 11','MAPEH - Overall'],['Grade 12','MAPEH - Music'],['Grade 11','MAPEH - Music & Arts']];
    i int;
  begin
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
    set local role authenticated;
    for i in 1 .. array_length(ok_rows, 1) loop
      insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
        values ('2025-2026','Term 3',asu,'Key Stage 1',ok_rows[i][1],ok_rows[i][2],65,91,70,'WRONG') returning id into rid;
      assert (select proficiency_level from public.assessment_records where id = rid) = 'Advanced', 'proficiency is computed by the database, not trusted from the client';
    end loop;
    for i in 1 .. array_length(bad_rows, 1) loop
      denied := false;
      begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
        values ('2025-2026','Term 3',asu,'Key Stage 1',bad_rows[i][1],bad_rows[i][2],65,80,70,'x');
      exception when check_violation then denied := true; end;
      assert denied, 'rule refuses ' || bad_rows[i][1] || ' / ' || bad_rows[i][2];
    end loop;
    -- editing into a forbidden combination is refused too
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
      values ('2025-2026','Term 3',asu,'Key Stage 2','Grade 5','MAPEH - Music',65,80,70,'x') returning id into rid;
    denied := false; begin update public.assessment_records set grade_level = 'Grade 2' where id = rid; exception when check_violation then denied := true; end;
    assert denied, 'moving a Music record to Grade 2 is refused';
    denied := false; begin update public.assessment_records set learning_area = 'MAPEH - Music & Arts' where id = rid; exception when check_violation then denied := true; end;
    assert denied, 'switching a Grade 5 record to a legacy combined area is refused';
    update public.assessment_records set learning_area = 'MAPEH - Arts', mps = 76 where id = rid; get diagnostics n = row_count; assert n = 1, 'a valid edit passes';
    assert (select proficiency_level from public.assessment_records where id = rid) = 'Developing', 'proficiency recomputed after an edit';
    assert (select updated_by from public.assessment_records where id = rid) = '00000000-0000-0000-0000-0000000000a1', 'editor is stamped';
    -- an out-of-range edit hits the existing check constraint
    denied := false; begin update public.assessment_records set mps = 120 where id = rid; exception when check_violation then denied := true; end;
    assert denied, 'mps above 100 is refused on edit';
    reset role;
    -- legacy rows already present stay editable on non-rule fields (grandfathered)
    alter table public.assessment_records disable trigger records_guard;  -- simulates a row that predates the rule
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
      values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 2','MAPEH - Music & Arts',65,70,70,'x','00000000-0000-0000-0000-0000000000a1')
      returning id into rid;
    alter table public.assessment_records enable trigger records_guard;
    set local role authenticated;
    update public.assessment_records set mps = 82 where id = rid; get diagnostics n = row_count; assert n = 1, 'legacy Grade 2 record can still be edited (score)';
    denied := false; begin update public.assessment_records set learning_area = 'MAPEH - Music & Arts', grade_level = 'Grade 3' where id = rid; denied := false; exception when check_violation then denied := true; end;
    assert denied, 'but cannot be re-saved into a different forbidden grade';
    reset role;
    -- the audit log names the soft delete and the restore
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
    set local role authenticated;
    perform public.app_delete_records(array[rid], 'audit check');
    perform public.app_restore_records(array[rid]);
    select count(*) into n from public.audit_log where row_id = rid::text and action = 'SOFT_DELETE' and (new->>'delete_reason') = 'audit check' and actor is not null; assert n = 1, 'audit has SOFT_DELETE with reason and actor';
    select count(*) into n from public.audit_log where row_id = rid::text and action = 'RESTORE'; assert n = 1, 'audit has RESTORE';
    reset role;
    raise notice 'PASS MAPEH rules, computed proficiency, edit and soft delete';
  end;

  -- ===== Editing one least-learned competency (0007) =====
  declare
    r_own bigint; r_far bigint; r_lvl bigint; ll_before jsonb; cnt_before int; cnt_after int;
  begin
    -- fixture rows: Asuncion elementary (own for b1), Carmen elementary (other district), Asuncion secondary (other level)
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,least_learned,created_by)
      values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 3','X',65,80,70,'x','[{"code":"LC-1","desc":"first"},{"code":"LC-2","desc":"second"},"plain string entry"]','00000000-0000-0000-0000-0000000000a1') returning id into r_own;
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,least_learned,created_by)
      values ('2025-2026','Term 1',car,'Key Stage 1','Grade 3','X',65,80,70,'x','[{"code":"LC-1","desc":"far"}]','00000000-0000-0000-0000-0000000000a1') returning id into r_far;
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,least_learned,created_by)
      values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 9','X',65,80,70,'x','[{"code":"LC-1","desc":"other level"}]','00000000-0000-0000-0000-0000000000a1') returning id into r_lvl;
    select count(*) into cnt_before from public.assessment_records;

    perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}',true);
    set local role authenticated;
    assert public.app_edit_competency(r_own, 1, 'second', 'LC-2b', '  corrected second  ') = 1, 'coordinator edits an entry on an own-scope record';
    reset role;
    select least_learned into ll_before from public.assessment_records where id = r_own;
    assert ll_before = '[{"code":"LC-1","desc":"first"},{"code":"LC-2b","desc":"corrected second"},"plain string entry"]'::jsonb, 'only the chosen entry changed; the others are untouched';
    select count(*) into cnt_after from public.assessment_records; assert cnt_after = cnt_before, 'editing creates no record';
    assert (select district_id = asu and grade_level = 'Grade 3' and learning_area = 'X' and sy = '2025-2026' and term = 'Term 1' and updated_by = '00000000-0000-0000-0000-0000000000b1' from public.assessment_records where id = r_own), 'associations kept; editor stamped';
    set local role authenticated;
    assert public.app_edit_competency(r_own, 2, 'plain string entry', 'LC-3', 'now an object') = 1, 'a legacy plain-text entry can be edited';
    denied := false; begin perform public.app_edit_competency(r_own, 0, 'stale text', 'LC-1', 'x'); exception when others then denied := sqlerrm like '%changed by someone else%'; end;
    assert denied, 'a stale edit is refused';
    denied := false; begin perform public.app_edit_competency(r_own, 0, 'first', 'LC-1', '   '); exception when others then denied := sqlerrm like '%cannot be empty%'; end;
    assert denied, 'empty description refused';
    denied := false; begin perform public.app_edit_competency(r_own, 0, 'first', '', 'x'); exception when others then denied := sqlerrm like '%code%'; end;
    assert denied, 'empty code refused';
    denied := false; begin perform public.app_edit_competency(r_own, 0, 'first', 'LC-1', repeat('x', 501)); exception when others then denied := sqlerrm like '%too long%'; end;
    assert denied, 'overlong description refused';
    denied := false; begin perform public.app_edit_competency(r_own, 9, 'first', 'LC-1', 'x'); exception when others then denied := sqlerrm like '%could not be found%'; end;
    assert denied, 'unknown entry refused';
    denied := false; begin perform public.app_edit_competency(r_far, 0, 'far', 'LC-1', 'hijack'); exception when others then denied := true; end;
    assert denied, 'coordinator cannot edit a competency in another district';
    denied := false; begin perform public.app_edit_competency(r_lvl, 0, 'other level', 'LC-1', 'hijack'); exception when others then denied := true; end;
    assert denied, 'coordinator cannot edit a competency of the other education level';
    denied := false; begin update public.assessment_records set least_learned = '"not a list"' where id = r_own; exception when check_violation then denied := true; end;
    assert denied, 'least_learned must stay a list';
    reset role;
    assert (select least_learned #>> '{0,desc}' from public.assessment_records where id = r_far) = 'far' and (select least_learned #>> '{0,desc}' from public.assessment_records where id = r_lvl) = 'other level', 'out-of-scope entries untouched';
    -- a deleted record cannot be edited, and a signed-out caller cannot call the function
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
    set local role authenticated;
    assert public.app_edit_competency(r_far, 0, 'far', 'LC-1', 'division edit') = 1, 'admin edits anywhere';
    perform public.app_delete_records(array[r_far], 'x');
    denied := false; begin perform public.app_edit_competency(r_far, 0, 'division edit', 'LC-1', 'again'); exception when others then denied := true; end;
    assert denied, 'a deleted record cannot be edited';
    reset role;
    set local role anon;
    denied := false; begin perform public.app_edit_competency(r_own, 0, 'first', 'LC-1', 'x'); exception when insufficient_privilege then denied := true; end;
    assert denied, 'signed-out callers cannot use it';
    reset role;
    raise notice 'PASS competency editing';
  end;

  -- ===== Signed out =====
  set local role anon;
  denied := false; begin perform public.app_delete_all_records(); exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon cannot call delete RPCs';
  reset role;
  set local role anon;
  denied := false; begin perform 1 from public.assessment_records limit 1; exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on assessment_records';
  denied := false; begin perform 1 from public.profiles limit 1; exception when insufficient_privilege then denied := true; end;
  assert denied, 'anon denied on profiles';
  reset role;
  raise notice 'PASS signed out';
end $$;

rollback;
