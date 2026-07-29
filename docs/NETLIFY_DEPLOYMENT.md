# Netlify Free Deployment

## Deployment status

This repository is ready for a static Netlify deployment. No Netlify CLI,
authenticated Netlify account, hosted Supabase project, or production URL was
available during Milestone 7, so no real deployment was performed or tested.

The target is:

- Netlify Free with the generated `.netlify.app` domain;
- Supabase Free for Auth and PostgreSQL;
- no custom server, Netlify Function, paid add-on, paid analytics, or paid
  monitoring.

`netlify.toml` defines `npm run build`, publishes `dist`, rewrites SPA routes to
`index.html`, pins Node 22, applies security headers, prevents HTML caching, and
long-caches fingerprinted assets. Netlify's Vite guidance uses the same build
command and publish directory:
https://docs.netlify.com/build/frameworks/framework-setup-guides/vite/

## 1. Prepare the production Supabase project

1. Create a new Supabase Free project. Store its generated database password in
   a password manager; do not put it in this repository, shell history,
   Netlify, screenshots, or tickets.
2. Protect the Supabase account with MFA.
3. Install a current Supabase CLI, authenticate, and link this repository:

   ```powershell
   supabase login
   supabase link --project-ref <production-project-ref>
   supabase migration list
   supabase db push --dry-run
   supabase db push
   supabase migration list
   ```

4. Do not use `--include-seed` in production. `supabase/seed.sql` is fictional
   local test data.
5. Do not edit the hosted schema in Table Editor after adopting migrations.
   Create a forward-only migration, replay locally, test, then push it.

Supabase records applied versions in
`supabase_migrations.schema_migrations`; `db push --dry-run` is the required
preflight. CLI reference:
https://supabase.com/docs/reference/cli/supabase-projects#supabase-db-push

## 2. Configure production authentication

In Supabase Dashboard:

1. Authentication > Providers:
   - enable Email;
   - disable public user sign-ups;
   - require confirmed emails;
   - do not enable OAuth, magic links, anonymous sign-in, or phone sign-in.
2. Authentication > URL Configuration:
   - Site URL: `https://<site-name>.netlify.app`
   - Additional production redirects, if password recovery is enabled:
     `https://<site-name>.netlify.app` and
     `https://<site-name>.netlify.app/sign-in`
   - Local development only: `http://127.0.0.1:5173/**`
   - If functional Deploy Previews use a separate synthetic Supabase project:
     `https://**--<site-name>.netlify.app/**`
3. Use an exact production Site URL. Wildcards are only for local/preview URLs.
   Supabase documents Netlify preview patterns at
   https://supabase.com/docs/guides/auth/redirect-urls#netlify-preview-urls.
4. Leave custom SMTP absent unless the product owner later supplies an approved
   free operational option. With the current MVP, owners create accounts and
   reset forgotten passwords manually in Dashboard.

## 3. Bootstrap the first supervisor

Run once in the Supabase SQL Editor before creating the Auth user. Replace the
placeholders directly in the editor; do not save real values in Git:

```sql
insert into public.staff (email, full_name, role, is_active)
values (
  lower(trim('<supervisor-email>')),
  trim('<supervisor-name>'),
  'supervisor',
  true
);
```

Then:

1. Authentication > Users > Add user.
2. Use the exact same normalized email.
3. Mark the email confirmed and assign a generated temporary password.
4. Share the password through a private channel.
5. Sign in at the production site, verify Supervisor Dashboard, and change the
   password from Profile.
6. Add subsequent staff in the application, then create each matching Auth user
   separately in Dashboard.

Do not create users with browser Auth admin APIs and do not place the
service-role key in the client.

## 4. Verify RLS and grants before adding production data

Run the local suite first:

```powershell
supabase db reset
supabase test db
```

In production SQL Editor, inspect rather than mutate:

```sql
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;

select
  routine_name,
  security_type
from information_schema.routines
where specific_schema = 'public'
order by routine_name;
```

Every public base table must report RLS enabled. Confirm with synthetic
production-test accounts that:

- an employee cannot read another employee's availability or notes;
- an employee cannot execute supervisor projections/commands;
- direct shift/assignment/audit mutations fail;
- a supervisor can complete the intended workflows;
- audit UPDATE and DELETE fail with `Roster audit history is append-only`.

Delete the synthetic production-test business records through normal historical
workflows where available. Never use real employee information in a public
Deploy Preview.

## 5. Configure Netlify

1. Push the reviewed commit to the production Git repository.
2. In Netlify, choose **Add new project > Import an existing project** and
   connect the repository.
3. Select the production branch, normally `main`.
4. Keep the settings from `netlify.toml`:
   - build command: `npm run build`;
   - publish directory: `dist`;
   - functions directory: none.
5. Use the free generated `.netlify.app` site name.
6. Under Project configuration > Environment variables add:

   | Key | Production value |
   |---|---|
   | `VITE_SUPABASE_URL` | `https://<project-ref>.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | Supabase publishable or legacy anon key |

These values need the Builds context. They are browser-public identifiers, not
authorization secrets. Never add `SUPABASE_SERVICE_ROLE_KEY`, `sb_secret_*`,
the database password, a JWT secret, or an access token.

Netlify recommends managing environment values in its UI instead of committing
them:
https://docs.netlify.com/build/environment-variables/overview/

### Deploy Preview environments

Preferred: use a separate free Supabase preview project containing the same
migrations and synthetic data only, and assign its public URL/key to the Deploy
Previews context.

If a separate project is unavailable, use non-functional placeholder preview
values that satisfy the build validator and limit preview review to static
routing/layout. Never ask a real employee to enter production credentials into
unreviewed preview code. Do not give Deploy Previews any secret/service-role
value.

## 6. Deploy and validate

Trigger the first production deploy only after the production checklist is
complete. Record the deploy ID, commit SHA, and generated URL.

Required live checks:

1. Open `/sign-in` and a deep route such as `/employee/schedule` in a new tab;
   both must return the SPA without a Netlify 404.
2. Inspect response headers for CSP, HSTS, `nosniff`, frame denial,
   referrer policy, and permissions policy.
3. Complete all smoke tests in `docs/PRODUCTION_CHECKLIST.md` with synthetic
   accounts.
4. Inspect browser Network and built assets. Only the Supabase URL and
   publishable/anon key may be present; no secret/service-role key may appear.
5. Test desktop and mobile widths and download/inspect a real CSV.
6. Sign out, refresh, and verify protected pages return to sign-in.

Do not state that deployment succeeded until the real URL and deep links have
been tested.

## Backup and export on Supabase Free

Supabase recommends regular CLI exports for Free projects because downloadable
Dashboard backups are not available on that plan:
https://supabase.com/docs/guides/platform/backups

Create an encrypted, access-controlled backup directory outside the repository.
Set the connection string only for the current shell:

```powershell
$env:ROSTER_PRODUCTION_DB_URL = '<Supabase direct connection string>'
supabase db dump --db-url $env:ROSTER_PRODUCTION_DB_URL --role-only -f roles.sql
supabase db dump --db-url $env:ROSTER_PRODUCTION_DB_URL -f schema.sql
supabase db dump --db-url $env:ROSTER_PRODUCTION_DB_URL --data-only --use-copy -f data.sql
Remove-Item Env:ROSTER_PRODUCTION_DB_URL
```

Unix:

```bash
export ROSTER_PRODUCTION_DB_URL='<Supabase direct connection string>'
supabase db dump --db-url "$ROSTER_PRODUCTION_DB_URL" --role-only -f roles.sql
supabase db dump --db-url "$ROSTER_PRODUCTION_DB_URL" -f schema.sql
supabase db dump --db-url "$ROSTER_PRODUCTION_DB_URL" --data-only --use-copy -f data.sql
unset ROSTER_PRODUCTION_DB_URL
```

Store dumps encrypted and off-site with date, project ref, migration version,
and a checksum. Test restoration into a disposable project at least quarterly.
Auth and Storage are managed schemas and may need explicit export/restore steps;
verify Auth users and linkage during every restore rehearsal. Do not restore
over production without an approved outage and rollback plan.

## Rollback

Frontend rollback:

1. In Netlify Deploys, select the last known-good production deploy and publish
   it.
2. Re-run deep-link, sign-in, role, and CSV smoke tests.

Database rollback:

- Migrations are forward-only. Prefer a corrective migration.
- Before any risky production migration, take a logical export and record the
  current migration list.
- If restoration is unavoidable, stop roster changes, export the failed state
  for forensics, restore into a new/disposable project first, validate it, then
  coordinate the production cutover.
- A frontend rollback does not undo schema/data changes; verify compatibility
  before republishing an older bundle.

Secret incident:

1. Remove the exposed value from Netlify and Git history/access points.
2. Rotate it in Supabase.
3. Rebuild and redeploy.
4. Invalidate affected sessions where appropriate.
5. Review audit/provider logs and document the incident.
