-- 0011_admin_panel.sql, part 1 of 4. For pasting into the Supabase SQL editor when the whole file is too long to paste.
-- Run the four parts in order, each as its own run. Together they equal 0011_admin_panel.sql.

-- 0011_admin_panel.sql: everything the /admin panel needs. Safe to run once on a project that has 0001 to 0010.
-- Run it BEFORE deploying the matching app version. Nothing existing is changed or removed.
--
-- Security model: every privileged operation is a database function that checks, on the server, that the caller is an
-- ACTIVE user with role 'admin' (app_is_admin). The browser never holds a service key. Supervisors, coordinators and school
-- accounts are refused by every function and by row level security, whatever the screen shows.
--   * admin_activity       audit trail of administrative actions (no passwords, tokens or secrets are ever written)
--   * site_content         editable text, plain text only (angle brackets are refused, so no HTML or script can be stored)
--   * site_content_versions history with restore
--   * site_settings        validated settings (title, organization, announcement, landing view, school year, contact)
--   * site_media / site_media_slots / storage bucket "site-media"   images, with usage tracking
--   * app_admin_* functions   user management, password reset, content, settings and media

create or replace function public.app_is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role_of_user()::text = 'admin', false)
$$;
revoke execute on function public.app_is_admin() from public, anon;
grant execute on function public.app_is_admin() to authenticated;

-- ===== audit trail of administrative actions =====
create table public.admin_activity (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  actor_name text,
  action text not null,
  resource text,
  resource_id text,
  outcome text not null default 'success' check (outcome in ('success', 'failure', 'denied')),
  details jsonb not null default '{}'
);
create index on public.admin_activity (at desc);
alter table public.admin_activity enable row level security;
revoke all on public.admin_activity from anon, authenticated;
grant select on public.admin_activity to authenticated;
create policy admin_activity_select on public.admin_activity for select to authenticated using (public.app_is_admin());

create or replace function public.app_admin_log(p_action text, p_resource text, p_resource_id text, p_outcome text, p_details jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.admin_activity (actor, actor_name, action, resource, resource_id, outcome, details)
  values (auth.uid(), (select display_name from public.profiles where id = auth.uid()), p_action, p_resource, p_resource_id,
          coalesce(p_outcome, 'success'), coalesce(p_details, '{}'))
$$;
revoke execute on function public.app_admin_log(text, text, text, text, jsonb) from public, anon, authenticated;

-- Events the admin page reports about itself (sign-in, sign-out, own password change). Admin only.
create or replace function public.app_admin_log_event(p_action text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_action not in ('login', 'logout', 'password_changed_self') then raise exception 'Unknown event.'; end if;
  perform public.app_admin_log('admin.' || p_action, 'session', null, 'success', '{}');
end $$;

-- A signed-in user who is NOT an administrator opened /admin: record it (at most once a minute per user).
create or replace function public.app_admin_log_denied() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  if exists (select 1 from public.admin_activity where actor = auth.uid() and action = 'admin.access_denied' and at > now() - interval '1 minute') then return; end if;
  perform public.app_admin_log('admin.access_denied', 'session', null, 'denied', '{}');
end $$;
revoke execute on function public.app_admin_log_event(text), public.app_admin_log_denied() from public, anon;
grant execute on function public.app_admin_log_event(text), public.app_admin_log_denied() to authenticated;

