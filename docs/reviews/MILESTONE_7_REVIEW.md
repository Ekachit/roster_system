# Milestone 7 Review

## Review status

Milestone 7 implementation and local release verification completed on
28 July 2026. On 29 July 2026, the owner-provisioned Supabase production target
was verified and the complete release gate was rerun against PostgreSQL 17. The
repository is deployment-ready, but it is **not yet deployed** at the point of
this release commit: hosted migrations, production Auth provisioning, Netlify
creation, and live smoke tests remain controlled release actions.

## Final scope

Milestone 7 includes only:

- static Netlify Free configuration and SPA routing;
- production build/environment validation and security headers;
- Supabase production, Auth, migration, provisioning, RLS, secret, backup,
  restore, and rollback documentation;
- final route, database, privacy, mutation, input, CSV, and audit hardening;
- one complete synthetic end-to-end MVP workflow;
- responsive, keyboard, labels/errors, contrast, focus, state, and destructive
  confirmation review;
- production and post-deployment checklists;
- dependency and secret review.

No calendar integration, email/SMS, payroll, timesheet import, clock-in, paid
monitoring, paid analytics, custom server, or Netlify Function was added.

## Deployment preparation

`netlify.toml` now defines:

- Node 22;
- `npm run build`;
- `dist`;
- `/* -> /index.html` with status 200 for BrowserRouter deep links;
- a CSP restricted to the site and Supabase HTTPS/WSS;
- HSTS, frame denial, `nosniff`, no-referrer, and restricted permissions;
- no-cache HTML and immutable fingerprinted assets.

The Vite production build fails closed when either public Supabase variable is
missing, when the production URL is not HTTPS, or when an obvious
secret/service-role value is supplied.

`docs/NETLIFY_DEPLOYMENT.md` and `docs/PRODUCTION_CHECKLIST.md` cover production
project creation, redirect URLs, Auth settings, migrations, first supervisor,
subsequent users, RLS/grant inspection, Netlify environment contexts, Deploy
Preview isolation, logical exports, restore rehearsal, smoke tests, and
rollback.

## Security findings and fixes

| Finding | Risk | Fix and evidence |
|---|---|---|
| Audit rows had no browser DML grants but no database-level mutation trigger. | A privileged or future mistaken SQL path could rewrite history. | Added `prevent_roster_audit_mutation` and a `BEFORE UPDATE OR DELETE` trigger. pgTAP proves owner-level update/delete rejection and browser denial. |
| A draft shift could change date/time/location/activity after assignment without re-evaluating the active assignment. | A protected supervisor command could leave an inactive/ineligible/unavailable or overlapping assignment. | Added a table trigger that blocks material scheduling/eligibility changes while any active assignment exists. Supervisors must remove/replace first; title, notes, and required staffing remain editable. |
| Browser-controlled text relied on partial UI limits. | Oversized values could create data bloat or inconsistent clients. | Added database maximum lengths for staff, private notes, reference names, availability notes, shift title/notes, assignment reasons, release fields, and audit reasons; aligned HTML limits. |
| Obsolete `is_shift_published` remained executable by authenticated users after its employee policies were removed. | A guessed UUID could reveal one bit of shift metadata. | Revoked authenticated execution; pgTAP verifies the grant is absent. |
| Production configuration could silently build without Supabase values or with an obvious privileged key. | Broken deployment or service-role exposure. | Production Vite validation now rejects missing/non-HTTPS/obvious privileged values; runtime rejects obvious secret/service-role keys. |
| Staff/reference deactivation and ordinary roster removal/replacement lacked a final explicit confirmation. | Accidental destructive workflow. | Added confirmations while preserving reason requirements and historical rows. |
| Local Supabase analytics/log collection repeatedly restarted under the current Windows Docker setup. | Transient Auth 502s made browser verification flaky. | Disabled unused local analytics, recreated only the disposable local stack, and made the E2E runner require a verified clean migration state plus three consecutive Auth health responses. |
| Development audit contained five ESLint/minimatch/brace-expansion findings. | Vulnerable development dependency graph. | Updated ESLint and compatible plugins/parser; those findings are gone. |
| React Router reports a high RSC-action CSRF advisory with no non-RSC fixed latest release. | Potential server action execution in React Server Components mode. | The application is a static BrowserRouter SPA with no RSC, SSR, loaders, actions, server routes, or action endpoint, so the affected path is absent. CSP and static hosting further constrain execution. The remaining audit result is recorded as a known upstream limitation, not silently waived. |

Existing controls re-reviewed and retained:

- operational identity continuously requires linked Auth UUID, normalized Auth
  email, active approved staff row, and protected role;
- employee supervisor routes fail closed, but RLS/RPC authorization remains the
  real boundary;
- all public base tables use RLS;
- shift/assignment base tables have no browser read/mutation grants;
- employees see only own availability, schedule, acknowledgements, and requests;
- co-worker projection returns names only;
- supervisor notes remain in a supervisor-only table/view path;
- protected functions derive actors from `auth.uid()`, use fixed empty
  `search_path`, and repeat authorization;
- assignment, replacement, request resolution, and audit writes are atomic;
- CSV excludes notes, availability, request/audit data, reasons, and internal
  IDs and protects spreadsheet formula prefixes;
- no browser service-role/Auth-admin path exists.

## End-to-end results

The Milestone 7 Playwright workflow uses generated credentials and synthetic
people only. It verifies, in order:

1. approved employee sign-in;
2. recurring Sunday availability submission;
3. timed date-specific unavailability;
4. supervisor shift creation;
5. correct `DATE_SPECIFIC_UNAVAILABLE` result;
6. reasoned supervisor availability override and regular assignment;
7. publication;
8. employee mobile schedule/detail and acknowledgement;
9. release request without automatic removal;
10. supervisor atomic replacement;
11. release-approval audit actor/reason;
12. replacement-only three-hour report total;
13. real downloaded CSV filename/content/duration and removed-employee
    exclusion;
14. absent employee supervisor navigation, direct-route denial, direct shift
    mutation denial, and direct report-RPC denial.

It also checks 390 x 844 employee overflow, 1440 x 1000 supervisor workflow,
labels through accessible queries, and first-Tab Skip to content focus.

Final result: `npm run test:e2e` exited 0; **1 complete workflow passed in
15.2 seconds** (60.7 seconds for reset, verification, fixture creation, health
gates, browser test, and cleanup). The final local reset replayed every
migration and seed but the CLI received a post-commit gateway 502 while
restarting services. The runner verified migration `202607280002`, the required
seed, and a clean M7 fixture state before continuing. No application assertion
was waived.

## Responsive and accessibility review

- Supervisor roster uses seven columns at `xl`, two columns at `md`, and a
  single-column agenda below that.
- Employee schedule, availability, requests, and report regression views use
  mobile-safe wrapping/scroll containment.
- Native links, buttons, inputs, selects, textareas, fieldsets, dialogs, and
  forms remain keyboard operable.
- Skip to content is first in the keyboard order and has a visible focused
  state.
- Every changed form control has a label; required/max constraints are native,
  server errors use `role="alert"`, success/loading use live status semantics,
  and empty states explain next steps.
- Global `focus-visible` outlines use a 2 px blue outline with offset.
- Reviewed Tailwind pairs use dark slate/blue/green/amber/red foregrounds on
  white or corresponding 50/100 backgrounds; status text is paired with words
  and not colour-only.
- Destructive changes require reason and/or confirmation, including
  availability deletion, staff/reference deactivation, shift cancellation,
  assignment removal/replacement, release resolution, and override.

Physical mobile hardware and an external automated accessibility scanner were
not available; the responsive evidence uses installed headless Edge.

## Commands run and exact results

Production release follow-up on 29 July 2026:

- the confirmed Supabase project uses PostgreSQL 17, while the reviewed local
  configuration still selected PostgreSQL 15;
- `supabase/config.toml` was aligned to PostgreSQL 17 before the final release
  gate so the full migration and database test replay uses the production major
  version;
- linking the production project generated connection metadata under
  `supabase/.temp/`, and the CLI update marker there had previously been
  tracked;
- `supabase/.temp/` is now ignored and the generated update marker is removed
  from version control so production-link metadata cannot enter a release
  commit;
- the linked target was verified as organisation `Roster System`, project
  `osaflyfzwtrxbvqkqgea`, Free plan, Oceania/Sydney, with no remote application
  migrations applied;
- `supabase db push --dry-run` listed exactly the eight reviewed migrations and
  no seed;
- the PostgreSQL 17 release gate passed: `npm ci`, lint, type checking, 66 unit
  and component tests, all eight migration/seed replay, 247 pgTAP assertions,
  all concurrency checks, and the complete Playwright workflow;
- a production build using only the confirmed project URL and publishable key
  passed, while the missing-variable build failed closed as expected;
- catalog inspection again found RLS on 13/13 public base tables, zero unsafe
  security-definer search paths, zero anonymous execution of security-definer
  functions, and zero inspected forbidden authenticated table grants;
- `git diff --check` and the credential-pattern scan passed. Both npm audit
  modes still report only the documented static-SPA-inapplicable React Router
  RSC advisory; no audit result was silently waived.

Final successful release gate:

- `git diff --check` — exit 0; no whitespace errors, informational
  LF-to-CRLF working-copy warnings only.
- `npm ci` — exit 0; **330 packages installed and 331 audited** from the final
  lockfile; one transitive `whatwg-encoding` deprecation notice and the two
  React Router audit findings were reported.
- `npm run lint` — exit 0; no warnings or errors.
- `npm run typecheck` — exit 0; strict TypeScript project build passed.
- `npm run test` — exit 0; **10 files, 66 tests passed**.
- `supabase stop --no-backup` — exit 0; disposable local services stopped and
  their local data was removed.
- `supabase start` — exit 0; a new local stack applied **all eight migrations**
  and the synthetic seed, and passed service health checks.
- `supabase test db` — exit 0; **7 SQL files, 247 assertions passed**.
- `npm run test:e2e` — exit 0; **1 complete Playwright workflow passed in
  19.5 seconds**.
- production `npm run build` with non-secret verification values — exit 0;
  Vite 7.3.6 transformed **107 modules** in 3.12 seconds and emitted
  `index.html` 0.46 kB, CSS 15.80 kB, and JavaScript 529.18 kB (148.23 kB
  gzip); the non-failing chunk-size warning remains.
- production `npm run build` with both browser variables deliberately absent —
  expected exit 1 with the exact missing-variable error for
  `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, proving fail-closed build
  validation.
- concurrency verification — exit 0; last-supervisor, duplicate assignment,
  overlapping assignment, conflicting replacement, acknowledgement, and all
  four release-request races passed with one valid terminal outcome.
- catalog/RLS/function inspection — exit 0; **13/13 public base tables** had
  RLS, zero security-definer functions had an unsafe search path, and all nine
  inspected direct mutation/private-table/obsolete-helper/trigger grants were
  false.
- secret scan — exit 0; **109 tracked or unignored files** checked with no
  private key, long `sb_secret_*` value, service-role-shaped JWT,
  credential-bearing PostgreSQL URL, or committed environment credential found.
- `npm audit` and `npm audit --omit=dev` — exit 1; **2 high findings** are the
  same React Router package/advisory chain for unused RSC action mode; no
  vulnerable ESLint development chain remains.
- `npm update @supabase/supabase-js postcss` — exit 0; seven dependency nodes
  changed, leaving Supabase JS 2.110.9 and PostCSS 8.5.24; lint, types, unit,
  build, and E2E were rerun against the resulting lockfile.
- `npm outdated` — exit 1; **9 packages** have a newer release, all outside the
  currently tested major-version constraints. No unreviewed major upgrade was
  applied during final hardening.

During implementation:

- the baseline `npm run lint`, `npm run typecheck`, and `npm run test` passed
  before changes (66 tests);
- the first ESLint 10 run enabled a new `set-state-in-effect` rule against the
  intentional loading-before-await fetch pattern; the rule is explicitly
  disabled with rationale while the rest of the updated ruleset remains active;
- first E2E run had an inexact `Roster` locator that matched the product title;
- another run encountered the local Auth gateway restart;
- later runs corrected a Playwright `selectOption` RegExp misuse and the
  expected duration label (`3 hr`);
- the final complete run passed without changing application assertions.

## Known limitations

- The production Supabase project exists, but hosted migrations, Auth
  provisioning, Netlify creation, the production URL, and live smoke results
  remain pending at the point of this release commit.
- Supabase Free requires owner-managed logical exports and can have
  provider-defined pause/retention behavior.
- Password provisioning/reset is manual without custom SMTP.
- Material draft shift schedule/location/activity changes require removing or
  replacing active assignments first.
- Shifts and availability cannot cross midnight.
- Scheduled hours are current rostered hours, not actual attendance/payroll.
- Audit UI is limited to the latest 200 matching events.
- Physical-device and external accessibility-scanner testing remain manual.
- The Vite main chunk retains a non-failing size warning.
- The upstream React Router RSC advisory remains reported despite the affected
  mode being absent.
- `npm outdated` reports newer major lines for nine development/build
  packages. The checked-in lockfile is the exact dependency set covered by
  this review.

## Deferred features

Still deferred:

- calendar integration;
- email/SMS notifications;
- payroll and timesheet import;
- actual attendance, clock-in/out, and geofencing;
- automatic allocation and employee-to-employee swapping;
- chat and native mobile applications;
- advanced/paid analytics and paid monitoring;
- multi-organisation support.

## Manual account-level steps

The user/production owner must:

1. create and secure the Supabase Free project;
2. link the CLI and review/push migrations without local seed;
3. configure email/password, disabled public sign-up, confirmations, Site URL,
   and redirect allowlist;
4. bootstrap the first supervisor and matching confirmed Auth user;
5. verify production RLS/grants with synthetic personas;
6. create the Netlify Free site connected to the reviewed branch;
7. add only the public Supabase URL and publishable/anon key;
8. configure a synthetic preview project or non-functional preview values;
9. perform and retain an encrypted logical backup;
10. deploy, record the URL/deploy/commit, and complete every production smoke
    check.

## Post-deployment smoke tests

On the real URL:

- deep-link refreshes return the SPA;
- security headers and Supabase CSP connection are correct;
- approved employee and supervisor sign in;
- unapproved/inactive/email-mismatched access fails closed;
- the complete 14-step workflow passes with synthetic data;
- employee table/RPC mutation attempts fail;
- report/CSV totals and privacy fields are correct;
- desktop/mobile/keyboard checks pass;
- browser/network/bundle inspection finds no secrets or private response fields;
- sign-out and session refresh behave correctly.

## Rollback guidance

Frontend:

- republish the last known-good Netlify deploy;
- verify compatibility with current migrations;
- rerun deep-link, Auth, role, schedule, and report smoke tests.

Database:

- do not reverse shared migration files;
- stop roster changes, take a forensic export, and prefer a forward corrective
  migration;
- if restore is unavoidable, validate roles, Auth linkage, RLS, functions,
  audit immutability, and application smoke tests in a disposable project before
  coordinated production cutover.

Secrets:

- remove and rotate the exposed value, rebuild/redeploy, invalidate relevant
  sessions, inspect logs, and document the incident.

## Final verdict

**Deployment-ready locally; production deployment pending.**

Milestone 7 code, database hardening, complete local MVP validation, and
operations documentation are complete. Acceptance criterion 18 (successful
Netlify production deployment) remains unmet until the account owner performs
and tests a real deployment. No claim of deployment is made.
