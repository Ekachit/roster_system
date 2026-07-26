# Milestone 1 Review

## Review status

Milestone 1 security closure completed on 27 July 2026. The two findings that
previously blocked approval—post-link approved-email enforcement and
concurrent final-supervisor protection—are closed by authoritative database
controls and direct verification.

This review covers Milestone 1 only. No availability, shifts, assignments,
schedules, release requests, reports, calendar integration, notifications, or
other Milestone 2+ work was implemented.

## Root causes

### Approved-email authorization

Initial authorization linked a confirmed Auth user to an approved staff row by
normalized email, but subsequent access checks used only `auth_user_id` and
active status. A later Auth email change therefore left the UUID link
authorized. The normal supervisor save command also allowed a linked staff
email to change without a controlled relink.

### Final active supervisor

The staff trigger checked for another active supervisor without serializing
role/deactivation commands. Concurrent transactions could each observe the
other supervisor and remove both. It also counted unlinked supervisor rows that
could not actually authenticate.

### Staff configuration integrity

The frontend saved profile/notes and eligibility using two independent RPCs.
The first transaction could commit even if eligibility replacement failed.
Eligibility query errors were also converted into empty checkbox selections,
creating an overwrite risk.

## Fixes implemented

### Continuous approved-email authorization

- `current_staff_id()` now requires all of:
  - `staff.auth_user_id = auth.uid()`;
  - normalized `auth.users.email = staff.email`;
  - `staff.is_active`.
- `is_supervisor()` inherits the same identity through `current_staff_id()`.
- `current_access_profile()` remains a deliberately limited status response
  and returns `email_matches`; it does not grant operational-table access.
- React route access denies an email-mismatched linked user and explains the
  administrator-controlled recovery process.
- A linked staff email is rejected by the ordinary staff configuration command.
- The supervisor UI disables the email field for linked profiles.
- README documents the deliberate unlink, update, confirm, and relink process.

### Serialized supervisor changes

- `save_staff_configuration()` and `set_staff_active()` acquire a
  `SHARE ROW EXCLUSIVE` lock on `staff` before authorization and mutation.
- Waiting transactions re-evaluate supervisor identity after obtaining the
  lock.
- The invariant counts only active, Auth-linked, normalized-email-matched
  supervisors.
- The row trigger retains sequential defense.
- A reusable PowerShell verifier runs genuine concurrent PostgreSQL sessions:
  one change commits, the competing final-supervisor change is rejected, and
  one authorized supervisor remains.

### Atomic staff configuration

`save_staff_configuration()` now saves, in one PostgreSQL transaction:

- staff profile and role;
- supervisor-only note;
- location eligibility;
- activity eligibility.

A failed FK, role invariant, linked-email check, or other step rolls back the
entire command. The frontend calls only this atomic RPC.

### Eligibility load safety

- Staff directory, location, and activity loading errors are surfaced.
- Both eligibility query errors are checked.
- Existing selections are not replaced after failure.
- Saving is disabled while eligibility loads or after a load failure.
- A clear retry action reloads the selected staff member's eligibility.

### Permission hardening

All public base tables have RLS. Trigger-only functions explicitly revoke
`EXECUTE` from `PUBLIC`, `anon`, and `authenticated`:

- `set_updated_at`
- `link_approved_auth_user`
- `protect_staff_invariants`

Client-executable security-definer functions use a fixed empty `search_path`
and derive identity from `auth.uid()`. No service-role key or Auth admin API is
used in browser code.

### Authentication operations

Email/password remains the MVP method. Public registration and email
invitations are disabled. The system owner:

1. creates the approved staff profile;
2. creates the matching Auth user in Supabase Dashboard;
3. privately supplies a temporary password.

The employee changes it from the authenticated Profile page. With production
SMTP intentionally absent, forgotten passwords are reset manually by the
system owner and communicated privately.

## Tables, policies, functions, and view

Base tables:

- `staff`
- `staff_private_notes`
- `locations`
- `activity_types`
- `staff_locations`
- `staff_activity_types`

All six have RLS enabled. Anonymous users have no table grants. Authenticated
table grants remain limited by employee-own/supervisor policies.

The `supervisor_staff_directory` view uses `security_invoker` and
`security_barrier`; it exposes private notes and linked status only through
supervisor RLS.

Browser RPCs:

- `current_access_profile`
- `current_staff_id`
- `is_supervisor`
- `save_staff_configuration`
- `set_staff_active`

## Tests added and expanded

Frontend:

- six access-decision tests;
- four rendered `RequireAuth`/`RequireRole` redirect and content-isolation tests;
- two accessible shared-state tests.

Database/RLS suite—41 assertions:

- anonymous denial from every base table;
- unapproved and inactive denial from every base table;
- documented inactive limited status response;
- employee A/B profile and both eligibility isolation;
- supervisor-note isolation;
- direct employee role, status, email, and Auth-link mutation denial;
- employee reference-data insert/update denial;
- supervisor staff, note, eligibility, location, and activity operations;
- atomic rollback after invalid eligibility;
- immutable linked email;
- post-link Auth email divergence removing operational access;
- sequential final-supervisor demotion/deactivation rejection;
- trigger-function execution-grant denial.

Concurrency:

- two real PostgreSQL sessions contend over deactivation and demotion;
- exactly one commits;
- the second receives the final-supervisor invariant error;
- exactly one authorized active supervisor remains.

## Files changed for security closure

- `supabase/migrations/202607260001_milestone_1_foundation.sql`
- `supabase/tests/milestone_1_rls.test.sql`
- `supabase/tests/concurrent_last_supervisor.ps1`
- `src/auth/AuthContext.tsx`
- `src/auth/auth-context.ts`
- `src/auth/RouteGuards.tsx`
- `src/auth/RouteGuards.test.tsx`
- `src/auth/access.ts`
- `src/auth/access.test.ts`
- `src/components/AppShell.tsx`
- `src/components/States.tsx`
- `src/components/States.test.tsx`
- `src/lib/env.ts`
- `src/lib/types.ts`
- `src/pages/DashboardPages.tsx`
- `src/pages/SignInPage.tsx`
- `src/pages/StaffManagementPage.tsx`
- `README.md`
- `docs/reviews/MILESTONE_1_REVIEW.md`

## Verification evidence

Final verification commands and results:

- `npm run lint` — exit 0, no warnings or errors.
- `npm run typecheck` — exit 0, strict TypeScript build passed.
- `npm run test` — exit 0; 3 files and 12 tests passed.
- `npm run build` — exit 0; production Vite build completed.
- `supabase db reset` — exit 0; fresh database recreated, migration applied,
  fictional seed applied, containers restarted.
- `supabase test db` — exit 0; 1 SQL file, 41 tests, all successful.
- `.\supabase\tests\concurrent_last_supervisor.ps1` — exit 0; one concurrent
  change succeeded, one protected rejection occurred, one supervisor remained.
- Live catalog inspection — six base tables reported RLS enabled; trigger-only
  functions reported `anon_execute = false` and
  `authenticated_execute = false`; client RPCs retained only intended
  authenticated execution.
- Secret scan — no Supabase secret, service-role assignment, or JWT-like token
  found.
- Scope scan — no Milestone 2+ implementation identifier found in application
  or migration code.

During remediation, the expanded suite initially exposed that the invariant
counted an unlinked seeded supervisor; this was fixed before the final clean
run. The concurrency script also initially exposed setup ordering before its
Auth links were established; the reusable verifier now establishes links
before changing other supervisor rows.

## Environment and manual setup

Required frontend environment variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

The local fallback URL now matches Supabase port `55321`. The browser never
uses a service-role/secret key.

Complete provisioning, temporary-password, manual-reset, and linked-email
maintenance procedures are in `README.md`.

## Requirement traceability

| Milestone 1 requirement | Evidence | Status |
|---|---|---|
| Supabase Auth, no public registration | Config, sign-in page, README | Satisfied |
| Approved staff email restriction | Continuous UUID/email/active checks and divergence test | Satisfied |
| Employee and supervisor roles | RLS helpers, route guards, direct mutation tests | Satisfied |
| Inactive/unapproved denial | Six-table persona assertions | Satisfied |
| Protected routes | Rendered guard tests | Satisfied |
| Staff management | Atomic staff command and supervisor success assertions | Satisfied |
| Active/inactive lifecycle | Serialized activation command and invariant tests | Satisfied |
| Locations/activity types | Supervisor CRUD and employee denial assertions | Satisfied |
| Staff eligibility | Atomic command and cross-employee isolation assertions | Satisfied |
| Supervisor-only notes | Separate table, RLS, employee denial assertion | Satisfied |
| Last supervisor preserved | Sequential and genuine concurrent verification | Satisfied |
| RLS authoritative | All six tables enabled; grants and policies inspected live | Satisfied |
| No frontend privileged secret/admin API | Source and secret scans | Satisfied |
| Reproducible migration/seed | Fresh `supabase db reset` passed | Satisfied |
| Lint/typecheck/tests/build | Final commands all passed | Satisfied |
| Milestone 2+ excluded | Scope scan and repository inspection | Satisfied |

## Remaining limitations

- User provisioning and forgotten-password reset require the system owner and
  Supabase Dashboard; this is an accepted MVP decision while production SMTP is
  absent.
- Linked email changes are intentionally not self-service. They require a
  trusted administrator maintenance procedure.
- The limited status RPC returns an inactive or email-mismatch flag to the
  linked user so the UI can explain denial. It exposes no operational data.
- The database concurrency verifier requires Docker, the Supabase CLI, and
  PowerShell.
- There is no generated Supabase TypeScript schema; this remains a maintainable
  limitation for the small Milestone 1 surface.

## Final Milestone 1 verdict

**Approved.**

Approval is based on the database design and live evidence, not test success
alone:

- operational authorization continuously requires matching Auth UUID,
  normalized approved email, and active status;
- linked email changes are blocked in the normal workflow;
- every exposed supervisor role/deactivation command serializes on a database
  lock and rechecks authorization/invariants after acquiring it;
- genuine concurrent sessions cannot remove all authorized supervisors;
- RLS, grants, atomicity, route boundaries, and secret handling were inspected
  and verified directly.

Milestone 1 is closed. Milestone 2 has not begun.
