-- =============================================================================
-- seed_project_from_template(project_id, template)
-- -----------------------------------------------------------------------------
-- Populates a freshly-created project with the default phases, exit criteria,
-- tasks, collateral, decisions, approvals, kickoff items, KPIs, and team
-- roles from the Mecoy Communications Website Strategy Proposal.
--
-- Pass template = 'mecoy_website' for now. Future templates can be added.
-- =============================================================================

create or replace function seed_project_from_template(p_project uuid, p_template text default 'mecoy_website')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid;
begin
  select workspace_id into ws from projects where id = p_project;
  if ws is null then raise exception 'Project % not found', p_project; end if;
  if not can_edit_workspace(ws) then raise exception 'Insufficient permissions'; end if;
  if p_template <> 'mecoy_website' then raise exception 'Unknown template: %', p_template; end if;

  -- Phases
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 1, 'Foundations',              'Environment setup, brand asset finalization, design tokens locked', '~1 week',           1) returning id into p1;
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 2, 'Discovery & Architecture', 'Wireframes, content inventory, IA validation',                      '~1.5 weeks',        2) returning id into p2;
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 3, 'Design',                   'High-fidelity designs for every template, motion specs, design system','~2.5 weeks',       3) returning id into p3;
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 4, 'Build',                    'Theme Builder templates, dynamic data wiring, forms, analytics hooks','~3 weeks',         4) returning id into p4;
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 5, 'Content & Integration',    'Real content loaded, integrations live, SEO baselined',              '~1.5 weeks',        5) returning id into p5;
  insert into phases (project_id, num, name, focus, duration, position) values (p_project, 6, 'Launch & Post-Launch',     'QA, go-live, 30/60/90-day review',                                   '~1 week + 30 days', 6) returning id into p6;

  -- Exit criteria
  insert into exit_criteria (phase_id, text, position) values
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
  insert into tasks (project_id, phase_id, title, priority, assignee, notes) values
    (p_project,p1,'Provision WordPress staging environment','High','Developer',null),
    (p_project,p1,'Install Elementor Pro + ACF Pro + Yoast SEO','High','Developer',null),
    (p_project,p1,'Set up Hello Elementor + custom child theme scaffold','High','Developer',null),
    (p_project,p1,'Confirm brand color palette & typography tokens','High','Designer','Deep Navy #1A2B3C, Slate #2F3E4E, Off-White #F7F5F1, Hairline #E5E2DC, Muted #6E7A85'),
    (p_project,p2,'Draft wireframe for Home','High','Designer','Hero, services preview, results preview, who we serve preview, single CTA'),
    (p_project,p2,'Draft wireframes for Who We Are / Who We Serve / What We Do','High','Designer',null),
    (p_project,p2,'Draft wireframes for Results + Case Study Detail','High','Designer',null),
    (p_project,p2,'Draft wireframe for Contact (6-field intake)','Medium','Designer',null),
    (p_project,p2,'Compile content inventory + gap list','High','Brand / Editorial Lead',null),
    (p_project,p3,'Hi-fi design: Home','High','Designer',null),
    (p_project,p3,'Hi-fi design: Service / What We Do','High','Designer','Image-led, scannable. Rename "Pitching & Coordinating Media Coverage" -> "Media Strategy & Coverage"'),
    (p_project,p3,'Hi-fi design: Case Study Detail template','High','Designer',null),
    (p_project,p3,'Define motion specs (slide-in reveals, flip cards)','Medium','Designer','No video, no carousel, no parallax, no splash'),
    (p_project,p4,'Build Elementor Theme Builder global templates','High','Developer',null),
    (p_project,p4,'Wire ACF for Case Studies (client moment, metric, narrative)','High','Developer',null),
    (p_project,p4,'Wire ACF for Team (two-paragraph bio structure)','Medium','Developer',null),
    (p_project,p4,'Build intake form + routing + acknowledgment from hello@mecoy.com','High','Developer',null),
    (p_project,p4,'Configure GA4 + GTM events per docs/ANALYTICS.md','Medium','Developer','Form submissions, scroll depth, CTA clicks, case-study >30s'),
    (p_project,p5,'Load case study content (real, not lorem)','High','Brand / Editorial Lead',null),
    (p_project,p5,'Load team bios (third-person, two paragraphs)','High','Brand / Editorial Lead',null),
    (p_project,p5,'Configure Yoast SEO for every page','Medium','Developer',null),
    (p_project,p5,'Configure WP Mail SMTP and test deliverability','High','Developer',null),
    (p_project,p6,'Cross-browser + mobile device QA','High','Developer',null),
    (p_project,p6,'Run Lighthouse audit and remediate','High','Developer','Targets: Perf >=85 / A11y >=95 / SEO >=95'),
    (p_project,p6,'DNS cutover + monitor','High','Developer',null),
    (p_project,p6,'30-day punchlist review','High','Project Owner',null);

  -- Collateral
  insert into collateral (project_id, category, name, status, notes) values
    (p_project,'Brand Assets','Logo files (vector, light + dark)','Requested','SVG preferred. AI / EPS acceptable.'),
    (p_project,'Brand Assets','Approved color palette confirmation','Provided','Per proposal: Deep Navy, Slate, Off-White, Hairline, Muted.'),
    (p_project,'Brand Assets','Typography license confirmation (Playfair Display + Inter)','Requested','Both available via Google Fonts.'),
    (p_project,'Imagery','Senior team headshots (editorial framing)','Requested','High-res, neutral background.'),
    (p_project,'Imagery','Office / environment photography','Requested','Composed, mid-tone, real (no stock).'),
    (p_project,'Imagery','Service-area photography (where available)','Requested','Reference Pivotal Strategies image-led services.'),
    (p_project,'Content','Case study #1 (real, with metrics)','Requested','Client moment -> what was at stake -> what was done -> what happened.'),
    (p_project,'Content','Case study #2 (real, with metrics)','Requested',null),
    (p_project,'Content','Case study #3 (real, with metrics)','Requested',null),
    (p_project,'Content','Team bios (two paragraphs each, third person)','Requested',null),
    (p_project,'Content','Service descriptions (plain language, <=60 words)','Requested','10 services per Section 5.'),
    (p_project,'Content','Representative client list + logos (with permission)','Requested',null),
    (p_project,'Content','Recent press placements (for "In the News")','Requested','Publication, headline, date.'),
    (p_project,'Content','Recognition / Awards list','Requested',null),
    (p_project,'Credentials','Hosting selection + admin access','Requested','Production WordPress hosting.'),
    (p_project,'Credentials','DNS access (registrar login or contact)','Requested',null),
    (p_project,'Credentials','Elementor Pro license key','Requested',null),
    (p_project,'Credentials','ACF Pro license key','Requested',null),
    (p_project,'Credentials','Google Analytics / GTM admin access','Requested',null),
    (p_project,'Credentials','Email account for hello@ form','Requested','For form acknowledgments.'),
    (p_project,'References','Final approved positioning statement','Provided','"Mecoy Communications helps you clearly, compellingly, and effectively communicate with the people who matter."'),
    (p_project,'References','Benchmark sites studied','Provided','Brunswick, FGS, Pivotal, Public Haus, Next PR, Hype, Zeno, J Public Relations.');

  -- Decisions
  insert into decisions (project_id, phase_id, title, owner, status, notes) values
    (p_project,p1,'Approve overall website strategy (Sections 4, 6, 7 of proposal)','Project Owner','Pending','Foundational. Required before kickoff.'),
    (p_project,p1,'Identify single Project Owner with phase sign-off authority','Mecoy Leadership','Pending','Speeds project 20-30%.'),
    (p_project,p1,'Confirm content readiness commitment (Phase 2 deadline)','Brand / Editorial Lead','Pending','Most common project delay is content.'),
    (p_project,p2,'Approve sitemap (5-item primary nav order)','Project Owner','Pending','Who We Are -> Who We Serve -> What We Do -> Results -> Contact.'),
    (p_project,p3,'Approve hi-fi designs (every template)','Project Owner','Pending','Visuals locked at this gate.'),
    (p_project,p5,'Pre-launch go / no-go','Project Owner','Pending','Final content + functionality review.');

  -- Approvals
  insert into approvals (project_id, phase_id, name, reviewer, status, notes) values
    (p_project,p2,'Phase 2 Exit — Wireframe Approval','Project Owner','Not Submitted','Architecture is locked at this gate.'),
    (p_project,p3,'Phase 3 Exit — Hi-Fi Design Approval','Project Owner','Not Submitted','Visuals locked at this gate.'),
    (p_project,p4,'Mid-Phase 4 — Build Progress Review','Project Owner','Not Submitted','Course-correct early.'),
    (p_project,p5,'Phase 5 Exit — Pre-Launch Content Review','Project Owner','Not Submitted','Final go / no-go.'),
    (p_project,p6,'30-day Post-Launch Performance Review','Project Owner','Not Submitted','Punchlist closure.'),
    (p_project,p6,'60-day Traffic & Inquiry Review','Project Owner','Not Submitted','First read on inquiry quality.'),
    (p_project,p6,'90-day Full Review','Project Owner','Not Submitted','What is working / not working / adjust.');

  -- Kickoff items
  insert into kickoff_items (project_id, text, position) values
    (p_project,'Proposal reviewed and approved',1),
    (p_project,'Project owner named',2),
    (p_project,'Designer engaged',3),
    (p_project,'Developer engaged',4),
    (p_project,'Content owner named (can be project owner)',5),
    (p_project,'Existing brand assets gathered (logos, photography, prior case studies)',6),
    (p_project,'Hosting environment selected',7),
    (p_project,'Plugin licenses available (Elementor Pro, ACF Pro)',8);

  -- KPIs
  insert into kpis (project_id, name, target, position) values
    (p_project,'Inquiry conversion rate (visitors -> form submissions)','>=1.5%',1),
    (p_project,'Engaged sessions (>30s + scroll past hero)','>=55%',2),
    (p_project,'Case study engagement (>30s on a single case study)','>=30%',3),
    (p_project,'Returning visitor share (90 days)','>=20%',4),
    (p_project,'Lighthouse — Performance','>=85',5),
    (p_project,'Lighthouse — Accessibility','>=95',6),
    (p_project,'Lighthouse — SEO','>=95',7),
    (p_project,'Core Web Vitals — LCP','<2.5s',8),
    (p_project,'Core Web Vitals — CLS','<0.1',9),
    (p_project,'Core Web Vitals — INP','<200ms',10);

  -- Team roster
  insert into team_members (project_id, role, org, notes, position) values
    (p_project,'Project Owner','Mecoy','Final approval at each phase exit. Decides on tradeoffs.',1),
    (p_project,'Brand / Editorial Lead','Mecoy','Reviews voice, copy, imagery decisions.',2),
    (p_project,'Designer','TBD','Visual design system, hi-fi templates, motion specs, asset prep, visual QA.',3),
    (p_project,'Developer','TBD','WordPress build, Elementor templates, ACF wiring, integrations, performance, security, deployment.',4),
    (p_project,'Project Coordinator','Optional','Schedules reviews, tracks decisions.',5);

  -- Activity
  insert into activity_log (project_id, user_id, text)
  values (p_project, auth.uid(), 'Project seeded from Mecoy website template');
end $$;

-- =============================================================================
-- Convenience: create_project_with_template
-- A single RPC the frontend can call to atomically create + seed a project.
-- =============================================================================
create or replace function create_project_with_template(
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
  if not can_admin_workspace(p_workspace) then
    raise exception 'You must be Owner or PM to create projects in this workspace.';
  end if;

  insert into projects (workspace_id, name, slug, client_name, created_by)
  values (p_workspace, p_name, p_slug, coalesce(p_client_name, p_name), auth.uid())
  returning id into pid;

  perform seed_project_from_template(pid, p_template);
  return pid;
end $$;

-- Make RPCs callable by authenticated users
grant execute on function seed_project_from_template(uuid, text)        to authenticated;
grant execute on function create_project_with_template(uuid, text, text, text, text) to authenticated;
