-- ProTracker Team: database setup for Supabase.
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- It is safe to run again; it only creates what's missing.

-- Who may publish and see everyone's tasks. Add yourself after your first sign-in:
--   insert into public.admins (user_id) select id from auth.users where email = 'you@example.com';
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.admins enable row level security;
-- No policies on purpose: nobody can read or change this table from the app.

-- One row per task. A person's tasks form a tree through parent_id.
-- Tasks published from ProTracker carry source_id (the ProTracker task id);
-- tasks people add themselves have source_id null.
create table if not exists public.team_tasks (
  id uuid primary key default gen_random_uuid(),
  assignee_email text not null check (assignee_email = lower(assignee_email) and assignee_email like '%_@_%'),
  source_id text,
  title text not null check (char_length(title) between 1 and 300),
  done boolean not null default false,
  completed_at timestamptz,
  parent_id uuid references public.team_tasks (id) on delete set null,
  sort double precision not null default 0,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assignee_email, source_id)
);
-- Tags from ProTracker (lowercase words, no #). Added after the first version, hence the separate statement.
alter table public.team_tasks add column if not exists tags text[] not null default '{}';
create index if not exists team_tasks_assignee on public.team_tasks (assignee_email);
create index if not exists team_tasks_parent on public.team_tasks (parent_id);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

create or replace function public.my_email() returns text
language sql stable set search_path = ''
as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

-- Keeps updated_at current, and keeps a task's parent inside the same person's tree.
-- security definer so the parent lookup sees every row, not only the ones this person may read.
create or replace function public.team_tasks_guard() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare parent_email text;
begin
  new.updated_at := now();
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'a task cannot be its own parent';
    end if;
    select assignee_email into parent_email from public.team_tasks where id = new.parent_id;
    -- A parent inserted in the same statement isn't visible yet; the foreign key still checks it exists.
    if parent_email is not null and parent_email <> new.assignee_email then
      raise exception 'a task can only be nested under a task of the same person';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists team_tasks_guard on public.team_tasks;
create trigger team_tasks_guard before insert or update on public.team_tasks
for each row execute function public.team_tasks_guard();

alter table public.team_tasks enable row level security;

-- Everyone sees only their own tasks; admins see all.
drop policy if exists "read own or admin" on public.team_tasks;
create policy "read own or admin" on public.team_tasks for select to authenticated
using (public.is_admin() or assignee_email = public.my_email());

-- People add tasks to their own tree only; admins publish to anyone.
drop policy if exists "add own or admin" on public.team_tasks;
create policy "add own or admin" on public.team_tasks for insert to authenticated
with check (
  public.is_admin()
  or (assignee_email = public.my_email() and source_id is null and created_by = auth.uid())
);

-- People change their own tasks (tick, rename, arrange) but can't hand them to someone else.
drop policy if exists "change own or admin" on public.team_tasks;
create policy "change own or admin" on public.team_tasks for update to authenticated
using (public.is_admin() or assignee_email = public.my_email())
with check (public.is_admin() or assignee_email = public.my_email());

-- People delete only tasks they added themselves; published tasks are removed by publishing.
drop policy if exists "delete own added or admin" on public.team_tasks;
create policy "delete own added or admin" on public.team_tasks for delete to authenticated
using (public.is_admin() or (assignee_email = public.my_email() and source_id is null and created_by = auth.uid()));

-- People can't rewrite which ProTracker task a row came from.
create or replace function public.team_tasks_lock_source() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if not public.is_admin() and new.source_id is distinct from old.source_id then
    raise exception 'source_id can only be changed by publishing';
  end if;
  return new;
end $$;

drop trigger if exists team_tasks_lock_source on public.team_tasks;
create trigger team_tasks_lock_source before update on public.team_tasks
for each row execute function public.team_tasks_lock_source();

-- Live updates in the app (rows are still filtered by the policies above).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_tasks'
  ) then
    alter publication supabase_realtime add table public.team_tasks;
  end if;
end $$;
