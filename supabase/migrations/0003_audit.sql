-- 0003_audit.sql: audit_log filled by triggers (CLAUDE.md section 11)

create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  table_name text not null,
  action text not null,
  row_id text,
  old jsonb,
  new jsonb
);

alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
create policy audit_select on public.audit_log for select to authenticated
  using (public.app_role_of_user() = 'admin');

create or replace function public.app_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  rid text;
begin
  if tg_op = 'DELETE' then
    rid := to_jsonb(old)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, old)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(old));
    return old;
  elsif tg_op = 'UPDATE' then
    rid := to_jsonb(new)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, old, new)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(old), to_jsonb(new));
    return new;
  else
    rid := to_jsonb(new)->>'id';
    insert into public.audit_log (actor, table_name, action, row_id, new)
      values (auth.uid(), tg_table_name, tg_op, rid, to_jsonb(new));
    return new;
  end if;
end $$;

create trigger audit_assessment_records after insert or update or delete on public.assessment_records
  for each row execute function public.app_audit();
create trigger audit_comparative_notes after insert or update or delete on public.comparative_notes
  for each row execute function public.app_audit();
create trigger audit_districts after insert or update or delete on public.districts
  for each row execute function public.app_audit();
create trigger audit_app_settings after insert or update or delete on public.app_settings
  for each row execute function public.app_audit();
