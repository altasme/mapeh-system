-- provision_coordinators.sql: creates the 22 Elementary and Secondary coordinator accounts from the SQL editor,
-- for use when the Node script (tools/provision-level-coordinators.mjs) cannot be run. Run AFTER 0004 and 0005.
--
--   Username  {district_code}_elemcoord / {district_code}_seccoord      (login: username only, as on the login screen)
--   Initial password  {district_code}@elem / {district_code}@sec        (initial credentials only)
--
-- Client decision for the testing phase: accounts use their initial password as is (no forced or voluntary change;
-- must_change_password stays false, see migration 0008). Safe to run twice: an account that already exists is
-- left alone (password and flag unchanged). It also retires the original 11 district-wide coordinators
-- (profiles.active = false and sign-in banned); undo by setting active = true and clearing banned_until.
-- The passwords below come from the agreed convention, so keep this repository private and hand accounts out together.
do $$
declare
  codes text[][] := array[
    ['Asuncion','asuncion'], ['B.E. Dujali','dujali'], ['Carmen','carmen'], ['Kapalong East','kapalonge'],
    ['Kapalong West','kapalongw'], ['New Corella','newcorella'], ['San Isidro','sanisidro'],
    ['Sto. Tomas East','stotomase'], ['Sto. Tomas West','stotomasw'], ['Talaingod','talaingod'], ['Langilan','langilan']];
  lv text[][] := array[['elementary','Elementary','elemcoord','elem'], ['secondary','Secondary','seccoord','sec']];
  i int; j int; v_dist text; v_code text; v_user text; v_email text; v_id uuid; v_did smallint;
  created int := 0; existed int := 0; retired int := 0;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'must_change_password') then
    raise exception 'Run supabase/migrations/0004_education_levels.sql first.';
  end if;
  for i in 1 .. array_length(codes, 1) loop
    v_dist := codes[i][1]; v_code := codes[i][2];
    select id into v_did from public.districts where name = v_dist;
    if v_did is null then raise exception 'Unknown district %', v_dist; end if;
    for j in 1 .. 2 loop
      v_user := v_code || '_' || lv[j][3];
      v_email := v_user || '@users.mapehdavnor.altasme.app';
      select id into v_id from auth.users where email = v_email;
      if v_id is null then
        v_id := gen_random_uuid();
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
            confirmation_token, recovery_token, email_change_token_new, email_change)
          values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
            extensions.crypt(v_code || '@' || lv[j][4], extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
        insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
          values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
            'email', now(), now(), now());
        insert into public.profiles (id, username, display_name, role, district_id, education_level, active, must_change_password)
          values (v_id, v_user, v_dist || ' ' || lv[j][2] || ' Coordinator', 'district_coordinator', v_did, lv[j][1], true, false);
        created := created + 1;
      else
        update public.profiles set district_id = v_did, education_level = lv[j][1], active = true, role = 'district_coordinator',
          display_name = v_dist || ' ' || lv[j][2] || ' Coordinator', username = v_user where id = v_id;
        existed := existed + 1;
      end if;
    end loop;
  end loop;

  -- 0004 already set active = false on the original district-wide coordinators; here their sign-in is also banned.
  update public.profiles set active = false where role = 'district_coordinator' and education_level is null and active;
  update auth.users set banned_until = now() + interval '100 years'
    where id in (select id from public.profiles where role = 'district_coordinator' and education_level is null);
  get diagnostics retired = row_count;

  raise notice 'Done: % created, % already existed, % original coordinators retired.', created, existed, retired;
end $$;

select count(*) filter (where education_level = 'elementary') as elementary,
       count(*) filter (where education_level = 'secondary') as secondary,
       count(*) as accounts
from public.profiles where role = 'district_coordinator' and active;
