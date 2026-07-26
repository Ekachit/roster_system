# Milestone 3 Review

## Final verdict

**Approved and closed.** Milestone 3 now supports a Monday-to-Sunday supervisor
roster. A supervisor can create a titled shift, assign regular or shadowing
employees, and publish it without bypassing availability, eligibility,
concurrency, staffing, history, or role protections.

No employee schedule, acknowledgement, release request, report, notification,
calendar integration, or deployment feature was added.

## Scope completed

- Required titled shifts with Melbourne-local date/time, location, activity,
  required regular staffing, optional notes, status, and actor/timestamp
  metadata.
- Seven-day weekly roster on desktop and responsive/mobile layouts, with
  previous/next/current-week navigation and location/activity filters.
- Draft creation/editing, title-preserving copy, audited publish/unpublish,
  cancellation, assignment, historical removal, and atomic replacement.
- Regular and shadowing assignment types. Both are real active assignments and
  obey duplicate, availability, and overlap rules. Only regular assignments
  count toward required staffing; database `shift_staffing` is the authority.
- Structured candidate conflicts, available eligible count, deliberate
  availability-only overrides, and hard eligibility denial.
- Future-assignment protection during staff deactivation.
- RLS, secure functions, database constraints, transaction locks, audit
  records, SQL tests, genuine two-session races, and real browser verification.

## Schema and migration

The locally applied-only and never hosted/shared migration
`202607270002_milestone_3_roster.sql` was corrected in place, then proven from a
fresh database reset.

It adds:

- `shift_status`: `DRAFT`, `PUBLISHED`, `CANCELLED`;
- `assignment_kind`: `REGULAR`, `SHADOWING`;
- `shifts`, including required trimmed `shift_title`;
- `shift_assignments`, including kind, override evidence, removal history, and
  replacement linkage;
- `roster_audit`;
- partial unique and roster lookup indexes;
- Melbourne local-time validation and secure staffing/candidate functions.

Copied shifts retain `shift_title` and exclude assignments. Create, edit, and
copy audit details include the title. Removed/replaced assignments are retained.

## Scheduling and Melbourne DST rules

Roster dates and times are Melbourne wall-clock intent stored as `date` and
`time`. Same-day end time must be later than start time; overnight shifts are
outside Milestone 3.

`is_valid_melbourne_local_time` round-trips each boundary through
`Australia/Melbourne`:

- nonexistent times during the Sunday spring-forward gap are rejected;
- repeated times during the Sunday autumn fall-back overlap are accepted using
  PostgreSQL's Melbourne timezone resolution;
- normal Saturday/Sunday shifts are accepted and queried with the seven-day
  week.

## Assignment and staffing rules

Required structured reasons:

- `DUPLICATE_ASSIGNMENT`
- `OVERLAPPING_ASSIGNMENT`
- `OUTSIDE_RECURRING_AVAILABILITY`
- `DATE_SPECIFIC_UNAVAILABLE`
- `PARTIALLY_AVAILABLE`
- `INACTIVE_EMPLOYEE`
- `LOCATION_NOT_ELIGIBLE`
- `ACTIVITY_NOT_ELIGIBLE`

Only the three availability reasons may be overridden. They require explicit
confirmation and a non-empty written reason, retained on the assignment and in
audit history.

Duplicate, overlap, inactive/non-employee, location eligibility, activity
eligibility, invalid shift time, cancelled shift, and unauthorised access are
database-enforced hard failures. UI state cannot convert them into overrides.

Assignment and replacement lock on the target employee, then re-evaluate
current database state inside the transaction. A partial unique index prevents
duplicate active assignments. Replacement validates and inserts the new row,
historically closes/links the old row, and audits the operation atomically.

`shift_staffing` returns required staff, regular active count, shadowing count,
and understaffed state. The roster cards consume this database result.
Shadowing employees remain visible but never satisfy required staffing.

## Deactivation integrity

The protected `set_staff_active` command locks staff changes and rejects
deactivation when the employee has an active assignment on a non-cancelled
draft or published shift whose Melbourne date is today or later. Cancelled and
historically removed assignments do not block deactivation.

## RLS and secure functions

RLS is enabled for shifts, assignments, and audit:

- supervisors read the full roster;
- employees cannot read the shift table in Milestone 3 and therefore cannot see
  drafts;
- employees can read only their own active assignment row when its shift is
  published, ready for a later explicitly requested employee schedule;
- browser roles have no direct shift/assignment/audit mutation grants.

Supervisor-authorised functions include `save_shift`, `copy_shift`,
`set_shift_status`, `assign_employee`, `remove_employee`,
`replace_employee`, `shift_candidates`, `assignment_conflicts`, and
`shift_staffing`.

## Pages and components

`/supervisor/roster` provides:

- seven day sections, Monday through Sunday;
- desktop seven-column layout and responsive one/two-column agenda;
- current/previous/next week controls;
- location and activity filters;
- titled cards with time, location, activity, status, database regular/required
  count, shadowing count, and understaffed state;
- accessible non-drag controls for create/edit/copy/status/assignment changes;
- candidate reasons, fully available state, and available eligible count;
- separate regular and shadowing assignment controls.

## Automated test evidence

Final verification on 27 July 2026:

- `supabase db reset` — exit 0; all three migrations and synthetic seed applied
  from scratch.
- `supabase test db` — exit 0; 3 SQL files and **104 assertions passed**.
- `powershell -File supabase/tests/concurrent_roster_integrity.ps1` — exit 0;
  three genuine two-session races passed:
  - duplicate assignment: one commit, one conflict rejection;
  - overlapping assignment: one commit, one conflict rejection;
  - conflicting replacement: one commit, one conflict rejection.
- `npm run lint` — exit 0.
- `npm run typecheck` — exit 0; strict project build passed.
- `npm run test` — exit 0; 5 files and **36 tests passed**.
- `npm run build` — exit 0; 99 modules transformed.
- `npm run test:browser:m3` through `run_m3_browser.ps1` — exit 0;
  **2 Playwright tests passed** in installed headless Microsoft Edge.

Coverage includes seven-day/Sunday dates, required title storage/copy/audit,
required staff count, regular/shadow staffing, all conflict reasons,
availability override evidence, hard eligibility denial, duplicate/overlap,
publication, replacement, future-assignment deactivation blocking, employee
permission/direct-write denial, draft isolation, and Melbourne spring/autumn
DST Sundays.

## Actual browser verification

Completed against the real local Vite/Supabase application with generated
synthetic accounts and a generated password stored only in the OS temporary
directory:

- [x] Signed in as a synthetic supervisor in desktop Edge.
- [x] Opened the supervisor roster and observed Monday through Sunday.
- [x] Created `Synthetic Sunday training` on Sunday with required title,
      location, activity, and staffing.
- [x] Observed the title and `0/1 regular assigned` understaffed card.
- [x] Opened candidates and observed the synthetic employee as eligible and
      fully available.
- [x] Assigned the employee as shadowing.
- [x] Observed `1 shadowing` while regular coverage remained `0/1`.
- [x] Published the shift through explicit confirmation.
- [x] Signed in as a synthetic employee at 390 × 844.
- [x] Confirmed there was no supervisor Roster navigation entry.
- [x] Navigated directly to `/supervisor/roster` and received Unauthorised.
- [x] Confirmed create, publish, and assignment controls were absent.

## Secret scanning

Tracked and untracked source files were scanned while excluding `.git`,
`node_modules`, build output, Playwright output, and local environment files.
No committed environment file, service-role key, private key, access token, or
browser-test password was found. Browser credentials were synthetic and the
generated password was not written to the repository.

`npm audit --omit=dev` also ran and reported two high-severity findings in
React Router's unused RSC action mode; the suggested fix is a forced downgrade.
The application is a Vite SPA and does not enable React Router RSC actions.
The complete development audit additionally reported five transitive
`brace-expansion`/ESLint findings whose suggested fix is a forced major ESLint
upgrade. No forced or breaking dependency change was made while closing this
milestone.

## Known limitations

- Shifts cannot cross midnight.
- The small-app replacement UI uses the displayed synthetic-safe employee ID
  rather than a dedicated dialog.
- Employee shift details remain intentionally deferred to Milestone 4.
- No shared/hosted migration or deployment was performed.

## Manual regression checklist

- [x] Seven days visible at desktop width.
- [x] Mobile employee role boundary verified.
- [x] Sunday titled shift created and published.
- [x] Shadow assignment shown but excluded from coverage.
- [x] Fully available candidate shown.
- [x] Employee direct supervisor route denied.
