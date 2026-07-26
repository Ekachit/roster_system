# Milestone 2 Review

## Scope completed

Milestone 2 implements employee availability only. Employees can create, edit,
read, and delete their own recurring weekly availability and date-specific
available/unavailable exceptions. Supervisors have a read-only view of all
active staff availability with employee, date, and weekday filters.

The seven-day correction supports ISO weekdays 1 (Monday) through 7 (Sunday)
across the schema, secure commands, employee form, supervisor view, and
Melbourne-local resolution. No shifts, assignments, roster publication,
schedules, or later-milestone features were added.

## Schema and migration changes

The undeployed migration `202607270001_milestone_2_availability.sql` adds:

- `availability_kind` (`available`, `unavailable`);
- `recurring_availability`, including ISO weekday 1–7, local start/end time,
  effective start/end dates, and note;
- `availability_exceptions`, including Melbourne local date, kind, timed
  interval or full-day unavailability, and note;
- staff/weekday and staff/date indexes;
- updated-at triggers;
- validation constraints and serialized overlap-protection triggers;
- secure owner-derived save/delete RPCs.

The migration was untracked and had no shared/hosted deployment evidence, so it
was safely corrected in place before a fresh database reset. No forward-only
corrective migration was required.

Overnight availability remains prohibited. A full-day exception is available
only for `unavailable`; full-day rows store null times.

## RLS changes

Both new tables have RLS enabled. Authenticated employees can select rows only
where `staff_id = current_staff_id()`. Supervisors can select all rows.

Browser roles have no direct insert, update, or delete grants. Mutation RPCs
derive the owner from `auth.uid()` through `current_staff_id()`, require the
linked active role to be `employee`, and accept no browser-supplied employee ID.
They update/delete only caller-owned records. Supervisors remain read-only.
Anonymous, inactive, unapproved, and email-mismatched identities receive no
availability-table access.

## Availability-resolution rules

`resolveAvailability()` is a pure TypeScript domain function. It returns a
structured status, full-availability Boolean, normalized available intervals,
human-readable reasons, applied rule/exception IDs, and the
`Australia/Melbourne` timezone.

Resolution:

1. Reject an inactive employee.
2. Validate the Melbourne local ISO date and same-day time range.
3. Select recurring rules effective on that ISO weekday and date.
4. Merge recurring intervals.
5. Apply non-overlapping date exceptions: available adds an interval;
   unavailable subtracts an interval; full-day unavailable subtracts the
   complete local day.
6. Merge adjacent/overlapping results and test complete interval coverage.

Structured statuses are:

- `fully_available`
- `partially_available`
- `no_recurring_availability`
- `date_specific_unavailable`
- `date_specific_available_override`
- `inactive_employee`
- `invalid_input`

The database rejects recurring rules whose time intervals and inclusive
effective-date periods overlap for the same employee and weekday. It rejects
overlapping date exceptions for the same employee/date regardless of kind.
Transaction advisory locks serialize competing saves, so concurrent requests
cannot create ambiguity. The pure resolver still merges overlapping input
deterministically to remain independently testable.

Availability uses local `date` and `time` values because it is wall-clock
intent. DST does not shift a recurring local time. Tests cover the Melbourne
Sundays on which daylight saving starts and ends.

## Pages and components

- `/employee/availability`: mobile-friendly recurring and one-off forms,
  Saturday/Sunday options, explanatory copy, local timezone, field validation,
  loading/empty/error states, success confirmations, editing, and confirmed
  deletion.
- `/supervisor/availability`: read-only active-staff view, distinct recurring
  and one-off sections/badges, seven weekday labels, and employee/date/weekday
  filters.
- Navigation and dashboards link to the role-appropriate availability view.

## Tests and results

Final seven-day corrective verification on 27 July 2026:

- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; strict TypeScript project build passed.
- `npm run test` — exit 0; 4 files and 27 tests passed.
- `npm run build` — exit 0; TypeScript build and production Vite bundle passed.
- `supabase db reset` — exit 0; both migrations and synthetic seed applied to a
  fresh local database.
- `supabase test db` — exit 0; 2 SQL files and 68 assertions passed.

Coverage includes full/partial/no-recurring results, unavailable and available
date overrides, Saturday and Sunday recurring rules, weekend no-availability,
weekend timed available overrides, weekend timed and full-day unavailable
exceptions, overlapping resolver input, invalid/overnight ranges, invalid ISO
weekdays, inactive staff, Melbourne DST-transition Sundays, employee A/B
weekend privacy, weekend staff-ID spoof prevention, supervisor visibility,
inactive denial, and database overlap rejection.

During corrective testing, expanding one employee from one rule to three
exposed a multi-row test-fixture subquery; the privacy test was constrained to
one owned row. Production behavior was unaffected. The final fresh reset and
complete suite passed.

## Known limitations

- Availability supports all seven weekdays but cannot cross midnight.
- Full-day available exceptions are not supported; an available override must
  use a time interval. Full-day unavailability is supported.
- Availability resolution is implemented for Milestone 2 as a pure domain
  function. Shift-backed database evaluation belongs to Milestone 3 because no
  shift table exists yet.
- The supervisor view is a compact list suitable for about ten users, not a
  weekly roster grid.

## Manual employee/supervisor verification

Completed against the actual local Vite/Supabase application in a headless Edge
browser at a 390 × 844 mobile viewport using synthetic accounts only:

- [x] Signed in as an active synthetic employee and opened **Availability**.
- [x] Confirmed the employee weekday selector contains Saturday (ISO 6) and
      Sunday (ISO 7).
- [x] Saved Saturday 09:00–17:00 recurring availability and observed the
      success confirmation and Saturday label.
- [x] Submitted a zero-length interval and observed the validation message.
- [x] Saved a Sunday timed available override and Saturday full-day
      unavailability and observed one-off labels.
- [x] Opened deletion confirmation and cancelled it; the recurring rule
      remained.
- [x] Signed in as a second synthetic employee and observed the empty own-only
      state rather than the first employee's weekend records.
- [x] Signed in as a synthetic supervisor and opened the read-only availability
      view.
- [x] Confirmed the supervisor weekday filter contains Saturday and Sunday,
      selected Saturday, and observed the first employee's Saturday rule.
- [x] Confirmed no availability edit/delete controls were exposed to the
      supervisor.
- [x] Confirmed `Australia/Melbourne` was displayed.

The browser verification exited 0. Database tests separately verify deletion,
editing authorization, overlap rejection, timed weekend unavailability,
full-day weekend unavailability, and employee ownership/RLS.

## Final verdict

**Approved.** Milestone 2 now supports seven-day recurring availability and
weekend date exceptions consistently across schema, secure RPCs, domain
resolution, employee forms, supervisor labels/filters, RLS tests, and
documentation. Overnight availability remains rejected. No shift, assignment,
or Milestone 3 functionality was implemented.
