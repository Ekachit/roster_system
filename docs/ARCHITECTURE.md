# Architecture

## Status and scope

This document completes the architecture portion of Milestone 0. It is a
recommendation, not an implementation. No application code, Supabase project,
or Netlify site has been created.

## Product understanding

AI Fitness Zone needs a small, single-organisation rostering application for
about ten people. It replaces availability messages and an Excel roster with
one authenticated source of truth.

There are two user roles:

- **Employees** maintain their own recurring availability and date-specific
  exceptions, see only their own published assignments, acknowledge shifts,
  and request release from a shift.
- **Supervisors** manage staff and reference data, create and publish shifts,
  assess availability and conflicts, assign or replace staff, resolve release
  requests, report scheduled hours, export CSV data, and inspect an audit
  history.

The most important domain rules are:

- date-specific exceptions override recurring availability only over their own
  time intervals;
- availability must cover the entire shift;
- inactive or ineligible staff cannot be assigned;
- a person cannot be assigned twice to one shift or to overlapping active
  shifts;
- assignment outside availability is allowed only as an explicit supervisor
  override with a reason;
- draft shifts are private to supervisors, while employees see only their own
  assignments on published shifts;
- release requests do not alter assignments automatically.

Supabase PostgreSQL is the source of truth. The workbook is an input for
possible one-time seed data only, never a runtime dependency.

## Repository inspection

Inspection on 26 July 2026 found:

- `docs/PRODUCT_REQUIREMENTS.md`, which is the only populated project file;
- an initialised Git repository on `main` with no commits;
- `docs/` containing the product requirements;
- empty directories named `package.json`, `README.md`, `src/`, `supabase/`,
  and `tests/`;
- no dependency manifest, source code, migrations, tests, environment example,
  CI configuration, or Netlify configuration;
- no repository-level `AGENTS.md`.

The directories named `package.json` and `README.md` will conflict with the
normal files of those names and should be removed or renamed during Milestone 1
after confirming they contain no intended material. That cleanup is not part
of Milestone 0.

### Workbook review

`reference/AI Fitness Zone Roster.xlsx` became available during the review and
was inspected read-only. It contains three worksheets:

- **1 - Staff Calendar View:** a Monday-Friday calendar with week blocks 11-19,
  editable Monday dates, activity/location labels, and one staff name per row;
- **Webinar Training Attendance:** a separate attendance list with date, time,
  text duration, session title, and comma-separated trainer names;
- **3 - Shift Data (auto):** a formula-derived, flattened eight-column sheet
  (`Week`, `Date`, `Day`, `Location / Type`, `Time`, `Staff`, `Working With`,
  `MatchRank`).

Concrete findings that affect migration:

- Calendar labels combine several concepts, for example `Clayton Drop-in`,
  `Climate Change Remote Drop-In`, `Webinar Facilitator`, training, events, and
  in-person sessions. They must be mapped deliberately into separate location
  and activity-type records.
- The confirmed editable default for both Clayton and Caulfield is
  `10:40–14:20`. The workbook's visible lookup area explicitly stores
  Caulfield Drop-in `10:40AM-2:20PM`, webinars `4:00PM-5:00PM`, and training
  `9:00AM-10:30AM`; Clayton's same default is a resolved product decision.
  Defaults assist shift creation but each shift stores its own actual times.
- The calendar accommodates multiple assignees by adjacent rows and contains
  special values such as `All Staff` and `Josh (shadowing)`, which are not
  canonical staff identities.
- Names are inconsistent (`Jamein`/`Jaemin`, case differences, trailing spaces,
  first names versus full names), so staff must be matched through an approved
  mapping table rather than imported by raw text.
- The attendance sheet mixes Excel serial dates with a text date and stores
  duration as strings such as `1 hr` and `7 hrs`.
- The automatic sheet contains 2,880 formula cells: 49 contain literal
  `#REF!`, one additional formula references the absent `2 - My Shifts`
  worksheet, and no cells are stored with cached Excel error values. Formula
  defects and cached values are therefore separate concerns. The sheet must not
  be treated as authoritative.
- The workbook contains planned/current roster material, but no employee email,
  role, active status, eligibility, private availability, acknowledgement,
  release request, or audit data.

Recommended source priority is the visible calendar for roster facts, the
attendance sheet only if historical training attendance is explicitly wanted,
and never the formula sheet without reconciliation. Import should be a one-time
staged process with a mapping/exception report and supervisor sign-off.

## Recommended system architecture

```text
Browser
  React + TypeScript + Tailwind
        |
        | Supabase JS client (anon/publishable key + user JWT)
        v
Supabase
  Auth ------ PostgreSQL tables/views/functions
                    |
                    +-- Row Level Security
                    +-- validation/constraint triggers
                    +-- audit triggers

Static production build
  GitHub --> Netlify Free --> browser
```

### Frontend

Use a Vite React TypeScript single-page application with:

- React Router for public, employee, and supervisor route boundaries;
- TanStack Query for server-state caching and invalidation;
- React Hook Form plus Zod for accessible forms and immediate validation;
- Tailwind CSS for responsive presentation;
- `@supabase/supabase-js` for authentication and database access;
- Vitest and React Testing Library for unit/component tests;
- Playwright only for a small, high-value browser smoke suite if it fits the
  free CI budget.

Client route guards improve navigation but are not security controls. Every
data permission and protected mutation must also be enforced in PostgreSQL.

### Backend and domain logic

Use Supabase Auth, PostgreSQL, Row Level Security, database constraints,
security-definer functions for carefully scoped multi-row commands, and
database triggers for invariant enforcement and auditing.

No custom application server is required for the MVP. Avoid Netlify Functions
and never place the service-role key in the frontend. Database functions should
be used for commands that need transactional behaviour, including assignment,
replacement, release resolution, and availability evaluation.

Direct table operations are suitable only for simple, RLS-safe CRUD. Important
commands should have purpose-specific RPC functions so all checks and related
writes occur in one transaction.

### Authentication and approved staff

The confirmed requirements are Supabase Authentication, approved staff email
addresses, and supervisor/employee roles. The sign-in method is not confirmed.
Use this provider-neutral flow:

1. A supervisor creates an approved staff record containing the staff email,
   role, and active status.
2. The staff member authenticates through the selected Supabase Auth method.
3. A database trigger or secure bootstrap command links `auth.users` to the
   pre-approved staff row using the verified, normalised email.
4. Every application RLS policy requires a linked, active staff record.
5. Unapproved or inactive accounts receive no application data access.

Email/password is the provisional lowest-complexity assumption; Google OAuth
or magic links must not be added unless the supervisor confirms the method and
its operational setup. A browser must never call Supabase Auth admin APIs.

Email comparison should use `lower(trim(email))`. Changing an approved email
after Auth linkage should be a deliberate workflow, not a normal profile edit.

### Time handling

The business timezone is `Australia/Melbourne`.

- Store actual shift boundaries as `timestamptz` UTC instants.
- Convert to/from Melbourne local time at the UI and database command boundary.
- Store recurring availability as local weekday plus `time` values because it
  represents a wall-clock rule.
- Store date-specific availability as Melbourne `date` plus local `time`.
- Calculate shift duration from UTC instants so daylight-saving transitions
  are correct.
- Persist all audit timestamps as `timestamptz`.

The MVP roster and availability interface covers Monday to Friday, as specified
in the requirements. The schema may use ISO weekday values without building a
weekend interface. Weekend scheduling is deferred unless separately approved.

Overnight shifts are prohibited in the MVP. A shift's Melbourne-local start and
end must fall on the same date, and the end must be later than the start.
Recurring and date-specific availability intervals likewise require
`end_time > start_time` and cannot cross midnight.

## Recommended page structure

### Public and account routes

| Route | Page | Access |
|---|---|---|
| `/sign-in` | Continue with Google | Public |
| `/access-pending` | Explains unapproved/inactive account | Authenticated but not active/linked |

### Shared authenticated routes

| Route | Page | Access |
|---|---|---|
| `/` | Role-aware redirect | Active staff |
| `/profile` | Own name/email summary and sign out | Active staff |

### Employee routes

| Route | Page | Main responsibilities |
|---|---|---|
| `/employee` | Dashboard | Next shift, this week, pending actions |
| `/employee/schedule` | My schedule | Upcoming published assignments |
| `/employee/shifts/:shiftId` | Shift detail | Details, co-workers, acknowledge, release request |
| `/employee/availability` | Availability | Recurring rules and date exceptions |
| `/employee/requests` | My release requests | Status and request details |

### Supervisor routes

| Route | Page | Main responsibilities |
|---|---|---|
| `/supervisor` | Dashboard | Understaffing, requests, unpublished work |
| `/supervisor/roster` | Weekly roster | Monday-Friday roster, filters, shift actions |
| `/supervisor/shifts/new` | New shift | Create shift |
| `/supervisor/shifts/:shiftId` | Shift detail/edit | Edit, copy, assign, replace, publish, cancel |
| `/supervisor/staff` | Staff list | Add, filter, activate/deactivate |
| `/supervisor/staff/:staffId` | Staff detail | Eligibility and supervisor notes |
| `/supervisor/locations` | Locations | Manage active locations |
| `/supervisor/activity-types` | Activity types | Manage active activity types |
| `/supervisor/release-requests` | Release queue | Review, reject, remove, or replace |
| `/supervisor/reports/hours` | Scheduled hours | Date range, totals, CSV export |
| `/supervisor/audit` | Audit history | Filter important actions |

On desktop, use a Monday-Friday grid. On mobile, use a Monday-Friday grouped
agenda rather than a compressed grid. Shift create/edit can use pages, not
nested modal routes, to preserve deep links and accessible focus behaviour.

## Availability and assignment approach

A database function should evaluate a candidate employee and shift and return
structured reason codes, not only a Boolean. Suggested codes include:

- `inactive_staff`
- `location_ineligible`
- `activity_ineligible`
- `date_exception_unavailable`
- `date_exception_not_covering_shift`
- `no_recurring_availability`
- `recurring_not_covering_shift`
- `overlapping_assignment`
- `available`

The function should apply this order:

1. Confirm active staff and eligibility.
2. Build the employee's recurring available intervals for the local weekday.
3. Overlay date-specific exceptions only across each exception's interval:
   `unavailable` subtracts that interval and `available` adds that interval.
   Outside those intervals, the recurring result remains unchanged. Conflicting
   or overlapping exceptions for the same employee/date are prohibited.
4. Merge adjacent resulting available intervals, then require their union to
   cover the complete shift.
5. Check overlap with assignments whose shifts are not cancelled.

The supervisor roster can call a set-returning function that evaluates all
active, eligible employees for one shift and returns availability status and
reasons. At this scale, on-demand computation is preferable to storing derived
availability counts.

Assignment should use an RPC command that locks the relevant rows, repeats all
checks server-side, validates any override reason, inserts the assignment, and
writes audit history atomically. UI conflict checks are advisory only.

Shift edits use a protected transactional `edit_shift` command rather than
direct table updates. It locks the shift and active assignments, validates
same-day/non-overnight timing, re-evaluates overlap, eligibility, active status,
and availability, requires per-assignment override reasons where permitted,
applies the edit, synchronises related workflow state, and audits everything
atomically.

Changing any employee-visible field on a published shift—title, date/time,
location, activity type, or notes—resets acknowledgements for all active
assignments. Changing required staffing alone does not. The command records
which acknowledgements were reset. Cancellation does not delete historical
acknowledgements.

Deactivating staff is blocked while they have future active assignments on
draft or published shifts. The supervisor must first remove/replace those
assignments and resolve the resulting workflow effects; the UI lists blockers.

Release approval and assignment removal/replacement occur atomically. The
behaviour of a pending request when its assignment is removed, replaced, or
cancelled for another reason remains an open workflow question; implementation
must not invent a status outside the confirmed `Pending`, `Approved`, and
`Rejected` values.

## Free-tier and operational fit

The design uses only a static Netlify deployment and Supabase Auth/PostgreSQL.
It requires no paid service, background worker, email/SMS integration, or
runtime Excel access. Expected usage for approximately ten staff is very small.

Free plans have provider-defined quotas and inactivity/retention behaviour that
can change. Before deployment, verify then-current Supabase and Netlify limits,
configure a lightweight backup/export routine, and document how to restore
data. This is an operational check, not a reason to introduce a paid service.

## Confirmed requirements

- The application is a single-organisation MVP for approximately ten users.
- The frontend is React, Vite, TypeScript, and Tailwind CSS.
- Supabase Free provides Auth and PostgreSQL; Netlify Free hosts the static app.
- Supervisor and employee permissions are enforced by RLS and secure functions.
- The roster interface is Monday-Friday and uses `Australia/Melbourne`.
- Calendar integration, notifications, payroll, timesheet import, automatic
  allocation, swapping, and other listed deferred features are excluded.

## Assumptions pending confirmation

- Email/password is the provisional authentication method.
- No availability record means unavailable.
- Date exceptions override recurring availability only for their time range.
- Shifts and availability do not cross midnight.
- Draft assignments participate in overlap checks.
- Eligibility cannot be overridden; only availability can be overridden.
- Material published-shift edits reset affected acknowledgements.
- Historical cancelled/removed records remain stored but are hidden from the
  normal employee schedule.
- Employees see co-worker names only.
- Scheduled-hours reports default to published, active assignments.
- CSV uses UTF-8, ISO dates, Melbourne 24-hour time, and integer minutes.

## Open inputs and questions

1. Confirm the sign-in method and approved-account workflow.
2. Identify the first supervisor's approved email for bootstrap.
3. Decide whether workbook week 11-19 roster data and the separate attendance
   sheet should be imported, and confirm the calendar year.
4. Supply canonical staff identities and approve mappings for
   `Jamein`/`Jaemin`, `All Staff`, shadowing annotations, and combined calendar
   labels.
5. Confirm availability, acknowledgement, reporting, and CSV assumptions above.
6. Confirm what happens to a pending release request when its assignment or
   shift changes for another reason.
7. Verify current Supabase/Netlify free-tier limits immediately before
   deployment.

## Architecture decisions to preserve

- PostgreSQL/RLS is the security boundary, not React routing.
- No service-role key or Auth admin operation runs in the browser.
- Complex roster mutations, including shift edits, are transactional database
  commands.
- Audit records are generated server-side and append-only.
- Historical records are preserved through status/deactivation, not deletion.
- Derived values such as availability counts and scheduled hours are computed,
  not manually stored.
- The solution remains single-organisation and free-tier compatible.
