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
next week navigation. Each assignment shows its date, Melbourne wall-clock
start/end, location, activity, assignment status, and acknowledgement state.

`/employee/shifts/:shiftId` shows the full employee-visible shift detail,
including notes, assignment kind, other active assigned staff names, and the
current acknowledgement state. A stale, removed, draft, cancelled, unrelated,
or otherwise inaccessible link fails closed with an unavailable state.

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

Employees retain no direct insert/update/delete grant on shifts, assignments,
acknowledgements, or audit records. Draft and cancelled shifts, removed
assignments, unrelated assignments, availability, private notes, and supervisor
notes are not returned by the employee schedule contract.

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

## Acknowledgement rules

- Only the employee who owns an active assignment on a currently published
  shift can acknowledge it.
- Removed assignments and cancelled/draft shifts cannot be acknowledged.
- Another employee's assignment cannot be acknowledged.
- Repeated calls return the original timestamp, create no duplicate row, and
  create only one acknowledgement audit event.
- Acknowledgement is represented as outstanding when no row exists and
  acknowledged when the timestamped row exists.
- Unpublishing resets acknowledgements before any draft correction;
  cancellation retains historical acknowledgement data.

## Tests and exact results

Final verification on 27 July 2026:

- `supabase db reset` — exit 0; all four migrations and synthetic seed applied
  from scratch.
- `supabase test db` — exit 0; 4 SQL files and **121 assertions passed**.
- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; strict TypeScript project build passed.
- `npm run test` — exit 0; 6 files and **37 tests passed**.
- `npm run build` — exit 0; 102 modules transformed and production assets
  emitted. Vite reported a non-failing 501.12 kB chunk-size warning.

SQL coverage proves own published visibility, unrelated employee isolation,
draft isolation, removed/cancelled exclusion, own acknowledgement, denial for
another employee, denial for removed/cancelled assignments, idempotency and one
audit event, co-worker name projection, and direct shift mutation denial.

The component test renders the employee schedule card inside a 320 px container
and verifies date/time, location, activity, assignment state, acknowledgement
state, and the touch-friendly full-width mobile details action.

## Known limitations

- The schedule is a grouped weekly list rather than a calendar grid by design
  for mobile readability.
- Shift times remain same-day Melbourne wall-clock values; overnight shifts are
  outside the approved MVP architecture.
- No browser automation was added for Milestone 4; database permission tests
  and the 320 px responsive component test cover the requested acceptance
  paths. Actual-device verification remains on the manual checklist.
- The production bundle has a non-failing Vite chunk-size warning. Code
  splitting is deferred because it is not required for this small internal
  milestone.

## Manual verification checklist

- [ ] Sign in as a synthetic employee with an active published assignment.
- [ ] Confirm the dashboard next shift, current-week list, and outstanding
      acknowledgement count.
- [ ] Navigate previous and next weeks at desktop width.
- [ ] Repeat schedule and detail checks at approximately 320–390 px width.
- [ ] Open shift detail and confirm notes plus colleague names are correct.
- [ ] Acknowledge the shift and confirm the timestamp and dashboard count update.
- [ ] Refresh and repeat acknowledgement to confirm the original state remains.
- [ ] Confirm a draft, cancelled, removed, and unrelated shift URL fails closed.
- [ ] Confirm employee navigation exposes no supervisor roster controls.
