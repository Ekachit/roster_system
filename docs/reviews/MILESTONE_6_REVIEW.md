# Milestone 6 Review

## Final verdict

**Approved and closed after remediation on 28 July 2026.**

Approval followed successful CSV formula-injection hardening, real downloaded
CSV verification, Melbourne default-week tests, desktop/mobile role checks,
fresh database replay, all SQL tests, and Milestone 3–5 browser regressions.

This milestone remains limited to current scheduled-hours reporting and CSV
export. Attendance entry, actual worked hours, payroll, timesheet import,
notifications, calendar integration, and deployment were not implemented.

## Scope completed

The supervisor can select an inclusive Melbourne-local start and end date plus
optional employee, location, and activity-type filters. The report displays:

- employee;
- shift count;
- total scheduled hours;
- detailed date, time, duration, location, activity, shift-status, and
  assignment-status rows.

The same applied filters produce a downloadable UTF-8 CSV. The page now states:

> This report shows current scheduled hours for published shifts with active
> assignments. It does not represent attendance, actual worked hours or
> payroll.

Removed assignments are excluded. If someone is removed after becoming sick or
leaving early, they contribute no hours to this current report. The historical
removal remains available in audit history.

## Calculation rules

- The date range is inclusive and applies to `shifts.local_date`, the stored
  `Australia/Melbourne` roster date.
- Only `PUBLISHED` shifts with assignments whose `removed_at` is null are
  included.
- `CANCELLED` and `DRAFT` shifts are excluded.
- Removed assignments remain stored with removal history, but are excluded
  from shift counts, scheduled-hour totals, report details, and CSV.
- A replacement contributes only the replacement's active assignment, not the
  removed original.
- Regular and shadowing active assignments both represent scheduled time and
  are included.
- Duration is derived on every report query; no stored duration is trusted.
- PostgreSQL converts `(local_date + start_time)` and
  `(local_date + end_time)` through `Australia/Melbourne`, subtracts the
  resulting instants, and returns rounded integer minutes.
- The UI sums integer minutes and displays whole hours/minutes, avoiding binary
  floating-point display errors.
- Existing roster constraints require same-day shifts with end after start.

## Melbourne default-week behavior

`melbourneScheduleWeek(now)` is the single default-range helper. It first
derives the ISO date using an explicit `Australia/Melbourne` formatter, then
performs ISO-date arithmetic at UTC noon to find Monday and the following
Sunday. It never uses an unqualified browser-local calendar date.

Automated coverage verifies:

- a Melbourne Monday;
- a Melbourne Sunday;
- instants immediately before and after the Sunday-to-Monday boundary;
- Melbourne daylight-saving time;
- an `America/Los_Angeles` system/browser timezone;
- an instant that is Sunday in Los Angeles but Monday in Melbourne.

The real Playwright context also runs with `timezoneId:
'America/Los_Angeles'` and confirms the report inputs still default to the
current Melbourne Monday-to-Sunday week.

## CSV schema

The browser generates UTF-8 CSV with a byte-order mark, CRLF record endings,
deterministic column order, Melbourne 24-hour times, and integer-minute
duration:

| Column | Value |
|---|---|
| `Employee name` | Approved staff full name |
| `Employee email` | Approved staff email |
| `Date` | ISO `YYYY-MM-DD` Melbourne-local shift date |
| `Start time` | Melbourne 24-hour `HH:MM` |
| `End time` | Melbourne 24-hour `HH:MM` |
| `Duration` | Integer minutes |
| `Location` | Location name |
| `Activity type` | Activity-type name |
| `Shift status` | `PUBLISHED` |
| `Assignment status` | `ASSIGNED` |

The filename is
`scheduled-hours_<start-date>_to_<end-date>.csv`.

Shift notes, supervisor-only staff notes, availability data, override/removal
reasons, release-request data, audit data, and internal IDs are not written to
CSV.

## CSV formula-injection protection

All headers and exported values pass through one function,
`serializeCsvCell`. Numeric duration remains numeric. For every text value the
function:

1. checks the first character for `=`, `+`, `-`, `@`, tab, carriage return,
   line feed, or the full-width equivalents `＝`, `＋`, `－`, and `＠`;
2. prefixes dangerous values with an ASCII apostrophe before any delimiter
   escaping;
3. encloses fields containing commas, quotes, tabs, CR, or LF in double quotes;
4. doubles embedded quotes.

The apostrophe strategy is appropriate for this human-viewed Microsoft Excel
export: Excel treats the cell as text instead of executing a formula. It does
change the raw value seen by programmatic CSV importers, and some spreadsheet
programs may display the apostrophe. No CSV sanitisation strategy is universally
safe across every spreadsheet program and programmatic importer. Consumers
requiring lossless machine data should use a typed non-CSV interface rather
than removing the protection.

Tests cover malicious-looking employee names, employee emails, locations,
activity types, and status-like values beginning with every supported ASCII
and full-width prefix. Ordinary text, numbers, commas, quotes, and internal line
breaks remain correct.

## Security controls

- `/supervisor/reports/hours` is under the existing supervisor React route
  guard.
- `scheduled_hours_report` is a `SECURITY DEFINER` PostgreSQL function with an
  empty fixed `search_path` and schema-qualified objects.
- It calls `require_supervisor()` before filter validation or data reads.
- `PUBLIC` and `anon` cannot execute it. `authenticated` may invoke it, but an
  employee receives `Supervisor access required` and no response data.
- All report filters are applied inside PostgreSQL. The employee client never
  loads unrestricted shift/assignment data.
- Authenticated browser roles have no direct `SELECT` privilege on `shifts` or
  `shift_assignments`.
- Report filter options request only staff `id`, `full_name`, and `role`; no
  private notes are requested.
- CSV is generated only from the authorized, filtered RPC result.
- No service-role key, paid service, or serverless function is used.

Fresh local-service verification also exposed that
`[auth.email] enable_signup = false` disabled the email provider itself after
a cold Supabase restart.
The config now keeps global `[auth] enable_signup = false` while enabling the
existing email provider. Live container inspection confirmed
`GOTRUE_DISABLE_SIGNUP=true` and `GOTRUE_EXTERNAL_EMAIL_ENABLED=true`; a direct
public signup attempt was denied with HTTP 422. This restores the previously
approved email/password sign-in method without enabling registration.

## Real browser evidence

The Milestone 6 Playwright suite runs against the actual local Vite/Supabase
application with synthetic fixtures and a generated password held only in the
process environment.

Desktop supervisor verification:

- signed in and opened **Reports**;
- confirmed the clarified current-scheduled-hours copy;
- confirmed Melbourne default-week values while the browser timezone was Los
  Angeles;
- applied employee, location, and activity filters separately and together;
- verified an explicit empty-result state;
- verified the report returned exactly three active published fixture shifts:
  two regular and one shadowing;
- verified cancelled, draft, and removed fixture shift IDs were absent;
- changed a filter after running and confirmed export was disabled until the
  report was rerun;
- downloaded through the real browser action;
- read the downloaded bytes from disk;
- confirmed UTF-8 BOM bytes `EF BB BF`, CRLF endings, exact filename, exact
  ten-column order, 24-hour times, integer-minute duration, quoting, and
  apostrophe formula protection;
- parsed every CSV record and confirmed ten cells per row;
- confirmed shift/private notes, availability, release-request data, audit
  data, removal reason, and internal IDs were absent.

Mobile and employee verification:

- supervisor report completed at 390 × 844 with no document-level horizontal
  overflow;
- synthetic employee navigation contained no Reports link;
- direct employee navigation failed closed with **Unauthorised**;
- an authenticated employee PostgREST invocation returned HTTP 403,
  `Supervisor access required`, and no report employee name or ID.

## Tests and exact final results

- `git diff --check` — exit 0; no whitespace errors. Git emitted only
  informational LF-to-CRLF working-copy warnings.
- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; strict TypeScript project build passed.
- `npm run test` — exit 0; **10 files and 66 tests passed**.
- `npm run build` — exit 0; **107 modules transformed** and production assets
  emitted. Vite reported a non-failing 528.14 kB main-chunk warning.
- `supabase db reset` — exit 0; all seven migrations and the synthetic seed
  applied from scratch.
- `supabase test db` — exit 0; **6 SQL files and 229 assertions passed**.
- `npm run test:browser:m6` through `run_m6_browser.ps1` — exit 0;
  **3 Playwright tests passed in 19.1 seconds**.
- `npm run test:browser:m3` through `run_m3_browser.ps1` — exit 0;
  **2 Playwright tests passed in 34.4 seconds**.
- `npm run test:browser:m4` through `run_m4_browser.ps1` — exit 0;
  **3 Playwright tests passed in 9.8 seconds**.
- `npm run test:browser:m5` through `run_m5_browser.ps1` — exit 0;
  **2 Playwright tests passed in 14.3 seconds**.
- RLS/function privilege inspection — exit 0; `staff`,
  `staff_private_notes`, `shifts`, and `shift_assignments` reported RLS
  enabled; the report reported `security_definer = true`,
  `search_path=""`, `PUBLIC execute = false`, `anon execute = false`, and
  `authenticated execute = true`; authenticated direct shift/assignment
  selection and anonymous private-note selection were false.
- Auth configuration and signup check — exit 0; email login enabled, global
  signup disabled, direct signup denied with HTTP 422.
- Secret scan — exit 0; no private keys, service-role assignments,
  `sb_secret` tokens, or credential-bearing PostgreSQL URLs were found.

## Remediation findings and corrections

- Delimiter quoting did not prevent spreadsheet formula injection. One central
  apostrophe-before-quoting serializer now protects every exported text cell.
- The default date range was composed from correct helpers but lacked a single
  contract and timezone-boundary tests. `melbourneScheduleWeek` and five tests
  now provide that contract.
- Milestone 6 had no real browser evidence. A dedicated fixture, runner, and
  three-test Playwright suite now verify the complete workflow.
- The first browser pass found a test locator selecting a hidden option instead
  of the visible row; the assertion now targets the report heading.
- The first mobile browser pass exposed real document-level overflow. Report
  grid, form, select, summary, and detail containers now use explicit
  `min-width: 0` containment while their tables retain local horizontal
  scrolling.
- A literal full-width test character was converted to `???` by the Windows
  PowerShell SQL pipeline. The fixture now creates it with PostgreSQL
  `chr(65309)`, making the test encoding-independent.
- A cold local Supabase restart exposed the disabled email provider described
  above. Configuration and public-registration denial were both verified.
- Local Supabase Vector log collection repeatedly restarted because Docker
  Desktop was not exposed on the documented Windows TCP endpoint. Two resets
  consequently returned transient HTTP 502 after migrations and seed had
  applied, and one combined reset command stalled. Exact workspace reset/Vite
  processes were inspected and stopped, the local stack was restarted, and
  the final fresh reset and every required suite completed with exit 0.

No application assertion was waived.

## Deferred actual-attendance requirement

A future attendance milestone may allow a supervisor to record or confirm:

- actual start time;
- actual end time or total minutes worked;
- attendance outcome such as completed, absent, sick, or left early;
- an optional reason or note;
- the recording supervisor and timestamp;
- immutable audit history.

Actual duration must come from that explicit attendance record. It must not be
inferred automatically from assignment `removed_at`, release-request submission
time, or request approval time.

This future requirement is recorded only. No attendance or actual-hours fields,
tables, commands, or UI were added in Milestone 6.

## Remaining limitations

- Scheduled hours are current rostered hours, not attendance or worked time.
- Someone removed after becoming sick or leaving early contributes no hours to
  this current report; audit history preserves the removal, but only a future
  explicit attendance workflow can represent partial work.
- The apostrophe mitigation prioritizes human viewing in Excel and changes raw
  dangerous-looking values for programmatic importers. Other spreadsheet
  programs may display the apostrophe.
- CSV `Duration` is integer minutes. Directly inserted legacy times with
  seconds are rounded to the nearest minute.
- Existing MVP roster rules prohibit overnight shifts.
- The production bundle retains a non-failing chunk-size warning.
- Windows local analytics/log collection requires the Docker daemon TCP
  setting documented by Supabase; it is not required for application behavior.
- No hosted migration or production deployment was performed; deployment
  remains Milestone 7.

## Manual verification checklist

- [x] Supervisor signed in and opened Reports.
- [x] Melbourne default week verified in a Los Angeles browser timezone.
- [x] Employee, location, and activity filters verified separately/together.
- [x] Cancelled, draft, and removed assignments confirmed absent.
- [x] Regular and shadowing active assignments confirmed present.
- [x] Empty results displayed clearly.
- [x] Export disabled after unapplied filter changes.
- [x] Real CSV downloaded and its bytes/content/filename parsed.
- [x] Formula prefixes, commas, quotes, and internal CRLF verified.
- [x] Sensitive notes, workflow data, audit data, and IDs confirmed absent.
- [x] Supervisor report verified at 390 × 844 without page overflow.
- [x] Employee Reports navigation absent and direct route unauthorized.
- [x] Employee report RPC denied without response data.
