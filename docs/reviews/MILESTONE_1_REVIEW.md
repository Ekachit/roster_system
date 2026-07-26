# Milestone 1 Review

## Scope completed

Milestone 1 foundation is implemented: React/Vite/strict TypeScript, Tailwind,
React Router, shared accessible states, Supabase configuration, approved-user
email/password authentication, active/inactive access handling, employee and
supervisor role boundaries, staff/configuration management, eligibility, local
fictional seed data, tests, and setup documentation.

No availability, shifts, schedules, release requests, reports, calendar/email
integration, or production deployment was added.

## Architecture decisions

- Supabase Auth sessions are restored and refreshed in one React provider.
- Email/password is the provisional method; there is no public sign-up UI and
  Supabase local configuration disables sign-up.
- Verified Auth users link only to a pre-approved normalized email.
- PostgreSQL RLS and scoped security-definer functions are the authority.
- Supervisor notes use `staff_private_notes`, separate from employee-readable
  profile data.
- Profiles and reference records are deactivated rather than deleted.
- The first real supervisor is a manual bootstrap; no real identity is stored.
- Roster-facing time is documented as `Australia/Melbourne`.

## Tables and migration

Migration `202607260001_milestone_1_foundation.sql` creates:

- `staff`
- `staff_private_notes`
- `locations`
- `activity_types`
- `staff_locations`
- `staff_activity_types`
- enum `staff_role`
- updated-at, Auth-linking, staff-invariant triggers
- access/profile/staff/eligibility functions
- `supervisor_staff_directory`

`supabase/seed.sql` adds fictional staff plus initial locations and activities.

## RLS policies reviewed

- `anon` has no public-table privileges.
- Staff reads: active employees see only their own safe row; active supervisors
  see all.
- Private notes: supervisors only.
- Locations/activity types: active users read active rows; supervisors read and
  manage all rows.
- Eligibility: employees read only their own; supervisors manage all.
- Inactive and unapproved accounts have no `current_staff_id`.
- Direct staff mutation is not granted. Staff saves, activation changes, and
  eligibility replacement use functions that re-check supervisor status.
- Auth linkage cannot be changed through ordinary staff operations.
- The last active supervisor cannot be demoted or deactivated.

The pgTAP suite proves anonymous denial, own-row isolation, role-elevation
denial, supervisor-note isolation, inactive/unapproved denial, and supervisor
visibility.

## Pages implemented

- `/sign-in`
- role-aware `/`
- `/profile`
- `/employee`
- `/supervisor`
- `/supervisor/staff`
- `/supervisor/locations`
- `/supervisor/activity-types`
- `/unauthorised`

Loading, error, empty, inactive, unapproved, and unauthorised states are present.

## Tests added

- Five access-decision unit tests for unauthenticated, unapproved, inactive,
  wrong-role, and correct-role cases.
- Two component tests for accessible shared states.
- Ten pgTAP integration assertions against the migrated local database and RLS.

## Commands run and exact results

- `npm install` — exit 0; 343 packages initially installed.
- `npm run lint` — exit 0; no errors (the initial run had one Fast Refresh
  warning, subsequently fixed).
- `npm run typecheck` — exit 0.
- `npm run test` — exit 0; 2 files passed, 7 tests passed.
- `npm run build` — exit 0; 94 modules transformed; production build completed.
- `supabase start --exclude studio,imgproxy,storage-api,realtime,edge-runtime,logflare,vector`
  — exit 0; migration and seed applied; local API `127.0.0.1:55321`.
- `supabase db reset` — exit 0; database recreated, migration and seed applied.
- `supabase test db` — final exit 0; 1 SQL file, 10 tests, all successful.
- `npm audit --omit=dev` — exit 1; reports two high advisories in React Router.
  They concern server/RSC behavior not used by this client-only SPA. No
  non-vulnerable range satisfies all currently reported, conflicting
  advisories; latest compatible React Router is retained.

## Environment variables

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY` (publishable/anon browser key only)

No service-role key is required or permitted in frontend code.

## Manual setup

Follow `README.md`: start or link Supabase, apply migrations, configure the two
variables, bootstrap one approved supervisor row without committing personal
data, create a confirmed matching Auth user, and keep public sign-up disabled.

## Known limitations

- Email/password and the bootstrap workflow remain assumptions pending owner
  confirmation.
- Auth-user creation is intentionally a Dashboard/admin operation, not a
  browser workflow.
- There is no password-reset UI yet; administrators use Supabase Auth tooling.
- There is no generated Supabase TypeScript schema; query result interfaces are
  maintained locally for this small foundation.
- The current dependency audit reports server/RSC React Router advisories; this
  static SPA uses neither server actions nor RSC.
- Two renamed, empty legacy placeholder directories
  (`package.json.placeholder`, `README.md.placeholder`) may remain locally
  because OneDrive denied their direct removal. They are empty and untracked.

## Acceptance criteria satisfied

- Approved active employee and supervisor profiles can link to Supabase Auth.
- No self-registration workflow is exposed.
- Session restore, sign-in, sign-out, and role-aware routing are implemented.
- Employees cannot use supervisor pages or database operations.
- Employees cannot change roles or read supervisor notes.
- Inactive/unapproved/anonymous users cannot access application data.
- Supervisors can manage staff status, role, notes, eligibility, locations, and
  activity types.
- RLS was applied locally and its security matrix passed 10 integration tests.
- Lint, typecheck, unit/component tests, database tests, and build pass.

## Items intentionally deferred

All Milestone 2+ work: availability, shifts/assignments, weekly roster, employee
schedule, acknowledgements, release requests, audit history, scheduled-hours
reporting, CSV, notifications, calendar integration, workbook import, and
Netlify production deployment.

## Independent review conclusion

No Milestone 1 implementation blocker remains. Hosted-project configuration and
creation of real approved users are manual operational steps by design. The
dependency advisory is recorded and does not expose the client-only runtime
path, but should be rechecked during routine dependency updates.
