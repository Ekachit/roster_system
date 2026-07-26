# AI Fitness Zone Roster

Milestone 1 foundation for a small internal rostering application. The app uses
React, Vite, strict TypeScript, Tailwind CSS, Supabase Auth/PostgreSQL/RLS, and
is designed for a later Netlify Free deployment.

## Prerequisites

- Node.js 20 or newer
- Docker Desktop
- Supabase CLI

## Local setup

1. Install dependencies: `npm install`
2. Start local Supabase: `supabase start`
3. Copy the local Project URL and publishable key shown by the CLI into `.env`:

   ```text
   VITE_SUPABASE_URL=http://127.0.0.1:55321
   VITE_SUPABASE_ANON_KEY=<local publishable key>
   ```

4. Start Vite: `npm run dev`
5. In local Supabase Studio/Auth, create a confirmed user whose email matches
   one of the fictional approved profiles in `supabase/seed.sql` after
   normalization. Public registration is disabled.

The local stack uses ports `55320`–`55327` to avoid collisions with another
Supabase project. `supabase db reset` reapplies migrations and fictional seed
data. Stop it with `supabase stop`.

## Hosted Supabase setup

1. Create a Supabase Free project.
2. Apply `supabase/migrations` with the Supabase CLI (`supabase link`, then
   `supabase db push`).
3. Do not apply the fictional local seed to production unless explicitly
   desired.
4. Disable public sign-ups in Auth settings and use email/password.
5. Bootstrap the first supervisor using the SQL editor before creating their
   Auth account:

   ```sql
   insert into public.staff (email, full_name, role)
   values ('approved-address@example.com', 'Supervisor name', 'supervisor');
   ```

6. Create and confirm that user through the Supabase Dashboard using exactly
   the same normalized email. Set a temporary password and share it only through
   a private channel.
7. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` locally or in the host.
   Never put a service-role/secret key in frontend environment variables.

### Provisioning each employee

Email/password is the selected MVP authentication method. There is no public
self-registration or email invitation workflow:

1. The system owner or supervisor creates the approved staff profile in the
   application.
2. The system owner separately creates the corresponding Auth user in the
   Supabase Dashboard using the exact same normalized email.
3. The system owner gives the employee the temporary password through a private
   channel.
4. The employee opens Profile after first sign-in and uses **Change password**
   to replace the temporary password.
5. While production SMTP is not configured, the system owner manually resets
   forgotten passwords through the Supabase Dashboard and communicates the new
   temporary password privately.

Authorization continuously requires the Auth user ID, normalized current Auth
email, and an active approved staff row to match. Changing an Auth email removes
operational access immediately.

A linked staff email is immutable in the normal supervisor workflow. A required
change is an administrator-controlled maintenance operation: disable access,
unlink `staff.auth_user_id`, update the approved email, create or update and
confirm the matching Auth user, then deliberately relink it. Perform and verify
this through trusted Supabase administration—not through the browser—and make
sure at least one other authorized supervisor remains throughout.

## Verification

```powershell
npm run lint
npm run typecheck
npm run test
npm run build
supabase test db
.\supabase\tests\concurrent_last_supervisor.ps1
```

Unix commands for npm and Supabase are identical. The concurrency verifier is a
PowerShell script and requires PowerShell plus Docker. The application displays
roster-facing time using `Australia/Melbourne`; Milestone 1 stores no roster
times yet.

## Security model

React route guards provide navigation feedback, while PostgreSQL RLS and
security-definer functions are authoritative. Only active users whose current
Auth UUID and normalized email both match their approved staff row receive an
operational application identity. Employee reads are limited to their safe own
profile and own eligibility. Supervisor notes live in a separate
supervisor-only table. Roles, activation, Auth linkage, and eligibility are
protected server-side. Inactive or email-mismatched linked users may read only
their limited access-status response so the UI can explain why access is
denied; they cannot read operational tables.

## Milestone scope

This milestone includes authentication, roles, staff, locations, activity
types, eligibility, and foundation pages. Availability, shifts, schedules,
release requests, reporting, notifications, calendar integration, and
deployment are intentionally not implemented.
