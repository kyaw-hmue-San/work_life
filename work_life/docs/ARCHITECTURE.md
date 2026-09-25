# Proposed architecture and data model

Status: connected local architecture implemented; server/sync architecture remains proposed.

## Implemented local core

`AppDatabase` owns database opening, foreign keys and migrations for `work_life.db`. `SqliteCaptureRepository` retains the capture API; `SqliteWorkspaceRepository` extends it with typed workspace records and writes. `WorkspaceModel` exposes committed shared records to the five destinations, task detail, Focus and editors. `InboxModel` retains its independent composer/search state. UI writes are serialized, and draft errors are visible. SQLite is the durable source; models are in-memory projections.

Schema version 1 contains original captures; version 2 adds life areas, projects, tasks, plans, routines, per-day routine records and focus sessions; version 3 adds project entries, task entry references and activity-area snapshots. Migrations are transactional through SQLite open callbacks. Existing version 2 activity snapshots are backfilled from their linked task/routine category at migration time because no earlier category snapshot existed.

IDs use 128 random bits. Original capture text is never trimmed or interpreted; whitespace checking only rejects an empty input. Tasks reference a source capture and/or entry, with unique source indexes preventing duplicate conversion in this initial one-next-action flow. Task source identity cannot change during editing. Project entries can link another entry in the same project. Checklist items have stable IDs; task edits preserve completion for unchanged checklist text.

Date-only deadlines are validated calendar strings selected explicitly through a date picker. Plan blocks reference tasks or hold personal/appointment labels; UTC instants are displayed in the current device zone. Moves/removals do not update tasks or other plans. Overlaps prompt the user to adjust or deliberately keep both. Blocks crossing midnight appear on both days. Device timezone and DST edge-case validation remain required; IANA-zone travel policy and advanced recurrence are not implemented.

Only one unfinished focus session is allowed by a database index. Persisted running timestamps and accumulated seconds support pause/resume/reopen. Finishing a session and explicitly completing its task is transactional. Partial/blocked leave the current task state; a cancelled/completed task is not automatically reopened. Ending/cancelling a task elsewhere pauses its active timer without inventing a focus outcome. Timer duration continues during app absence, is clamped against backwards clock movement, and is described as elapsed timer time rather than proof of continuous activity. Focus notes are persisted when finishing.

Routines currently repeat daily from their creation date using the device date, with descriptive flexible windows and alternatives. The routine/day primary key makes outcome changes idempotent. “Later” remains pending; no record means unknown. Focus and routine outcomes snapshot their life area. Seven-day reflection derives totals from these records, not from inferred inactivity.

No server, account ownership, outbound queue or sync revision exists yet. Define local-record adoption and migrations before implementing authentication. There are no notification schedules, export/deletion controls or AI calls. The wider boundaries/entities below remain the target proposal.

## Boundaries

Flutter screens use ViewModels that call repositories and shared domain operations. Domain operations read and write a local repository. The repository persists records and a durable outbound queue in SQLite. A sync adapter exchanges authenticated changes with Postgres. Device notification scheduling observes committed record changes. Server functions handle privileged AI and integration requests.

SQLite is the device's immediate working store; the server reconciles shared account state. UI memory is not durable storage. AI and network availability must not block saving a capture locally.

## Core entities

All user-owned entities need stable identifiers, owner identity, creation/update metadata, and a synchronization revision. Define relational ownership constraints as well as access policies.

| Entity | Main fields and relationships |
| --- | --- |
| Capture | Original text, source, captured time, review state, related project |
| Project | Title, description, life area, active/archived state |
| Project entry | Note, bug, idea, or decision; project, source capture, related entries |
| Task | Title, status, project, source capture, optional confirmed deadline, effort, completion condition |
| Checklist item | Parent task, text, completion state |
| Appointment | Confirmed start/end and timezone, fixed-time semantics |
| Plan block | Task reference or personal-time label, start/end, scheduling flexibility |
| Routine | Recurrence rule, timezone behavior, flexible window, smaller alternative |
| Routine occurrence | Routine reference, unique occurrence identity, planned window, outcome |
| Reminder | Task/appointment/occurrence reference, intended time, snooze state |
| Device schedule | Reminder and device references, OS notification identifier, scheduling status |
| Focus session | Task reference, planned duration, start/pause/end times, recorded elapsed time, outcome |
| Life area | User-defined name and preferences |
| AI draft | Source references, proposed changes, uncertainties, review state, acceptance operation ID |
| Preferences | Quiet hours, working times, reminder limits, timezone settings |

Do not duplicate tasks into each screen. Today and Insights are derived views. A partial or blocked focus result leaves the linked task open unless the user explicitly chooses another state.

## State and time rules

Task states: open, in_progress, completed, cancelled. Scheduling and overdue indicators are derived separately. Reminder dismissal never changes task state. Snoozing changes the next reminder time; it does not silently move a deadline. Routine occurrences have separate outcomes so one skipped day does not cancel recurrence.

Represent date-only deadlines separately from precise instants. Store precise instants with timezone context; preserve a routine's local wall-clock intent and chosen IANA zone. Decide whether a routine follows travel or a home zone before implementation. Define daylight-saving gaps, repeated times, quiet-hour handling, and date-only reminder defaults explicitly. Never resolve ambiguous user input silently.

## Offline synchronization proposal

1. Commit each local domain change and its outbound operation atomically before reporting it saved.
2. Generate stable IDs and idempotency keys on-device. Retrying an upload must not create duplicate entities.
3. Authenticate on the server and check ownership, payload validity, and base revision. Apply accepted operations transactionally.
4. Pull changes using a stable server cursor, including deletion tombstones. Keep failed outbound operations until acknowledged or explicitly resolved.
5. If base revision is stale, retain local and remote versions and surface a conflict. Do not silently overwrite dates, completion, or edited capture content with last-write-wins.
6. Reconcile notification schedules after committed changes. A completed task must not be recreated by an old offline operation.

Synchronization needs a prototype before this design is accepted. Define cursor retention, tombstone cleanup, expired sessions, migrations, and crash recovery as part of that work. On sign-out, isolate local data and handle unsynced changes explicitly; a different account must never see them.

## Reminder reconciliation

Persist intended reminder state independently from device scheduling results. Cancel or replace stale OS identifiers when reminders move or tasks finish. Reconcile at app launch/resume and after sync; do not depend on a continuously running Dart timer. Bound the scheduled horizon to platform limits and show in-app pending commitments when permissions are blocked. Later push delivery must have a deduplication strategy alongside local reminders.

## AI and data boundaries

Send only selected necessary context to the server-side AI adapter. Validate structured draft output; keep uncertain dates unresolved. Accept a draft transactionally with an idempotency key so repeated taps or retries do not duplicate tasks. Draft generation cannot send messages or mutate external calendars.

Keep provider keys and integration refresh tokens server-side. Select an appropriate protected mobile session storage approach after checking SDK compatibility. Avoid logging capture text and sensitive appointment details. Design export and deletion across cloud records, local caches, and later attachments; document backup retention and deletion completion behavior before pilot release.


## Reminder checkpoint — 9 September 2026

Schema 7 stores one reminder per task in `reminders` (ID, unique task foreign key, UTC scheduled instant, delivery status, origin), one persisted Quiet Hours policy, one Reminder Defaults preference, and explicit per-task reminder suppressions. Task planning can create one default-origin reminder when a task first receives a future planned time; explicit saves replace it and explicit removal suppresses future automatic creation. Snooze replaces the next reminder time while preserving the reminder ID, task status, and deadline. Today derives a chronological list for active tasks, including elapsed reminders. Viewing or dismissing a reminder does not acknowledge or complete the task. Quiet Hours delay in-window task notifications to the local window end; notification reconciliation replaces changed schedules without duplicates. Completion/cancellation deletes reminder intent, including through Focus. Physical-device notification behavior remains unverified.
