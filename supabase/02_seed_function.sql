-- =============================================================================
-- seed_project_from_template + create_project_with_template
-- -----------------------------------------------------------------------------
-- Table-driven version: reads from the project_templates / template_phases /
-- template_tasks / etc tables created in 03_admin_and_templates.sql.
--
-- This file is idempotent — running it more than once just replaces the
-- function definitions.
-- =============================================================================

drop function if exists public.seed_project_from_template(uuid, text);
create or replace function public.seed_project_from_template(
  p_project uuid,
  p_template_key text default 'mecoy_website'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
  tpl_id uuid;
  phase_rec record;
  new_phase_id uuid;
begin
  -- Resolve project workspace + permission check
  select workspace_id into ws from projects where id = p_project;
  if ws is null then raise exception 'Project % not found', p_project; end if;
  if not (can_edit_workspace(ws) or is_super_admin()) then
    raise exception 'Insufficient permissions';
  end if;

  -- Resolve template (skip if no template specified)
  if p_template_key is null then return; end if;

  select id into tpl_id from project_templates
    where key = p_template_key and (is_active or is_super_admin())
    limit 1;
  if tpl_id is null then
    raise exception 'Unknown or inactive template: %', p_template_key;
  end if;

  -- Phases (and remember mapping so child rows can attach to the new phase IDs)
  for phase_rec in
    select * from template_phases where template_id = tpl_id order by position
  loop
    insert into phases (project_id, num, name, focus, duration, position)
    values (p_project, phase_rec.num, phase_rec.name, phase_rec.focus, phase_rec.duration, phase_rec.position)
    returning id into new_phase_id;

    -- Exit criteria for this phase
    insert into exit_criteria (phase_id, text, position)
    select new_phase_id, text, position
    from template_exit_criteria where template_phase_id = phase_rec.id
    order by position;

    -- Tasks attached to this phase
    insert into tasks (project_id, phase_id, title, priority, assignee, notes)
    select p_project, new_phase_id, title, priority, assignee, notes
    from template_tasks where template_phase_id = phase_rec.id
    order by position;

    -- Decisions attached to this phase
    insert into decisions (project_id, phase_id, title, owner, status, notes)
    select p_project, new_phase_id, title, owner, status, notes
    from template_decisions where template_phase_id = phase_rec.id
    order by position;

    -- Approvals attached to this phase
    insert into approvals (project_id, phase_id, name, reviewer, status, notes)
    select p_project, new_phase_id, name, reviewer, status, notes
    from template_approvals where template_phase_id = phase_rec.id
    order by position;
  end loop;

  -- Project-scoped items
  insert into collateral (project_id, category, name, status, notes)
  select p_project, category, name, status, notes
  from template_collateral where template_id = tpl_id
  order by position;

  insert into kickoff_items (project_id, text, position)
  select p_project, text, position
  from template_kickoff_items where template_id = tpl_id
  order by position;

  insert into kpis (project_id, name, target, notes, position)
  select p_project, name, target, notes, position
  from template_kpis where template_id = tpl_id
  order by position;

  insert into team_members (project_id, role, org, notes, position)
  select p_project, role, org, notes, position
  from template_team_roles where template_id = tpl_id
  order by position;

  -- Activity log
  insert into activity_log (project_id, user_id, text)
  values (
    p_project,
    auth.uid(),
    'Project seeded from template: ' || p_template_key
  );
end $$;

grant execute on function public.seed_project_from_template(uuid, text) to authenticated;

-- =============================================================================
-- create_project_with_template
-- One-shot RPC the frontend can call to atomically create + seed a project.
-- =============================================================================
drop function if exists public.create_project_with_template(uuid, text, text, text, text);
create or replace function public.create_project_with_template(
  p_workspace uuid,
  p_name text,
  p_slug text,
  p_client_name text default null,
  p_template text default 'mecoy_website'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
begin
  if not (can_admin_workspace(p_workspace) or is_super_admin()) then
    raise exception 'You must be Owner or PM to create projects in this workspace.';
  end if;

  insert into projects (workspace_id, name, slug, client_name, created_by)
  values (p_workspace, p_name, p_slug, coalesce(p_client_name, p_name), auth.uid())
  returning id into pid;

  if p_template is not null and p_template <> '' then
    perform seed_project_from_template(pid, p_template);
  end if;
  return pid;
end $$;

grant execute on function public.create_project_with_template(uuid, text, text, text, text) to authenticated;

-- =============================================================================
-- create_workspace
-- SECURITY DEFINER bypass for workspace creation (used by frontend)
-- =============================================================================
drop function if exists public.create_workspace(text);
create or replace function public.create_workspace(p_name text)
returns public.workspaces
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  new_ws public.workspaces;
  new_slug text;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  new_slug := lower(regexp_replace(coalesce(p_name,''), '[^a-zA-Z0-9]+', '-', 'g'))
              || '-' || substring(md5(random()::text), 1, 6);
  insert into public.workspaces (name, slug, created_by)
  values (p_name, new_slug, uid)
  returning * into new_ws;
  return new_ws;
end $$;

grant execute on function public.create_workspace(text) to authenticated;

notify pgrst, 'reload schema';
