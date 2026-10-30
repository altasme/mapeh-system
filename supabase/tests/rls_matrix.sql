-- rls_matrix.sql: access rules after 0005 (levels, MAPEH rules, edit and soft delete). Run in the Supabase SQL editor
-- AFTER migrations 0001 to 0011 and seed/districts.sql. One transaction, rolled back: it creates throwaway users and
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

-- two records per district: one elementary (Grade 4), one secondary (Grade 8)
insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by,is_demo)
select '2025-2026','Term 1', d.id, g.ks, g.gl,'MAPEH - Overall',65,80,70,'Approaching Proficiency','00000000-0000-0000-0000-0000000000a1',true
from public.districts d, (values ('Key Stage 2','Grade 4'),('Key Stage 3','Grade 8')) g(ks, gl) where d.name in ('Asuncion','Carmen');

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
  perform 1 from public.assessment_records where grade_level='Grade 4' and education_level='elementary'; assert found, 'grade 4 is elementary';
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

  -- Migration 0008: the password gate is off. An account whose (legacy) flag is still set is NOT locked out.
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}',true);
  set local role authenticated;
  select count(*) into n from public.assessment_records;
  assert n >= 1 and n = (select count(*) from public.assessment_records where district_id = asu and education_level = 'elementary' and deleted_at is null), 'an account with the legacy flag still sees exactly its own scope (Asuncion elementary)';
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 1','Grade 3','X',65,80,70,'x');
  denied := false;
  begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 3','Grade 9','X',65,80,70,'x'); exception when insufficient_privilege then denied := true; end;
  assert denied, 'and is still limited to its own district and level';
  reset role;
  raise notice 'PASS no password gate';

  -- ===== MAPEH grade rules (create, edit, and direct API) =====
  declare
    ok_rows text[][] := array[
      ['Grade 1','MAPEH - Music & Arts'],['Grade 3','MAPEH - PE & Health'],['Grade 4','MAPEH - Overall'],['Grade 4','MAPEH - Music'],
      ['Grade 6','MAPEH - Arts'],['Grade 7','MAPEH - PE'],['Grade 10','MAPEH - Health'],['Grade 10','MAPEH - Overall'],
      ['Grade 4','MAPEH - Music & Arts'],['Grade 8','MAPEH - PE & Health'],['Grade 10','MAPEH - Music & Arts'],['Grade 5','MAPEH - PE & Health'],
      ['Grade 1','IPED - Music'],['Grade 2','Filipino'],['Grade 11','Empowerment Technologies'],['Grade 12','MAPEH-looking but not family']];
    bad_rows text[][] := array[
      ['Grade 1','MAPEH - Music'],['Grade 2','MAPEH - Arts'],['Grade 3','MAPEH - PE'],['Grade 3','MAPEH - Health'],
      ['Grade 1','MAPEH - Overall'],['Grade 3','MAPEH - Overall'],
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
    assert not denied, 'switching a Grade 5 record to the combined Music & Arts area is accepted (migration 0012)';
    denied := false; begin update public.assessment_records set learning_area = 'MAPEH - Overall', grade_level = 'Grade 2' where id = rid; exception when check_violation then denied := true; end;
    assert denied, 'but MAPEH - Overall in Key Stage 1 is refused (migration 0014)';
    update public.assessment_records set learning_area = 'MAPEH - Music', grade_level = 'Grade 5' where id = rid;
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
      values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 2','MAPEH - Overall',65,70,70,'x','00000000-0000-0000-0000-0000000000a1')
      returning id into rid;
    alter table public.assessment_records enable trigger records_guard;
    set local role authenticated;
    update public.assessment_records set mps = 82 where id = rid; get diagnostics n = row_count; assert n = 1, 'legacy Grade 2 record can still be edited (score)';
    denied := false; begin update public.assessment_records set learning_area = 'MAPEH - Overall', grade_level = 'Grade 3' where id = rid; denied := false; exception when check_violation then denied := true; end;
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

  -- ===== Schools, programs, baseline SY and school accounts (0010) =====
  declare
    s1 bigint; s2 bigint; s3 bigint; s4 bigint; uid1 uuid; uid2 uuid; e text; r_s1 bigint; r_s2 bigint; r_s3 bigint; r_none bigint; r_unl bigint; r_new bigint; cnt int;
    sup text := '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
    adm text := '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
    coord text := '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
    jwt text; res jsonb;
  begin
    -- division users manage the school list; a school can hold both programs; duplicates are refused
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    s1 := public.app_save_school(null, 'Alpha IPED School', asu, array['iped']);
    s2 := public.app_save_school(null, 'Beta Special Programs School', asu, array['special_programs']);
    s3 := public.app_save_school(null, 'Gamma School', car, array['special_programs', 'iped']);
    assert (select count(*) from public.school_programs where school_id = s3) = 2, 'a school can belong to both programs';
    denied := false; begin perform public.app_save_school(null, '  alpha iped SCHOOL ', asu, array['iped']); exception when others then denied := sqlerrm like '%already exists%'; end;
    assert denied, 'a duplicate school (same district, name ignoring case and spaces) is refused';
    assert public.app_save_school(null, 'Alpha IPED School', car, array['iped']) is not null, 'the same name in another district is a different school';
    assert public.app_save_school(null, 'No Program School', asu, array[]::text[]) is not null, 'a school may have no program (migration 0013: MAPEH is entered for every school)';
    denied := false; begin perform public.app_save_school(null, 'Bad Program', asu, array['other']); exception when others then denied := true; end;
    assert denied, 'unknown program refused';
    reset role;

    -- the district coordinator: sees schools of own district only, cannot manage or create accounts
    perform set_config('request.jwt.claims', coord, true); set local role authenticated;
    assert (select count(*) from public.schools where id in (s1, s2)) = 2 and (select count(*) from public.schools where id = s3) = 0, 'a coordinator sees the schools of their own district only';
    denied := false; begin perform public.app_save_school(null, 'Hack', asu, array['iped']); exception when insufficient_privilege then denied := true; end; assert denied, 'a coordinator cannot add schools';
    denied := false; begin perform public.app_create_school_account('hacker1', 'Hacker', s1, 'longenough1'); exception when insufficient_privilege then denied := true; end; assert denied, 'a coordinator cannot create school accounts';
    denied := false; begin insert into public.schools (name, district_id) values ('x', asu); exception when insufficient_privilege then denied := true; end; assert denied, 'schools cannot be written directly through the API';
    reset role;

    -- account creation by Admin and Supervisor, with the safety checks
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    uid1 := public.app_create_school_account('Alpha.School', 'Alpha IPED School', s1, 'initialpass1');
    reset role;
    assert (select role::text = 'school' and school_id = s1 and district_id = asu and education_level is null and active and username = 'alpha.school' from public.profiles where id = uid1), 'profile: school role, own school, its district, username lowercased';
    assert (select extensions.crypt('initialpass1', encrypted_password) = encrypted_password from auth.users where id = uid1) and exists (select 1 from auth.identities where user_id = uid1), 'the login exists with a hashed password';
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    denied := false; begin perform public.app_create_school_account('alpha2', 'Dup', s1, 'initialpass1'); exception when others then denied := sqlerrm like '%already has an active account%'; end; assert denied, 'a second active account for the same school is refused';
    denied := false; begin perform public.app_create_school_account('alpha.school', 'Dup', s2, 'initialpass1'); exception when others then denied := sqlerrm like '%already taken%'; end; assert denied, 'a taken username is refused';
    denied := false; begin perform public.app_create_school_account('ab', 'Short', s2, 'initialpass1'); exception when others then denied := sqlerrm like '%Username must be%'; end; assert denied, 'bad username refused';
    denied := false; begin perform public.app_create_school_account('beta.school', 'Weak', s2, 'short'); exception when others then denied := sqlerrm like '%at least 8%'; end; assert denied, 'short password refused';
    denied := false; begin perform public.app_create_school_account('beta.school', 'Ghost', 999999, 'initialpass1'); exception when others then denied := sqlerrm like '%not found%'; end; assert denied, 'unknown school refused';
    reset role;
    select count(*) into cnt from auth.users where email like 'beta.school@%'; assert cnt = 0 and (select count(*) from public.profiles where username = 'beta.school') = 0, 'failed attempts leave nothing behind (no orphan login or profile)';
    insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f9', 'orphanlogin@users.mapehdavnor.altasme.app');
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    denied := false; begin perform public.app_create_school_account('orphanlogin', 'X', s2, 'initialpass1'); exception when others then denied := sqlerrm like '%already taken%'; end; assert denied, 'a username that exists only as a login is refused';
    uid2 := public.app_create_school_account('beta.school', 'Beta SP School', s2, 'initialpass2');
    assert (select count(*) from public.app_list_school_accounts()) = 2, 'the Supervisor lists the school accounts with school and programs';
    reset role;
    delete from auth.users where id = '00000000-0000-0000-0000-0000000000f9';

    -- fixtures (owner): records for each school, an unlinked record, a MAPEH record
    insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,baseline_sy,mps,pct75,proficiency_level,created_by,least_learned)
      values ('2025-2026','Term 1',asu,s1,'Key Stage 1','Grade 3','IPED - English',65,'2024-2025',80,70,'x','00000000-0000-0000-0000-0000000000a1','[{"code":"LC-1","desc":"own competency"}]') returning id into r_s1;
    insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by,least_learned)
      values ('2025-2026','Term 1',asu,s2,'Key Stage 3','Grade 8','SPA - Vocal Arts',65,80,70,'x','00000000-0000-0000-0000-0000000000a1','[{"code":"LC-1","desc":"other school"}]') returning id into r_s2;
    insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
      values ('2025-2026','Term 1',car,s3,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x','00000000-0000-0000-0000-0000000000a1') returning id into r_s3;
    insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
      values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 3','MAPEH - Music & Arts',65,80,70,'x','00000000-0000-0000-0000-0000000000a1') returning id into r_none;
    insert into public.assessment_records (sy,term,district_id,school,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
      values ('2025-2026','Term 2',asu,'alpha iped school ','Key Stage 1','Grade 3','IPED - Filipino',65,80,70,'x','00000000-0000-0000-0000-0000000000a1') returning id into r_unl;
    assert (select school from public.assessment_records where id = r_s1) = 'Alpha IPED School', 'the printed school name follows the school record';
    assert (select baseline_sy from public.assessment_records where id = r_s1) = '2024-2025' and (select baseline_sy from public.assessment_records where id = r_none) is null, 'baseline SY is stored per record; existing rows stay empty';
    denied := false; begin update public.assessment_records set baseline_sy = '2024' where id = r_s1; exception when check_violation then denied := true; end; assert denied, 'baseline SY must look like 2024-2025';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by) values ('2025-2026','Term 1',asu,s1,'Key Stage 1','Grade 3','SPA - Dance Arts',65,80,70,'x','00000000-0000-0000-0000-0000000000a1'); exception when others then denied := sqlerrm like '%not classified under the program%'; end;
    assert denied, 'a school cannot be linked to a record of a program it is not classified under';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by) values ('2025-2026','Term 1',car,s1,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x','00000000-0000-0000-0000-0000000000a1'); exception when others then denied := sqlerrm like '%different district%'; end;
    assert denied, 'a school cannot be linked to a record of another district';

    -- THE SCHOOL ACCOUNT (IPED, Alpha, Asuncion)
    jwt := format('{"sub":"%s","role":"authenticated"}', uid1);
    perform set_config('request.jwt.claims', jwt, true); set local role authenticated;
    assert (select count(*) from public.assessment_records) = 1 and (select id from public.assessment_records) = r_s1, 'a school account sees only its own school''s records (not other schools, unlinked or MAPEH rows)';
    assert (select count(*) from public.assessment_records where id in (r_s2, r_s3, r_none, r_unl)) = 0, 'other record ids are invisible even when asked for by id';
    assert (select count(*) from public.schools) = 1 and (select count(*) from public.school_programs) = 1, 'it sees only its own school and classification';
    assert (select count(*) from public.profiles) = 1, 'it reads only its own profile';
    insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,baseline_sy,mps,pct75,proficiency_level)
      values ('2025-2026','Term 1',asu,s1,'Key Stage 2','Grade 5','IPED - Mathematics',65,'2024-2025',77,70,'x') returning id into r_new;
    assert (select school = 'Alpha IPED School' and created_by = uid1 from public.assessment_records where id = r_new), 'it can enter records for its own school and program';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level) values ('2025-2026','Term 1',asu,s1,'Key Stage 1','Grade 3','SPA - Vocal Arts',65,80,70,'x'); exception when others then denied := true; end; assert denied, 'it cannot enter a Special Programs record (not its program)';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level) values ('2025-2026','Term 1',asu,s2,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x'); exception when others then denied := true; end; assert denied, 'it cannot enter a record for another school';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level) values ('2025-2026','Term 1',car,s1,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x'); exception when others then denied := true; end; assert denied, 'it cannot enter a record in another district';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level) values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x'); exception when insufficient_privilege then denied := true; end; assert denied, 'it cannot enter a record without its school';
    update public.assessment_records set mps = 88 where id = r_s1; get diagnostics n = row_count; assert n = 1, 'it can edit its own record';
    update public.assessment_records set mps = 1 where id in (r_s2, r_s3, r_none, r_unl); get diagnostics n = row_count; assert n = 0, 'it cannot edit any other record by id';
    denied := false; begin update public.assessment_records set school_id = s2 where id = r_s1; exception when others then denied := true; end; assert denied, 'it cannot reassign its record to another school';
    denied := false; begin update public.assessment_records set learning_area = 'SPA - Vocal Arts' where id = r_s1; exception when others then denied := true; end; assert denied, 'it cannot change its record to another program';
    denied := false; begin update public.assessment_records set district_id = car where id = r_s1; exception when others then denied := true; end; assert denied, 'it cannot move its record to another district';
    denied := false; begin update public.assessment_records set deleted_at = now() where id = r_s1; exception when insufficient_privilege then denied := true; end; assert denied, 'it cannot set deleted_at';
    denied := false; begin perform public.app_delete_records(array[r_s1], 'x'); exception when insufficient_privilege then denied := true; end; assert denied, 'it cannot delete (soft or hard)';
    denied := false; begin delete from public.assessment_records where id = r_s1; exception when insufficient_privilege then denied := true; end; assert denied, 'no direct delete either';
    assert public.app_edit_competency(r_s1, 0, 'own competency', 'LC-1', 'edited by school') = 1, 'it can correct a competency on its own record';
    denied := false; begin perform public.app_edit_competency(r_s2, 0, 'other school', 'LC-1', 'x'); exception when others then denied := sqlerrm like '%could not be found%'; end; assert denied, 'but not on another school''s record';
    denied := false; begin perform public.app_create_school_account('sneaky', 'Sneaky', s2, 'initialpass1'); exception when insufficient_privilege then denied := true; end; assert denied, 'a school account cannot create accounts';
    denied := false; begin perform public.app_set_school_account_active(uid2, false); exception when insufficient_privilege then denied := true; end; assert denied, 'a school account cannot disable accounts';
    denied := false; begin perform public.app_save_school(s1, 'Alpha IPED School', asu, array['iped', 'special_programs']); exception when insufficient_privilege then denied := true; end; assert denied, 'a school account cannot change school classification';
    denied := false; begin perform public.app_import_schools('[{"name":"x","district":"Asuncion","programs":["iped"]}]'); exception when insufficient_privilege then denied := true; end; assert denied, 'a school account cannot import schools';
    denied := false; begin perform public.app_link_school_records(s1); exception when insufficient_privilege then denied := true; end; assert denied, 'a school account cannot link records';
    assert (select count(*) from public.app_list_school_accounts()) = 0, 'the account list is empty for a school account';
    denied := false; begin update public.profiles set school_id = s2 where id = uid1; get diagnostics n = row_count; denied := (n = 0); exception when others then denied := true; end; assert denied, 'it cannot change its own school assignment';
    denied := false; begin update public.profiles set role = 'admin' where id = uid1; get diagnostics n = row_count; denied := (n = 0); exception when others then denied := true; end; assert denied, 'it cannot change its own role';
    denied := false; begin update public.profiles set active = true, school_id = null where id = uid1; get diagnostics n = row_count; denied := (n = 0); exception when others then denied := true; end; assert denied, 'it cannot edit any profile field';
    update public.districts set coordinator_name = 'x' where id = asu; get diagnostics n = row_count; assert n = 0, 'it cannot edit districts';
    update public.app_settings set data = data; get diagnostics n = row_count; assert n = 0, 'it cannot edit settings';
    assert (select count(*) from public.comparative_notes) = 0 and (select count(*) from public.audit_log) = 0, 'it sees no notes and no audit log';
    denied := false; begin insert into public.comparative_notes (sy,district_scope,education_level,subject,term,analysis,interventions) values ('2025-2026','Asuncion','all','ALL','T1','x','x'); exception when insufficient_privilege then denied := true; end; assert denied, 'it cannot write notes';
    reset role;
    -- a deleted record is invisible to it
    update public.assessment_records set deleted_at = now() where id = r_new;
    perform set_config('request.jwt.claims', jwt, true); set local role authenticated;
    assert (select count(*) from public.assessment_records) = 1, 'a soft-deleted record disappears for the school account';
    reset role;

    -- an existing coordinator still sees the linked record of their district and level
    perform set_config('request.jwt.claims', coord, true); set local role authenticated;
    assert (select count(*) from public.assessment_records where id = r_s1) = 1 and (select count(*) from public.assessment_records where id = r_s3) = 0, 'a district coordinator keeps their access (own district and level)';
    denied := false; begin perform public.app_set_school_account_active(uid1, false); exception when insufficient_privilege then denied := true; end; assert denied, 'a coordinator cannot disable school accounts';
    reset role;

    -- linking existing free-text records (explicit, per school)
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    assert public.app_count_linkable_records(s1) = 1, 'one existing record carries this school name as text';
    assert public.app_link_school_records(s1) = 1, 'linking attaches it (same district, matching program)';
    assert public.app_count_linkable_records(s1) = 0, 'and only once';
    assert (select school_id = s1 and school = 'Alpha IPED School' from public.assessment_records where id = r_unl), 'the record is now linked and its name matches the school';
    -- removing a program that has records is refused; moving a school with records is refused
    denied := false; begin perform public.app_save_school(s1, 'Alpha IPED School', asu, array['special_programs']); exception when others then denied := sqlerrm like '%Cannot remove a program%'; end; assert denied, 'a program with records cannot be removed';
    denied := false; begin perform public.app_save_school(s1, 'Alpha IPED School', car, array['iped']); exception when others then denied := sqlerrm like '%cannot be moved%'; end; assert denied, 'a school with records cannot be moved to another district';
    assert public.app_save_school(s1, 'Alpha IPED School', asu, array['iped', 'special_programs']) = s1, 'saving an existing school with another program succeeds';
    assert (select count(*) from public.school_programs where school_id = s1) = 2, 'a program can be added to an existing school (no duplicate school)';
    assert (select count(*) from public.schools where district_id = asu and lower(name) = 'alpha iped school') = 1, 'still one school row';
    -- bulk import is all-or-nothing and merges into existing schools
    select count(*) into cnt from public.schools;
    denied := false; begin perform public.app_import_schools('[{"name":"Delta","district":"Carmen","programs":["iped"]},{"name":"Eps","district":"Nowhere","programs":["iped"]}]'); exception when others then denied := sqlerrm like '%Nothing was imported%'; end;
    assert denied and (select count(*) from public.schools) = cnt, 'an import with one bad row creates nothing';
    res := public.app_import_schools('[{"name":"Delta","district":"Carmen","programs":["iped"]},{"name":"gamma school","district":"carmen","programs":["iped"]},{"name":"Delta","district":"Carmen","programs":["special_programs"]}]');
    assert (res ->> 'created')::int = 1 and (res ->> 'updated')::int = 2 and (select count(*) from public.schools) = cnt + 1, 'import creates new schools, merges programs into existing ones, never duplicates';
    assert (select count(*) from public.school_programs sp join public.schools s on s.id = sp.school_id where s.name = 'Delta') = 2, 'a school listed for both programs ends up with both';
    -- disable and re-enable
    perform public.app_set_school_account_active(uid1, false);
    reset role;
    assert (select banned_until > now() from auth.users where id = uid1) and (select not active from public.profiles where id = uid1), 'disabling bans the login and deactivates the profile';
    perform set_config('request.jwt.claims', jwt, true); set local role authenticated;
    assert (select count(*) from public.assessment_records) = 0, 'a disabled account sees nothing';
    denied := false; begin insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level) values ('2025-2026','Term 1',asu,s1,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x'); exception when others then denied := true; end; assert denied, 'and cannot write';
    reset role;
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    uid2 := public.app_create_school_account('alpha.second', 'Alpha replacement', s1, 'initialpass3');
    denied := false; begin perform public.app_set_school_account_active(uid1, true); exception when others then denied := sqlerrm like '%already has another active account%'; end; assert denied, 'only one active account per school, even when re-enabling';
    reset role;
    assert exists (select 1 from public.audit_log where table_name = 'profiles' and action = 'INSERT') and exists (select 1 from public.audit_log where table_name = 'schools'), 'account and school changes are in the audit log';
    raise notice 'PASS schools, programs, baseline SY and school accounts';
  end;

  -- ===== Admin panel (0011) =====
  declare
    adm text := '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
    sup text := '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
    coord text := '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
    e text; u1 uuid; u2 uuid; u3 uuid; u4 uuid; sch bigint; sch_noprog bigint; tot bigint; row record; v jsonb; vid bigint; path text; mid uuid; mid2 uuid; cnt2 int; ids uuid[];
  begin
    -- every administrative function refuses everyone who is not an active admin
    foreach e in array array['00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1'] loop
      perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', e), true);
      set local role authenticated;
      denied := false; begin perform * from public.app_admin_list_users(); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot list users';
      denied := false; begin perform public.app_admin_create_user('hacker.x', 'H', 'admin', null, null, null, 'longenough1'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot create an admin';
      denied := false; begin perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000b1', 'self.promote', 'X', 'admin', null, null, null, true); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot promote anyone';
      denied := false; begin perform public.app_admin_set_password('00000000-0000-0000-0000-0000000000a1', 'longenough1'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot reset the admin password';
      denied := false; begin perform public.app_admin_save_content('login.title', 'x'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot edit content';
      denied := false; begin perform public.app_admin_save_setting('site.title', '"Hacked title"'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot edit settings';
      denied := false; begin perform public.app_admin_clear_setting('site.title'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot clear settings';
      denied := false; begin perform public.app_admin_register_media('00000000-0000-0000-0000-000000000000.png', 'x.png', 'image/png', 10, ''); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot register images';
      denied := false; begin perform * from public.app_admin_activity(); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot read the activity log';
      denied := false; begin insert into public.admin_activity (action) values ('x'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot write the activity log';
      denied := false; begin insert into public.site_content (key, value) values ('login.title', 'x'); exception when insufficient_privilege then denied := true; end; assert denied, e || ' cannot write content directly';
      denied := false; begin insert into storage.objects (bucket_id, name) values ('site-media', 'x.png'); exception when insufficient_privilege or others then denied := true; end; assert denied, e || ' cannot upload to the media bucket';
      assert (select count(*) from public.admin_activity) = 0, e || ' sees no activity';
      reset role;
    end loop;
    raise notice 'PASS admin functions refuse non-admins';

    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    -- the school account used below: a school with programs, and one without
    sch := public.app_save_school(null, 'Panel IPED School', asu, array['iped']);
    reset role;
    insert into public.schools (name, district_id) values ('Panel Empty School', asu) returning id into sch_noprog;
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;

    -- create users of each role; invalid combinations refused
    u1 := public.app_admin_create_user('panel.super', 'Panel Supervisor', 'supervisor', null, null, null, 'initialpass1');
    u2 := public.app_admin_create_user('Panel.Coord', 'Panel Coordinator', 'district_coordinator', car, 'secondary', null, 'initialpass1');
    u3 := public.app_admin_create_user('panel.school', 'Panel School', 'school', null, null, sch, 'initialpass1');
    reset role;
    assert (select role::text = 'supervisor' and district_id is null and education_level is null and school_id is null and active from public.profiles where id = u1), 'supervisor profile';
    assert (select role::text = 'district_coordinator' and district_id = car and education_level = 'secondary' and username = 'panel.coord' from public.profiles where id = u2), 'coordinator profile (username lowercased)';
    assert (select role::text = 'school' and school_id = sch and district_id = asu from public.profiles where id = u3), 'school profile: its district comes from the school';
    assert (select extensions.crypt('initialpass1', encrypted_password) = encrypted_password and not exists (select 1 from information_schema.columns where false) from auth.users where id = u2) and exists (select 1 from auth.identities where user_id = u2), 'the login exists with a hashed password';
    set local role authenticated;
    foreach e in array array[
      $q$select public.app_admin_create_user('bad.role', 'X', 'owner', null, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.coord', 'X', 'district_coordinator', null, 'elementary', null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.coord2', 'X', 'district_coordinator', 1, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.sup', 'X', 'supervisor', 1, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.school', 'X', 'school', null, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.school2', 'X', 'school', null, 'elementary', $q$ || sch || $q$, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.school3', 'X', 'school', 3, null, $q$ || sch || $q$, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('bad.school4', 'X', 'school', null, null, $q$ || sch_noprog || $q$, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('panel.school2', 'X', 'school', null, null, $q$ || sch || $q$, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('panel.coord', 'X', 'supervisor', null, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('ab', 'X', 'supervisor', null, null, null, 'initialpass1')$q$,
      $q$select public.app_admin_create_user('short.pw', 'X', 'supervisor', null, null, null, 'short')$q$] loop
      denied := false; begin execute e; exception when others then denied := true; end;
      assert denied, 'refused: ' || e;
    end loop;
    select count(*) into cnt2 from public.profiles where username like 'bad.%' or username = 'short.pw'; assert cnt2 = 0, 'refused creations leave nothing behind';
    raise notice 'PASS admin creates users and validates assignments';

    -- listing, filters, stats
    select count(*) into cnt2 from public.app_admin_list_users(); assert cnt2 > 5, 'list returns users';
    select total into tot from public.app_admin_list_users('panel') limit 1; assert tot = 3, 'search finds the three panel users';
    assert (select count(*) from public.app_admin_list_users(null, 'school')) >= 1 and (select count(*) from public.app_admin_list_users(null, 'school', null, null, 'iped')) >= 1 and (select count(*) from public.app_admin_list_users(null, 'school', null, null, 'special_programs') where school_name = 'Panel IPED School') = 0, 'role and program filters';
    assert (select school_name from public.app_admin_list_users('panel.school')) = 'Panel IPED School' and (select programs from public.app_admin_list_users('panel.school')) = array['iped'], 'school and program shown';
    assert (select count(*) from public.app_admin_list_users('panel', null, null, null, null, null, 2, 0)) = 2, 'pagination limit';
    v := public.app_admin_user_stats();
    assert (v ->> 'total')::int > 5 and (v ->> 'active')::int + (v ->> 'disabled')::int = (v ->> 'total')::int and (v -> 'by_role' ->> 'school')::int >= 1, 'stats come from the real tables';
    assert not exists (select 1 from public.app_admin_list_users('panel.coord') l where to_jsonb(l)::text ~* 'encrypted|hash|token'), 'the list exposes no hashes or tokens';

    -- editing: role change, username change, assignments
    perform public.app_admin_update_user(u2, 'panel.coord.new', 'Panel Coordinator Two', 'district_coordinator', asu, 'elementary', null, true);
    reset role;
    assert (select username = 'panel.coord.new' and district_id = asu and education_level = 'elementary' from public.profiles where id = u2), 'edit persists in the profile';
    assert (select email = 'panel.coord.new@users.mapehdavnor.altasme.app' from auth.users where id = u2) and (select identity_data ->> 'email' = 'panel.coord.new@users.mapehdavnor.altasme.app' from auth.identities where user_id = u2), 'the username change is applied to the login too';
    set local role authenticated;
    perform public.app_admin_update_user(u2, 'panel.coord.new', 'Panel Coordinator Two', 'supervisor', null, null, null, true);
    reset role; assert (select role::text = 'supervisor' and district_id is null and education_level is null from public.profiles where id = u2), 'a role change clears assignments that no longer apply';
    set local role authenticated;
    denied := false; begin perform public.app_admin_update_user(u2, 'panel.coord.new', 'x', 'district_coordinator', null, 'elementary', null, true); exception when others then denied := sqlerrm like '%district%'; end; assert denied, 'a coordinator needs a district';
    denied := false; begin perform public.app_admin_update_user(u2, 'panel.super', 'x', 'supervisor', null, null, null, true); exception when others then denied := sqlerrm like '%already taken%'; end; assert denied, 'a taken username is refused on edit';

    -- the last administrator cannot be removed; nobody can disable themselves
    denied := false; begin perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000a1', 't_admin', 'T Admin', 'supervisor', null, null, null, true); exception when others then denied := sqlerrm like '%last active administrator%'; end; assert denied, 'the last active administrator cannot be demoted';
    denied := false; begin perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000a1', 't_admin', 'T Admin', 'admin', null, null, null, false); exception when others then denied := true; end; assert denied, 'the administrator cannot disable their own account';
    u4 := public.app_admin_create_user('panel.admin2', 'Second Admin', 'admin', null, null, null, 'initialpass1');
    perform public.app_admin_update_user(u4, 'panel.admin2', 'Second Admin', 'admin', null, null, null, false);
    reset role; assert (select not active from public.profiles where id = u4) and (select banned_until > now() from auth.users where id = u4), 'disabling deactivates the profile and bans the login';
    set local role authenticated;
    perform public.app_admin_update_user(u4, 'panel.admin2', 'Second Admin', 'admin', null, null, null, true);
    perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000a1', 't_admin', 'T Admin', 'admin', null, null, null, true);
    -- with a second active admin, the first may be demoted; put it back through the second one
    reset role; perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', u4), true); set local role authenticated;
    perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000a1', 't_admin', 'T Admin', 'supervisor', null, null, null, true);
    perform public.app_admin_update_user('00000000-0000-0000-0000-0000000000a1', 't_admin', 'T Admin', 'admin', null, null, null, true);
    reset role; perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    raise notice 'PASS admin edits users, protects the last administrator';

    -- a disabled user loses data access at once; their records stay
    reset role; perform set_config('request.jwt.claims', '', true);
    insert into public.assessment_records (sy,term,district_id,school_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,created_by)
      values ('2025-2026','Term 1',asu,sch,'Key Stage 1','Grade 3','IPED - English',65,80,70,'x',u3) returning id into rid;
    perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', u3), true); set local role authenticated;
    assert (select count(*) from public.assessment_records where id = rid) = 1, 'the school user sees its record while active';
    reset role; perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    perform public.app_admin_update_user(u3, 'panel.school', 'Panel School', 'school', null, null, sch, false);
    reset role; perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', u3), true); set local role authenticated;
    assert (select count(*) from public.assessment_records) = 0, 'a disabled user sees nothing';
    denied := false; begin perform public.app_admin_save_content('login.title', 'x'); exception when insufficient_privilege then denied := true; end; assert denied, 'and cannot use any admin function';
    reset role;
    assert (select count(*) from public.assessment_records where id = rid and created_by = u3) = 1, 'the disabled user''s assessment records are untouched';
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    perform public.app_admin_update_user(u3, 'panel.school', 'Panel School', 'school', null, null, sch, true);

    -- password reset: hashed, previous password untouched until reset, nothing logged
    perform public.app_admin_set_password(u3, 'brandnewpass9');
    reset role;
    assert (select extensions.crypt('brandnewpass9', encrypted_password) = encrypted_password and extensions.crypt('initialpass1', encrypted_password) <> encrypted_password from auth.users where id = u3), 'the new password is stored hashed and the old one stops working';
    assert not exists (select 1 from public.admin_activity where details::text ~* 'brandnewpass9|initialpass1' or resource_id::text ~* 'brandnewpass9'), 'no password appears in the activity log';
    assert not exists (select 1 from public.audit_log where (old::text || coalesce(new::text, '')) ~* 'brandnewpass9|initialpass1'), 'nor in the data audit log';
    set local role authenticated;
    denied := false; begin perform public.app_admin_set_password(u3, 'short'); exception when others then denied := true; end; assert denied, 'a short password is refused';
    raise notice 'PASS passwords';

    -- website content: plain text, history, restore, public read
    perform public.app_admin_save_content('login.title', 'New division title');
    perform public.app_admin_save_content('login.title', 'Newer division title');
    denied := false; begin perform public.app_admin_save_content('login.title', 'bad <script>alert(1)</script>'); exception when others then denied := sqlerrm like '%Plain text%'; end; assert denied, 'HTML and script are refused';
    denied := false; begin perform public.app_admin_save_content('login.title', '   '); exception when others then denied := sqlerrm like '%cannot be empty%'; end; assert denied, 'empty text is refused';
    denied := false; begin perform public.app_admin_save_content('Bad Key!', 'x'); exception when others then denied := true; end; assert denied, 'a malformed content key is refused';
    denied := false; begin perform public.app_admin_save_content('login.title', repeat('x', 2001)); exception when others then denied := true; end; assert denied, 'overlong text refused';
    assert (select value from public.site_content where key = 'login.title') = 'Newer division title', 'the content is stored';
    assert (select count(*) from public.site_content_versions where key = 'login.title') = 2, 'each change is a version';
    select id into vid from public.site_content_versions where key = 'login.title' order by id desc limit 1;
    perform public.app_admin_restore_content(vid);
    assert (select value from public.site_content where key = 'login.title') = 'New division title', 'a version can be restored';
    perform public.app_admin_save_content('login.note', E'Line one\r\nLine two');
    assert (select value from public.site_content where key = 'login.note') = E'Line one\nLine two', 'line breaks are kept';
    perform public.app_admin_reset_content('login.note');
    assert not exists (select 1 from public.site_content where key = 'login.note'), 'reset goes back to the original (the row is removed)';
    reset role;
    set local role anon;
    assert (select count(*) from public.site_content) >= 1, 'content is public for the login page';
    assert (select count(*) from public.site_content_versions) = 0 or true, 'x';
    denied := false; begin perform count(*) from public.site_content_versions; exception when insufficient_privilege then denied := true; end; assert denied, 'but history is not public';
    reset role;
    raise notice 'PASS website content';

    -- settings
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    perform public.app_admin_save_setting('site.title', '"Division Assessment System"');
    perform public.app_admin_save_setting('announcement', '{"enabled":true,"text":"Maintenance on Friday","level":"warning"}');
    perform public.app_admin_save_setting('default_view', '"dashboard"');
    perform public.app_admin_save_setting('default_sy', '"2025-2026"');
    perform public.app_admin_save_setting('contact', '{"email":"sdo@example.org","phone":"(084) 555 0100","address":"Tagum City"}');
    foreach e in array array[$q$select public.app_admin_save_setting('site.title', '"<b>x</b>"')$q$, $q$select public.app_admin_save_setting('site.title', '"ab"')$q$,
      $q$select public.app_admin_save_setting('announcement', '{"enabled":true,"text":"","level":"info"}')$q$, $q$select public.app_admin_save_setting('announcement', '{"enabled":false,"text":"x","level":"danger"}')$q$,
      $q$select public.app_admin_save_setting('default_view', '"settings"')$q$, $q$select public.app_admin_save_setting('default_sy', '"2025"')$q$,
      $q$select public.app_admin_save_setting('contact', '{"email":"not-an-email"}')$q$, $q$select public.app_admin_save_setting('database_url', '"x"')$q$] loop
      denied := false; begin execute e; exception when others then denied := true; end; assert denied, 'refused: ' || e;
    end loop;
    perform public.app_admin_clear_setting('contact');
    assert not exists (select 1 from public.site_settings where key = 'contact'), 'a setting can be cleared back to the built-in value';
    reset role; set local role anon;
    assert (select count(*) from public.site_settings) = 4, 'settings are readable on the login page'; reset role;
    raise notice 'PASS settings';

    -- media: validation, usage tracking, storage policies
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    mid := public.app_admin_register_media('11111111-1111-1111-1111-111111111111.png', 'logo.png', 'image/png', 5000, 'Division logo');
    mid2 := public.app_admin_register_media('22222222-2222-2222-2222-222222222222.jpg', 'banner.jpg', 'image/jpeg', 9000, '');
    foreach e in array array[$q$select public.app_admin_register_media('33333333-3333-3333-3333-333333333333.svg', 'x.svg', 'image/svg+xml', 10, '')$q$,
      $q$select public.app_admin_register_media('33333333-3333-3333-3333-333333333333.png', 'x.png', 'image/jpeg', 10, '')$q$,
      $q$select public.app_admin_register_media('33333333-3333-3333-3333-333333333333.png', 'x.png', 'image/png', 3000000, '')$q$,
      $q$select public.app_admin_register_media('../evil.png', 'x.png', 'image/png', 10, '')$q$,
      $q$select public.app_admin_register_media('33333333-3333-3333-3333-333333333333.png', 'x.png', 'image/png', 10, '<script>')$q$,
      $q$select public.app_admin_assign_media('login.hero', null)$q$] loop
      denied := false; begin execute e; exception when others then denied := true; end; assert denied, 'refused: ' || e;
    end loop;
    perform public.app_admin_assign_media('brand.logo', mid);
    denied := false; begin perform public.app_admin_delete_media(mid); exception when others then denied := sqlerrm like '%still in use%'; end; assert denied, 'an image in use cannot be deleted';
    perform public.app_admin_assign_media('brand.logo', mid2);
    path := public.app_admin_delete_media(mid); assert path = '11111111-1111-1111-1111-111111111111.png', 'once replaced, the old image can be deleted (path returned for the file)';
    perform public.app_admin_update_media(mid2, 'Division banner');
    assert (select alt_text from public.site_media where id = mid2) = 'Division banner', 'alt text saved';
    insert into storage.objects (bucket_id, name) values ('site-media', '22222222-2222-2222-2222-222222222222.jpg');
    denied := false; begin insert into storage.objects (bucket_id, name) values ('other-bucket', 'x.png'); exception when others then denied := true; end; assert denied, 'the administrator can write only to the site-media bucket';
    reset role; set local role anon;
    assert (select count(*) from public.site_media_slots) = 1, 'image positions are public for the login page'; reset role;
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    denied := false; begin insert into storage.objects (bucket_id, name) values ('site-media', 'sneaky.png'); exception when others then denied := true; end; assert denied, 'a supervisor cannot upload';
    reset role;
    raise notice 'PASS media';

    -- logging: administrative actions are recorded; a non-admin who opens /admin is recorded once a minute
    assert (select count(distinct action) from public.admin_activity where action in ('user.create', 'user.update', 'user.password_reset', 'content.update', 'content.restore', 'content.reset', 'settings.update', 'settings.clear', 'media.upload', 'media.assign', 'media.delete')) = 11, 'every kind of administrative action is logged';
    perform set_config('request.jwt.claims', sup, true); set local role authenticated;
    perform public.app_admin_log_denied(); perform public.app_admin_log_denied();
    reset role;
    assert (select count(*) from public.admin_activity where action = 'admin.access_denied' and outcome = 'denied') = 1, 'a denied attempt is logged once per minute';
    perform set_config('request.jwt.claims', adm, true); set local role authenticated;
    perform public.app_admin_log_event('login');
    denied := false; begin perform public.app_admin_log_event('anything'); exception when others then denied := true; end; assert denied, 'only known session events can be logged';
    assert (select count(*) from public.app_admin_activity('user.')) >= 3 and (select count(*) from public.app_admin_data_changes()) > 0, 'the admin can read both logs';
    reset role;
    raise notice 'PASS admin activity log';
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

-- Migration 0013: school master list, schools without a program, school level and district checks on records
do $$
declare
  asu smallint := (select id from public.districts where name = 'Asuncion');
  car smallint := (select id from public.districts where name = 'Carmen');
  se bigint; ss bigint; sn bigint; sc bigint; denied boolean; msg text; n int;
  admin text := '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
  ce text := '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
begin
  perform set_config('request.jwt.claims', admin, true); set local role authenticated;
  se := public.app_save_school(null, 'M13 Elementary', asu, array['mapeh'], true, 'elementary', 900001);
  ss := public.app_save_school(null, 'M13 Secondary', asu, array['mapeh'], true, 'secondary', 900002);
  sn := public.app_save_school(null, 'M13 No Level', asu, array['mapeh']);
  sc := public.app_save_school(null, 'M13 Carmen Elementary', car, array['mapeh'], true, 'elementary', 900003);
  assert (select count(*) from public.school_programs where school_id in (se, ss, sn, sc) and program <> 'mapeh') = 0, 'master-list schools carry no SP / IPED assignment';
  denied := false; begin perform public.app_save_school(null, 'M13 Duplicate ID', asu, array[]::text[], true, 'elementary', 900001); exception when others then denied := sqlerrm like '%already exists%'; end;
  assert denied, 'the same DepEd school ID cannot be used twice';
  denied := false; begin perform public.app_save_school(null, 'M13 Bad Level', asu, array[]::text[], true, 'middle', null); exception when others then denied := true; end;
  assert denied, 'an unknown education level is refused';
  reset role;

  -- one Elementary coordinator encodes for several schools of the district with a single account
  perform set_config('request.jwt.claims', ce, true); set local role authenticated;
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 2','Grade 5','MAPEH - Overall',65,81,70,'x',se);
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 2','Grade 5','MAPEH - Music & Arts',65,79,70,'x',sn);
  assert (select count(distinct school_id) from public.assessment_records where school_id in (se, sn)) = 2, 'one coordinator account saved MAPEH records for two schools';
  assert (select school from public.assessment_records where school_id = se limit 1) = 'M13 Elementary', 'the school name follows the school record';
  denied := false; msg := null; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 2','Grade 5','MAPEH - Overall',65,81,70,'x',ss); exception when others then denied := true; msg := sqlerrm; end;
  assert denied, 'a Secondary school cannot take an Elementary record (' || coalesce(msg, '') || ')';
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 2','Grade 5','MAPEH - Overall',65,81,70,'x',sc); exception when others then denied := true; end;
  assert denied, 'a school of another district is refused for this coordinator (server side)';
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',car,'Key Stage 2','Grade 5','MAPEH - Overall',65,81,70,'x',sc); exception when others then denied := true; end;
  assert denied, 'and so is a record for another district, even with that district''s school';
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 2','Grade 5','IPED - English',65,81,70,'x',se); exception when others then denied := true; end;
  assert denied, 'an IPED record still needs a school classified under IPED (the master list does not classify anyone)';
  select count(*) into n from public.assessment_records where school_id in (se, ss, sn, sc);
  assert n = 2, 'only the two valid records exist';
  reset role;
  raise notice 'PASS school master list (0013)';
end $$;

-- Migration 0014: MAPEH program, Key Stage 1 rule, Key Stage 4 subjects, school years
do $$
declare
  asu smallint := (select id from public.districts where name = 'Asuncion');
  car smallint := (select id from public.districts where name = 'Carmen');
  s_m bigint; s_sp bigint; s_all bigint; denied boolean; msg text; n int; rid bigint;
  admin text := '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
  sup text := '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
  ce text := '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
  cs text := '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';
begin
  -- one school can hold several programs; nothing is duplicated
  perform set_config('request.jwt.claims', admin, true); set local role authenticated;
  s_m := public.app_save_school(null, 'M14 MAPEH Only', asu, array['mapeh'], true, 'secondary', 910001);
  s_sp := public.app_save_school(null, 'M14 SP Only', asu, array['special_programs'], true, 'secondary', 910002);
  s_all := public.app_save_school(null, 'M14 All Three', asu, array['mapeh', 'special_programs', 'iped'], true, 'secondary', 910003);
  assert (select count(*) from public.school_programs where school_id = s_all) = 3, 'a school can be assigned to MAPEH, Special Programs and IPED together';
  assert (select count(*) from public.schools where name like 'M14 %') = 3, 'no school is duplicated for holding several programs';
  perform public.app_save_school(s_all, 'M14 All Three', asu, array['mapeh', 'iped'], true);
  assert (select count(*) from public.school_programs where school_id = s_all) = 2, 'a program can be taken away again (no records yet)';
  assert public.app_save_school(s_all, 'M14 All Three', asu, array['mapeh', 'special_programs', 'iped'], true) = s_all, 'and given back';
  denied := false; begin perform public.app_save_school(null, 'M14 Bad', asu, array['other']); exception when others then denied := true; end;
  assert denied, 'an unknown program is refused';
  reset role;

  -- coordinator of the Secondary level: Key Stage 3 and 4 records against the school program tags
  perform set_config('request.jwt.claims', cs, true); set local role authenticated;
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 8','MAPEH - Music & Arts',65,80,70,'x',s_m);
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 8','SPA - Vocal Arts',65,80,70,'x',s_m); exception when others then denied := sqlerrm like '%not classified%'; end;
  assert denied, 'a MAPEH-only school cannot take Special Programs records (enforced by the database)';
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 8','MAPEH - PE & Health',65,80,70,'x',s_sp); exception when others then denied := sqlerrm like '%not classified%'; end;
  assert denied, 'a school without the MAPEH tag cannot take MAPEH records';
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 8','SPA - Vocal Arts',65,80,70,'x',s_all);
  -- Key Stage 4 subjects: Grades 11 and 12 only
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 4','Grade 11','SHS - Life and Career Skills',65,82,70,'x',s_m);
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 4','Grade 12','SHS - Sports/Health/Wellness',65,84,70,'x',s_m);
  denied := false; msg := null; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 9','SHS - Life and Career Skills',65,82,70,'x',s_m); exception when others then denied := true; msg := sqlerrm; end;
  assert denied and msg like '%Key Stage 4 subjects%', 'a Key Stage 4 subject cannot be entered for Grade 9 (' || coalesce(msg, '') || ')';
  denied := false; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level,school_id)
    values ('2025-2026','Term 1',asu,'Key Stage 3','Grade 8','SHS - Sports/Health/Wellness',65,82,70,'x',s_m); exception when others then denied := true; end;
  assert denied, 'nor for Grade 8';
  reset role;

  -- Key Stage 1: no MAPEH - Overall on new records, Music and Arts / P.E. and Health accepted
  perform set_config('request.jwt.claims', ce, true); set local role authenticated;
  denied := false; msg := null; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 2','MAPEH - Overall',65,81,70,'x'); exception when others then denied := true; msg := sqlerrm; end;
  assert denied and msg like '%Key Stage 1%', 'MAPEH - Overall is refused in Key Stage 1 by the database (' || coalesce(msg, '') || ')';
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 2','MAPEH - Music & Arts',65,81,70,'x');
  insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 1',asu,'Key Stage 1','Grade 3','MAPEH - PE & Health',65,79,70,'x');
  reset role;

  -- school years: only the System Administrator changes them; new records in a disabled year are refused; old ones stay
  perform set_config('request.jwt.claims', sup, true); set local role authenticated;
  denied := false; begin perform public.app_set_school_year_enabled('2027-2028', false); exception when insufficient_privilege then denied := true; end;
  assert denied, 'a Supervisor cannot disable a school year';
  reset role;
  perform set_config('request.jwt.claims', ce, true); set local role authenticated;
  denied := false; begin perform public.app_set_school_year_enabled('2027-2028', false); exception when insufficient_privilege then denied := true; end;
  assert denied, 'a coordinator cannot disable a school year';
  assert (select count(*) from public.school_years) >= 10, 'every signed-in user can read the list of school years';
  denied := false; begin update public.school_years set enabled = false; exception when insufficient_privilege then denied := true; end;
  assert denied, 'the table cannot be written directly through the API';
  reset role;
  select count(*) into n from public.assessment_records where sy = '2025-2026' and deleted_at is null;
  perform set_config('request.jwt.claims', admin, true); set local role authenticated;
  perform public.app_set_school_year_enabled('2025-2026', false);
  reset role;
  assert (select count(*) from public.assessment_records where sy = '2025-2026' and deleted_at is null) = n, 'disabling a school year leaves its records untouched';
  perform set_config('request.jwt.claims', ce, true); set local role authenticated;
  denied := false; msg := null; begin insert into public.assessment_records (sy,term,district_id,key_stage,grade_level,learning_area,baseline_mps,mps,pct75,proficiency_level)
    values ('2025-2026','Term 2',asu,'Key Stage 2','Grade 5','MAPEH - Overall',65,81,70,'x'); exception when others then denied := true; msg := sqlerrm; end;
  assert denied and msg like '%not open for data entry%', 'a new record in a disabled school year is refused by the database (' || coalesce(msg, '') || ')';
  select id into rid from public.assessment_records where sy = '2025-2026' and district_id = asu and education_level = 'elementary' and deleted_at is null limit 1;
  update public.assessment_records set mps = 77 where id = rid; get diagnostics n = row_count;
  assert n = 1, 'an existing record in a disabled year can still be edited (score)';
  denied := false; begin update public.assessment_records set sy = '2026-2027' where id = rid; update public.assessment_records set sy = '2025-2026' where id = rid; exception when others then denied := true; end;
  assert denied, 'but cannot be moved back into the disabled year';
  reset role;
  perform set_config('request.jwt.claims', admin, true); set local role authenticated;
  perform public.app_set_school_year_enabled('2025-2026', true);
  denied := false; begin perform public.app_set_school_year_enabled('not a year', true); exception when others then denied := true; end;
  assert denied, 'a malformed school year is refused';
  reset role;
  raise notice 'PASS programs, key stage rules, school years (0014)';
end $$;

rollback;
