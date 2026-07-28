# Milestone 5 Review

## Scope completed

Milestone 5 is limited to release requests, supervisor resolution, replacement,
and complete audit history.

Employees can:

- request release from their own active assignment on a published shift before
  it starts or while it is in progress;
- provide a required reason and optional explanatory note;
- see the server-recorded submission time and complete request history;
- remain assigned until a supervisor explicitly approves the request.

Supervisors can:

- review pending requests and open the related shift and assignment;
- reject a request with a reason;
- approve and remove the assigned employee;
- approve and replace the employee in one atomic database workflow;
- see database-evaluated replacement conflicts and provide a reason for an
  eligible availability override;
- inspect append-only audit history.

The employee and supervisor pages include clear status badges, confirmations,
replacement conflict explanations, loading/empty/error/success states, and a
mobile-safe layout. Reporting, calendar integration, notifications, attendance,
timesheets, payroll, and other later milestones were not implemented.

## Corrected status semantics

`release_request_status` contains:

- `PENDING`: awaiting supervisor action;
- `APPROVED`: explicitly completed through approve-and-remove or
  approve-and-replace;
- `REJECTED`: explicitly rejected by a supervisor;
- `CANCELLED`: made obsolete by an independent assignment removal,
  assignment replacement, or shift cancellation.

Only `PENDING` can transition, and only to one of the three terminal statuses.
Submitted details and terminal requests are immutable. Employee-initiated
cancellation is not implemented.

Independent removal, replacement, and shift cancellation write a clear
system-generated resolution reason and exactly one
`RELEASE_REQUEST_CANCELLED` event. Unpublishing or editing a shift retains the
pending request.

## Schema and migration changes

Migration `202607270005_milestone_5_release_requests_audit.sql` adds:

- the four-value `release_request_status` enum;
- `release_requests`, linked to the exact historical assignment;
- a partial unique index permitting only one pending request per assignment;
- owner, status, and submission indexes;
- request shape and immutable-transition protections;
- generic entity, release-request, reason, and minimal before/after fields on
  `roster_audit`;
- audit lookup indexes and normalisation for existing audit writers;
- release-request projections and protected workflow functions.

Historical assignments are preserved. Removal records actor, timestamp, and
reason. Replacement additionally links the original assignment to the new one.

### Migration handling decision

The Milestone 5 migration was corrected in place. Inspection showed:

- `git ls-files --error-unmatch` returned no tracked file;
- `git log --all --` returned no history for the migration;
- `git status` showed the migration as untracked;
- no local Supabase project reference existed;
- the prior review recorded no hosted migration or deployment.

This is evidence that the migration was uncommitted, unshared, and undeployed.
No shared migration history was rewritten.

## RLS and database function changes

`release_requests` has RLS enabled with own-only employee selection and
supervisor selection. Browser roles have no direct insert, update, or delete
grant on requests, assignments, or audit rows.

The browser contract uses:

- `submit_release_request`
- `employee_release_request_assignments`
- `employee_release_requests`
- `supervisor_release_requests`
- `release_request_candidates`
- `reject_release_request`
- `approve_release_request_remove`
- `approve_release_request_replace`
- `supervisor_audit_history`

Submission derives the employee through `auth.uid()` and `current_staff_id()`;
it accepts no employee ID. Supervisor functions re-check the authenticated
active supervisor role. Internal locking, temporal-validation, and automatic
cancellation helpers are not executable by browser roles. All affected
security-definer functions set an empty `search_path` and schema-qualify
objects.

Replacement repeats active-status, eligibility, duplicate, overlap, and
availability checks inside the transaction. Only availability conflicts can be
overridden, and an explicit non-empty reason is required.

## In-progress submission rule

The database permits submission only when:

- the caller owns the active assignment;
- the shift is `PUBLISHED`;
- the assignment is not removed;
- database `now()` is earlier than the shift's end instant calculated from its
  local date and end time in `Australia/Melbourne`.

Submission works before the start and during the shift. It fails at the exact
end instant and afterwards. The browser clock is not trusted. The employee page
explains that the workflow can be used after becoming sick or needing to leave
early.

This is a staffing-release workflow only. It preserves the request, historical
assignment, removal time, reason, and audit history, but does not track partial
attendance or worked hours.

## Transaction and lock design

All workflows that can change the same request or assignment use one lock order:

1. acquire a transaction-scoped advisory lock for the shift;
2. lock and re-check the original active assignment;
3. lock and re-check the pending request;
4. where needed, take the existing replacement-employee advisory lock;
5. re-evaluate replacement conflicts;
6. perform staffing, request, and audit writes.

Approval-and-replace then:

1. reads the original `assignment_kind` from the locked row;
2. inserts the replacement with that database-derived kind;
3. marks and links the original assignment as removed;
4. resolves the request as `APPROVED`;
5. writes assignment-created, optional override, assignment-removed,
   replacement, and release-approval audit rows.

The approval RPC no longer accepts an assignment kind from the browser.
Ordinary replacement defensively rejects a mismatched requested kind and uses
the original kind. Consequently regular replacement preserves regular coverage,
while shadowing replacement remains shadowing and does not increase regular
staffing.

Approval functions perform their own staffing updates and approval audit writes;
they do not call the independent-change cancellation path. Ordinary removal,
ordinary replacement, and shift cancellation call a protected cancellation
helper instead.

Every RPC is one PostgreSQL transaction. Any exception rolls back staffing,
request, and audit writes. A database test installs a transaction-scoped
failure trigger after the replacement insert and original-assignment update and
proves that the request, both assignments, and audit history all roll back.

## Concurrency evidence

`supabase/tests/concurrent_release_requests.ps1` opens genuine simultaneous
database sessions. A deterministic first session holds the same shift advisory
lock briefly so each second operation overlaps rather than running
incidentally in sequence.

The suite proves:

- two supervisor resolutions produce one terminal result and one terminal
  audit event;
- submission racing direct removal leaves one `CANCELLED` request, one removed
  assignment, and one cancellation audit;
- approval racing shift cancellation leaves one `CANCELLED` request, a
  cancelled shift, the consistent assignment lifecycle, and no approval audit;
- two approval-and-replace attempts create one replacement, one `APPROVED`
  request, and one replacement/approval audit set.

The losing operations fail without partial writes, duplicate replacements,
conflicting states, or contradictory audits.

## Audit coverage

Audit records contain actor, action, entity type and ID, timestamp, reason where
relevant, related shift/assignment/request/employee identifiers, and minimal
before/after data where appropriate.

Covered actions include:

- availability: `AVAILABILITY_CREATED`, `AVAILABILITY_UPDATED`,
  `AVAILABILITY_REMOVED`;
- shifts: `SHIFT_CREATED`, `SHIFT_EDITED`, `SHIFT_PUBLISHED`,
  `SHIFT_UNPUBLISHED`, `SHIFT_CANCELLED`;
- assignments: `EMPLOYEE_ASSIGNED`, `EMPLOYEE_REMOVED`,
  `EMPLOYEE_REPLACED`;
- override: `ASSIGNMENT_OVERRIDDEN`;
- acknowledgement: `ASSIGNMENT_ACKNOWLEDGED` and reset history;
- requests: `RELEASE_REQUEST_CREATED`, `RELEASE_REQUEST_APPROVED`,
  `RELEASE_REQUEST_REJECTED`, `RELEASE_REQUEST_CANCELLED`.

Employees cannot query supervisor audit history or directly mutate audit rows.

## Tests and exact results

Final successful verification:

- `git diff --check` — exit 0.
- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; TypeScript project build passed.
- `npm run test` — exit 0; **7 files and 42 tests passed**.
- `npm run build` — exit 0; **105 modules transformed** and production assets
  emitted. Vite reported the existing non-failing 519.44 kB chunk warning.
- `supabase db reset` — exit 0; all six migrations and synthetic seed applied
  from scratch.
- `supabase test db` — exit 0; **5 SQL files and 211 assertions passed**.
- `npm run db:test:concurrency` — exit 0; all **4 simultaneous-session races
  passed**.
- `run_m3_browser.ps1` — exit 0; **2 Playwright tests passed**.
- `run_m4_browser.ps1` — exit 0; **3 Playwright tests passed**.
- `run_m5_browser.ps1` — exit 0; **2 Playwright tests passed**.
- privilege/RLS catalog inspection — exit 0; RLS was enabled and anonymous plus
  authenticated direct mutation was false for `release_requests`,
  `shift_assignments`, and `roster_audit`; unsafe release-related
  security-definer search paths: **0**; internal lock/cancellation execution:
  false.
- secret scan — exit 0; no private keys, service-role keys, `sb_secret` tokens,
  or credential-bearing PostgreSQL URLs found.

The SQL suite covers pre-start, in-progress, exact-end, and after-end
submission; unchanged assignment on submission; duplicate prevention;
unassigned denial; employee privacy; explicit approval and rejection; external
cancellation; unpublication retention; kind preservation; staffing counts;
cancelled histories; exact audit counts; atomic rollback; and browser-role
mutation/function denial.

The browser suite verifies the in-progress guidance, Cancelled history badge,
submission, continued assignment visibility, supervisor request and shift
details, replacement conflict state, controlled replacement, approval status,
audit history, and 390 px mobile layout.

During development, one clean reset returned a transient HTTP 502 after all
migrations and seed had applied; service health recovered, and two later clean
resets completed with exit 0. The first concurrency assertion expected only one
valid loser error message, and the first browser wording locator did not match
the implemented sentence. Both test defects were corrected and the complete
final suites above passed; no application assertion was waived.

## Known limitations

- Employees cannot cancel their own pending request.
- Partial attendance and worked hours are not tracked. How to report partial
  hours remains a future supervisor decision for Milestone 6; no reporting was
  implemented here.
- The audit UI returns the latest 200 filtered events. The protected query
  permits up to 500; pagination is not required for the approximately ten-user
  MVP.
- Confirmation for submission, rejection, and removal uses native browser
  dialogs; replacement uses an in-page conflict-rich form.
- The production bundle retains the existing non-failing chunk-size warning.
- No hosted migration or public deployment was performed.

## Manual verification checklist

- [x] Submit a request for an upcoming published shift.
- [x] Verify the page explains in-progress sickness/early-leave use.
- [x] Confirm submission records the reason and note but does not remove the
      employee.
- [x] Confirm a Cancelled historical request displays its reason and badge.
- [x] Open the pending queue as a supervisor and inspect the related shift.
- [x] Reject a request with a reason.
- [x] Approve a request by removing the employee.
- [x] Approve a request with a conflict-checked replacement.
- [x] Confirm replacement preserves regular or shadowing classification.
- [x] Inspect approval, cancellation, assignment, and override audit events.
- [x] Verify the employee Requests page at 390 x 844 without overflow.
- [x] Verify employee request privacy and direct request/audit mutation denial.

## Final verdict

**Approved and closed.** Release submission is available before and during a
shift but not at or after its Melbourne-local end. Only explicit approval
produces `APPROVED`; independent roster changes produce `CANCELLED`.
Replacement classification is database-derived, resolution races are
serialised, failed operations roll back completely, and the full audit history
is supervisor-readable and browser-immutable.
