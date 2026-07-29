# Database Design

## Design goals

The implemented Supabase PostgreSQL schema supports the MVP while keeping:

- authentication identity separate from staff/business data;
- private employee data protected by Row Level Security (RLS);
- roster invariants enforced in the database;
- history intact when people, locations, activities, or shifts become inactive;
- times and durations correct in `Australia/Melbourne`;
- derived values out of mutable columns where practical.

The authoritative physical schema is the ordered SQL in
`supabase/migrations`. This document describes the implemented model through
Milestone 7; production deployment must apply those migrations rather than
recreating tables from prose.

## Extensions and conventions

- Primary keys: `uuid` with `gen_random_uuid()`.
- Timestamps: `timestamptz`, default `now()`.
- Names: `snake_case`.
- Auth identity: nullable unique `staff.auth_user_id` referencing
  `auth.users(id)`; nullable allows supervisor pre-approval before the owner
  creates the email/password Auth user. RLS requires exact normalized-email
  linkage to an active approved staff row.
- Email: `citext` or a unique index on `lower(trim(email))`.
- Every mutable table has `created_at` and `updated_at`; meaningful authorship
  columns are included where needed.
- Use enum types for closed workflow states and lookup tables for
  supervisor-managed reference data.
- The business timezone is an application/database constant,
  `Australia/Melbourne`, not a per-user preference in MVP.

## Enums

| Enum | Values |
|---|---|
| `staff_role` | `supervisor`, `employee` |
| `shift_status` | `DRAFT`, `PUBLISHED`, `CANCELLED` |
| `assignment_kind` | `REGULAR`, `SHADOWING` |
| assignment lifecycle | active when `removed_at is null`; otherwise historical |
| `release_request_status` | `PENDING`, `APPROVED`, `REJECTED`, `CANCELLED` |
| `availability_kind` | `available`, `unavailable` |

Replacement is represented as one historically removed assignment plus one new
active assignment in the same transaction. `REGULAR` contributes to required
staffing; `SHADOWING` is still conflict-checked, visible, acknowledgeable,
audited, and included in current scheduled-hours reporting.

## Entity overview

```text
auth.users 0..1 ---- 1 staff
                       |\
                       | +---- staff_private_notes
                       | +---- staff_locations ---- locations
                       | +---- staff_activity_types ---- activity_types
                       | +---- recurring_availability
                       | +---- availability_exceptions
                       |
shifts ---- shift_assignments ---- staff
   |               |
   |               +---- shift_acknowledgements
   |               +---- release_requests
   |
   +---- locations
   +---- activity_types

roster_audit --> actor staff and optional subject/shift/request identifiers
```

## Tables

### `staff`

Approved staff directory and application authorisation record.

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `auth_user_id` | `uuid` | nullable, unique, FK to `auth.users` |
| `email` | `citext` | unique, required |
| `full_name` | `text` | required, non-blank |
| `role` | `staff_role` | required, defaults `employee` |
| `is_active` | `boolean` | required, defaults true |
| `created_by` | `uuid` | nullable FK to `staff`; null for bootstrap |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Role and `auth_user_id` changes must not be allowed through general employee
profile updates. Prevent deactivation/demotion of the last active supervisor.
Milestone 7 limits names to 120 characters and emails to 320 characters.

### `staff_private_notes`

Supervisor-only notes are physically separated from safe staff identity data.

| Column | Type | Rules |
|---|---|---|
| `staff_id` | `uuid` | PK/FK to `staff` |
| `note` | `text` | nullable, maximum 2,000 characters |
| `updated_at` | `timestamptz` | required |

Employees have no row visibility. The supervisor directory is a
`security_invoker`/`security_barrier` view so underlying RLS still applies.

### `locations`

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `name` | `text` | required, case-insensitive unique |
| `is_active` | `boolean` | required, defaults true |
| `default_start_time` | `time` | nullable; shift-form default only |
| `default_end_time` | `time` | nullable; greater than default start |
| `created_at`, `updated_at` | `timestamptz` | required |

Deactivate rather than delete a referenced location.
Seed both Clayton and Caulfield with editable defaults `10:40`–`14:20`.
Defaults prefill new shifts but never replace times stored on a shift.

### `activity_types`

Same structure and lifecycle as `locations`. Location and activity remain
independent dimensions.

### `staff_locations`

| Column | Type | Rules |
|---|---|---|
| `staff_id` | `uuid` | FK `staff`, part of PK |
| `location_id` | `uuid` | FK `locations`, part of PK |
| `created_at` | `timestamptz` | required |

### `staff_activity_types`

Equivalent many-to-many table for `staff` and `activity_types`.

An empty eligibility set should mean eligible for none, not eligible for all.
This is safer and makes incomplete setup visible.

### `recurring_availability`

Local weekly wall-clock rules.

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `staff_id` | `uuid` | FK `staff`, required |
| `weekday` | `smallint` | required, ISO 1=Monday through 7=Sunday |
| `start_time` | `time` | required |
| `end_time` | `time` | required, greater than start |
| `kind` | `availability_kind` | required |
| `note` | `text` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Disallow overlapping records for the same employee and weekday when both their
time intervals and effective-date periods overlap.

No recurring rule means unavailable. The primary UI creates available recurring
windows; date exceptions add or subtract availability at interval level.

### `availability_exceptions`

Date-specific local rules.

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `staff_id` | `uuid` | FK `staff`, required |
| `local_date` | `date` | required |
| `start_time` | `time` | required |
| `end_time` | `time` | required, greater than start |
| `kind` | `availability_kind` | required |
| `note` | `text` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Use interval-level overlay semantics. Begin with recurring available intervals
for the weekday; an `unavailable` exception subtracts only its interval, while
an `available` exception adds only its interval. Recurring availability remains
effective outside exception intervals. Merge adjacent resulting available
intervals before checking full-shift coverage. Prohibit overlapping exception
records for one employee/date so contradictory kinds cannot be ambiguous. An
“unavailable all day” action uses the complete local-day interval. No
availability interval may cross midnight.

### `shifts`

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `shift_title` | `text` | required, trimmed, maximum 160 characters |
| `local_date` | `date` | required Melbourne roster date |
| `start_time` | `time` | required |
| `end_time` | `time` | required, greater than start |
| `location_id` | `uuid` | FK `locations`, required |
| `activity_type_id` | `uuid` | FK `activity_types`, required |
| `required_staff_count` | `integer` | required, 1 through 100 |
| `notes` | `text` | nullable, employee-visible, maximum 2,000 characters |
| `status` | `shift_status` | required, defaults `DRAFT` |
| `created_by` | `uuid` | FK `staff`, required |
| `updated_by` | `uuid` | FK `staff`, required |
| `published_at` | `timestamptz` | nullable |
| `cancelled_at` | `timestamptz` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Status transition commands populate/clear the relevant metadata. “Copy” creates
a new draft and does not copy assignments, acknowledgements, or release
requests.

The database validates each boundary through `Australia/Melbourne`, rejects
nonexistent DST times, accepts all seven weekdays, and prohibits overnight
shifts. Reports convert the two local boundaries to instants before calculating
duration. Status commands preserve the actor and reason in `roster_audit`;
copying creates a new draft without assignments, acknowledgements, or requests.

### `shift_assignments`

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `shift_id` | `uuid` | FK `shifts`, required |
| `staff_id` | `uuid` | FK `staff`, required |
| `assignment_kind` | `assignment_kind` | `REGULAR` or `SHADOWING` |
| `assigned_by` | `uuid` | FK `staff`, required |
| `assigned_at` | `timestamptz` | required |
| `removed_by` | `uuid` | nullable FK `staff` |
| `removed_at` | `timestamptz` | nullable |
| `removal_reason` | `text` | nullable, maximum 1,000 characters |
| `override_confirmed` | `boolean` | required, defaults false |
| `override_reason` | `text` | nullable, maximum 1,000 characters |
| `override_conflicts` | `jsonb` | structured server-evaluated reasons |
| `replaced_by_assignment_id` | `uuid` | nullable self-FK |

Use a partial unique index on `(shift_id, staff_id)` where
`removed_at is null`. When `override_confirmed` is true, require a non-blank
reason and structured conflicts. Only availability failures are overridable; inactive,
ineligible, duplicate, and overlapping assignment failures remain prohibited.
Only active regular assignments count toward `required_staff_count`. Shadowing
assignments are still scheduled, conflict-checked, employee-visible,
acknowledgeable, audited, and included in scheduled-hours reporting.

Because shift time/status lives in another table, a simple exclusion constraint
cannot fully protect cross-shift overlap. Enforce overlap in the assignment RPC
and a database trigger, with advisory/row locking to prevent concurrent races.

### `shift_acknowledgements`

| Column | Type | Rules |
|---|---|---|
| `assignment_id` | `uuid` | PK, FK `shift_assignments` |
| `staff_id` | `uuid` | FK `staff`, required |
| `acknowledged_at` | `timestamptz` | required |

The redundant `staff_id` makes ownership policies straightforward but must equal
the assignment’s employee via trigger/command. An employee can acknowledge only
their own currently assigned, published shift. Editing a published shift's
employee-visible fields (start/end, location, activity type, or
notes) resets acknowledgements for every active assignment and writes an audit
event. Changing only `required_staff_count` does not reset them. Cancellation
retains historical acknowledgements.

### `release_requests`

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `assignment_id` | `uuid` | FK `shift_assignments`, required |
| `staff_id` | `uuid` | FK `staff`, required |
| `reason` | `text` | required, non-blank, maximum 200 characters |
| `note` | `text` | nullable, maximum 1,000 characters |
| `status` | `release_request_status` | required, defaults `PENDING` |
| `submitted_at` | `timestamptz` | required |
| `resolved_at` | `timestamptz` | nullable |
| `resolved_by` | `uuid` | nullable FK `staff` |
| `resolution_reason` | `text` | nullable, maximum 1,000 characters |
| `replacement_assignment_id` | `uuid` | nullable FK `shift_assignments` |
| `created_at`, `updated_at` | `timestamptz` | required |

Use a partial unique index on `assignment_id` where `status = 'PENDING'`.
Employee inserts derive `staff_id` from the current linked profile and validate
assignment ownership. Only a supervisor command resolves requests. Approval and
assignment removal/replacement occur in the same transaction.

Approve-and-remove or approve-and-replace sets the selected request to
`APPROVED`. An independent removal, replacement, or shift cancellation sets an
otherwise pending request to `CANCELLED` with a system-generated explanation.
Unpublishing retains it. Request transitions, assignment changes, and audit
events are atomic.

### `roster_audit`

Append-only system history.

| Column | Type | Rules |
|---|---|---|
| `id` | `bigint generated always as identity` | PK |
| `created_at` | `timestamptz` | required |
| `actor_staff_id` | `uuid` | FK `staff`, required |
| `action` | `text` | required, controlled action code |
| `entity_type`, `entity_id` | `text`, `uuid` | normalized target |
| `shift_id` | `uuid` | nullable FK `shifts` |
| `assignment_id` | `uuid` | nullable FK `shift_assignments` |
| `subject_staff_id` | `uuid` | nullable FK `staff` |
| `release_request_id` | `uuid` | nullable FK `release_requests` |
| `reason` | `text` | nullable, maximum 2,000 characters |
| `before_data`, `after_data` | `jsonb` | minimal changed fields |
| `details` | `jsonb` | required, defaults `{}` |

Audit data contains only relevant changed fields and must never contain Auth
tokens, passwords, or unrestricted private notes. Audit writes come from
trusted commands. Browser roles lack mutation privileges and the Milestone 7
`BEFORE UPDATE OR DELETE` trigger rejects even privileged SQL mutation.

## Views and database functions

Prefer views/functions that return the minimum columns required.

### Helper functions

- `current_staff_id()` — linked active staff ID for `auth.uid()`, or null.
- `is_supervisor()` — true only for linked, active supervisor.
- `require_supervisor()` — raises before protected supervisor data is read.
- Internal workflow locks and validators are not browser executable.

Implement helpers as stable SQL security-definer functions with a fixed
`search_path`, schema-qualified objects, and no public execute permission unless
needed by clients.

### Query functions/views

- `assignment_conflicts(shift_id, staff_id)` and `shift_candidates(shift_id)`
  return structured active/eligibility/overlap/availability reasons to
  supervisors.
- `supervisor_roster_shifts(start_date, end_date)`,
  `supervisor_roster_assignments()`, and `shift_staffing(shift_id)` return the
  supervisor roster contract without broad base-table reads.
- `employee_schedule()` returns only the caller's active published assignments
  plus their own cancelled history and constrained co-worker names.
- Employee and supervisor release-request projections expose only their
  role-specific workflow fields.
- `supervisor_audit_history(action, entity_type, limit)` returns append-only
  history to supervisors.
- `scheduled_hours_report(start_date, end_date, staff_id, location_id,
  activity_type_id)` returns only published active assignments and the exact
  CSV-safe columns.

The report converts both local boundaries through `Australia/Melbourne`,
subtracts the resulting instants, and rounds to integer minutes. It never
trusts a stored duration.

### Command functions

- `save_staff_configuration(...)`, `set_staff_active(...)`
- availability save/delete functions for recurring rules and date exceptions
- `save_shift(...)`, `copy_shift(...)`, `set_shift_status(...)`
- `assign_employee(...)`, `remove_employee(...)`, `replace_employee(...)`
- `acknowledge_assignment(assignment_id)`
- `submit_release_request(...)`, `reject_release_request(...)`
- `approve_release_request_remove(...)`,
  `approve_release_request_replace(...)`

Each command checks the caller, locks relevant records, enforces invariants,
writes all changes, and produces audit events in one transaction. Revoke
function execution from `public`/`anon` and grant only to `authenticated` where
the function performs its own authorisation.

`save_shift` is the only browser-accessible way to create or edit a shift and
edits only `DRAFT` rows. Status, assignment, replacement, release resolution,
and acknowledgement transitions use separate purpose-specific functions. Every
function derives the actor from `auth.uid()` and repeats authorization and
invariants inside the transaction.

`set_staff_active` serializes staff-state changes and rejects deactivation while
the person has an active assignment on a draft or published shift whose
Melbourne date is today or later. The supervisor must remove or replace those
assignments first.

## Row Level Security approach

Enable RLS on every table in `public`. Revoke unnecessary table privileges from
`anon`; the application uses the `authenticated` role. RLS is additive, so
policies should be small and tested as a matrix.

### Access matrix

| Data | Employee | Supervisor |
|---|---|---|
| Own safe staff profile | Read | Read all |
| Other staff identity | Names only through constrained published-shift query | Read all |
| Supervisor notes | Never | Read/write |
| Own availability | Read/create/update/delete | Read all |
| Other availability | No | Read all |
| Locations/activity types | Read active rows | Read/manage all |
| Own eligibility | Read if useful | Read/manage all |
| Shifts | Own assigned published shifts only | Read/manage all |
| Assignments | Own published active assignments; co-worker names only through constrained query | Read/manage all |
| Acknowledgements | Own only | Read all |
| Release requests | Own only | Read/resolve all |
| Audit events | No | Read only |

### Critical policy patterns

**Staff**

- Employee `SELECT`: own row only. Do not grant direct access to other complete
  staff rows merely to show co-worker names.
- Supervisor `SELECT/INSERT`: all rows. General safe-field edits may use a
  restricted command; role and active-state transitions use protected commands
  so last-supervisor and future-assignment checks cannot be bypassed.
- No direct employee update of role, active status, Auth linkage, eligibility,
  email, or supervisor notes. If self-editing is later desired, expose a
  restricted function for `full_name`.

**Availability**

- Employee policies require `staff_id = current_staff_id()` in both `USING`
  and `WITH CHECK`.
- Supervisor policies allow all rows.
- A trigger rejects changes for inactive staff and invalid/overlapping ranges.

**Reference and eligibility data**

- Active users may read active locations/activity types.
- Supervisors manage reference rows and all eligibility joins.
- Employees can at most read their own eligibility joins.

**Shifts and assignments**

- Authenticated browser roles have no direct shift/assignment base-table read
  or mutation grants. Supervisors use protected projections and commands.
- Employee schedule reads require the caller's active assignment and
  `shift.status = 'PUBLISHED'`; their own cancelled history is returned
  separately by the same constrained function.
- Do not provide employees a broad assignments policy for the same shift: it
  could expose staffing history. A constrained function/view should return only
  current co-worker IDs and names for a shift the caller is actively assigned
  to.
- Employees never insert/update/delete shifts or assignments.

**Acknowledgements and release requests**

- Employees read their own rows.
- Creation uses command functions, not unrestricted direct inserts, to prevent
  spoofed `staff_id` or assignment IDs.
- Employees cannot update resolution fields or approve requests.
- Supervisors read all; resolutions use a transactional command.

**Audit**

- Supervisors have `SELECT`.
- No browser role has direct `INSERT`, `UPDATE`, or `DELETE`.
- Trigger/function owner writes events; audit rows are immutable.

### Avoiding RLS recursion and privilege leaks

- Do not make a `staff` policy query `staff` directly to discover the role;
  use a carefully defined helper function.
- All security-definer functions set a fixed empty/safe `search_path` and use
  fully qualified names.
- Functions derive the actor from `auth.uid()`; never accept an actor ID from
  the browser as authority.
- Grant execute only on named functions and revoke default public access.
- Never use user-editable JWT metadata for authorisation. Role and active status
  live in the protected `staff` table.
- Index all columns used by RLS predicates and joins.

## Constraints and indexes

At minimum:

- unique normalised `staff.email`;
- unique non-null `staff.auth_user_id`;
- unique case-insensitive location/activity names;
- primary keys on both eligibility join columns;
- check `end_time > start_time` for availability;
- check `end_time > start_time`, valid Melbourne boundaries, and
  `required_staff_count` between 1 and 100;
- partial unique active assignment `(shift_id, staff_id)` where
  `removed_at is null`;
- partial unique pending release request per assignment;
- check override reason is present exactly when required;
- indexes on availability `(staff_id, weekday)` and
  `(staff_id, local_date)`;
- indexes on `shifts(local_date, status)`, active assignment staff/shift, and
  audit foreign keys/timestamp.

Add database-trigger protection for:

- concurrent overlapping active assignments;
- assignment to inactive/ineligible staff;
- invalid status transitions;
- deactivation while future active assignments exist;
- acknowledgement resets after material published-shift edits;
- release-request synchronisation after assignment/shift changes;
- mutation of immutable audit events;
- employee/Auth email linkage integrity;
- `updated_at` maintenance.

## Audit action codes

Use stable machine-readable codes such as:

- `availability.recurring_created`, `availability.recurring_updated`,
  `availability.recurring_deleted`
- `availability.exception_created`, `availability.exception_updated`,
  `availability.exception_deleted`
- `shift.created`, `shift.updated`, `shift.published`, `shift.cancelled`
- `assignment.created`, `assignment.removed`, `assignment.replaced`
- `assignment.availability_overridden`, `assignment.acknowledged`
- `release_request.submitted`, `release_request.approved`,
  `release_request.rejected`
- `staff.created`, `staff.updated`, `staff.deactivated`

Human-readable labels belong in the UI so audit codes remain stable.

## Seed and migration strategy

1. Apply versioned SQL migrations through the Supabase CLI.
2. Seed initial locations and activity types from confirmed workbook mappings.
3. Bootstrap the first supervisor via a documented, one-time SQL/dashboard
   procedure.
4. Add approved staff rows, then link Auth users by verified, normalised email
   using the confirmed Supabase Auth method.
5. Stage visible workbook calendar values outside production tables; normalise
   whitespace/case and apply explicit mappings for staff names and combined
   location/activity labels.
6. Produce a dry-run report for unknown names, `All Staff`, shadowing notes,
   blank/default times, duplicates, and invalid dates, then require supervisor
   sign-off before inserting shifts/assignments.
7. Treat the formula-generated `3 - Shift Data (auto)` sheet as a comparison
   aid only: among 2,880 formulas, 49 contain literal `#REF!` and one other
   formula references absent `2 - My Shifts`; zero cells are stored as cached
   Excel error values.
8. Import attendance history only if its purpose and schema are separately
   confirmed; attendance is not the same as a scheduled assignment.
9. Never import formulas; import reconciled business values only.

Seed scripts must be idempotent and contain no real credentials. Tests, seed
files, screenshots, and public previews must use synthetic people only.
Production personal data must not be committed to Git.

## Database tests

Use migration-level SQL tests to prove:

- anonymous and unapproved users see nothing;
- employees cannot read another employee’s availability, notes, requests, or
  assignments;
- employees cannot elevate role or mutate shifts;
- supervisors can perform intended operations;
- inactive/ineligible/duplicate/overlapping assignments fail;
- unavailable assignment requires supervisor plus reason;
- interval exceptions affect only their covered time and adjacent result
  intervals merge correctly;
- weekend shifts succeed and Melbourne-local overnight shifts fail;
- material published-shift edits reset acknowledgement and staffing-only edits
  do not;
- staff with future active assignments cannot be deactivated;
- release submission does not remove an assignment;
- an employee cannot resolve any release request;
- assignment removal/replacement and shift cancellation synchronise pending
  release requests;
- default reports include published active assignments but exclude drafts,
  cancelled shifts, and removed assignments;
- audit rows are created and cannot be edited;
- duration remains correct across Melbourne daylight-saving boundaries.
