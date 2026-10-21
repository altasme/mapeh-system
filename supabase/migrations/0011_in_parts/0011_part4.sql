-- 0011_admin_panel.sql, part 4 of 4. For pasting into the Supabase SQL editor when the whole file is too long to paste.
-- Run the four parts in order, each as its own run. Together they equal 0011_admin_panel.sql.

-- ===== images and media =====
create table public.site_media (
  id uuid primary key default gen_random_uuid(),
  path text not null unique check (path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'),
  original_name text not null check (char_length(original_name) between 1 and 200),
  mime text not null check (mime in ('image/png', 'image/jpeg', 'image/webp')),
  size_bytes integer not null check (size_bytes between 1 and 2097152),
  alt_text text not null default '' check (char_length(alt_text) <= 200),
  uploaded_by uuid,
  uploaded_at timestamptz not null default now()
);
create table public.site_media_slots (
  slot text primary key check (slot in ('brand.logo', 'print.header_logo', 'print.footer_logo_1', 'print.footer_logo_2', 'print.footer_logo_3')),
  media_id uuid not null references public.site_media(id) on delete restrict,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.site_media enable row level security;
alter table public.site_media_slots enable row level security;
revoke all on public.site_media, public.site_media_slots from anon, authenticated;
grant select on public.site_media, public.site_media_slots to anon, authenticated;
create policy site_media_read on public.site_media for select to anon, authenticated using (true);
create policy site_media_slots_read on public.site_media_slots for select to anon, authenticated using (true);

create or replace function public.app_admin_register_media(p_path text, p_name text, p_mime text, p_size integer, p_alt text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_mime not in ('image/png', 'image/jpeg', 'image/webp') then raise exception 'Only PNG, JPEG or WebP images are allowed.'; end if;
  if p_size is null or p_size < 1 or p_size > 2097152 then raise exception 'The image must be 2 MB or smaller.'; end if;
  if p_path is null or p_path !~ ('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.' || case p_mime when 'image/png' then 'png' when 'image/jpeg' then 'jpg' else 'webp' end || '$') then
    raise exception 'The file name does not match its type.';
  end if;
  if btrim(coalesce(p_alt, '')) ~ '[<>]' then raise exception 'Plain text only for the description.'; end if;
  insert into public.site_media (path, original_name, mime, size_bytes, alt_text, uploaded_by)
    values (p_path, left(regexp_replace(btrim(coalesce(p_name, 'image')), '[<>"\\/]', '_', 'g'), 200), p_mime, p_size, left(btrim(coalesce(p_alt, '')), 200), auth.uid()) returning id into v_id;
  perform public.app_admin_log('media.upload', 'media', v_id::text, 'success', jsonb_build_object('name', left(coalesce(p_name, ''), 80), 'size', p_size, 'mime', p_mime));
  return v_id;
end $$;

create or replace function public.app_admin_update_media(p_id uuid, p_alt text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if btrim(coalesce(p_alt, '')) ~ '[<>]' or char_length(btrim(coalesce(p_alt, ''))) > 200 then raise exception 'Plain text only, 200 characters at most.'; end if;
  update public.site_media set alt_text = btrim(coalesce(p_alt, '')) where id = p_id;
  if not found then raise exception 'Image not found.'; end if;
  perform public.app_admin_log('media.update', 'media', p_id::text, 'success', '{}');
end $$;

create or replace function public.app_admin_assign_media(p_slot text, p_media_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  if p_slot not in ('brand.logo', 'print.header_logo', 'print.footer_logo_1', 'print.footer_logo_2', 'print.footer_logo_3') then raise exception 'Unknown image position.'; end if;
  if p_media_id is null then
    delete from public.site_media_slots where slot = p_slot;
  else
    if not exists (select 1 from public.site_media where id = p_media_id) then raise exception 'Image not found.'; end if;
    insert into public.site_media_slots (slot, media_id, updated_by, updated_at) values (p_slot, p_media_id, auth.uid(), now())
      on conflict (slot) do update set media_id = excluded.media_id, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
  perform public.app_admin_log('media.assign', 'media', p_slot, 'success', jsonb_build_object('slot', p_slot, 'media', p_media_id));
end $$;

-- Removes an image record that is not in use; returns its storage path so the page can delete the file too.
create or replace function public.app_admin_delete_media(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_path text; used text;
begin
  if not public.app_is_admin() then raise exception 'Only an administrator can do this.' using errcode = '42501'; end if;
  select string_agg(slot, ', ') into used from public.site_media_slots where media_id = p_id;
  if used is not null then raise exception 'This image is still in use (%). Replace or clear those positions first.', used; end if;
  delete from public.site_media where id = p_id returning path into v_path;
  if v_path is null then raise exception 'Image not found.'; end if;
  perform public.app_admin_log('media.delete', 'media', p_id::text, 'success', '{}');
  return v_path;
end $$;

revoke execute on function public.app_admin_list_users(text, text, smallint, bigint, text, text, integer, integer), public.app_admin_user_stats(),
  public.app_admin_create_user(text, text, text, smallint, text, bigint, text), public.app_admin_update_user(uuid, text, text, text, smallint, text, bigint, boolean),
  public.app_admin_set_password(uuid, text), public.app_admin_activity(text, text, integer, integer), public.app_admin_data_changes(integer, integer),
  public.app_admin_save_content(text, text), public.app_admin_reset_content(text), public.app_admin_restore_content(bigint),
  public.app_admin_save_setting(text, jsonb), public.app_admin_clear_setting(text), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
  public.app_admin_assign_media(text, uuid), public.app_admin_delete_media(uuid) from public, anon;
grant execute on function public.app_admin_list_users(text, text, smallint, bigint, text, text, integer, integer), public.app_admin_user_stats(),
  public.app_admin_create_user(text, text, text, smallint, text, bigint, text), public.app_admin_update_user(uuid, text, text, text, smallint, text, bigint, boolean),
  public.app_admin_set_password(uuid, text), public.app_admin_activity(text, text, integer, integer), public.app_admin_data_changes(integer, integer),
  public.app_admin_save_content(text, text), public.app_admin_reset_content(text), public.app_admin_restore_content(bigint),
  public.app_admin_save_setting(text, jsonb), public.app_admin_clear_setting(text), public.app_admin_register_media(text, text, text, integer, text), public.app_admin_update_media(uuid, text),
  public.app_admin_assign_media(text, uuid), public.app_admin_delete_media(uuid) to authenticated;

-- ===== storage: a public bucket for site images; only an administrator can write to it =====
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      values ('site-media', 'site-media', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
      on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];
    execute 'drop policy if exists site_media_admin_insert on storage.objects';
    execute 'drop policy if exists site_media_admin_update on storage.objects';
    execute 'drop policy if exists site_media_admin_delete on storage.objects';
    execute $p$create policy site_media_admin_insert on storage.objects for insert to authenticated with check (bucket_id = 'site-media' and public.app_is_admin())$p$;
    execute $p$create policy site_media_admin_update on storage.objects for update to authenticated using (bucket_id = 'site-media' and public.app_is_admin()) with check (bucket_id = 'site-media' and public.app_is_admin())$p$;
    execute $p$create policy site_media_admin_delete on storage.objects for delete to authenticated using (bucket_id = 'site-media' and public.app_is_admin())$p$;
  end if;
end $$;

create trigger audit_site_content after insert or update or delete on public.site_content for each row execute function public.app_audit();
