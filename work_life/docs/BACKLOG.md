# Staged delivery backlog

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

Status: connected local core and optional account slice implemented; the full pilot remains incomplete, with native-device acceptance and sync outstanding; local export/reset is implemented. Stages preserve the full proposal; they do not commit dates. Initial scenario order is provisional.

## Stage one establish the foundation

| ID | Work | Acceptance |
| --- | --- | --- |
| F01 | Confirm test devices, learning pace, pilot users, budget | Decisions logged; unknowns remain explicit |
| F02 | Build and validate an original Flutter design | Lovable review superseded by owner instruction; five destinations and connected local workflows implemented; owner/device review pending |
| F03 | Confirm data and state model | Form, bug/idea/focus and daily-routine journeys implemented locally and covered by tests; sync/account model still proposed |
| F04 | Prototype offline sync after implementation is authorized | Restart, retry, conflicting edits, and deletion cases pass |
| F05 | Prototype notifications on chosen phones | Permission, reschedule, completion action, and timezone results recorded |

## Stage two daily use pilot

| ID | Work | Acceptance |
| --- | --- | --- |
| P01 | Onboarding, account isolation, preferences | Minimal workspace onboarding implemented; Email/Google sign-in, secure sessions, local account isolation, Quiet Hours, and Reminder Defaults are implemented and tested; broader preferences, server ownership and cloud sync remain |
| P02 | Text capture, Inbox, retrieval | Implemented with SQLite and search; database reopen and widget tests pass; phone force-close/offline validation pending |
| P03 | Projects, entries, tasks and preparation checklists | Implemented locally: related project entries, task source links, editable preparation checklist, explicit task states; device walkthrough pending |
| P04 | Today and editable Planner | Implemented locally: shared task IDs, confirmed date-only deadlines, editable/fixed/personal blocks, overlap confirmation and overnight visibility; device/timezone testing pending |
| P05 | Reminders and in-app pending list | In-app set/reschedule/remove, native scheduling, permission status, Quiet Hours, Snooze, and Reminder Defaults are implemented and automated-tested; real-device delivery remains. Defaults apply only to new planned reminder intent; explicit completion/cancellation clears reminders, including through Focus |
| P06 | Routines and Focus | Local daily routines and persistent pause/resume/outcomes implemented; task/duration links tested; advanced recurrence, native restart and timezone checks pending |
| P07 | Basic Life Map and Insights | Custom life areas and seven-day recorded focus/routine summary implemented with unknown-data wording; planned-versus-recorded comparison and saved weekly review remain |
| P08 | Sync, recovery, export and deletion | Current-workspace JSON export and confirmed local reset implemented; account retained, notifications cancelled, defaults restored. Import/recovery and sync remain deferred |
| P09 | Pilot review | Baseline and participant feedback recorded; next priorities revised |

Deliver connected slices rather than isolated mock screens: capture through completion first, then project through focus, then routine through reflection. Stage two is finished only when all pilot capabilities above are usable, including basic Life Map and Insights.

## Stage three AI assistance

| ID | Work | Acceptance |
| --- | --- | --- |
| A01 | Capture interpretation and clarification | Unclear dates trigger questions; source retained |
| A02 | Task, project, and plan drafts | User can edit/reject; acceptance creates records once |
| A03 | Brainstorming and holiday planning | Unknowns and hypotheses remain visible; no booking |
| A04 | Voice capture and adaptive suggestions | Transcription correction supported; failures preserve available input |
| A05 | Expanded reflection | Insights use recorded activity and suggestions are dismissible |

## Stage four integrations and expansion

Gmail summaries within chosen scope, calendar connection, images/links, optional shared planning, and later repository assistance. Specify permissions, provenance, disconnection, duplicate handling, and failure recovery per integration. Decide repository review and execution boundaries before code assistance can apply changes. Complete broader accessibility and recovery testing before wider release.

## Completion standard

A feature is complete when its connected journey works, relevant validation passes, error/empty/offline states are handled, and documentation reflects actual behavior. A rendered screen alone does not complete a workflow.
