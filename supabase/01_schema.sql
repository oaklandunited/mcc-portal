-- =============================================================================
-- Mecoy Communications — Project Portal
-- Supabase / Postgres schema + Row-Level Security
-- =============================================================================
-- Multi-tenant model: Agency -> Workspaces -> Projects
-- Roles per workspace member: 'owner' | 'pm' | 'client_edit' | 'client_view'
-- Auth: Supabase Auth (auth.users)
-- =============================================================================

-- Extensions ------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- =============================================================================
-- Enums
-- =============================================================================
do $$ begin
  create type member_role as enum ('owner','pm','client_edit','client_view');
exception when duplicate_object then null; end $$;

do $$ begin
  create type phase_status as enum ('Not Started','In Progress','Blocked','Complete','On Hold');
exception when duplicate_object then null; end $$;

do $$ begin
  create type task_status as enum ('To Do','In Progress','Blocked','Done');
exception when duplicate_object then null; end $$;

do $$ begin
  create type task_priority as enum ('Low','Medium','High','Critical');
exception when duplicate_object then null; end $$;

do $$ begin
  create type collateral_status as enum ('Requested','In Progress','Provided','Approved','N/A');
exception when duplicate_object then null; end $$;

do $$ begin
  create type decision_status as enum ('Pending','Approved','Rejected','Deferred');
exception when duplicate_object then null; end $$;

do $$ begin
  create type approval_status as enum ('Not Submitted','Submitted','Approved','Changes Requested','Rejected');
exception when duplicate_object then null; end $$;

-- =============================================================================
-- Core tables
-- =============================================================================

-- Workspaces (one per client / one per agency-customer relationship) -----------
create table if not exists workspaces (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists workspaces_created_by_idx on workspaces(created_by);

-- Workspace members (which auth users belong to which workspaces, with role) --
create table if not exists workspace_members (
  workspace_id uuid not null references workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role member_role not null default 'client_view',
  invited_email text,
  added_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index if not exists workspace_members_user_idx on workspace_members(user_id);

-- Pending invites (invited by email, before signup) ---------------------------
create table if not exists workspace_invites (
  id uuid primary key default uuid_generate_v4(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  email text not null,
  role member_role not null default 'client_view',
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (workspace_id, email)
);

-- Projects (one workspace can have many projects) -----------------------------
create table if not exists projects (
  id uuid primary key default uuid_generate_v4(),
  workspace_id uuid not null references workspaces(id) on delete cascade,
  name text not null,
  slug text not null,
  client_name text,
  status_note text,
  kickoff_date date,
  target_launch date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, slug)
);
create index if not exists projects_workspace_idx on projects(workspace_id);

-- Phases ----------------------------------------------------------------------
create table if not exists phases (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  num int not null,
  name text not null,
  focus text,
  duration text,
  status phase_status not null default 'Not Started',
  position int not null default 0,
  created_at timestamptz not null default now(),
  unique (project_id, num)
);
create index if not exists phases_project_idx on phases(project_id);

-- Exit criteria (per phase) ---------------------------------------------------
create table if not exists exit_criteria (
  id uuid primary key default uuid_generate_v4(),
  phase_id uuid not null references phases(id) on delete cascade,
  text text not null,
  done boolean not null default false,
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists exit_criteria_phase_idx on exit_criteria(phase_id);

-- Tasks -----------------------------------------------------------------------
create table if not exists tasks (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  phase_id uuid references phases(id) on delete set null,
  title text not null,
  status task_status not null default 'To Do',
  priority task_priority not null default 'Medium',
  assignee text,
  due_date date,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tasks_project_idx on tasks(project_id);
create index if not exists tasks_phase_idx on tasks(phase_id);

-- Collateral ------------------------------------------------------------------
create table if not exists collateral (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  category text not null default 'Other',
  status collateral_status not null default 'Requested',
  file_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists collateral_project_idx on collateral(project_id);

-- Decisions -------------------------------------------------------------------
create table if not exists decisions (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  phase_id uuid references phases(id) on delete set null,
  title text not null,
  owner text,
  status decision_status not null default 'Pending',
  decided_on date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists decisions_project_idx on decisions(project_id);

-- Approvals -------------------------------------------------------------------
create table if not exists approvals (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  phase_id uuid references phases(id) on delete set null,
  name text not null,
  reviewer text,
  status approval_status not null default 'Not Submitted',
  reviewed_on date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists approvals_project_idx on approvals(project_id);

-- Kickoff items ---------------------------------------------------------------
create table if not exists kickoff_items (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  text text not null,
  done boolean not null default false,
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists kickoff_items_project_idx on kickoff_items(project_id);

-- KPIs ------------------------------------------------------------------------
create table if not exists kpis (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  target text,
  current_value text,
  notes text,
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists kpis_project_idx on kpis(project_id);

-- Project team roster ---------------------------------------------------------
create table if not exists team_members (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  role text not null,
  name text,
  org text,
  email text,
  notes text,
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists team_members_project_idx on team_members(project_id);

-- Activity log ----------------------------------------------------------------
create table if not exists activity_log (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  text text not null,
  created_at timestamptz not null default now()
);
create index if not exists activity_log_project_idx on activity_log(project_id, created_at desc);

-- =============================================================================
-- updated_at trigger
-- =============================================================================
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  for t in select unnest(array['projects','tasks','collateral','decisions','approvals','kpis']) loop
    execute format('drop trigger if exists trg_%s_updated on %s', t, t);
    execute format('create trigger trg_%s_updated before update on %s for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

-- =============================================================================
-- Helper: is the current user a member of the given workspace?
-- =============================================================================
create or replace function is_workspace_member(ws uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from workspace_members
    where workspace_id = ws and user_id = auth.uid()
  );
$$;

create or replace function workspace_role(ws uuid)
returns member_role
language sql
stable
security definer
set search_path = public
as $$
  select role from workspace_members
  where workspace_id = ws and user_id = auth.uid()
  limit 1;
$$;

create or replace function project_workspace(pid uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select workspace_id from projects where id = pid;
$$;

create or replace function can_edit_workspace(ws uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select workspace_role(ws) in ('owner','pm','client_edit');
$$;

create or replace function can_admin_workspace(ws uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select workspace_role(ws) in ('owner','pm');
$$;

-- =============================================================================
-- Trigger: when a workspace is created, the creator becomes its owner
-- =============================================================================
create or replace function workspaces_set_owner() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into workspace_members (workspace_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists trg_workspaces_owner on workspaces;
create trigger trg_workspaces_owner after insert on workspaces
for each row execute function workspaces_set_owner();

-- =============================================================================
-- Row-Level Security
-- =============================================================================
alter table workspaces        enable row level security;
alter table workspace_members enable row level security;
alter table workspace_invites enable row level security;
alter table projects          enable row level security;
alter table phases            enable row level security;
alter table exit_criteria     enable row level security;
alter table tasks             enable row level security;
alter table collateral        enable row level security;
alter table decisions         enable row level security;
alter table approvals         enable row level security;
alter table kickoff_items     enable row level security;
alter table kpis              enable row level security;
alter table team_members      enable row level security;
alter table activity_log      enable row level security;

-- Workspaces ------------------------------------------------------------------
drop policy if exists ws_select on workspaces;
create policy ws_select on workspaces for select
  using (is_workspace_member(id));

drop policy if exists ws_insert on workspaces;
create policy ws_insert on workspaces for insert
  with check (created_by = auth.uid());

drop policy if exists ws_update on workspaces;
create policy ws_update on workspaces for update
  using (workspace_role(id) = 'owner')
  with check (workspace_role(id) = 'owner');

drop policy if exists ws_delete on workspaces;
create policy ws_delete on workspaces for delete
  using (workspace_role(id) = 'owner');

-- Workspace members -----------------------------------------------------------
drop policy if exists wm_select on workspace_members;
create policy wm_select on workspace_members for select
  using (is_workspace_member(workspace_id));

drop policy if exists wm_insert on workspace_members;
create policy wm_insert on workspace_members for insert
  with check (
    -- The owner trigger inserts as definer, but we also allow Owner/PM to add members
    workspace_role(workspace_id) in ('owner','pm')
    or user_id = auth.uid() -- self-join via accepted invite (handled in app)
  );

drop policy if exists wm_update on workspace_members;
create policy wm_update on workspace_members for update
  using (workspace_role(workspace_id) in ('owner','pm'));

drop policy if exists wm_delete on workspace_members;
create policy wm_delete on workspace_members for delete
  using (
    workspace_role(workspace_id) = 'owner'
    or user_id = auth.uid() -- a user can remove themselves
  );

-- Workspace invites -----------------------------------------------------------
drop policy if exists wi_select on workspace_invites;
create policy wi_select on workspace_invites for select
  using (
    workspace_role(workspace_id) in ('owner','pm')
    or lower(email) = lower(coalesce((auth.jwt() ->> 'email'), ''))
  );

drop policy if exists wi_insert on workspace_invites;
create policy wi_insert on workspace_invites for insert
  with check (workspace_role(workspace_id) in ('owner','pm'));

drop policy if exists wi_delete on workspace_invites;
create policy wi_delete on workspace_invites for delete
  using (
    workspace_role(workspace_id) in ('owner','pm')
    or lower(email) = lower(coalesce((auth.jwt() ->> 'email'), ''))
  );

-- Projects --------------------------------------------------------------------
drop policy if exists p_select on projects;
create policy p_select on projects for select
  using (is_workspace_member(workspace_id));

drop policy if exists p_insert on projects;
create policy p_insert on projects for insert
  with check (can_admin_workspace(workspace_id));

drop policy if exists p_update on projects;
create policy p_update on projects for update
  using (can_edit_workspace(workspace_id));

drop policy if exists p_delete on projects;
create policy p_delete on projects for delete
  using (can_admin_workspace(workspace_id));

-- Generic per-project tables --------------------------------------------------
-- Same shape: SELECT for any workspace member, INSERT/UPDATE/DELETE for editors
do $$
declare tbl text;
begin
  for tbl in
    select unnest(array['phases','tasks','collateral','decisions','approvals','kickoff_items','kpis','team_members','activity_log'])
  loop
    execute format('drop policy if exists %1$s_select on %1$s', tbl);
    execute format('create policy %1$s_select on %1$s for select using (is_workspace_member(project_workspace(project_id)))', tbl);

    execute format('drop policy if exists %1$s_insert on %1$s', tbl);
    execute format('create policy %1$s_insert on %1$s for insert with check (can_edit_workspace(project_workspace(project_id)))', tbl);

    execute format('drop policy if exists %1$s_update on %1$s', tbl);
    execute format('create policy %1$s_update on %1$s for update using (can_edit_workspace(project_workspace(project_id)))', tbl);

    execute format('drop policy if exists %1$s_delete on %1$s', tbl);
    execute format('create policy %1$s_delete on %1$s for delete using (can_edit_workspace(project_workspace(project_id)))', tbl);
  end loop;
end $$;

-- exit_criteria is one level deeper (joined through phase) --------------------
drop policy if exists ec_select on exit_criteria;
create policy ec_select on exit_criteria for select using (
  exists (select 1 from phases p where p.id = phase_id and is_workspace_member(project_workspace(p.project_id)))
);
drop policy if exists ec_insert on exit_criteria;
create policy ec_insert on exit_criteria for insert with check (
  exists (select 1 from phases p where p.id = phase_id and can_edit_workspace(project_workspace(p.project_id)))
);
drop policy if exists ec_update on exit_criteria;
create policy ec_update on exit_criteria for update using (
  exists (select 1 from phases p where p.id = phase_id and can_edit_workspace(project_workspace(p.project_id)))
);
drop policy if exists ec_delete on exit_criteria;
create policy ec_delete on exit_criteria for delete using (
  exists (select 1 from phases p where p.id = phase_id and can_edit_workspace(project_workspace(p.project_id)))
);

-- =============================================================================
-- View: my_workspaces (convenience)
-- =============================================================================
create or replace view my_workspaces as
  select w.*, wm.role as my_role
  from workspaces w
  join workspace_members wm on wm.workspace_id = w.id
  where wm.user_id = auth.uid();

-- =============================================================================
-- End of schema
-- =============================================================================
