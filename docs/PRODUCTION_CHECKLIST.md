# Production Checklist

This checklist must be completed against the real Supabase project and Netlify
`.netlify.app` URL. Repository/local verification alone is not a production
deployment.

## Ownership and change control

- [ ] Production owner and backup owner are identified.
- [ ] Supabase and source-control owner accounts use MFA.
- [ ] The release commit SHA and migration list are recorded.
- [ ] No unrelated or deferred feature is included.
- [ ] No real employee data exists in tests, seed, screenshots, or previews.

## Automated release gate

- [ ] `npm ci` succeeds.
- [ ] `npm run lint` exits 0.
- [ ] `npm run typecheck` exits 0.
- [ ] `npm run test` exits 0.
- [ ] `supabase db reset` replays every migration and synthetic seed.
- [ ] `supabase test db` exits 0.
- [ ] All concurrency scripts required by the changed database workflows exit 0.
- [ ] `npm run test:e2e` exits 0.
- [ ] Production `npm run build` exits 0 with only public Supabase values.
- [ ] `npm audit` and `npm audit --omit=dev` results are reviewed and recorded.
- [ ] `git diff --check` exits 0.
- [ ] Secret scan finds no credentials/private keys.

## Supabase production

- [ ] Free production project exists and its database password is in a password
      manager only.
- [ ] Migration list matches the reviewed repository.
- [ ] `supabase db push --dry-run` was reviewed before `supabase db push`.
- [ ] Fictional local seed was not pushed.
- [ ] Email/password is enabled.
- [ ] Public sign-up, anonymous sign-in, OAuth, phone, and unused providers are
      disabled.
- [ ] Email confirmation is enabled.
- [ ] Site URL is the exact production `.netlify.app` URL.
- [ ] Redirect allowlist includes only required production/local/preview URLs.
- [ ] First supervisor was bootstrapped with an approved normalized email.
- [ ] Matching Auth user is confirmed and linked.
- [ ] A second owner can recover administrative access.
- [ ] Every public base table has RLS enabled.
- [ ] Security-definer functions have a fixed empty `search_path`.
- [ ] `PUBLIC`/`anon` cannot execute protected functions.
- [ ] Trigger-only/internal functions are not browser executable.
- [ ] Employees cannot read supervisor notes or another employee's availability.
- [ ] Employees cannot mutate shifts, assignments, roles, requests, or audit
      history directly.
- [ ] Audit UPDATE and DELETE fail at the database trigger.
- [ ] Service-role/secret keys are absent from frontend and Netlify.
- [ ] Supabase Security Advisor findings are reviewed.
- [ ] Database SSL enforcement and account-level security settings are reviewed.

## Netlify production

- [ ] Netlify Free site is connected to the reviewed repository/branch.
- [ ] Site uses the free `.netlify.app` domain.
- [ ] `netlify.toml` is detected.
- [ ] Build command is `npm run build`.
- [ ] Publish directory is `dist`.
- [ ] No Functions or paid add-ons are configured.
- [ ] Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are configured.
- [ ] Deploy Preview values use a synthetic project or non-functional public
      placeholders, never production credentials/secrets.
- [ ] `/employee/schedule`, `/supervisor/roster`, and an unknown client route
      load the SPA rather than return a Netlify 404.
- [ ] CSP permits the intended Supabase HTTPS/WSS origin and no broader origin.
- [ ] Security, cache, frame, referrer, and permissions headers are present.
- [ ] Built JavaScript contains no secret/service-role key or private fixture.

## End-to-end production smoke test

Use synthetic approved accounts.

- [ ] Approved employee signs in.
- [ ] Employee creates recurring availability.
- [ ] Employee creates a date-specific exception.
- [ ] Supervisor creates a shift.
- [ ] Candidate conflict/availability reason is correct.
- [ ] Supervisor assigns the employee with a reason when override is required.
- [ ] Supervisor publishes the shift.
- [ ] Employee sees the published shift and permitted co-worker names only.
- [ ] Employee acknowledges the shift.
- [ ] Employee submits a release request and remains assigned.
- [ ] Supervisor rejects, removes, or replaces through the controlled workflow.
- [ ] Historical assignment remains stored.
- [ ] Expected audit events, actor, subject, reason, and time are correct.
- [ ] Scheduled-hours report contains only current published active assignments.
- [ ] CSV filename, BOM, columns, quoting, formula protection, and minutes are
      correct.
- [ ] Employee navigation omits supervisor features.
- [ ] Direct employee supervisor URL fails closed.
- [ ] Direct employee RPC/table mutation is denied without response data.
- [ ] Sign-out and refresh return protected routes to sign-in.
- [ ] Melbourne date/time and DST-sensitive duration are correct.

## Responsive and accessibility

- [ ] Supervisor roster is usable at 1440 x 1000 without clipped actions.
- [ ] Employee dashboard, schedule, availability, and requests are usable at
      390 x 844 without document-level horizontal overflow.
- [ ] Keyboard Tab reaches Skip to content first and all actions are operable.
- [ ] Focus indicators are visible on links, buttons, inputs, selects, and
      textareas.
- [ ] Every form control has an accessible label.
- [ ] Required/invalid values produce a visible announced error.
- [ ] Loading states use status announcements.
- [ ] Empty states explain the next action.
- [ ] Success and error status does not rely on colour alone.
- [ ] Text/background and control colours meet WCAG AA contrast.
- [ ] Shift cancellation, assignment removal/replacement, staff/reference
      deactivation, availability deletion, and release resolution require
      confirmation/reason as applicable.

## Backup and recovery

- [ ] Pre-launch logical roles/schema/data export exists outside the repository.
- [ ] Backup is encrypted, access-controlled, checksummed, and stored off-site.
- [ ] Backup schedule and responsible owner are documented.
- [ ] Restore was rehearsed in a disposable project.
- [ ] Auth-user and approved-staff linkage was verified after restore.
- [ ] Netlify last-known-good deploy is identified.
- [ ] Frontend rollback compatibility with the current schema is confirmed.

## Go-live and observation

- [ ] Production deploy URL, deploy ID, commit SHA, and time are recorded.
- [ ] Complete smoke test passed on the real URL.
- [ ] Browser console/network show no unexpected errors or private-field leaks.
- [ ] Supervisor confirms roster totals against a manually checked synthetic
      scenario.
- [ ] Users receive the production URL and private temporary credentials only
      through approved channels.
- [ ] Post-launch owner checks Auth failures, Supabase logs/advisors, and Netlify
      deploy status during the agreed observation window.

## Stop/go rule

Do not go live when any security, migration, role-isolation, backup, deep-link,
or complete-MVP smoke item is incomplete. Roll back the frontend immediately
for a client regression. Stop roster changes and follow the coordinated
database recovery procedure for a data/schema incident.
