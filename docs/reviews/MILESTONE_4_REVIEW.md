# Milestone 4 Review

## Scope completed

Milestone 4 is complete and limited to employee schedule and acknowledgement.
No release request, replacement workflow, reporting, export, notification, or
deployment feature was added.

The employee dashboard now shows:

- the next active published assigned shift;
- published shifts in the current Melbourne week;
- the count of upcoming outstanding acknowledgements;
- helpful empty states when there are no published shifts, no shifts this week,
  or no future shift.

`/employee/schedule` provides a responsive grouped weekly list with previous and
next week navigation plus a separate cancelled-shift history. Each assignment
shows its title, date, Melbourne wall-clock start/end, location, activity,
regular/shadowing kind, assignment status, and acknowledgement state.

`/employee/shifts/:shiftId` shows the full employee-visible shift detail,
including notes, assignment kind, permitted colleague names, and the current
acknowledgement state. Employees can reopen their own cancelled assignment
details, but cancellation is clearly marked and acknowledgement is disabled.
A stale, removed, draft, unrelated, or otherwise inaccessible link fails closed
with an unavailable state.

## RLS and database changes

Migration `202607270003_milestone_4_employee_schedule.sql` adds:

- `shift_acknowledgements`, keyed one-to-one by assignment and retaining the
  acknowledging staff ID and timestamp;
- employee shift RLS allowing a published shift only when the caller has their
  own active assignment on it;
- acknowledgement RLS allowing employees to read only their own row;
- `employee_schedule()`, a security-definer query constrained to the caller's
  active published assignments;
- co-worker projection restricted to active colleague names on those same
  shifts;
- `acknowledge_assignment(uuid)`, a secure ownership-checked and idempotent
  command;
- acknowledgement reset on deliberate unpublication, so a later draft edit and
  republication cannot preserve a stale acknowledgement;
- server-side `ASSIGNMENT_ACKNOWLEDGED` and
  `ASSIGNMENT_ACKNOWLEDGEMENTS_RESET` roster audit events.

Hardening migration `202607270004_milestone_4_hardening.sql`:

- revokes authenticated `SELECT` on the `shifts` and `shift_assignments` base
  tables, preventing employees from selecting internal actor, override,
  removal, publication, or cancellation columns through PostgREST;
- removes the employee base-table RLS policies as defence in depth;
- adds supervisor-only `supervisor_roster_shifts(date,date)` and
  `supervisor_roster_assignments()` projections so the supervisor roster
  continues to work without broad base-table grants;
- extends `employee_schedule()` with only approved employee-facing fields,
  shift status, assignment status, cancellation time, and own cancelled history;
- retains published rows only for active assignments and cancelled rows only
  for the employee's own historical assignments.

Employees retain no direct insert/update/delete grant on shifts, assignments,
acknowledgements, or audit records and no direct select grant on the shift or
assignment base tables. Draft shifts, unrelated assignments, removed active
assignments, availability, private notes, supervisor notes, override evidence,
and internal actor identifiers are not returned by the employee schedule
contract.

## Pages and components

- Employee dashboard in `src/pages/DashboardPages.tsx`.
- Mobile-friendly weekly schedule and shift details in
  `src/pages/EmployeeSchedulePage.tsx`.
- Shared schedule loading hook in `src/pages/useEmployeeSchedule.ts`.
- Melbourne date/week and wall-clock display helpers in
  `src/domain/schedule.ts`.
- Employee routes in `src/App.tsx`.
- `My Schedule` employee navigation in `src/components/AppShell.tsx`.
- Employee schedule response type in `src/lib/types.ts`.
- Supervisor roster data loading in `src/pages/RosterPage.tsx` now uses the
  supervisor-only projections.

## Acknowledgement rules

- Only the employee who owns an active assignment on a currently published
  shift can acknowledge it.
- Removed assignments and cancelled/draft shifts cannot be acknowledged.
- Cancelled assignments remain readable as history but show acknowledgement as
  not required; any pre-cancellation acknowledgement timestamp is retained.
- Another employee's assignment cannot be acknowledged.
- Repeated calls return the original timestamp, create no duplicate row, and
  create only one acknowledgement audit event.
- Acknowledgement is represented as outstanding when no row exists and
  acknowledged when the timestamped row exists.
- Unpublishing resets acknowledgements before any draft correction;
  cancellation retains historical acknowledgement data.

## Tests and exact results

Final verification on 27 July 2026:

- `supabase db reset` — exit 0; all five migrations and synthetic seed applied
  from scratch.
- `supabase test db` — exit 0; 4 SQL files and **127 assertions passed**.
- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; strict TypeScript project build passed.
- `npm run test` — exit 0; 6 files and **38 tests passed**.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  supabase/tests/concurrent_acknowledgement.ps1` — exit 0; two genuine
  concurrent sessions both succeeded and produced exactly one acknowledgement
  row and one audit event.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  supabase/tests/run_m4_browser.ps1` — exit 0; **3 Playwright tests passed** in
  installed headless Microsoft Edge in 1.1 minutes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  supabase/tests/run_m3_browser.ps1` — exit 0; **2 supervisor/mobile regression
  tests passed** in installed headless Microsoft Edge in 1.6 minutes.
- `npm run build` — exit 0; 102 modules transformed and production assets
  emitted. Vite reported a non-failing 502.82 kB chunk-size warning.

SQL coverage proves own published visibility, unrelated employee isolation,
draft isolation, removed active-assignment exclusion, cancelled history access,
own acknowledgement, denial for another employee, denial for removed/cancelled
acknowledgement, idempotency and one audit event, constrained co-worker names,
Saturday and Sunday schedules, exact titles and regular/shadowing kinds, direct
base-table denial, supervisor projection denial, and direct shift mutation
denial.

The component tests render published and cancelled schedule cards inside a
320 px container and verify weekend date, title, time, location, activity,
regular/shadowing kind, status, acknowledgement state, and the touch-friendly
full-width details action.

The Milestone 4 browser suite verifies:

- desktop dashboard, schedule, active detail, and cancelled detail at
  1440 × 1000;
- exact shift titles and regular/shadowing kinds in all three employee views;
- Saturday and Sunday cards;
- cancelled history/detail access and absence of its acknowledgement action;
- active acknowledgement followed by reload persistence;
- mobile layout at 390 × 844 with no document-level horizontal overflow;
- authenticated direct PostgREST requests for internal shift and assignment
  columns return permission-denied responses and no internal actor ID.

## Known limitations

- The schedule is a grouped weekly list rather than a calendar grid by design
  for mobile readability.
- Shift times remain same-day Melbourne wall-clock values; overnight shifts are
  outside the approved MVP architecture.
- The production bundle has a non-failing Vite chunk-size warning. Code
  splitting is deferred because it is not required for this small internal
  milestone.
- Browser verification used installed headless Microsoft Edge at real desktop
  and mobile viewport sizes; it did not use physical mobile hardware.

## Manual verification checklist

- [x] Sign in as a synthetic employee with active published assignments.
- [x] Confirm the dashboard next shift, current-week list, and outstanding
      acknowledgement count.
- [x] Verify exact titles and regular/shadowing kinds on dashboard, schedule,
      and detail views.
- [x] Verify Saturday and Sunday schedule cards at desktop and mobile widths.
- [x] Repeat schedule and detail checks at 390 px width without horizontal
      overflow.
- [x] Open active shift detail and confirm notes plus colleague names are correct.
- [x] Open cancelled history detail and confirm acknowledgement is disabled.
- [x] Acknowledge an active shift and confirm the timestamp persists after reload.
- [x] Confirm authenticated PostgREST base-table requests for internal columns
      fail with permission denied.
- [x] Confirm employee navigation exposes no supervisor roster controls.
