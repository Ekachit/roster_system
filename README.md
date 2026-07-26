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
   one of the fictional approved profiles in `supabase/seed.sql`. Public
   registration is disabled.

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

6. Create and confirm that user through the Supabase Dashboard. The Auth trigger
   links the verified normalized email to the approved staff row.
7. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` locally or in the host.
   Never put a service-role/secret key in frontend environment variables.

Further staff are approved in the supervisor Staff page before their Auth users
are created. Changing an already-linked email requires an intentional admin
workflow; ordinary UI operations cannot change Auth linkage.

## Verification

```powershell
npm run lint
npm run typecheck
npm run test
npm run build
supabase test db
```

Unix commands are identical. The application displays roster-facing time using
`Australia/Melbourne`; Milestone 1 stores no roster times yet.

## Security model

React route guards provide navigation feedback, while PostgreSQL RLS and
security-definer functions are authoritative. Only active linked users receive
an application identity. Employee reads are limited to their safe own profile
and own eligibility. Supervisor notes live in a separate supervisor-only table.
Roles, activation, Auth linkage, and eligibility are protected server-side.

## Milestone scope

This milestone includes authentication, roles, staff, locations, activity
types, eligibility, and foundation pages. Availability, shifts, schedules,
release requests, reporting, notifications, calendar integration, and
deployment are intentionally not implemented.
