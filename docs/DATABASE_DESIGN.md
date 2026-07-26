# Database Design

## Design goals

The proposed Supabase PostgreSQL schema supports the MVP while keeping:

- authentication identity separate from staff/business data;
- private employee data protected by Row Level Security (RLS);
- roster invariants enforced in the database;
- history intact when people, locations, activities, or shifts become inactive;
- times and durations correct in `Australia/Melbourne`;
- derived values out of mutable columns where practical.

This is a logical design. Exact SQL and migrations belong to Milestone 1 and
later milestones.

## Extensions and conventions

- Primary keys: `uuid` with `gen_random_uuid()`.
- Timestamps: `timestamptz`, default `now()`.
- Names: `snake_case`.
- Auth identity: nullable unique `staff.auth_user_id` referencing
  `auth.users(id)`; nullable allows supervisor pre-approval before first Google
  OAuth login. RLS requires exact normalised-email linkage to an active approved
  staff row.
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
| `shift_status` | `draft`, `published`, `cancelled` |
| `assignment_status` | `assigned`, `removed` |
| `release_request_status` | `pending`, `approved`, `rejected` |
| `availability_kind` | `available`, `unavailable` |

`assignment_status` preserves removal history and makes reporting semantics
explicit. Replacement is represented as one removed assignment plus one new
assignment in the same transaction, linked through audit metadata.

## Entity overview

```text
auth.users 0..1 ---- 1 staff
                       |\
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

audit_events --> actor staff and optional subject/shift/request identifiers
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
| `supervisor_notes` | `text` | nullable, supervisor-only |
| `created_by` | `uuid` | nullable FK to `staff`; null for bootstrap |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Role and `auth_user_id` changes must not be allowed through general employee
profile updates. Prevent deactivation/demotion of the last active supervisor.

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
| `weekday` | `smallint` | required, ISO 1=Monday through 5=Friday for MVP |
| `start_time` | `time` | required |
| `end_time` | `time` | required, greater than start |
| `kind` | `availability_kind` | required |
| `note` | `text` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Initially disallow overlapping records for the same employee, weekday, and kind,
or provide a command that normalises them. Weekend support is deferred.

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
| `starts_at` | `timestamptz` | required |
| `ends_at` | `timestamptz` | required, greater than start |
| `location_id` | `uuid` | FK `locations`, required |
| `activity_type_id` | `uuid` | FK `activity_types`, required |
| `required_staff_count` | `integer` | required, at least 1 |
| `notes` | `text` | nullable, employee-visible when published |
| `status` | `shift_status` | required, defaults `draft` |
| `created_by` | `uuid` | FK `staff`, required |
| `published_at` | `timestamptz` | nullable |
| `published_by` | `uuid` | nullable FK `staff` |
| `cancelled_at` | `timestamptz` | nullable |
| `cancelled_by` | `uuid` | nullable FK `staff` |
| `cancellation_reason` | `text` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Status transition commands populate/clear the relevant metadata. “Copy” creates
a new draft and does not copy assignments, acknowledgements, or release
requests.

A constraint/trigger requires start and end to fall on the same
`Australia/Melbourne` local date. The MVP accepts Monday-Friday shifts only;
weekend and overnight shifts are prohibited.

### `shift_assignments`

| Column | Type | Rules |
|---|---|---|
| `id` | `uuid` | PK |
| `shift_id` | `uuid` | FK `shifts`, required |
| `staff_id` | `uuid` | FK `staff`, required |
| `counts_toward_staffing` | `boolean` | generated/derived true only for `regular` |
| `status` | `assignment_status` | required, defaults `assigned` |
| `assigned_by` | `uuid` | FK `staff`, required |
| `assigned_at` | `timestamptz` | required |
| `removed_by` | `uuid` | nullable FK `staff` |
| `removed_at` | `timestamptz` | nullable |
| `removal_reason` | `text` | nullable |
| `availability_overridden` | `boolean` | required, defaults false |
| `override_reason` | `text` | nullable |
| `created_at`, `updated_at` | `timestamptz` | required |

Use a partial unique index on `(shift_id, staff_id)` where
`status = 'assigned'`. When `availability_overridden` is true, require a
non-blank reason. Only availability failures are overridable; inactive,
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
| `reason` | `text` | required, non-blank |
| `status` | `release_request_status` | required, defaults `pending` |
| `submitted_at` | `timestamptz` | required |
| `resolved_at` | `timestamptz` | nullable |
| `resolved_by` | `uuid` | nullable FK `staff` |
| `resolution_note` | `text` | nullable |
| `replacement_assignment_id` | `uuid` | nullable FK `shift_assignments` |
| `created_at`, `updated_at` | `timestamptz` | required |

Use a partial unique index on `assignment_id` where `status = 'pending'`.
Employee inserts derive `staff_id` from the current linked profile and validate
assignment ownership. Only a supervisor command resolves requests. Approval and
assignment removal/replacement occur in the same transaction.

Approve-and-remove or approve-and-replace sets the selected request to
`approved`. The outcome when an assignment changes for another reason remains
open in `docs/OPEN_QUESTIONS.md`. Confirmed request transitions, assignment
changes, and audit events must be atomic.

### `audit_events`

Append-only system history.

| Column | Type | Rules |
|---|---|---|
| `id` | `bigint generated always as identity` | PK |
| `occurred_at` | `timestamptz` | required |
| `actor_staff_id` | `uuid` | nullable FK `staff` |
| `action` | `text` | required, controlled action code |
| `shift_id` | `uuid` | nullable FK `shifts` |
| `subject_staff_id` | `uuid` | nullable FK `staff` |
| `release_request_id` | `uuid` | nullable FK `release_requests` |
| `reason` | `text` | nullable |
| `details` | `jsonb` | required, defaults `{}` |

The actor can be null for bootstrap/system actions. `details` should contain
only relevant before/after fields and must never contain Auth tokens, password
data, or unrestricted private notes. Audit writes come from triggers or trusted
commands, never direct browser inserts.

## Views and database functions

Prefer views/functions that return the minimum columns required.

### Helper functions

- `current_staff_id()` — linked active staff ID for `auth.uid()`, or null.
- `is_supervisor()` — true only for linked, active supervisor.
- `local_shift_date(shift_id)` — Melbourne date.

Implement helpers as stable SQL security-definer functions with a fixed
`search_path`, schema-qualified objects, and no public execute permission unless
needed by clients.

### Query functions/views

- `evaluate_staff_for_shift(p_shift_id, p_staff_id)` returns eligibility,
  availability, overlap, `is_assignable`, `requires_override`, and reason codes.
- `available_staff_for_shift(p_shift_id)` returns one row per active eligible
  staff member plus structured reason data; supervisors only.
- `supervisor_weekly_roster(p_week_start, p_location_id, p_activity_type_id)`
  returns shift cards and computed staffing counts.
- `employee_schedule(p_from, p_to)` returns only the caller’s published,
  currently assigned shifts.
- `scheduled_hours_report(p_from, p_to, p_statuses default
  array['published'], p_assignment_statuses default array['assigned'])`
  returns shift rows and duration minutes for supervisors; the frontend creates
  CSV.

The report should calculate `extract(epoch from (ends_at - starts_at))/60`.
Do not trust a stored duration. Default scope is published, non-cancelled shifts
with currently active assignments. Draft, cancelled, and removed records
require an explicit supervisor filter.

### Command functions

- `assign_staff(p_shift_id, p_staff_id, p_override_reason default null)`
- `edit_shift(p_shift_id, p_expected_updated_at, p_patch,
  p_assignment_override_reasons default '{}')`
- `remove_assignment(p_assignment_id, p_reason)`
- `replace_assignment(p_assignment_id, p_new_staff_id, p_reason,
  p_override_reason default null)`
- `deactivate_staff(p_staff_id)`
- `publish_shift(p_shift_id)`
- `cancel_shift(p_shift_id, p_reason)`
- `acknowledge_assignment(p_assignment_id)`
- `submit_release_request(p_assignment_id, p_reason)`
- `resolve_release_request(...)`

Each command checks the caller, locks relevant records, enforces invariants,
writes all changes, and produces audit events in one transaction. Revoke
function execution from `public`/`anon` and grant only to `authenticated` where
the function performs its own authorisation.

`edit_shift` is the only browser-accessible way to mutate an existing shift. It
uses `p_expected_updated_at` for stale-edit detection and accepts only an
allowlisted typed patch. It locks the shift and assignments; validates
Monday-Friday same-day timing and status; rechecks active status,
eligibility, overlap, and availability; requires per-assignment reasons for
permitted availability overrides; resets acknowledgements when required;
synchronises release requests; and audits the transaction.

`deactivate_staff` locks the staff row and rejects deactivation while that
person has an active assignment on a draft or published shift with
`ends_at > now()`. The supervisor UI lists those assignments so they can be
removed or replaced first.

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

- Supervisors read and create shifts. Revoke direct `UPDATE`/`DELETE` from
  browser roles; existing shifts change only through protected commands,
  including mandatory transactional `edit_shift`.
- Employee shift reads require a currently assigned row belonging to the caller
  and `shift.status = 'published'`.
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
- check `ends_at > starts_at` and `required_staff_count >= 1` for shifts;
- check shift boundaries share one Melbourne-local date;
- partial unique active assignment `(shift_id, staff_id)`;
- partial unique pending release request per assignment;
- check override reason is present exactly when required;
- indexes on availability `(staff_id, weekday)` and
  `(staff_id, local_date)`;
- indexes on `shifts(starts_at, status)`, `shift_assignments(staff_id, status)`,
  and audit foreign keys/timestamp.

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
- weekend and Melbourne-local overnight shifts fail;
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
