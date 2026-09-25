# Product requirements

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

Source: September 2026 proposal, preserved in [PROPOSAL_REFERENCE.md](PROPOSAL_REFERENCE.md). This document condenses that proposal; navigation and pilot priorities below are recommendations.

## Purpose and users

Help the creator and a small group of friends manage study, work, projects, appointments, and personal life. Success means fewer missed commitments, easier capture and planning, and attention to the life areas users value. More screen time and equal time in every life area are not goals.

## Connected journey

Capture → clarify → organize → plan → act → reflect. A user may enter at any stage. A note need not become a task, and an appointment can be scheduled directly.

## Recommended first scenarios

1. A partner requests a form by Friday: capture it, confirm the date, add photo preparation, schedule a reminder, reschedule while busy, and explicitly complete it.
2. A restaurant software bug: preserve the error and unknowns, link a later idea, choose an investigation, and carry its notes and duration into Focus.
3. Meals or exercise during busy days: choose flexible windows, postpone or use a smaller alternative, and review recorded activity without guilt.

These three are proposed priorities, pending the owner's choice. Important dates and holiday planning remain in the vision; AI itinerary drafting belongs to the later AI stage.

## Product areas

| Area | Required purpose |
| --- | --- |
| Today | Manageable priorities, commitments, routines, next useful action |
| Capture | Save short text promptly; voice, links, and images later |
| Inbox | Review and clarify unorganized captures |
| Projects | Connect notes, bugs, ideas, decisions, and tasks; retrieve original wording |
| Planner | Appointments, deadlines, effort, available time, buffers, personal time |
| Focus | Selected task, duration, completion condition, notes, pause and outcome |
| Routines | Recurrence, flexible windows, smaller alternatives |
| Insights | Recorded versus planned activity, postponements, weekly reflection |
| Life Map | User-defined work, study, health, relationship, and rest areas |
| Settings | Quiet hours, notification intensity, work time, priorities, data controls |

Current mobile navigation: Today, Inbox, Projects, Planner, and More, with quick Capture. Open Focus from a task; expose Routines, Life Map, Insights, and Settings through More. Validate the implemented navigation with users and adjust as needed.

The owner chose to skip the Lovable reference and build an original Flutter UI for Android and iPhone. Use a calm visual style, readable contrast, and useful empty, loading, error, offline, and saved states. The connected local app now implements Today, Inbox, Projects, Planner and More, with Focus from tasks and Routines/Life Map/reflection in More. These initial interactions still need owner and real-device feedback. Support accessible text sizing and screen-reader labels.

Quiet Hours are available in More → Settings. When enabled, task reminders whose local device time falls in the configured window are scheduled for the window's end. Start is inclusive and end is exclusive; cross-midnight windows are supported. The saved task reminder time and task state are unchanged. Routine notifications are not currently scheduled by the app, so this policy currently affects task reminders only.

Reminder Defaults are also available in More → Settings. The selected option is applied only when a task is first given a future Planner time and has no existing or explicitly suppressed reminder: none, at scheduled time, 10 minutes before, 30 minutes before, or 1 hour before. Explicit reminder saves and explicit reminder removal take priority. Date-only deadlines and unscheduled tasks do not receive an invented clock time.

## Behavior requirements

- Completing or cancelling a task requires an explicit product action. Closing a notification leaves the task pending.
- Distinguish deadline from scheduled work time. Moving a plan block does not alter its task deadline.
- AI outputs are editable drafts; acceptance is required to create active tasks. Keep sources and hypotheses visible.
- Sending messages, modifying external calendars, booking travel, or applying repository code is not part of draft acceptance. Travel booking is outside initial scope.
- Core records survive restart and offline capture syncs without loss. Show local save and cloud sync status separately.
- Support account separation, export, deletion, integration disconnection, and disclosure of content sent to AI.
- Insights describe recorded patterns. Health and immigration dates come from user-confirmed information.

## Pilot measurement

Collect a baseline before setting numerical targets: missed commitments, capture effort, postponed reminders, recovered ideas, useful focus sessions, and perceived planning effort. Ask whether personal life receives the attention each participant wants. Use actual pilot feedback to change scope and priorities.
