-- 0011_admin_panel.sql, part 3 of 4. For pasting into the Supabase SQL editor when the whole file is too long to paste.
-- Run the four parts in order, each as its own run. Together they equal 0011_admin_panel.sql.

-- ===== website content (plain text) with history =====
create table public.site_content (
  key text primary key check (key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$' and char_length(key) <= 80),
  value text not null check (char_length(value) between 1 and 2000),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create table public.site_content_versions (
  id bigint generated always as identity primary key,
  key text not null,
  old_value text,
  new_value text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
create index on public.site_content_versions (key, changed_at desc);
alter table public.site_content enable row level security;
alter table public.site_content_versions enable row level security;
revoke all on public.site_content, public.site_content_versions from anon, authenticated;
grant select on public.site_content to anon, authenticated;
grant select on public.site_content_versions to authenticated;
create policy site_content_read on public.site_content for select to anon, authenticated using (true);
create policy site_content_versions_read on public.site_content_versions for select to authenticated using (public.app_is_admin());

create or replace function public.app_admin_save_content(p_key text, p_value text) returns void
language plpgsql security definer set search_path = '' as $$
declare v text := btrim(replace(coalesce(p_value, ''), E'\r', '')); old text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_key is null or p_key !~ '^[a-z0-9]+([._-][a-z0-9]+)*$' or char_length(p_key) > 80 then raise exception 'Unknown content item.'; end if;
  if v = '' then raise exception 'This text cannot be empty. Use "Reset to default" to go back to the original.'; end if;
  if char_length(v) > 2000 then raise exception 'This text is too long (2000 characters at most).'; end if;
  if v ~ '[<>]' then raise exception 'Plain text only: the characters < and > are not allowed.'; end if;
  if v ~ '[\x00-\x08\x0b\x0c\x0e-\x1f]' then raise exception 'The text contains characters that are not allowed.'; end if;
  select value into old from public.site_content where key = p_key;
  if old is not distinct from v then return; end if;
  insert into public.site_content_versions (key, old_value, new_value, changed_by) values (p_key, old, v, auth.uid());
  insert into public.site_content (key, value, updated_by, updated_at) values (p_key, v, auth.uid(), now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform public.app_admin_log('content.update', 'content', p_key, 'success', jsonb_build_object('key', p_key, 'length', char_length(v)));
end $$;

create or replace function public.app_admin_reset_content(p_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare old text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select value into old from public.site_content where key = p_key;
  if old is null then return; end if;
  insert into public.site_content_versions (key, old_value, new_value, changed_by) values (p_key, old, null, auth.uid());
  delete from public.site_content where key = p_key;
  perform public.app_admin_log('content.reset', 'content', p_key, 'success', jsonb_build_object('key', p_key));
end $$;

-- put back the text a version replaced (the old text of that version, or the default when it was the first edit)
create or replace function public.app_admin_restore_content(p_version_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare ver record;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select * into ver from public.site_content_versions where id = p_version_id;
  if not found then raise exception 'Version not found.'; end if;
  if ver.old_value is null then perform public.app_admin_reset_content(ver.key); else perform public.app_admin_save_content(ver.key, ver.old_value); end if;
  perform public.app_admin_log('content.restore', 'content', ver.key, 'success', jsonb_build_object('key', ver.key, 'version', p_version_id));
end $$;

-- ===== website settings (validated) =====
create table public.site_settings (
  key text primary key check (key in ('site.title', 'org.name', 'announcement', 'default_view', 'default_sy', 'contact')),
  value jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;
revoke all on public.site_settings from anon, authenticated;
grant select on public.site_settings to anon, authenticated;
create policy site_settings_read on public.site_settings for select to anon, authenticated using (true);

create or replace function public.app_admin_save_setting(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare t text; txt text; lvl text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_key in ('site.title', 'org.name') then
    if jsonb_typeof(p_value) <> 'string' then raise exception 'Enter text.'; end if;
    t := btrim(p_value #>> '{}');
    if char_length(t) < 3 or char_length(t) > 120 then raise exception 'Use 3 to 120 characters.'; end if;
    if t ~ '[<>]' then raise exception 'Plain text only: the characters < and > are not allowed.'; end if;
    p_value := to_jsonb(t);
  elsif p_key = 'announcement' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'Invalid announcement.'; end if;
    txt := btrim(coalesce(p_value ->> 'text', '')); lvl := coalesce(p_value ->> 'level', 'info');
    if lvl not in ('info', 'warning') then raise exception 'Choose Information or Warning.'; end if;
    if char_length(txt) > 300 or txt ~ '[<>]' then raise exception 'The announcement must be plain text of 300 characters at most.'; end if;
    if coalesce((p_value ->> 'enabled')::boolean, false) and txt = '' then raise exception 'Enter the announcement text before turning it on.'; end if;
    p_value := jsonb_build_object('enabled', coalesce((p_value ->> 'enabled')::boolean, false), 'text', txt, 'level', lvl);
  elsif p_key = 'default_view' then
    if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') not in ('division', 'dashboard', 'district-view', 'comparative', 'grade-view', 'least-learned', 'data-input', 'manage-records') then
      raise exception 'Choose one of the listed screens.'; end if;
  elsif p_key = 'default_sy' then
    if jsonb_typeof(p_value) <> 'string' or ((p_value #>> '{}') <> 'ALL' and (p_value #>> '{}') !~ '^[0-9]{4}-[0-9]{4}$') then raise exception 'Choose All school years or a school year like 2025-2026.'; end if;
  elsif p_key = 'contact' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'Invalid contact details.'; end if;
    p_value := jsonb_build_object('email', btrim(coalesce(p_value ->> 'email', '')), 'phone', btrim(coalesce(p_value ->> 'phone', '')), 'address', btrim(coalesce(p_value ->> 'address', '')));
    if (p_value ->> 'email') <> '' and (p_value ->> 'email') !~ '^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$' then raise exception 'Enter a valid email address.'; end if;
    if char_length(p_value ->> 'phone') > 40 or (p_value ->> 'phone') ~ '[<>]' or char_length(p_value ->> 'address') > 200 or (p_value ->> 'address') ~ '[<>]' then raise exception 'The phone (40) or address (200) is too long or contains characters that are not allowed.'; end if;
  else
    raise exception 'Unknown setting.';
  end if;
  insert into public.site_settings (key, value, updated_by, updated_at) values (p_key, p_value, auth.uid(), now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform public.app_admin_log('settings.update', 'setting', p_key, 'success', jsonb_build_object('key', p_key));
end $$;

-- back to the built-in value: removes the override
create or replace function public.app_admin_clear_setting(p_key text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  delete from public.site_settings where key = p_key;
  if found then perform public.app_admin_log('settings.clear', 'setting', p_key, 'success', jsonb_build_object('key', p_key)); end if;
end $$;

