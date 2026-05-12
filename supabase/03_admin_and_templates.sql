-- =============================================================================
-- Super admins + project templates
-- -----------------------------------------------------------------------------
-- Adds:
--   1. app_admins table + is_super_admin() helper
--   2. Cross-workspace visibility for super admins (RLS updates)
--   3. project_templates table family — data-driven templates
--   4. Seeds the existing Mecoy template into the new tables
--   5. clone_project_to_template() function
--
-- Idempotent: safe to re-run.
-- =============================================================================

-- =============================================================================
-- 1) Super admins
-- =============================================================================
create table if not exists app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  notes text
);

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from app_admins where user_id = auth.uid());
$$;

grant execute on function public.is_super_admin() to authenticated;

-- Super admins can see/manage the admin list itself
alter table app_admins enable row level security;
drop policy if exists aa_select on app_admins;
create policy aa_select on app_admins for select to authenticated
  using (is_super_admin() or user_id = auth.uid());
drop policy if exists aa_insert on app_admins;
create policy aa_insert on app_admins for insert to authenticated
  with check (is_super_admin());
drop policy if exists aa_delete on app_admins;
create policy aa_delete on app_admins for delete to authenticated
  using (is_super_admin() and user_id <> auth.uid());  -- can't delete self

grant select on app_admins to authenticated;
grant insert, delete on app_admins to authenticated;

-- =============================================================================
-- 2) Cross-workspace visibility for super admins
-- -----------------------------------------------------------------------------
-- Update every policy that gates by workspace membership to ALSO allow
-- super admins.
-- =============================================================================

-- workspaces
drop policy if exists ws_select on public.workspaces;
create policy ws_select on public.workspaces for select to authenticated
  using (is_workspace_member(id) or is_super_admin());
drop policy if exists ws_update on public.workspaces;
create policy ws_update on public.workspaces for update to authenticated
  using (workspace_role(id) = 'owner' or is_super_admin())
  with check (workspace_role(id) = 'owner' or is_super_admin());
drop policy if exists ws_delete on public.workspaces;
create policy ws_delete on public.workspaces for delete to authenticated
  using (workspace_role(id) = 'owner' or is_super_admin());

-- workspace_members
drop policy if exists wm_select on public.workspace_members;
create policy wm_select on public.workspace_members for select to authenticated
  using (is_workspace_member(workspace_id) or is_super_admin());
drop policy if exists wm_insert on public.workspace_members;
create policy wm_insert on public.workspace_members for insert to authenticated
  with check (
    workspace_role(workspace_id) in ('owner','pm')
    or user_id = auth.uid()
    or is_super_admin()
  );
drop policy if exists wm_update on public.workspace_members;
create policy wm_update on public.workspace_members for update to authenticated
  using (workspace_role(workspace_id) in ('owner','pm') or is_super_admin());
drop policy if exists wm_delete on public.workspace_members;
create policy wm_delete on public.workspace_members for delete to authenticated
  using (
    workspace_role(workspace_id) = 'owner'
    or user_id = auth.uid()
    or is_super_admin()
  );

-- workspace_invites
drop policy if exists wi_select on public.workspace_invites;
create policy wi_select on public.workspace_invites for select to authenticated
  using (
    workspace_role(workspace_id) in ('owner','pm')
    or lower(email) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or is_super_admin()
  );
drop policy if exists wi_insert on public.workspace_invites;
create policy wi_insert on public.workspace_invites for insert to authenticated
  with check (workspace_role(workspace_id) in ('owner','pm') or is_super_admin());
drop policy if exists wi_delete on public.workspace_invites;
create policy wi_delete on public.workspace_invites for delete to authenticated
  using (
    workspace_role(workspace_id) in ('owner','pm')
    or lower(email) = lower(coalesce((auth.jwt() ->> 'email'), ''))
    or is_super_admin()
  );

-- Generic per-project tables: phases, tasks, collateral, decisions, approvals,
-- kickoff_items, kpis, team_members, activity_log
do $$
declare tbl text;
begin
  for tbl in
    select unnest(array['phases','tasks','collateral','decisions','approvals','kickoff_items','kpis','team_members','activity_log'])
  loop
    execute format('drop policy if exists %1$s_select on public.%1$s', tbl);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (is_workspace_member(project_workspace(project_id)) or is_super_admin())', tbl);

    execute format('drop policy if exists %1$s_insert on public.%1$s', tbl);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated with check (can_edit_workspace(project_workspace(project_id)) or is_super_admin())', tbl);

    execute format('drop policy if exists %1$s_update on public.%1$s', tbl);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated using (can_edit_workspace(project_workspace(project_id)) or is_super_admin())', tbl);

    execute format('drop policy if exists %1$s_delete on public.%1$s', tbl);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated using (can_edit_workspace(project_workspace(project_id)) or is_super_admin())', tbl);
  end loop;
end $$;

-- exit_criteria
drop policy if exists ec_select on public.exit_criteria;
create policy ec_select on public.exit_criteria for select to authenticated using (
  exists (select 1 from phases p where p.id = phase_id and (is_workspace_member(project_workspace(p.project_id)) or is_super_admin()))
);
drop policy if exists ec_insert on public.exit_criteria;
create policy ec_insert on public.exit_criteria for insert to authenticated with check (
  exists (select 1 from phases p where p.id = phase_id and (can_edit_workspace(project_workspace(p.project_id)) or is_super_admin()))
);
drop policy if exists ec_update on public.exit_criteria;
create policy ec_update on public.exit_criteria for update to authenticated using (
  exists (select 1 from phases p where p.id = phase_id and (can_edit_workspace(project_workspace(p.project_id)) or is_super_admin()))
);
drop policy if exists ec_delete on public.exit_criteria;
create policy ec_delete on public.exit_criteria for delete to authenticated using (
  exists (select 1 from phases p where p.id = phase_id and (can_edit_workspace(project_workspace(p.project_id)) or is_super_admin()))
);

-- projects (update + delete already had can_admin check; add super admin)
drop policy if exists p_select on public.projects;
create policy p_select on public.projects for select to authenticated
  using (is_workspace_member(workspace_id) or is_super_admin());
drop policy if exists p_insert on public.projects;
create policy p_insert on public.projects for insert to authenticated
  with check (can_admin_workspace(workspace_id) or is_super_admin());
drop policy if exists p_update on public.projects;
create policy p_update on public.projects for update to authenticated
  using (can_edit_workspace(workspace_id) or is_super_admin());
drop policy if exists p_delete on public.projects;
create policy p_delete on public.projects for delete to authenticated
  using (can_admin_workspace(workspace_id) or is_super_admin());

-- =============================================================================
-- 3) Project templates — data-driven
-- =============================================================================
create table if not exists project_templates (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  name text not null,
  description text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists template_phases (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  num int not null,
  name text not null,
  focus text,
  duration text,
  position int not null default 0,
  unique (template_id, num)
);

create table if not exists template_exit_criteria (
  id uuid primary key default uuid_generate_v4(),
  template_phase_id uuid not null references template_phases(id) on delete cascade,
  text text not null,
  position int not null default 0
);

create table if not exists template_tasks (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  template_phase_id uuid references template_phases(id) on delete set null,
  title text not null,
  priority task_priority not null default 'Medium',
  assignee text,
  notes text,
  position int not null default 0
);

create table if not exists template_collateral (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  category text not null default 'Other',
  name text not null,
  status collateral_status not null default 'Requested',
  notes text,
  position int not null default 0
);

create table if not exists template_decisions (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  template_phase_id uuid references template_phases(id) on delete set null,
  title text not null,
  owner text,
  status decision_status not null default 'Pending',
  notes text,
  position int not null default 0
);

create table if not exists template_approvals (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  template_phase_id uuid references template_phases(id) on delete set null,
  name text not null,
  reviewer text,
  status approval_status not null default 'Not Submitted',
  notes text,
  position int not null default 0
);

create table if not exists template_kickoff_items (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  text text not null,
  position int not null default 0
);

create table if not exists template_kpis (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  name text not null,
  target text,
  notes text,
  position int not null default 0
);

create table if not exists template_team_roles (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references project_templates(id) on delete cascade,
  role text not null,
  org text,
  notes text,
  position int not null default 0
);

-- Indexes
create index if not exists tpl_phases_template_idx on template_phases(template_id);
create index if not exists tpl_ec_phase_idx on template_exit_criteria(template_phase_id);
create index if not exists tpl_tasks_template_idx on template_tasks(template_id);
create index if not exists tpl_collateral_template_idx on template_collateral(template_id);
create index if not exists tpl_decisions_template_idx on template_decisions(template_id);
create index if not exists tpl_approvals_template_idx on template_approvals(template_id);
create index if not exists tpl_kickoff_template_idx on template_kickoff_items(template_id);
create index if not exists tpl_kpis_template_idx on template_kpis(template_id);
create index if not exists tpl_team_template_idx on template_team_roles(template_id);

-- =============================================================================
-- 4) Template RLS
-- -----------------------------------------------------------------------------
-- All authenticated users can SELECT active templates (needed to pick one when
-- creating a project). Only super admins can write/edit/delete templates.
-- =============================================================================
alter table project_templates    enable row level security;
alter table template_phases      enable row level security;
alter table template_exit_criteria enable row level security;
alter table template_tasks       enable row level security;
alter table template_collateral  enable row level security;
alter table template_decisions   enable row level security;
alter table template_approvals   enable row level security;
alter table template_kickoff_items enable row level security;
alter table template_kpis        enable row level security;
alter table template_team_roles  enable row level security;

-- project_templates: readable by all authenticated, writable by super admins
drop policy if exists tpl_select on public.project_templates;
create policy tpl_select on public.project_templates for select to authenticated
  using (is_active or is_super_admin());
drop policy if exists tpl_insert on public.project_templates;
create policy tpl_insert on public.project_templates for insert to authenticated
  with check (is_super_admin());
drop policy if exists tpl_update on public.project_templates;
create policy tpl_update on public.project_templates for update to authenticated
  using (is_super_admin());
drop policy if exists tpl_delete on public.project_templates;
create policy tpl_delete on public.project_templates for delete to authenticated
  using (is_super_admin() and not is_system);

-- Child tables: readable when the parent template is readable; writable only by super admins
do $$
declare tbl text;
begin
  for tbl in
    select unnest(array['template_phases','template_tasks','template_collateral','template_decisions','template_approvals','template_kickoff_items','template_kpis','template_team_roles'])
  loop
    execute format('drop policy if exists %1$s_select on public.%1$s', tbl);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (exists (select 1 from project_templates t where t.id = template_id and (t.is_active or is_super_admin())))', tbl);

    execute format('drop policy if exists %1$s_insert on public.%1$s', tbl);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated with check (is_super_admin())', tbl);

    execute format('drop policy if exists %1$s_update on public.%1$s', tbl);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated using (is_super_admin())', tbl);

    execute format('drop policy if exists %1$s_delete on public.%1$s', tbl);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated using (is_super_admin())', tbl);
  end loop;
end $$;

-- template_exit_criteria: parent is template_phase, parent template is found via that
drop policy if exists tec_select on public.template_exit_criteria;
create policy tec_select on public.template_exit_criteria for select to authenticated
  using (exists (
    select 1 from template_phases tp
    join project_templates t on t.id = tp.template_id
    where tp.id = template_phase_id and (t.is_active or is_super_admin())
  ));
drop policy if exists tec_insert on public.template_exit_criteria;
create policy tec_insert on public.template_exit_criteria for insert to authenticated
  with check (is_super_admin());
drop policy if exists tec_update on public.template_exit_criteria;
create policy tec_update on public.template_exit_criteria for update to authenticated
  using (is_super_admin());
drop policy if exists tec_delete on public.template_exit_criteria;
create policy tec_delete on public.template_exit_criteria for delete to authenticated
  using (is_super_admin());

-- Table grants
grant select on project_templates, template_phases, template_exit_criteria,
                template_tasks, template_collateral, template_decisions,
                template_approvals, template_kickoff_items, template_kpis,
                template_team_roles to authenticated;
grant insert, update, delete on project_templates, template_phases, template_exit_criteria,
                                  template_tasks, template_collateral, template_decisions,
                                  template_approvals, template_kickoff_items, template_kpis,
                                  template_team_roles to authenticated;

-- =============================================================================
-- 5) Seed: migrate the Mecoy website template into the new tables
-- =============================================================================
do $$
declare
  tpl_id uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid;
begin
  -- Only seed if not already present
  if not exists (select 1 from project_templates where key = 'mecoy_website') then
    insert into project_templates (key, name, description, is_system, is_active)
    values (
      'mecoy_website',
      'Website Redesign (Mecoy template)',
      'Full website redesign engagement: 6 phases (Foundations → Launch), 26 default tasks, 22 collateral items, decisions, approvals, kickoff checklist, KPI targets.',
      true,
      true
    )
    returning id into tpl_id;

    -- Phases
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 1, 'Foundations',              'Environment setup, brand asset finalization, design tokens locked', '~1 week', 1) returning id into p1;
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 2, 'Discovery & Architecture', 'Wireframes, content inventory, IA validation', '~1.5 weeks', 2) returning id into p2;
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 3, 'Design',                   'High-fidelity designs for every template, motion specs, design system', '~2.5 weeks', 3) returning id into p3;
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 4, 'Build',                    'Theme Builder templates, dynamic data wiring, forms, analytics hooks', '~3 weeks', 4) returning id into p4;
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 5, 'Content & Integration',    'Real content loaded, integrations live, SEO baselined', '~1.5 weeks', 5) returning id into p5;
    insert into template_phases (template_id, num, name, focus, duration, position) values
      (tpl_id, 6, 'Launch & Post-Launch',     'QA, go-live, 30/60/90-day review', '~1 week + 30 days', 6) returning id into p6;

    -- Exit criteria
    insert into template_exit_criteria (template_phase_id, text, position) values
      (p1,'Hosting environment selected and provisioned',1),
      (p1,'WordPress + Elementor + ACF Pro installed on staging',2),
      (p1,'Brand assets (logo, palette, typography) consolidated',3),
      (p1,'Design tokens locked (color, type, spacing scale)',4),
      (p1,'Repository / version control initialized',5),
      (p2,'Sitemap approved (5-item primary nav)',1),
      (p2,'Wireframes for Home, Who We Are, Who We Serve, What We Do, Results, Case Study, Contact',2),
      (p2,'Content inventory complete — gaps identified',3),
      (p2,'Wireframe approval signed off by Project Owner',4),
      (p3,'Hi-fi designs approved for every template',1),
      (p3,'Motion specs documented (no video, no carousel, no parallax)',2),
      (p3,'Design system documented (Playfair Display + Inter, palette, spacing)',3),
      (p3,'Mobile breakpoints reviewed',4),
      (p3,'Hi-fi design approval signed off by Project Owner',5),
      (p4,'All Elementor Theme Builder templates built',1),
      (p4,'ACF custom fields wired (case studies, team)',2),
      (p4,'Intake form built with routing & acknowledgment email',3),
      (p4,'GA4 + GTM events configured',4),
      (p4,'Mid-phase build review complete',5),
      (p4,'Performance budgets validated (LCP < 2.5s)',6),
      (p5,'All real content loaded (case studies, team bios, services)',1),
      (p5,'SEO baselined (Yoast, sitemap, OG images)',2),
      (p5,'Mail SMTP configured & tested',3),
      (p5,'Security plugin configured (Wordfence / Solid Security)',4),
      (p5,'Caching configured (LiteSpeed / WP Rocket)',5),
      (p5,'Pre-launch content review signed off',6),
      (p6,'Cross-browser & device QA complete',1),
      (p6,'Lighthouse: Perf >=85, A11y >=95, SEO >=95',2),
      (p6,'DNS cutover complete',3),
      (p6,'Backup & restore verified',4),
      (p6,'30-day punchlist closed',5),
      (p6,'60-day traffic & inquiry review',6),
      (p6,'90-day full review & adjustments documented',7);

    -- Tasks
    insert into template_tasks (template_id, template_phase_id, title, priority, assignee, notes, position) values
      (tpl_id,p1,'Provision WordPress staging environment','High','Developer',null,1),
      (tpl_id,p1,'Install Elementor Pro + ACF Pro + Yoast SEO','High','Developer',null,2),
      (tpl_id,p1,'Set up Hello Elementor + custom child theme scaffold','High','Developer',null,3),
      (tpl_id,p1,'Confirm brand color palette & typography tokens','High','Designer','Deep Navy #1A2B3C, Slate #2F3E4E, Off-White #F7F5F1, Hairline #E5E2DC, Muted #6E7A85',4),
      (tpl_id,p2,'Draft wireframe for Home','High','Designer','Hero, services preview, results preview, who we serve preview, single CTA',5),
      (tpl_id,p2,'Draft wireframes for Who We Are / Who We Serve / What We Do','High','Designer',null,6),
      (tpl_id,p2,'Draft wireframes for Results + Case Study Detail','High','Designer',null,7),
      (tpl_id,p2,'Draft wireframe for Contact (6-field intake)','Medium','Designer',null,8),
      (tpl_id,p2,'Compile content inventory + gap list','High','Brand / Editorial Lead',null,9),
      (tpl_id,p3,'Hi-fi design: Home','High','Designer',null,10),
      (tpl_id,p3,'Hi-fi design: Service / What We Do','High','Designer','Image-led, scannable.',11),
      (tpl_id,p3,'Hi-fi design: Case Study Detail template','High','Designer',null,12),
      (tpl_id,p3,'Define motion specs (slide-in reveals, flip cards)','Medium','Designer','No video, no carousel, no parallax, no splash',13),
      (tpl_id,p4,'Build Elementor Theme Builder global templates','High','Developer',null,14),
      (tpl_id,p4,'Wire ACF for Case Studies (client moment, metric, narrative)','High','Developer',null,15),
      (tpl_id,p4,'Wire ACF for Team (two-paragraph bio structure)','Medium','Developer',null,16),
      (tpl_id,p4,'Build intake form + routing + acknowledgment email','High','Developer',null,17),
      (tpl_id,p4,'Configure GA4 + GTM events','Medium','Developer','Form submissions, scroll depth, CTA clicks',18),
      (tpl_id,p5,'Load case study content (real, not lorem)','High','Brand / Editorial Lead',null,19),
      (tpl_id,p5,'Load team bios (third-person, two paragraphs)','High','Brand / Editorial Lead',null,20),
      (tpl_id,p5,'Configure Yoast SEO for every page','Medium','Developer',null,21),
      (tpl_id,p5,'Configure WP Mail SMTP and test deliverability','High','Developer',null,22),
      (tpl_id,p6,'Cross-browser + mobile device QA','High','Developer',null,23),
      (tpl_id,p6,'Run Lighthouse audit and remediate','High','Developer','Targets: Perf >=85 / A11y >=95 / SEO >=95',24),
      (tpl_id,p6,'DNS cutover + monitor','High','Developer',null,25),
      (tpl_id,p6,'30-day punchlist review','High','Project Owner',null,26);

    -- Collateral
    insert into template_collateral (template_id, category, name, status, notes, position) values
      (tpl_id,'Brand Assets','Logo files (vector, light + dark)','Requested','SVG preferred. AI / EPS acceptable.',1),
      (tpl_id,'Brand Assets','Approved color palette confirmation','Provided',null,2),
      (tpl_id,'Brand Assets','Typography license confirmation','Requested',null,3),
      (tpl_id,'Imagery','Senior team headshots (editorial framing)','Requested','High-res, neutral background.',4),
      (tpl_id,'Imagery','Office / environment photography','Requested','Composed, mid-tone, real (no stock).',5),
      (tpl_id,'Imagery','Service-area photography (where available)','Requested',null,6),
      (tpl_id,'Content','Case study #1 (real, with metrics)','Requested','Client moment -> what was at stake -> what was done -> what happened.',7),
      (tpl_id,'Content','Case study #2 (real, with metrics)','Requested',null,8),
      (tpl_id,'Content','Case study #3 (real, with metrics)','Requested',null,9),
      (tpl_id,'Content','Team bios (two paragraphs each, third person)','Requested',null,10),
      (tpl_id,'Content','Service descriptions (plain language, <=60 words)','Requested',null,11),
      (tpl_id,'Content','Representative client list + logos (with permission)','Requested',null,12),
      (tpl_id,'Content','Recent press placements','Requested','Publication, headline, date.',13),
      (tpl_id,'Content','Recognition / Awards list','Requested',null,14),
      (tpl_id,'Credentials','Hosting selection + admin access','Requested','Production WordPress hosting.',15),
      (tpl_id,'Credentials','DNS access (registrar login or contact)','Requested',null,16),
      (tpl_id,'Credentials','Elementor Pro license key','Requested',null,17),
      (tpl_id,'Credentials','ACF Pro license key','Requested',null,18),
      (tpl_id,'Credentials','Google Analytics / GTM admin access','Requested',null,19),
      (tpl_id,'Credentials','Email account for hello@ form','Requested','For form acknowledgments.',20),
      (tpl_id,'References','Final approved positioning statement','Provided',null,21),
      (tpl_id,'References','Benchmark sites studied','Provided','Brunswick, FGS, Pivotal, Public Haus, Next PR, Hype, Zeno, J Public Relations.',22);

    -- Decisions
    insert into template_decisions (template_id, template_phase_id, title, owner, status, notes, position) values
      (tpl_id,p1,'Approve overall website strategy','Project Owner','Pending','Foundational. Required before kickoff.',1),
      (tpl_id,p1,'Identify single Project Owner with phase sign-off authority','Client Leadership','Pending','Speeds project 20-30%.',2),
      (tpl_id,p1,'Confirm content readiness commitment','Brand / Editorial Lead','Pending','Most common project delay is content.',3),
      (tpl_id,p2,'Approve sitemap','Project Owner','Pending',null,4),
      (tpl_id,p3,'Approve hi-fi designs','Project Owner','Pending','Visuals locked at this gate.',5),
      (tpl_id,p5,'Pre-launch go / no-go','Project Owner','Pending','Final content + functionality review.',6);

    -- Approvals
    insert into template_approvals (template_id, template_phase_id, name, reviewer, status, notes, position) values
      (tpl_id,p2,'Phase 2 Exit — Wireframe Approval','Project Owner','Not Submitted','Architecture is locked at this gate.',1),
      (tpl_id,p3,'Phase 3 Exit — Hi-Fi Design Approval','Project Owner','Not Submitted','Visuals locked at this gate.',2),
      (tpl_id,p4,'Mid-Phase 4 — Build Progress Review','Project Owner','Not Submitted','Course-correct early.',3),
      (tpl_id,p5,'Phase 5 Exit — Pre-Launch Content Review','Project Owner','Not Submitted','Final go / no-go.',4),
      (tpl_id,p6,'30-day Post-Launch Performance Review','Project Owner','Not Submitted','Punchlist closure.',5),
      (tpl_id,p6,'60-day Traffic & Inquiry Review','Project Owner','Not Submitted','First read on inquiry quality.',6),
      (tpl_id,p6,'90-day Full Review','Project Owner','Not Submitted','What is working / not working / adjust.',7);

    -- Kickoff items
    insert into template_kickoff_items (template_id, text, position) values
      (tpl_id,'Proposal reviewed and approved',1),
      (tpl_id,'Project owner named',2),
      (tpl_id,'Designer engaged',3),
      (tpl_id,'Developer engaged',4),
      (tpl_id,'Content owner named (can be project owner)',5),
      (tpl_id,'Existing brand assets gathered (logos, photography, prior case studies)',6),
      (tpl_id,'Hosting environment selected',7),
      (tpl_id,'Plugin licenses available (Elementor Pro, ACF Pro)',8);

    -- KPIs
    insert into template_kpis (template_id, name, target, notes, position) values
      (tpl_id,'Inquiry conversion rate (visitors -> form submissions)','>=1.5%','Primary funnel KPI.',1),
      (tpl_id,'Engaged sessions (>30s + scroll past hero)','>=55%',null,2),
      (tpl_id,'Case study engagement (>30s on a single case study)','>=30%',null,3),
      (tpl_id,'Returning visitor share (90 days)','>=20%',null,4),
      (tpl_id,'Lighthouse — Performance','>=85',null,5),
      (tpl_id,'Lighthouse — Accessibility','>=95',null,6),
      (tpl_id,'Lighthouse — SEO','>=95',null,7),
      (tpl_id,'Core Web Vitals — LCP','<2.5s',null,8),
      (tpl_id,'Core Web Vitals — CLS','<0.1',null,9),
      (tpl_id,'Core Web Vitals — INP','<200ms',null,10);

    -- Team roles
    insert into template_team_roles (template_id, role, org, notes, position) values
      (tpl_id,'Project Owner','Client','Final approval at each phase exit. Decides on tradeoffs.',1),
      (tpl_id,'Brand / Editorial Lead','Client','Reviews voice, copy, imagery decisions.',2),
      (tpl_id,'Designer','TBD','Visual design system, hi-fi templates, motion specs, asset prep, visual QA.',3),
      (tpl_id,'Developer','TBD','WordPress build, Elementor templates, ACF wiring, integrations, performance, security, deployment.',4),
      (tpl_id,'Project Coordinator','Optional','Schedules reviews, tracks decisions.',5);
  end if;
end $$;

-- =============================================================================
-- 6) Clone an existing project's current state into a new template
-- =============================================================================
create or replace function public.clone_project_to_template(
  p_project uuid,
  p_template_key text,
  p_template_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  tpl_id uuid;
  phase_rec record;
  new_phase_id uuid;
begin
  if not is_super_admin() then
    raise exception 'Only super admins can create templates';
  end if;

  insert into project_templates (key, name, description, created_by, is_system, is_active)
  values (p_template_key, p_template_name, p_description, auth.uid(), false, true)
  returning id into tpl_id;

  -- Phases (and remember mapping to copy children)
  for phase_rec in select * from phases where project_id = p_project order by position loop
    insert into template_phases (template_id, num, name, focus, duration, position)
    values (tpl_id, phase_rec.num, phase_rec.name, phase_rec.focus, phase_rec.duration, phase_rec.position)
    returning id into new_phase_id;

    insert into template_exit_criteria (template_phase_id, text, position)
    select new_phase_id, text, position
    from exit_criteria where phase_id = phase_rec.id order by position;

    insert into template_tasks (template_id, template_phase_id, title, priority, assignee, notes, position)
    select tpl_id, new_phase_id, title, priority, assignee, notes, row_number() over (order by created_at)
    from tasks where phase_id = phase_rec.id;

    insert into template_decisions (template_id, template_phase_id, title, owner, status, notes, position)
    select tpl_id, new_phase_id, title, owner, status, notes, row_number() over (order by created_at)
    from decisions where phase_id = phase_rec.id;

    insert into template_approvals (template_id, template_phase_id, name, reviewer, status, notes, position)
    select tpl_id, new_phase_id, name, reviewer, status, notes, row_number() over (order by created_at)
    from approvals where phase_id = phase_rec.id;
  end loop;

  -- Project-scoped items (no phase relation)
  insert into template_collateral (template_id, category, name, status, notes, position)
  select tpl_id, category, name, status, notes, row_number() over (order by created_at)
  from collateral where project_id = p_project;

  insert into template_kickoff_items (template_id, text, position)
  select tpl_id, text, position from kickoff_items where project_id = p_project order by position;

  insert into template_kpis (template_id, name, target, notes, position)
  select tpl_id, name, target, notes, position from kpis where project_id = p_project order by position;

  insert into template_team_roles (template_id, role, org, notes, position)
  select tpl_id, role, org, notes, position from team_members where project_id = p_project order by position;

  return tpl_id;
end $$;

grant execute on function public.clone_project_to_template(uuid, text, text, text) to authenticated;

-- =============================================================================
-- 7) updated_at trigger on project_templates
-- =============================================================================
drop trigger if exists trg_project_templates_updated on project_templates;
create trigger trg_project_templates_updated before update on project_templates
for each row execute function set_updated_at();

-- =============================================================================
-- 8) Force PostgREST to pick up the new tables and policies
-- =============================================================================
notify pgrst, 'reload schema';
