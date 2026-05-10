# Project Portal

A multi-tenant client-accessible project management portal. Built around the Mecoy Communications website redesign template, but the template is one row in a function — add more.

**Stack**

- Frontend: single-file static HTML/CSS/JS (no build step). Deploys to Vercel, Netlify, Cloudflare Pages, S3, or anywhere else that serves files.
- Backend: [Supabase](https://supabase.com) (Postgres + Auth + Row-Level Security).
- Auth: email + password, with one-click magic link option.

**Multi-tenancy model**

```
Agency (you)
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
```

**Roles** (per workspace member): `owner`, `pm`, `client_edit`, `client_view`. Edit/delete buttons hide automatically for view-only users.

---

## Setup — first time (10 minutes)

### 1. Create a Supabase project

- Go to [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**.
- Pick a region near your users. Save the database password.
- Wait ~2 minutes for provisioning.

### 2. Run the schema

In the Supabase dashboard:

- **SQL Editor** → **New query**
- Paste the contents of `supabase/01_schema.sql` → **Run**.
- New query → paste `supabase/02_seed_function.sql` → **Run**.

Both should finish with no errors.

### 3. Configure auth

- **Authentication** → **Providers** → make sure **Email** is enabled.
- (Optional) **Authentication** → **URL Configuration** → set **Site URL** to where you'll host the portal (e.g. `https://portal.youragency.com`). Magic-link emails will use this.
- (Optional) Disable email confirmation while testing: **Authentication** → **Sign In / Up** → toggle off "Confirm email".

### 4. Wire up the frontend

- Copy `config.example.js` to `config.js`.
- In Supabase: **Project Settings** → **API**. Copy the **Project URL** and **anon public** key into `config.js`. (The anon key is safe to publish — RLS policies are what protect data.)

### 5. Run locally

Any static-file server works:

```bash
cd portal
python3 -m http.server 8000
# then open http://localhost:8000
```

Or use `npx serve`, VS Code's Live Server, etc.

### 6. Sign up

- Open the portal → **Create account** → use any email + password.
- You'll be prompted to create your first workspace.
- Inside the workspace, click **+ New project** → pick the Mecoy template → done. The new project is fully populated with phases, tasks, collateral, decisions, etc.

---

## Deployment

### Vercel

```bash
cd portal
npx vercel
```

- When prompted, accept the defaults. The included `vercel.json` configures it as a static site.
- After deploy, set the **Site URL** in Supabase → Authentication → URL Configuration to your Vercel URL so magic links land on the right host.

### Netlify

```bash
cd portal
npx netlify deploy --prod
```

The included `netlify.toml` handles static hosting.

### Anywhere else

It's just three files (`index.html`, `config.js`, fonts via CDN). Drop them on any static host.

---

## Inviting clients

1. Sign in as the workspace Owner.
2. Sidebar → **Members**.
3. **+ Invite member** → email + role.
4. Tell the client to sign up at your portal URL with that exact email. They'll automatically appear in the workspace with the assigned role.

**Role guide**

| Role            | Sees workspace | Edits content | Manages members | Creates / deletes projects |
|-----------------|----------------|---------------|-----------------|----------------------------|
| Owner           | ✔              | ✔             | ✔               | ✔                          |
| PM              | ✔              | ✔             | ✔               | ✔                          |
| Client (edit)   | ✔              | ✔             | —               | —                          |
| Client (view)   | ✔              | —             | —               | —                          |

---

## Adding a new project template

Templates live as `if` branches inside `seed_project_from_template()` in `supabase/02_seed_function.sql`. To add one:

1. Add a new `elsif p_template = 'my_template' then` block.
2. Inside, use the same `insert into phases / exit_criteria / tasks / collateral / ...` pattern as the Mecoy block.
3. Add the template's display name to the `<select id="f-tpl">` in `index.html` (search for "Website redesign (Mecoy template)").

---

## File map

```
portal/
├── index.html             # The whole frontend
├── config.example.js      # Copy to config.js, add your Supabase keys
├── config.js              # (gitignored) your Supabase URL + anon key
├── README.md              # This file
├── vercel.json            # Vercel deploy config
├── netlify.toml           # Netlify deploy config
├── .gitignore
└── supabase/
    ├── 01_schema.sql      # Tables + RLS policies + helpers
    └── 02_seed_function.sql  # Postgres function: create + populate a project
```

---

## What's protected by what

- **Auth (Supabase)** decides whether you're signed in.
- **Row-Level Security (RLS)** decides what you can see and write. Every table's policies check workspace membership via the `is_workspace_member()`, `can_edit_workspace()`, and `can_admin_workspace()` helper functions.
- **Frontend role gates** hide UI elements you can't act on. They're a UX nicety — RLS is the actual enforcement boundary.

This means the anon key in `config.js` is fine to publish. A malicious client running their own queries can never see another workspace's data; the database refuses.

---

## Troubleshooting

**"Configuration needed" on first load.**
You haven't created `config.js` yet, or the Supabase URL still says `YOUR-PROJECT`. Edit `config.js`.

**Magic link redirects to localhost in production.**
Set the **Site URL** in Supabase → Authentication → URL Configuration to your real production URL.

**RLS errors when creating projects.**
You're not an Owner or PM in the workspace. Either you're acting as a client_view/client_edit user, or the workspace ownership trigger didn't fire — re-run `01_schema.sql`.

**Invite never gets accepted.**
The invited user must sign up with the exact email address (case-insensitive). The first sign-in triggers `acceptPendingInvites()` and moves the row from `workspace_invites` into `workspace_members`.
