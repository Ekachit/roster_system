# AI Fitness Zone Rostering App — Product Requirements

## 1. Product overview

The AI Fitness Zone Rostering App is a small internal web application for approximately 10 staff members.

It will replace the current process where:

- Employees send their availability through Slack, email or direct messages.
- The supervisor manually edits an Excel roster.
- Employees check the spreadsheet to find their allocated shifts.
- The supervisor manually removes or replaces staff when availability changes.
- The supervisor cross-checks the roster against timesheets manually.

The application will provide one central place for availability, shift allocation and employee schedules.

## 2. Primary objective

The main objective is to make roster management easier for the supervisor and clearer for employees.

The system must allow:

- Employees to submit availability.
- The supervisor to create and assign shifts.
- Employees to view their own allocated shifts.
- The supervisor to remove, replace or reassign employees.
- The system to identify availability and scheduling conflicts.
- The supervisor to view scheduled hours and export roster data.

## 3. Target users

### Supervisor

The supervisor manages the roster and staff.

The supervisor can:

- View all staff members.
- View employee availability.
- Create, edit, publish and cancel shifts.
- Assign one or more employees to a shift.
- Remove or replace an employee.
- See whether a shift is understaffed.
- See which employees are available.
- Review employee requests to leave a shift.
- View scheduled hours.
- Export roster information as CSV.
- View a basic history of roster changes.

### Employee

Employees submit availability and view their own roster.

An employee can:

- Sign in securely.
- Submit recurring weekly availability.
- Submit date-specific unavailability.
- View their own published shifts.
- Acknowledge an assigned shift.
- Request removal from a shift.
- View the status of their own requests.

Employees must not be able to view private availability belonging to other employees.

## 4. MVP features

### 4.1 Authentication

The application must:

- Require users to sign in.
- Restrict access to approved staff email addresses.
- Support two roles: Supervisor and Employee.
- Protect supervisor pages and actions.
- Prevent employees from accessing another employee’s private information.
- Use Supabase Authentication.

### 4.2 Staff management

Each staff profile must include:

- Full name
- Email address
- Role
- Active or inactive status
- Eligible locations
- Eligible activity types
- Optional supervisor-only notes

The supervisor can add, edit or deactivate a staff member.

Inactive staff must not be available for future shift assignment.

### 4.3 Locations

The supervisor can manage locations such as:

- Clayton
- Caulfield
- Remote or Online
- Other locations added later

Locations must be stored separately from shift types.

### 4.4 Activity types

The supervisor can manage activity types such as:

- Drop-in
- Webinar Facilitator
- Webinar Support
- Training
- Event
- In-person Session
- Other activity types added later

### 4.5 Employee availability

Employees can submit:

1. Recurring weekly availability  
   Example: available every Tuesday from 9:00 am to 5:00 pm.

2. Date-specific exceptions  
   Example: unavailable on Tuesday 18 August.

Each availability record includes:

- Employee
- Day or date
- Start time
- End time
- Available or unavailable status
- Optional note

Rules:

- Date-specific exceptions override recurring availability.
- An employee is considered available only when their availability covers the full shift.
- Existing overlapping shifts create a conflict.
- Inactive employees cannot be assigned.
- Conflict messages must explain the reason.

### 4.6 Shift management

Each shift includes:

- Date
- Start time
- End time
- Location
- Activity type
- Required number of staff
- Notes
- Status: Draft, Published or Cancelled

The supervisor can:

- Create a shift.
- Edit a shift.
- Copy a shift.
- Assign multiple employees.
- Remove an employee.
- Replace an employee.
- Publish a shift.
- Cancel a shift.

The system must prevent:

- Duplicate assignment to the same shift.
- Overlapping active shifts.
- Assignment of inactive staff.
- Assignment outside availability without a supervisor override.

A supervisor override must require a reason.

### 4.7 Supervisor weekly roster

The application must provide a seven-day weekly roster view.

Each shift should display:

- Time
- Location
- Activity type
- Assigned staff
- Required number of staff
- Available employee count
- Understaffed status

The supervisor must be able to:

- Move between weeks.
- Filter by location.
- Filter by activity type.
- Open a shift to see assigned and available employees.
- See why a particular employee is unavailable.
- Assign, remove or replace employees.

### 4.8 Employee schedule

Employees must have a personalised schedule.

The employee dashboard should show:

- Their next shift.
- Their shifts this week.
- Upcoming published shifts.
- Shift date and time.
- Location.
- Activity type.
- Other assigned staff.
- Shift notes.

Employees must only see their own published assignments.

### 4.9 Shift acknowledgement

Employees can acknowledge that they have seen an assigned shift.

The system should record:

- Who acknowledged the shift.
- When they acknowledged it.

### 4.10 Release request

If an employee can no longer attend an assigned shift, they can submit a release request.

The request includes:

- Shift
- Employee
- Reason
- Date submitted
- Status: Pending, Approved or Rejected

Submitting a request must not automatically remove the employee.

The supervisor must review the request and then:

- Reject it.
- Remove the employee.
- Replace the employee.

### 4.11 Scheduled-hours report

The supervisor can select a date range and view:

- Each employee.
- Assigned shifts.
- Total scheduled hours.

The supervisor can export a CSV file containing:

- Employee
- Date
- Start time
- End time
- Duration
- Location
- Activity type
- Assignment status

This is for timesheet cross-checking only.

Payroll and timesheet importing are not part of the MVP.

### 4.12 Audit history

The system must record important changes, including:

- Availability created or edited.
- Shift created or edited.
- Shift published or cancelled.
- Employee assigned or removed.
- Employee replaced.
- Release request submitted or resolved.
- Supervisor conflict override.

Each history record should include:

- User who performed the action
- Action
- Date and time
- Relevant employee or shift
- Optional reason

## 5. Workbook context

The existing Excel roster contains:

- A Monday-to-Friday weekly calendar.
- Staff names allocated across different activities.
- Locations such as Clayton and Caulfield.
- Remote and online activities.
- Webinar, training and event information.
- An automatically generated shift-data worksheet.
- Broken formulas and references.

The workbook should be used as a reference and possible source of initial seed data.

The production application must use Supabase as its source of truth.

The Excel file must not be used during normal application operation.

## 6. Technical requirements

Use:

- React
- Vite
- TypeScript
- Tailwind CSS
- Supabase Authentication
- Supabase PostgreSQL
- Supabase Row Level Security
- Netlify Free hosting
- GitHub for source control
- Australia/Melbourne timezone

The application should be responsive and usable on both desktop and mobile.

## 7. Security requirements

The system must:

- Require authentication.
- Restrict access to approved email addresses.
- Enforce permissions using Supabase Row Level Security.
- Prevent employees from reading other employees’ private availability.
- Prevent employees from editing shifts.
- Prevent employees from changing roles.
- Prevent employees from approving their own requests.
- Store secrets in environment variables.
- Never commit secret keys to GitHub.
- Never expose the Supabase service role key in frontend code.

## 8. Out of scope for the MVP

Do not build these features in the first version:

- Google Calendar integration
- Email notifications
- SMS notifications
- Payroll
- Timesheet importing
- Clock-in and clock-out
- Geofencing
- Employee chat
- Automatic shift allocation
- Employee-to-employee shift swapping
- Native mobile applications
- Advanced analytics
- Multi-organisation support
- Paid services

## 9. Deployment requirements

The application must:

- Be hosted on Netlify Free.
- Use a free `.netlify.app` address.
- Use Supabase Free for authentication and database storage.
- Avoid Netlify serverless functions unless absolutely necessary.
- Use Netlify Deploy Previews for testing.
- Include setup instructions.
- Include environment-variable documentation.
- Include a post-deployment test checklist.

## 10. MVP acceptance criteria

The MVP is complete when:

1. Employees can sign in.
2. The supervisor can sign in.
3. Employees can submit recurring availability.
4. Employees can add a date-specific exception.
5. The supervisor can create a shift.
6. The system shows which employees are available.
7. The supervisor can assign employees.
8. The supervisor can publish the roster.
9. Employees can view their own published shifts.
10. Employees can acknowledge shifts.
11. Employees can submit release requests.
12. The supervisor can remove or replace employees.
13. Overlapping assignments are prevented.
14. Role permissions are enforced.
15. Scheduled hours are calculated correctly.
16. CSV export works.
17. Important changes appear in the audit history.
18. The application is deployed successfully on Netlify.

## 11. Development milestones

### Milestone 0 — Planning

- Review the workbook.
- Confirm requirements.
- Design the database.
- Design the page structure.
- Identify unanswered questions.

### Milestone 1 — Foundation

- React and Vite setup.
- Supabase setup.
- Authentication.
- Roles.
- Protected routes.
- Staff, locations and activity types.

### Milestone 2 — Availability

- Recurring availability.
- Date-specific exceptions.
- Availability conflict logic.

### Milestone 3 — Supervisor roster

- Shift creation.
- Weekly roster.
- Assignment.
- Conflict detection.
- Publication.

### Milestone 4 — Employee schedule

- My Schedule.
- Shift details.
- Shift acknowledgement.

### Milestone 5 — Roster changes

- Release requests.
- Removal and replacement.
- Audit history.

### Milestone 6 — Reporting

- Scheduled hours.
- CSV export.

### Milestone 7 — Deployment

- Netlify deployment.
- Security review.
- Mobile testing.
- Final production checklist.
