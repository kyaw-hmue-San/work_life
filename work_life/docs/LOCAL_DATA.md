# Local backup, export, restore, and reset

Implemented 9 September 2026 in **More → Settings → Data**. These controls operate on the currently selected local workspace, including guest mode. They do not aggregate or delete other account databases.

## Restorable backup format version 1

`Create backup` generates UTF-8 JSON and opens the existing `share_plus` file delivery mechanism with `work_life_backup.json` and MIME type `application/json`. The destination is chosen by the user. Generation is independent of delivery and reads all categories in one SQLite transaction. This is the only format accepted by Restore because it retains stable IDs, relationships, settings, and reminder intent.

The root is `{ "formatVersion": 1, "exportedAt": "<UTC ISO-8601 instant>", "app": "Work Life", "data": { ... } }`.

| Data key | Contents |
| --- | --- |
| `captures` | Stable ID, exact original text, creation instant; includes Inbox captures and linked sources |
| `projects` | ID, title, life area, description |
| `projectEntries` | ID, project ID, title, body, kind, related entry ID, capture ID |
| `tasks` | ID, title, area, project/capture/entry IDs, date-only deadline, duration, notes, status, ordered checklist with item IDs/text/done |
| `planner` | ID, title, nullable task ID, start instant, duration, area, fixed flag; includes personal time and appointments |
| `focusSessions` | ID, task ID, planned minutes, start/running-since instants, accumulated seconds, nullable outcome, notes, historical area |
| `routines` | ID, title, area, text window, `alternative` (Minimum), `normal`, `strong`, creation day |
| `routineRecords` | Routine ID, day, recorded outcome, historical area, `level` (minimum/normal/strong or null) |
| `lifeAreas` | Built-in and custom area names, which serve as area identifiers |
| `reminders` | Stable ID, task ID, next scheduled instant (including snooze), explicit/defaulted origin |
| `reminderSuppressions` | Task IDs with explicit no-reminder intent |
| `settings` | `quietHours` (`enabled`, `startMinute`, `endMinute`) and `reminderDefault` enum name |

Entity lists are sorted by ID; routine history by routine ID then day; areas/suppressions lexically. Checklist order remains meaningful. With the same snapshot and injected clock, output is identical. JSON null is retained. Instants use UTC ISO-8601; deadlines and routine days stay `YYYY-MM-DD`. Quiet Hours minutes are device-local minutes since midnight, not UTC instants. Focus seconds and running-since preserve the saved timer state, rather than fabricating activity totals.

There are no separate Inbox, Today, Life Map insight, or account-profile tables to export. These are derived views or separate authentication state. Excluded: authentication/session credentials, email/account IDs and database namespace hashes, secure-storage contents, configuration keys, OS notification IDs/payloads, notification delivery status, SQLite row IDs/schema bookkeeping, workspace onboarding completion (startup metadata), unsaved forms. Delivery status is device bookkeeping, not portable reminder intent. User-authored text is exported exactly, including any private information the user typed; the exporter does not redact that text.

## Human-readable exports

`Export readable report` produces `work_life_report.md`, with a summary followed by projects and their tasks, unassigned tasks, Planner blocks, recurring commitments, and routines. It is intended for reading, archiving, and sharing; it is not accepted by Restore.

`Export tasks as CSV` produces `work_life_tasks.csv`, with one row per task and columns for title, status, priority, area, project, deadline, duration, notes, and checklist. CSV values are quoted and embedded quotes are escaped. It is intended for spreadsheet analysis; it does not duplicate every internal database table and is not a backup.

## Delete semantics

Confirmation is mandatory and explains that only the current workspace is reset. No automatic or required export occurs. Duplicate requests are blocked during work; errors are shown, and success is reported only after persistence cleanup commits.

A single SQLite transaction deletes `focus_sessions`, `routine_records`, `reminders`, `reminder_suppressions`, `plans`, `tasks`, `project_entries`, `projects`, `routines`, `captures`, and `life_areas`, in foreign-key-safe order. It restores Work, Study, Health, Relationships, and Rest; Quiet Hours disabled with 23:00–07:00 bounds; and Reminder Default `none`. There are no remaining user content records. Empty/default data remains valid after reopening and supports immediate new captures/tasks.

Account identity and secure sign-in survive, as do other workspace databases and OS notification permission preferences. This is workspace reset, not sign-out or account deletion. Settings closes to the root workspace after success; the shared model drops deleted records and the retained Inbox is recreated, clearing its capture list/search/draft. No restart is required. Schema 8 also resets workspace onboarding completion; the root now shows Welcome, with Skip or Finish returning to normal navigation.

## Notification sequencing and failure policy

Reset is serialized on the same coordinator queue as reconciliation and scheduling. After earlier schedules finish, it calls the Work Life driver's `cancelAll` (pending and delivered app notifications) before starting the SQLite transaction. Generation checks abort if the active account changes before cancellation or before deletion. Later reconciliation reads the empty database and cannot recreate deleted reminder intent. Notification IDs and ordinary reminder policies are unchanged.

Cancellation failure aborts before SQL deletion and is reported to the user. A SQL failure rolls back all database changes; notifications may already have been cancelled. A subsequent normal reconciliation can restore reminders for the retained content, or the user can retry reset. SQLite and the OS cannot participate in a common atomic transaction. Process termination between cancellation and SQL commit leaves the workspace intact; the next launch may reconcile its retained reminders. Successful commit leaves no reminder intent to reschedule.

If reading the reset workspace fails after commit, stale records are still discarded and a reload message is shown. This does not claim the deletion failed after it actually committed.

## Limits and device acceptance

Paste-based JSON restore, task CSV, readable Markdown, and signed-in workspace synchronization are implemented. Automatic file backup and cloud-account deletion are not. Exports are unencrypted and loaded in memory; very large workspaces may require streaming in a future version. The native sharing plugin may create OS-managed temporary cache files; reset does not recall exports already saved/shared or securely erase storage media. Saved exports remain under the user's control.

Automated tests verify the share-delivery arguments and JSON bytes, not native share-sheet behavior. On physical Android/iPhone (including an iPad popover where applicable), verify export save/cancel/error, then reset with pending notifications and confirm no alerts remain. Notification delivery, reboot, and OS reliability have not been physically validated.
