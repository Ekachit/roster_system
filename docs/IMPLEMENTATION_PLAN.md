# Implementation Plan

## Purpose

This plan sequences the work after Milestone 0. It keeps the MVP within React,
Vite, TypeScript, Tailwind CSS, Supabase Free, Netlify Free, and GitHub. No
application implementation is included in this document.

## Milestone 0 completion and gates

Completed:

- read and analysed `docs/PRODUCT_REQUIREMENTS.md`;
- inspected the repository;
- recommended the architecture, page structure, schema, RLS model, and
  authoritative conflict logic;
- recorded confirmed requirements, assumptions, and open questions;
- created the initial architecture, database design, and implementation plan;
- completed the review recorded in `docs/reviews/MILESTONE_0_REVIEW.md`.

Still required before or at the start of Milestone 1:

- resolve the blocking questions in `docs/OPEN_QUESTIONS.md`;
- confirm import scope and mappings from the reviewed workbook;
- identify the first supervisor's approved email;
- resolve the empty directories named `package.json` and `README.md`;
- make the initial source-control commit when approved.

## Delivery principles

- Build vertical slices with RLS tests, not an unsecured UI followed by a late
  security pass.
- Treat database rules as authoritative; duplicate only friendly validation in
  the UI.
- Keep migrations versioned and reproducible.
- Use status/deactivation rather than destructive deletion for historical data.
- Test with separate supervisor, employee A, employee B, inactive, and
  unapproved accounts.
- Do not introduce paid services, a custom server, or Netlify Functions unless
  a confirmed requirement cannot be met securely without one.
- Use synthetic staff identities in tests, seed data, screenshots, and public
  previews.
- After each implementation milestone, run linting, type checking, tests, and
  the production build, and record the actual results.
- Keep accessibility and responsive behaviour in each milestone’s definition
  of done.

## Milestone 1 — Foundation

### Repository and tooling

- Replace the accidental empty `package.json`/`README.md` directories with the
  expected files after confirmation.
- Scaffold Vite React TypeScript without overwriting planning documents.
- Add Tailwind CSS, linting, formatting, Vitest, and test setup.
- Create `.env.example`, `.gitignore`, setup instructions, and a typed
  environment loader.
- Configure Supabase CLI directories and local development workflow.

### Database foundation

- Create enums, `staff`, `locations`, `activity_types`, and eligibility tables.
- Add common timestamps, constraints, indexes, role helpers, and RLS.
- Configure the confirmed Supabase Auth method and add the approved-email/Auth
  linking trigger and RLS gate.
- Document and execute the one-time first-supervisor bootstrap.
- Seed confirmed initial locations/activity types, including editable Clayton
  and Caulfield defaults of `10:40`–`14:20`.

### Application foundation

- Implement the confirmed sign-in flow, sign out, session restore, and
  pending/inactive access states.
- Implement role-aware layouts and protected routes.
- Add supervisor staff and reference-data management.
- Ensure employees cannot access supervisor routes or data.

### Verification

- Unit-test route and form behaviour.
- SQL-test anonymous, unapproved, employee, and supervisor access.
- Manually test sign-up/linking, inactive access, refresh, and session expiry.

### Definition of done

An approved employee and supervisor can sign in; an unapproved/inactive user
cannot access application data; the supervisor can safely manage staff,
eligibility, locations, and activities; RLS tests pass.

## Milestone 2 — Availability

### Database

- Add recurring availability and date-specific exception tables.
- Add time-range checks, overlap/normalisation rules, audit triggers, and RLS.
- Implement interval-level exception overlay, interval merging, and full-shift
  coverage evaluation.
- Return structured unavailability reason codes.

### UI

- Build employee availability page with weekly rules and exception management.
- Clearly show Melbourne timezone and interval-level exception behaviour.
- Build supervisor read-only staff availability view.
- Provide accessible validation for invalid and overlapping ranges.

### Verification

- Test full/partial coverage, no rules, interval overlays, merged windows,
  all seven ISO weekdays, inactive staff, and Melbourne daylight-saving
  dates.
- Prove employees cannot read or modify another employee’s availability.

### Definition of done

Employees manage only their own availability, supervisors can inspect all
availability, and server-side evaluation consistently explains availability.

## Milestone 3 — Supervisor roster

### Database

- Add shifts, assignments, assignment commands, status transitions, and audit.
- Implement location/activity eligibility, active-staff, duplicate, overlap,
  and availability enforcement.
- Require a reason for permitted availability overrides.
- Add protected transactional `edit_shift`, weekly-roster, and
  candidate-evaluation functions.

### UI

- Build a seven-day desktop roster and mobile day agenda.
- Add week navigation and location/activity filters.
- Build create, edit, copy, publish, and cancel workflows.
- Build shift detail with assigned/candidate staff, reason messages, staffing
  count, and understaffed state.
- Build atomic assign, remove, and replace actions with explicit override UI.

### Verification

- Add concurrent assignment tests, not only sequential happy-path tests.
- Test draft/published/cancelled transitions and understaffing calculations.
- Test acceptance of weekend shifts, rejection of Melbourne-local overnight shifts, protected
  stale-safe shift editing, acknowledgement resets, and deactivation blockers.
- Verify browser attempts cannot bypass override reasons or mutation rights.

### Definition of done

The supervisor can create and publish a roster and safely manage assignments;
all conflicts are enforced and explained by the database.

## Milestone 4 — Employee schedule

### Database

- Add employee schedule query and acknowledgement table/command.
- Restrict employee reads to their own current assignments on published shifts.
- Add the constrained co-worker-name query.

### UI

- Build employee dashboard, next shift, weekly/upcoming schedule, and shift
  detail.
- Add acknowledgement action and timestamp display.
- Handle empty, loading, error, cancelled, and stale-link states.

### Verification

- Prove employee A cannot query employee B’s private data or draft shifts.
- Prove co-worker response contains names only.
- Test acknowledgement ownership, idempotency, and published-shift restriction.
- Test that material published-shift edits reset acknowledgements while
  staffing-count-only changes do not.

### Definition of done

Employees see only their published schedule, permitted shift information, and
co-worker names, and can acknowledge their own assignments.

## Milestone 5 — Roster changes and audit

### Database

- Add release requests, uniqueness rules, RLS, and transactional resolution
  commands.
- Synchronise pending requests when assignments are otherwise removed/replaced
  or their shift is cancelled.
- Implement reject, approve-and-remove, and approve-and-replace actions.
- Complete append-only audit coverage for required business events.

### UI

- Add employee request submission and request-status pages.
- Add supervisor release queue and resolution workflows.
- Add filtered supervisor audit history.

### Verification

- Confirm submission never removes an assignment.
- Confirm employees cannot resolve or edit request state.
- Test replacement conflicts and rollback of the whole command on failure.
- Test cancellation/system reasons and that ordinary shift edits retain pending
  requests.
- Verify required audit actor, action, time, subject, shift, and reason data.

### Definition of done

Release workflows are explicit and transactional, and supervisors can review an
immutable history of all required important changes.

## Milestone 6 — Reporting

### Database and UI

- Implement scheduled-hours query by Melbourne-local date range.
- Default to published, non-cancelled shifts with active assignments; expose
  explicit historical status filters.
- Display per-employee shift rows and total duration.
- Generate escaped UTF-8 CSV in the browser with deterministic columns and
  filename; no serverless function is needed.

### Verification

- Test partial date ranges, empty results, removed/cancelled/draft semantics,
  CSV quoting/newlines, and DST-aware duration.
- Reconcile sample results against a manually verified workbook subset.

### Definition of done

The supervisor can view correct scheduled hours and download a usable CSV for
timesheet cross-checking.

## Milestone 7 — Deployment

### Supabase production setup

- Create the production project on Supabase Free.
- Apply migrations and controlled seed data.
- Configure the confirmed Supabase Auth method, Auth URLs, and approved users.
- Verify RLS and function grants in production.
- Store only the Supabase URL and publishable/anon key in Netlify; neither is a
  substitute for RLS. Never configure a service-role key in frontend settings.

### Netlify setup

- Connect the GitHub repository to Netlify Free.
- Configure build command and publish directory.
- Add SPA fallback routing.
- Configure environment variables separately for production and deploy
  previews where appropriate.
- Use the free `.netlify.app` domain and Deploy Previews.

### Documentation and operations

- Complete README setup instructions.
- Document environment variables, migrations, bootstrap, seed/import, backup,
  restore, and rollback.
- Add a post-deployment checklist and a minimal recurring manual data export
  process appropriate to free tier.

### Final verification

- Run automated tests and a production smoke test.
- Test desktop and mobile layouts.
- Test role isolation with distinct synthetic test accounts.
- Exercise every acceptance criterion.
- Check browser/network output for secret or private-field leakage.
- Verify timezone and CSV output.

### Definition of done

All 18 product acceptance criteria pass on the Netlify production URL, security
checks pass, and another developer can set up and operate the system from the
documentation.

## Test strategy

### Database/security tests

Highest priority. Run migrations against a disposable/local Supabase database
and set JWT claims for each persona. Test both allowed and denied operations,
including direct REST/table attempts that bypass the UI.

### Unit tests

Cover local date/time conversion, duration formatting, CSV escaping,
availability reason presentation, validators, and role/route decisions.
Database functions remain the authority for domain rules.

### Component tests

Cover key forms, roster cards, responsive agenda behaviour, error states,
confirmation steps, and accessible labels/focus.

### End-to-end smoke tests

Keep the suite small enough for free CI:

1. supervisor creates and publishes a shift;
2. employee sees and acknowledges it;
3. employee requests release;
4. supervisor replaces or removes the employee;
5. report and audit reflect the result;
6. employee isolation checks fail closed.

## Suggested migration sequence

1. Extensions, enums, shared timestamp utilities.
2. Staff, reference data, eligibility, Auth linking, base RLS.
3. Availability tables, policies, evaluation functions.
4. Shifts, assignments, constraints, commands, roster queries.
5. Acknowledgements and employee schedule query.
6. Release requests and resolution commands.
7. Audit hardening and history query.
8. Reporting query and performance indexes.
9. Confirmed seed data/import tooling.

Every migration should be forward-only, reviewable, and paired with tests.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Workbook has combined labels, inconsistent names, special values, 49 literal `#REF!` formulas, and one missing-sheet formula reference | Use visible calendar values only after explicit mappings and a signed-off dry-run exception report |
| Frontend-only architecture tempts admin API exposure | Use allowlist linkage, RLS, and scoped SQL commands; no service key in browser |
| RLS leaks through joins/views | Use minimal RPC results, invoker security where appropriate, and cross-user denial tests |
| Concurrent supervisors create overlap | Lock/serialize assignment commands and retain trigger protection |
| Melbourne DST causes wrong hours | Store actual instants as `timestamptz`; test DST boundaries |
| Published shift edits invalidate acknowledgement | Reset on employee-visible material changes through protected transactional edit and audit the reset |
| Free provider quotas/policies change | Verify current limits before launch; monitor usage; document exports/restores |
| Spreadsheet formula sheet is unreliable (49 literal `#REF!` formulas plus one absent-sheet reference, despite no cached error-typed cells) | Import reconciled visible business values only; never import formulas blindly |
| Empty placeholder directories obstruct scaffold | Confirm empty, then remove/replace only in Milestone 1 |

## Requirement traceability

| Acceptance criteria | Primary milestone |
|---|---|
| Sign in and role permissions | 1 |
| Recurring availability and exceptions | 2 |
| Shift creation, candidate availability, assignment, publication | 3 |
| Published employee schedule and acknowledgement | 4 |
| Release, removal/replacement, audit | 5 |
| Scheduled hours and CSV | 6 |
| Production deployment | 7 |

## Explicitly deferred

The out-of-scope list in the product requirements remains deferred, including
notifications, payroll/timesheet import, auto-allocation, shift swapping,
calendar integration, chat, native apps, and advanced analytics. Workbook
import is a controlled setup activity, not an ongoing integration.
