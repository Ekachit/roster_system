# AI Fitness Zone Roster

An internal rostering MVP for approximately ten staff. The application is
deployment-ready for a static Netlify Free site backed by Supabase Free. The
production Supabase target is owner-provisioned; migration, authentication,
deployment, and live smoke-test results must still be verified before the
application is described as live.

## MVP capabilities

- Approved email/password users with employee and supervisor roles
- Recurring and date-specific employee availability
- Seven-day supervisor roster, conflict evaluation, assignment, publication,
  removal, and replacement
- Employee schedule, acknowledgement, and release requests
- Append-only supervisor audit history
- Current scheduled-hours reporting and formula-safe UTF-8 CSV export
- Responsive employee and supervisor views using `Australia/Melbourne`

The browser interface is not the security boundary. Supabase Row Level Security,
restricted grants, database constraints, and authorization-checking RPCs enforce
all private reads and protected mutations.

## Technology

- React 19, Vite, TypeScript, and Tailwind CSS
- Supabase Auth and PostgreSQL with RLS
- Vitest, React Testing Library, pgTAP, and Playwright
- Static Netlify hosting; no Netlify Functions or paid add-ons

## Prerequisites

- Node.js 22
- Docker Desktop
- Supabase CLI
- PowerShell for the local concurrency and end-to-end runners

## Local setup

1. Install exact dependencies:

   ```powershell
   npm ci
   ```

2. Start the local stack:

   ```powershell
   supabase start
   ```

3. Copy `.env.example` to `.env.local` and use the local Project URL and
   publishable/legacy anon key printed by `supabase status`:

   ```text
   VITE_SUPABASE_URL=http://127.0.0.1:55321
   VITE_SUPABASE_ANON_KEY=<local publishable or anon key>
   ```

4. Rebuild the disposable local database and synthetic seed:

   ```powershell
   supabase db reset
   ```

5. Start Vite:

   ```powershell
   npm run dev
   ```

Public registration is disabled. To sign in locally, create a confirmed
synthetic Auth user whose normalized email matches a synthetic approved profile
in `supabase/seed.sql`. Never add real staff data to seed, test, screenshot, or
preview fixtures.

Local analytics is disabled in `supabase/config.toml` because it is unused by
the application and the Supabase log collector is unreliable on the current
Windows Docker configuration.

## Environment variables

| Variable | Browser-safe value |
|---|---|
| `VITE_SUPABASE_URL` | Supabase Project URL |
| `VITE_SUPABASE_ANON_KEY` | Supabase publishable key or legacy anon key |

Vite embeds every `VITE_*` value in public JavaScript. Never use a Supabase
secret key, service-role key, database password, access token, or private key.
Production builds fail when either required variable is absent, when the URL is
not HTTPS, or when an obvious secret/service-role key is supplied.

## Verification

```powershell
npm run lint
npm run typecheck
npm run test
supabase test db
npm run test:e2e
$env:VITE_SUPABASE_URL='https://example.supabase.co'
$env:VITE_SUPABASE_ANON_KEY='sb_publishable_build_verification'
npm run build
npm audit
npm audit --omit=dev
git diff --check
```

`npm run test:e2e` resets the disposable local database and runs the complete
MVP workflow with generated synthetic credentials. On the affected Windows
Docker setup, `supabase db reset` can return a gateway 502 after migrations and
seed have committed; the runner verifies the exact migration/fixture state
before continuing and then requires three consecutive healthy Auth responses.

## Production setup

Follow:

- [Netlify deployment](docs/NETLIFY_DEPLOYMENT.md)
- [Production checklist](docs/PRODUCTION_CHECKLIST.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Database design](docs/DATABASE_DESIGN.md)
- [Milestone 7 review](docs/reviews/MILESTONE_7_REVIEW.md)

Production account creation, migration push, staff provisioning, Netlify site
creation, environment configuration, and smoke testing are manual account-level
steps. Do not describe the application as deployed until the real
`.netlify.app` URL has passed the production checklist.

## Authentication and provisioning

Email/password is the MVP method. Public sign-up and invitation workflows are
disabled.

1. Bootstrap the first approved supervisor row through trusted SQL as described
   in `docs/NETLIFY_DEPLOYMENT.md`.
2. Create and confirm the matching Auth user in the Supabase Dashboard.
3. The supervisor adds subsequent approved staff profiles in the application.
4. A system owner creates each matching Auth account and privately supplies a
   temporary password.
5. The user changes it from Profile after first sign-in.

Authorization continuously requires a matching Auth UUID, normalized current
Auth email, active approved staff row, and protected database role. Linked email
changes require the documented administrator unlink-and-relink procedure.

## Known limitations

- Shifts and availability cannot cross midnight.
- Scheduled hours are current rostered hours, not actual attendance or payroll.
- Password reset is a manual owner task while custom production SMTP remains
  intentionally out of scope.
- The audit page returns the latest 200 matching events.
- The current Vite bundle reports a non-failing large-chunk warning.
- `npm audit` reports the upstream React Router RSC-action advisory. This Vite
  SPA has no React Server Components, server actions, SSR, loaders, or actions,
  so the affected execution path is absent; see the Milestone 7 review.

Calendar integration, email/SMS, payroll, timesheet import, clock-in,
geofencing, chat, automatic allocation, swapping, native applications, paid
monitoring, and paid analytics remain out of scope.
