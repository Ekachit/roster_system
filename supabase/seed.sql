-- Fictional configuration and people only. This seed is for local development.
insert into public.locations (name, default_start_time, default_end_time) values
  ('Clayton', '10:40', '14:20'),
  ('Caulfield', '10:40', '14:20'),
  ('Remote / Online', null, null)
on conflict (name) do nothing;

insert into public.activity_types (name) values
  ('Drop-in'),
  ('Webinar Facilitator'),
  ('Webinar Support'),
  ('Training'),
  ('Event'),
  ('In-person Session')
on conflict (name) do nothing;

-- Synthetic approved profiles. Create matching local Auth users manually if needed.
-- Passwords are intentionally not stored here.
insert into public.staff (email, full_name, role, is_active) values
  ('supervisor@example.test', 'Sam Supervisor', 'supervisor', true),
  ('employee.one@example.test', 'Alex Example', 'employee', true),
  ('employee.inactive@example.test', 'Taylor Inactive', 'employee', false)
on conflict (email) do nothing;
