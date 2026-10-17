-- 0008_no_password_gate.sql: client decision for the testing phase: accounts keep their initial passwords and there is
-- no forced or voluntary password change. The "must change password" lock from 0004 is switched off:
--   * every account's flag is cleared, and
--   * the access helper functions no longer look at it, so no account can be locked out by it.
-- The column and the trigger stay in place (harmless), so the lock can be switched back on later by restoring the
-- four helper functions as written in 0004 (see HANDOVER section 15). Safe to run more than once.
update public.profiles set must_change_password = false where must_change_password;

create or replace function public.app_session_ok() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select active from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.app_role_of_user() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.app_district_of_user() returns smallint
language sql stable security definer set search_path = '' as $$
  select district_id from public.profiles where id = auth.uid() and active
$$;

create or replace function public.app_education_level_of_user() returns text
language sql stable security definer set search_path = '' as $$
  select education_level from public.profiles where id = auth.uid() and active
$$;
