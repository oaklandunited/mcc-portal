# Project Portal

A multi-tenant client-accessible project management portal. Built around the Mecoy Communications website redesign template, but templates are now data-driven — super admins can clone any project into a new template or build templates from scratch.

**Stack**

- Frontend: single-file static HTML/CSS/JS (no build step). Deploys to Vercel, Netlify, Cloudflare Pages, S3, or anywhere else that serves files.
- Backend: [Supabase](https://supabase.com) (Postgres + Auth + Row-Level Security).
- Auth: email + password, with one-click magic link option.

**Multi-tenancy model**

```
Super admins (you, your team)
  └── Workspaces (one per client, e.g. "Mecoy Communications")
        └── Projects (one per engagement, e.g. "Website Redesign")
              ├── Phases + exit criteria
              ├── Tasks
              ├── Collateral
              ├── Decisions
              ├── Approvals
              ├── Kickoff items
              ├── KPIs
              ├── Team roster
              └── Activity log

Templates (managed by super admins)
  └── Reusable blueprints — phases, tasks, collateral, etc.
      Used to pre-populate new projects.
```

**Roles**

- **Super admin** (cross-workspace): you and your team. See and edit everything, manage templates, promote other super admins.
- **Workspace roles** (per workspace member): `owner`, `pm`, `client_edit`, `client_view`. Edit/delete buttons hide automatically for view-only users.

---

## Setup — first time (15 minutes)

### 1. Create a Supabase project

- Go to [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**.
- Pick a region near your users. Save the database password.
- Wait ~2 minutes for provisioning.

### 2. Run the schema (3 files, in order)

In the Supabase dashboard:

- **SQL Editor** → **New query**
- Paste the contents of `supabase/01_schema.sql` → **Run**.
- New query → paste `supabase/03_admin_and_templates.sql` → **Run**.
- New query → paste `supabase/02_seed_function.sql` → **Run**.

(Order matters: 01 creates the base tables, 03 adds admin + templates, 02 defines the seed function that depends on the template tables.)

### 3. Make yourself the first super admin

In Supabase: **Authentication** → **Users** → find your user → copy the UUID.

Then in SQL Editor:

```sql
insert into app_admins (user_id, notes)
values ('YOUR-USER-UUID', 'Founding super admin');
```

After this, your account has cross-workspace visibility and can manage templates. You can promote other super admins from the **Admin → Super Admins** section in the portal UI.

### 4. Configure auth

- **Authentication** → **Providers** → make sure **Email** is enabled.
- **Authentication** → **URL Configuration** → set **Site URL** to your deployed URL (e.g. `https://portal.youragency.com`). Add both production and `http://localhost:8000` to **Redirect URLs**.
- (Optional) Disable email confirmation while testing: **Authentication** → **Sign In / Up** → toggle off "Confirm email".

### 5. Wire up the frontend

Locally:

```bash
cp config.example.js config.js
```

Edit `config.js` and paste your **Project URL** and **anon/publishable key** from Supabase → Project Settings → API Keys.

### 6. Run locally

```bash
cd portal
python3 -m http.server 8000
# then open http://localhost:8000
```

### 7. Sign up

- Open the portal → **Create account** → use the email you set as super admin.
- You'll skip the workspace-onboarding screen and land in the Admin dashboard since you're a super admin with no workspaces yet.
- Create your first workspace via **+ New workspace** in the sidebar.

---

## Deployment

### Vercel (recommended)

```bash
cd portal
npx vercel
```

The included `vercel.json` runs `bash build.sh` which generates `config.js` from environment variables at deploy time. Set these in Vercel → Project Settings → Environment Variables:

- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_ANON_KEY` — your Supabase anon/publishable key

After deploy, update Supabase Auth → URL Configuration → Site URL to your Vercel URL.

### Netlify

```bash
cd portal
npx netlify deploy --prod
```

The included `netlify.toml` does the same thing. Set the same env vars in Netlify → Site Settings → Environment Variables.

---

## Working with templates

### Creating a template by cloning an existing project (fastest)

1. Open a project whose structure you like.
2. Sidebar → **Settings**.
3. **Save as template** → name it (e.g. "Brand Identity Engagement"), key (e.g. `brand_identity`).
4. The template snapshots all phases, exit criteria, tasks, collateral, decisions, approvals, kickoff items, KPIs, and team roles.
5. Find it in **Admin → Templates**.

### Creating a template from scratch

1. Sidebar → **Admin → Templates** → **+ New template**.
2. Fill in name, key, description.
3. After creation, use **Admin → Templates → Edit** to set basic fields. For now, populating the template's phases/tasks/etc. requires editing the `template_*` tables in Supabase's table editor (a full visual editor is on the roadmap).

The fastest workflow: create one real project with the structure you want, then **Save as template** from its Settings.

### Using a template

When creating a new project, the **Template** dropdown lists all active templates. Pick one and the project is pre-populated. Pick "(no template — empty project)" to start blank.

---

## Inviting clients

1. Sign in as a workspace Owner or PM.
2. Sidebar → **Members**.
3. **+ Invite member** → email + role.
4. Tell the client to sign up at your portal URL with that exact email. They'll automatically appear in the workspace with the assigned role.

**Role guide**

| Role            | Sees workspace | Edits content | Manages members | Creates / deletes projects |
|-----------------|----------------|---------------|-----------------|----------------------------|
| Super admin     | ALL workspaces | ✔             | ✔               | ✔                          |
| Owner           | This workspace | ✔             | ✔               | ✔                          |
| PM              | This workspace | ✔             | ✔               | ✔                          |
| Client (edit)   | This workspace | ✔             | —               | —                          |
| Client (view)   | This workspace | —             | —               | —                          |

---

## File map

```
portal/
├── index.html                 # The whole frontend
├── config.example.js          # Copy to config.js, add Supabase keys
├── config.js                  # (gitignored) your Supabase URL + anon key
├── build.sh                   # Vercel/Netlify build script — generates config.js from env vars
├── vercel.json                # Vercel config
├── netlify.toml               # Netlify config
├── README.md                  # This file
├── .gitignore
└── supabase/
    ├── 01_schema.sql                 # Base tables, RLS policies, helper functions
    ├── 02_seed_function.sql          # Functions for creating workspaces + projects from templates
    └── 03_admin_and_templates.sql    # Super admins, project templates schema + seed data
```

---

## What's protected by what

- **Auth (Supabase)** decides whether you're signed in.
- **Row-Level Security (RLS)** decides what you can see and write. Every table's policies check workspace membership via the `is_workspace_member()`, `can_edit_workspace()`, `can_admin_workspace()`, and `is_super_admin()` helper functions.
- **Frontend role gates** hide UI elements you can't act on. They're a UX nicety — RLS is the actual enforcement boundary.

The anon key in `config.js` is fine to publish. A malicious user running their own queries can never see another workspace's data unless they're a member of it (or a super admin).

---

## Troubleshooting

**"new row violates row-level security policy for table workspaces" when creating a workspace.**
This was an early bug with direct INSERTs against `auth.uid()` policy contexts under the newer Supabase JWT signing system. The current `create_workspace` RPC bypasses it via SECURITY DEFINER. If you still see this error, make sure `02_seed_function.sql` has been applied — it defines the `create_workspace` function.

**Magic link redirects to localhost in production.**
Set the **Site URL** in Supabase → Authentication → URL Configuration to your real production URL.

**"Configuration needed" on first load.**
You haven't created `config.js` yet, or the Supabase URL still says `YOUR-PROJECT`. Edit `config.js` (locally) or set `SUPABASE_URL` and `SUPABASE_ANON_KEY` env vars (Vercel/Netlify).

**Invite never gets accepted.**
The invited user must sign up with the exact email address (case-insensitive). The first sign-in triggers `acceptPendingInvites()` and moves the row from `workspace_invites` into `workspace_members`.

**I can't see the Admin sidebar.**
You're not a super admin. Run the SQL from Step 3 above with your user UUID. Reload the page.

**The template I just created via "Save as template" doesn't appear in the new-project dropdown.**
The frontend caches the templates list at sign-in. Reload the page to refresh it. (The new project modal also reads from this cache.)
