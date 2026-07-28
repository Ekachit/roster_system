$ErrorActionPreference = 'Stop'
if (-not $env:M6_BROWSER_PASSWORD) { throw 'M6_BROWSER_PASSWORD is required.' }

$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' |
  Where-Object { $_ -like '*ai-fitness-zone-roster*' } |
  Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

$escapedPassword = $env:M6_BROWSER_PASSWORD.Replace("'", "''")
$sql = @"
insert into public.locations(id,name,is_active) values
('58000000-0000-0000-0000-000000000001',chr(65309) || E'Clayton, "Formula"',true),
('58000000-0000-0000-0000-000000000002','Remote M6',true);

insert into public.activity_types(id,name,is_active) values
('68000000-0000-0000-0000-000000000001',E'@Training, "A"',true),
('68000000-0000-0000-0000-000000000002','Event M6',true);

insert into public.staff(id,email,full_name,role,is_active) values
('28000000-0000-0000-0000-000000000001','m6.browser.supervisor@example.test','M6 Browser Supervisor','supervisor',true),
('28000000-0000-0000-0000-000000000002','+formula@example.test',E'=SUM(1,1), "Synthetic"\r\nEmployee','employee',true),
('28000000-0000-0000-0000-000000000003','m6.browser.shadow@example.test','M6 Browser Shadow Employee','employee',true),
('28000000-0000-0000-0000-000000000004','m6.browser.employee@example.test','M6 Browser Employee','employee',true);

insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  phone_change_token,email_change_token_current,reauthentication_token,created_at,updated_at
) values
('18000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm6.browser.supervisor@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now()),
('18000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm6.browser.employee@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now());

update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id in (
  '18000000-0000-0000-0000-000000000001',
  '18000000-0000-0000-0000-000000000002'
);

insert into public.staff_private_notes(staff_id,note) values
('28000000-0000-0000-0000-000000000002','M6_PRIVATE_NOTE_SENTINEL');

insert into public.availability_exceptions(
  id,staff_id,local_date,kind,start_time,end_time,is_full_day,note
) values (
  '78000000-0000-0000-0000-000000000001',
  '28000000-0000-0000-0000-000000000002',
  '2026-08-20','unavailable','12:00','13:00',false,
  'M6_AVAILABILITY_SENTINEL'
);

insert into public.shifts(
  id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,
  required_staff_count,notes,status,published_at,cancelled_at,created_by,updated_by
) values
(
  '38000000-0000-0000-0000-000000000001','M6 active regular','2026-08-10','09:05','10:35',
  '58000000-0000-0000-0000-000000000001','68000000-0000-0000-0000-000000000001',
  1,'M6_SHIFT_NOTE_SENTINEL','PUBLISHED',now(),null,
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
),
(
  '38000000-0000-0000-0000-000000000002','M6 active second','2026-08-11','10:35','11:05',
  '58000000-0000-0000-0000-000000000002','68000000-0000-0000-0000-000000000002',
  1,null,'PUBLISHED',now(),null,
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
),
(
  '38000000-0000-0000-0000-000000000003','M6 active shadowing','2026-08-12','13:00','14:15',
  '58000000-0000-0000-0000-000000000001','68000000-0000-0000-0000-000000000002',
  1,null,'PUBLISHED',now(),null,
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
),
(
  '38000000-0000-0000-0000-000000000004','M6 excluded cancelled','2026-08-10','15:00','16:00',
  '58000000-0000-0000-0000-000000000001','68000000-0000-0000-0000-000000000001',
  1,null,'CANCELLED',now(),now(),
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
),
(
  '38000000-0000-0000-0000-000000000005','M6 excluded draft','2026-08-11','15:00','16:00',
  '58000000-0000-0000-0000-000000000001','68000000-0000-0000-0000-000000000001',
  1,null,'DRAFT',null,null,
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
),
(
  '38000000-0000-0000-0000-000000000006','M6 excluded removed','2026-08-12','15:00','16:00',
  '58000000-0000-0000-0000-000000000001','68000000-0000-0000-0000-000000000001',
  1,null,'PUBLISHED',now(),null,
  '28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'
);

insert into public.shift_assignments(
  id,shift_id,staff_id,assignment_kind,assigned_by,removed_at,removed_by,removal_reason
) values
(
  '48000000-0000-0000-0000-000000000001','38000000-0000-0000-0000-000000000001',
  '28000000-0000-0000-0000-000000000002','REGULAR',
  '28000000-0000-0000-0000-000000000001',null,null,null
),
(
  '48000000-0000-0000-0000-000000000002','38000000-0000-0000-0000-000000000002',
  '28000000-0000-0000-0000-000000000002','REGULAR',
  '28000000-0000-0000-0000-000000000001',null,null,null
),
(
  '48000000-0000-0000-0000-000000000003','38000000-0000-0000-0000-000000000003',
  '28000000-0000-0000-0000-000000000003','SHADOWING',
  '28000000-0000-0000-0000-000000000001',null,null,null
),
(
  '48000000-0000-0000-0000-000000000004','38000000-0000-0000-0000-000000000004',
  '28000000-0000-0000-0000-000000000003','REGULAR',
  '28000000-0000-0000-0000-000000000001',null,null,null
),
(
  '48000000-0000-0000-0000-000000000005','38000000-0000-0000-0000-000000000005',
  '28000000-0000-0000-0000-000000000003','REGULAR',
  '28000000-0000-0000-0000-000000000001',null,null,null
),
(
  '48000000-0000-0000-0000-000000000006','38000000-0000-0000-0000-000000000006',
  '28000000-0000-0000-0000-000000000003','REGULAR',
  '28000000-0000-0000-0000-000000000001',now(),
  '28000000-0000-0000-0000-000000000001','M6_REMOVAL_SENTINEL'
);

insert into public.release_requests(
  id,assignment_id,staff_id,reason,note,status,submitted_at
) values (
  '88000000-0000-0000-0000-000000000001',
  '48000000-0000-0000-0000-000000000001',
  '28000000-0000-0000-0000-000000000002',
  'M6_RELEASE_REASON_SENTINEL','M6_RELEASE_NOTE_SENTINEL','PENDING',now()
);

insert into public.roster_audit(
  actor_staff_id,action,shift_id,assignment_id,subject_staff_id,reason,details
) values (
  '28000000-0000-0000-0000-000000000001','M6_BROWSER_AUDIT',
  '38000000-0000-0000-0000-000000000001',
  '48000000-0000-0000-0000-000000000001',
  '28000000-0000-0000-0000-000000000002',
  'M6_AUDIT_REASON_SENTINEL','{"private":"M6_AUDIT_DATA_SENTINEL"}'::jsonb
);
"@

$sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Synthetic Milestone 6 browser fixtures created.'
