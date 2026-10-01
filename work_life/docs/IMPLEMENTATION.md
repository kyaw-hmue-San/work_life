# Connected local app

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

The owner confirmed expanding the existing Flutter project into the full app on 7 September 2026. This is the working local core of that staged project; it is not a completed cloud pilot.

## Try a connected journey

1. Open Inbox and save the exact thought you want to keep.
2. Open it and choose **Turn into a task**. Edit the next action, choose a project/life area if useful, and add preparation steps. A phrase like “Friday?” does not set a deadline; use the date picker after confirming it.
3. Open the task from its project or **More → All tasks**. Choose **Plan time for this**. It appears in Planner and in Today on the planned day. Moving the block leaves the deadline alone.
4. Start Focus from the task. Pause for a break or leave and return. Finishing as partial/blocked keeps the task unfinished; **Finish and complete task** is explicit.
5. In Projects, add a bug entry and a later idea linked to it. Create a next step from the idea; its source remains available from task details.
6. Use Planner to protect lunch, rest or time together without creating a task. Fixed appointment blocks are moved only through their own edit action. Overlaps ask whether to keep both blocks.
7. Add a daily routine in More, with a flexible window and a smaller alternative. Record done, smaller, later or skipped for today. Missing records stay unknown.
8. Open a task and choose **Set reminder**. Confirm a future date and time. Return to Today to see it in **Pending reminders**. Reschedule or remove it from task details; the deadline stays unchanged. Elapsed reminders stay visible until removed or the task is completed/cancelled. Device scheduling is available when permission is allowed; the in-app list remains the source of truth when delivery is blocked or unavailable.
9. Open **Life Map & reflection** for custom areas and seven-day recorded focus/routine totals. These describe recorded timer time/outcomes, not all your activity.
10. Open **More → Settings** to enable Quiet Hours and choose start/end times. Task reminders inside the local-device window are scheduled at its end; the original reminder and task remain unchanged.
11. From a task with a reminder, choose **Snooze** and select 10 minutes, 30 minutes, 1 hour, or Tomorrow. Repeating the action replaces the same reminder and notification; the task deadline and status remain unchanged.
12. In **More → Settings**, choose a Default reminder. It is used when a task first receives a future Planner time without an existing or explicitly removed reminder. Date-only deadlines and unscheduled tasks do not create a clock-based reminder.

Captures, shared records, plans, focus state and account-scoped workspaces persist
in SQLite first. Authenticated workspaces then synchronize incrementally through
Supabase; guest workspaces remain local unless explicitly exported.

Schema v14 adds a durable SQLite outbox, per-record remote revision metadata and
a server checkpoint. SQLite triggers enqueue domain changes in the same local
transaction as the user action. Startup, resume, successful mutations, Inbox
capture and manual retry run the coordinator. Failed uploads remain queued with
bounded exponential backoff.

The remote store uses one generic versioned record per stable domain ID. Server
revisions, not device clocks, drive incremental download. Ordinary concurrent
edits use deterministic server-arrival last-write-wins. On first sync, an
already-versioned remote record wins over an unversioned local record with the
same stable ID; local-only records are then uploaded. A remote tombstone cannot
be resurrected by an offline client whose base revision predates that
tombstone. Upload mutation IDs make retries idempotent.

Remote batches are applied to SQLite transactionally in dependency order while
outbox triggers are suppressed. Checklist IDs remain embedded stable child IDs.
Reminder intent, defaults, suppressions and Quiet Hours synchronize, while
native notification delivery status/IDs remain device-local. Unsaved forms,
temporary images, AI responses and platform bookkeeping are not synchronized.
See [Supabase and Google sign-in setup](SUPABASE_GOOGLE_SETUP.md).

## Code map and learning notes

| Location | Responsibility |
| --- | --- |
| `lib/main.dart` | App theme and repository injection |
| `lib/accounts/` | Supabase email/Google sign-in, secure sessions and account-scoped local databases |
| `lib/sync/` | Durable offline outbox, incremental coordinator and Supabase remote adapter |
| `lib/data/app_database.dart` | SQLite schema, foreign keys, versioned migrations |
| `lib/captures/` | Original text capture, search and save-error handling |
| `lib/workspace/records.dart` | Typed records and time/overlap helpers |
| `lib/workspace/workspace_repository.dart` | Reads/writes, source integrity and transactional focus changes |
| `lib/workspace/workspace_model.dart` | Shared in-memory view of committed data and derived Today tasks |
| `lib/workspace/workspace_screen.dart` | Five destinations, project entries, routines and reflection |
| `lib/workspace/editors.dart` | Validated user forms for tasks, projects, entries, plans and routines |
| `lib/workspace/task_detail.dart` | Shared task actions, checklist and original sources |
| `lib/workspace/reminder_editor.dart` | Future date/time confirmation, in-app reminder save/retry, shared local-time labels |
| `lib/workspace/focus_screen.dart` | Timer display, pause/resume and explicit outcomes |
| `test/` | Database/migration and interaction regressions |
| `tool/render_review.dart` | Explicit synthetic mobile screenshot review harness |

A **repository** handles storage, so screens do not write SQL. A **ViewModel** holds the current view of saved data and notifies widgets when it changes. A **foreign key** prevents a task from referring to a project/capture that does not exist. A **transaction** commits linked changes together: finishing Focus and completing the task cannot be half-saved.

This version uses native Navigator routes and constructor injection. Account configuration is supplied at build time; no secrets or AI keys belong in the client.

## Remaining milestones

- Android SDK setup; physical Android/iPhone and accessibility validation.
- Quiet Hours, Snooze, and Reminder Defaults are implemented locally with persisted settings and notification rescheduling. Physical-device delivery and timezone/DST behavior remain to be validated.
- Broader preferences, local-record adoption, server ownership and sync feasibility. The current optional account slice covers sign-in, secure sessions and local account isolation; it is not cloud sync.
- Recovery/import, richer recurrence, planned-versus-recorded insights and saved reflection.
- AI drafts, voice and integrations in their later backlog stages.

Single-device local data is useful now. Robust multi-device synchronization still requires its own implementation and failure tests; a cloud SDK alone will not supply it.

## Day Architect — implementation checkpoint (28 September 2026)

The Day Architect slice builds on Plan My Day instead of replacing it. SQLite schema v17 adds recurring weekly schedules, per-date cancellation/time/move exceptions, and planning preferences including sleep/work windows, meals, exercise, buffers and planning style; the schedule and preferences are exposed from Settings and as optional onboarding setup. Schedule-image proposals capture weekday and can be reviewed, edited, assigned a semester date range, and saved as recurring commitments. These records are included in JSON backup/import and in the local sync outbox. Supabase needs migration `202609280001_day_architect_entities.sql` applied before these records can sync remotely.

`DayContextBuilder` now gathers only date-relevant recurring commitments, existing Planner blocks, near-term/due/overdue or already scheduled tasks, routines, preferences, and capacity estimates. `WeekContextBuilder` deliberately builds seven contexts by reusing the same day model. AI schedule proposals include explicit block kind and operation labels; existing omitted flexible blocks become reviewable removal suggestions, while fixed blocks are locked and preserved. Repository approval remains transactional/idempotent and validates overlaps, recurring commitments, transition buffer, waking hours, focus cutoff, and available daily capacity. Lifestyle blocks continue to be Planner-only, with no fake Task creation.

AI output remains editable and the provider remains optional; no automated test calls a paid model. Physical-device acceptance, cloud migration deployment, and live-provider verification remain external.

## Plan My Week — implementation checkpoint (28 September 2026)

Planner now exposes **Plan My Week with AI** for the Monday-to-Sunday week containing the selected calendar date. `WeekContextBuilder` reuses the hardened date-scoped context and adds a compact weekly payload containing fixed/recurring commitments, existing Planner blocks, relevant deadline work, cross-day capacity totals, overloaded dates, lighter dates, routines, planning preferences, and one temporary natural-language adjustment.

The provider returns the existing typed `AiScheduleProposal`; no second persistence model was introduced. The review screen groups native editable cards under all seven dates, shows intentional open days, permits per-block inclusion and locking, exposes ADD/MOVE/CHANGE/REMOVE/UNCHANGED diffs, constrains manual date edits to the week, and supports regeneration or conversational adjustment. Fixed recurring commitments and fixed Planner blocks are normalized back to their exact IDs/times and locked before review.

Approval uses the existing transaction and normal Planner/reminder/sync paths. All seven day fingerprints are checked inside the transaction, so a change on any affected date makes the proposal stale before writes. Cross-day moves preserve plan/task IDs; split sessions can share one Task without creating duplicate Tasks; linked work after its Task deadline is rejected; partial acceptance still validates against retained blocks. Lifestyle blocks remain Planner-only.
