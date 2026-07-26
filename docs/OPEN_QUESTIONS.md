# Open Questions

This document separates decisions still requiring supervisor confirmation from
confirmed product requirements. Defaults below are planning assumptions only.

## Blocking before Milestone 1

1. Which Supabase Auth method should the MVP use?  
   Assumption: email/password for the smallest operational footprint.
2. Who is the initial supervisor, and what approved email will bootstrap that
   account?  
   No real identity or email should be committed to the repository.
3. Should any workbook roster or attendance data be imported, and what calendar
   year do weeks 11-19 represent?  
   Assumption: no production import until mappings and a dry run are approved.
4. What are the canonical staff identities and location/activity mappings for
   workbook variants, `All Staff`, and shadowing annotations?

## Blocking before affected milestones

1. Does no submitted availability mean unavailable?  
   Assumption: yes.
2. Does a date-specific exception override only its time interval or the whole
   date?  
   Assumption: its interval only.
3. May shifts or availability cross midnight?  
   Assumption: no for the MVP.
4. Do draft assignments participate in overlap checks?  
   Assumption: yes.
5. Can location or activity eligibility ever be overridden?  
   Assumption: no; only availability can be overridden with a reason.
6. Which published-shift edits reset acknowledgements?  
   Assumption: date/time, location, activity type, or employee-visible notes.
7. What happens to a pending release request if the assignment is removed,
   replaced, or its shift is cancelled for another reason?
8. Should copied shifts include assignments?  
   Assumption: no.
9. Are cancelled shifts hidden from the normal employee schedule while retained
   in history?  
   Assumption: yes.
10. Is co-worker visibility limited to names?  
    Assumption: yes.
11. Which statuses count in scheduled-hours reports?  
    Assumption: published shifts with active assignments.
12. Is the proposed CSV format acceptable: UTF-8, ISO date, Melbourne 24-hour
    time, and duration in integer minutes?
13. How long must audit history be retained?  
    Assumption: for the life of the application, supervisor-readable only.

## Confirmed and not open

- The MVP roster and availability interfaces support all seven days.
- Roster dates and times display in `Australia/Melbourne`.
- The security boundary is Supabase RLS and secure database functions.
- Netlify Free and Supabase Free are the only hosting/backend services.
- Calendar integration, payroll, timesheet importing, notifications,
  auto-allocation, swapping, and other deferred features are out of scope.
