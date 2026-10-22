-- ProTracker (hosted at protracker.indexhomes.in): where each person's ProTracker data lives in Supabase.
-- Same shape as the claude.ai artifact's per-user collection: one row per document. Task documents use the
-- task id; the people list, saved tags, tag categories and team ticks are the documents _people, _tags,
-- _tagcats and _team. Run once in the SQL Editor (safe to run again). Needs team/schema.sql first.
create table if not exists public.pt_docs (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (char_length(id) between 1 and 200),
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.pt_docs enable row level security;

-- Each person reads and writes only their own documents.
drop policy if exists "own docs: read" on public.pt_docs;
create policy "own docs: read" on public.pt_docs for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "own docs: add" on public.pt_docs;
create policy "own docs: add" on public.pt_docs for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "own docs: change" on public.pt_docs;
create policy "own docs: change" on public.pt_docs for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "own docs: remove" on public.pt_docs;
create policy "own docs: remove" on public.pt_docs for delete to authenticated using (user_id = (select auth.uid()));

-- Live updates between devices (rows still filtered by the policies above).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pt_docs'
  ) then
    alter publication supabase_realtime add table public.pt_docs;
  end if;
end $$;

-- Which ProTracker each team member gets: "simple" (one list: what the owner assigned them plus their own
-- tasks) or "full" (all of ProTracker plus an Assigned tab). No row means simple. Only the owner (public.admins)
-- sets it, from the People view; each member can read only their own row.
create table if not exists public.pt_members (
  email text primary key check (email = lower(email) and email like '%_@_%'),
  mode text not null default 'simple' check (mode in ('simple', 'full')),
  updated_at timestamptz not null default now()
);
alter table public.pt_members enable row level security;
drop policy if exists "members: read own or owner" on public.pt_members;
create policy "members: read own or owner" on public.pt_members for select to authenticated
using (email = public.my_email() or public.is_admin());
drop policy if exists "members: owner adds" on public.pt_members;
create policy "members: owner adds" on public.pt_members for insert to authenticated with check (public.is_admin());
drop policy if exists "members: owner changes" on public.pt_members;
create policy "members: owner changes" on public.pt_members for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "members: owner removes" on public.pt_members;
create policy "members: owner removes" on public.pt_members for delete to authenticated using (public.is_admin());

-- Team members who may assign tasks (set by the owner), and who assigned each task.
alter table public.pt_members add column if not exists can_assign boolean not null default false;
alter table public.team_tasks add column if not exists assigned_by text;
alter table public.team_tasks add column if not exists assigned_by_name text check (assigned_by_name is null or char_length(assigned_by_name) <= 60);

-- True for a member the owner allowed to assign (Full version only).
create or replace function public.can_assign() returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.pt_members where email = public.my_email() and can_assign and mode = 'full') $$;
revoke all on function public.can_assign() from public, anon;
grant execute on function public.can_assign() to authenticated;

-- Who assigned a task comes from the assigner's sign-in, never from what the page sends; it never changes after.
create or replace function public.team_tasks_assigner() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.assigned_by := case when new.source_id is null then null else public.my_email() end;
  else
    new.assigned_by := old.assigned_by;
  end if;
  return new;
end $$;
drop trigger if exists team_tasks_assigner on public.team_tasks;
create trigger team_tasks_assigner before insert or update on public.team_tasks
for each row execute function public.team_tasks_assigner();
-- Existing assigned tasks: their creator assigned them (the trigger above would keep them empty, so it's paused).
alter table public.team_tasks disable trigger team_tasks_assigner;
update public.team_tasks t set assigned_by = lower(u.email) from auth.users u
where u.id = t.created_by and t.source_id is not null and t.assigned_by is null;
alter table public.team_tasks enable trigger team_tasks_assigner;

-- Assigners see, change and remove the tasks they assigned; everyone else as before.
drop policy if exists "read own or admin" on public.team_tasks;
create policy "read own or admin" on public.team_tasks for select to authenticated
using (public.is_admin() or assignee_email = public.my_email() or created_by = (select auth.uid()));

drop policy if exists "add own or admin" on public.team_tasks;
create policy "add own or admin" on public.team_tasks for insert to authenticated
with check (
  public.is_admin()
  or (assignee_email = public.my_email() and source_id is null and created_by = (select auth.uid()))
  or (public.can_assign() and source_id is not null and created_by = (select auth.uid()))
);

drop policy if exists "change own or admin" on public.team_tasks;
create policy "change own or admin" on public.team_tasks for update to authenticated
using (public.is_admin() or assignee_email = public.my_email() or (created_by = (select auth.uid()) and public.can_assign()))
with check (public.is_admin() or assignee_email = public.my_email() or (created_by = (select auth.uid()) and public.can_assign()));

drop policy if exists "delete own added or admin" on public.team_tasks;
create policy "delete own added or admin" on public.team_tasks for delete to authenticated
using (
  public.is_admin()
  or (assignee_email = public.my_email() and source_id is null and created_by = (select auth.uid()))
  or (created_by = (select auth.uid()) and source_id is not null and public.can_assign())
);

-- ---- Security clean-up (Oct 23 2026) ----
-- The old claude.ai sync key (team.indexhomes.in "Connect ProTracker", replaced by the Supabase connector) is gone.
drop function if exists public.team_progress(text);
drop function if exists public.create_sync_key();
drop table if exists public.sync_keys;
-- Who created and who assigned a task never change after it's made (an assignee can't take a task over).
create or replace function public.team_tasks_assigner() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.assigned_by := case when new.source_id is null then null else public.my_email() end;
  else
    new.assigned_by := old.assigned_by;
    new.created_by := old.created_by;
  end if;
  return new;
end $$;
-- Nothing callable without signing in except what the access rules need; trigger functions not callable at all.
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke execute on function public.team_tasks_guard() from public, anon, authenticated;
revoke execute on function public.team_tasks_lock_source() from public, anon, authenticated;
revoke execute on function public.team_tasks_assigner() from public, anon, authenticated;
