# Decisions and project state

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

Updated: 9 September 2026.

## Confirmed context

- The owner supplied a September 2026 work–life balance mobile app proposal.
- The owner requested Markdown files for future IDE AI context and technology recommendations before implementation.
- The current workspace initially contained no application files.
- The proposal describes the creator and friends as initial users.
- The owner confirmed both Android and iPhone, prefers Flutter, and wants to learn through development.
- The owner subsequently chose an original Flutter UI, without using or reviewing the Lovable UI. No Lovable source is reused.

## Decision register

| ID | Proposal | Status and condition |
| --- | --- | --- |
| D01 | Flutter and Dart, Android and iPhone | Confirmed owner direction on 7 September 2026 |
| D02 | SQLite locally; Supabase cloud | SQLite/sqflite adopted for the authorized first local slice; Supabase and sync remain proposed |
| D03 | Local notifications before remote push | Proposed; dependent on target-device testing |
| D04 | Form, restaurant bug, meals/exercise as first scenarios | Proposed; owner may reorder |
| D05 | Today, Inbox, Projects, Planner, More, with quick Capture | Implemented as the current navigation; owner usability feedback pending |
| D07 | Original Flutter UI without Lovable dependency | Confirmed owner direction; implementation authorized on 7 September 2026 |
| D06 | AI provider chosen later | Proposed; evaluate real cases and budget at AI stage |

## Open decisions

1. Actual Android and iPhone test devices and distribution arrangements.
2. Learning pace and team capacity; owner is open to learning languages.
3. Validate the original Flutter UI with the owner during development.
4. Name, pilot participants, three priority scenarios, available time, monthly budget.
5. Single-device or concurrent multi-device expectations, and sync implementation choice.
6. Home-zone versus travel-following routines and quiet-hour exceptions; Reminder Defaults use the current device timezone and apply only to newly planned reminder intent.
7. AI provider, permitted data, usage limits, and later integration order.

## Current handoff

### Codebase review — 21 September 2026

The local app includes capture, shared tasks, planning, Focus, daily routines with three effort levels, onboarding, reminder controls, local data export/reset, and optional account isolation. `flutter analyze --no-pub` passes and `flutter test --no-pub` passes all 77 tests. These checks do not establish phone notification delivery or native sharing behavior.

Next pilot step: run the device scenarios in VALIDATION.md and ANDROID_SETUP.md on an actual Android phone and iPhone, recording model, OS version, permission state, expected and actual results. No mobile device or emulator was available to Flutter during this review. The iOS simulator service also failed to connect in this environment. Routine restart is a proposed later feature; it does not replace the outstanding pilot acceptance gate. The old Android/iOS build logs describe earlier attempts and are not current build results.

### Simulator onboarding visibility — 12 September 2026

User could not find onboarding in the iPhone simulator. Read-only inspection found its guest database at schema 7, predating onboarding. Existing workspaces intentionally migrate as completed. User explicitly requested Settings → Run setup again; added a safe rerun action using current values and the same repository. It preserves content, completion and reminders; Skip keeps the existing preference, Finish changes only the selected default. Simulator build/install validation is recorded in VALIDATION.md.


### Routine levels — 12 September 2026

Extended existing smaller-alternative and daily-outcome behavior. Schema 9 adds Normal/Strong descriptions; existing alternative remains Minimum. Legacy done/smaller outcomes retain their meanings; Strong adds a valid completion outcome. Shared Today/Routines controls and Life Map counting use the same records. Export format 1 receives additive fields; reset and reminder policy stay unchanged. No automatic selection, recovery or Planner/Focus integration. See ROUTINE_LEVELS.md. Next recommended feature: Gentle Routine Restart, not implemented.


### Minimal onboarding — 10 September 2026

Schema 8 adds workspace-scoped completion metadata. New databases use three setup steps; existing databases migrate as returning workspaces. Choices reuse Life Map and Reminder Default. Reset clears completion transactionally; Skip preserves current settings. No area activation model, planning preference, permission prompt, or manual rerun was added. Analysis and all 70 tests pass. Next recommended feature: Routine Minimum / Normal / Strong levels; not implemented in this slice.


### Local data controls — 9 September 2026

Completed the existing partial export/reset slice without changing SQLite schema 7 or adding dependencies. Chosen scope: active workspace only; retain sign-in and other workspaces. Export is a coherent version 1 snapshot. Reset requires successful serialized OS cancellation before transactional cleanup. See LOCAL_DATA.md for rollback and crash policy. Next recommended feature: minimal onboarding using existing settings, after physical-device acceptance work.


### Step 2 checkpoint — 9 September 2026 (validation in progress)

Owner asked to fix Android setup and build one more feature, then confirmed continuing after the context-limit concern. Java 17 and Android command-line tools have been downloaded from official sources, checksums verified, and installed under ignored `.tooling/`. SDK platforms 36 and 37.0, build tools 36.0.0, platform tools and NDK 28.2.13676358 are installed. `tool/flutter_android.sh` selects these local tools without editing global shell settings. Initial Android build exposed the pre-existing secure-storage dependency's SDK 37 requirement; compile SDK is now 37 and AGP is patched from 9.1.0 to 9.1.1, whose official compatibility includes 37.0. Native builds are being verified; do not claim they pass until the logs complete.

Notification implementation is connected: one shared serialized coordinator, account generation guards, local OS driver, permission/settings/retry controls in Today, schema 7 delivery status, Quiet Hours, and Reminder Defaults separate from reminder intent. Quiet Hours use a persisted enabled/start/end policy, start-inclusive/end-exclusive boundaries, and delay in-window task reminders to the window end without changing tasks or reminder intent. Reminder Defaults are persisted typed options applied only when an active task first receives a future planned time without an existing or suppressed reminder. Notifications use confirmed UTC instants, generic text, Android inexact-while-idle scheduling, iOS alerts and Android reboot receivers. No automatic permission prompt, exact-alarm access, background task completion, AI or cloud sync. Automated tests cover replacement, failures, account-switch races, bounded future scheduling, Quiet Hours, Reminder Defaults, and elapsed/dismissed reminders. Physical-device reliability is not established.

Resume from `.tooling/android-build.log`, `.tooling/ios-build.log`, and `.tooling/tests.log`; finish analysis/tests/native builds, then update this checkpoint and VALIDATION.md with actual results. Notification snooze actions remain a separate feature; real-phone reliability is not established by builds.

### Incremental checkpoint — 8 September 2026

Owner requested implementation one feature at a time, with resumable notes. Step 1 is complete: connect existing reminder storage to task details and Today. Users can confirm a future device-local date/time, reschedule the same reminder, or remove it without changing the task or deadline. Times are stored as UTC instants and displayed in the current device timezone; this is a one-off instant, not a recurring wall-clock rule. Today lists all pending reminders in time order, including elapsed ones until explicitly removed or the task is completed/cancelled. Both task completion and explicit Focus completion clear the reminder transactionally. Partial/blocked Focus outcomes retain it. The UI explicitly says device notifications are not connected.

Existing reminder schema/repository code was present at inspection; this step connected it and fixed Focus cleanup and the incomplete test repository. No dependencies were added. All 27 automated tests pass; native notification delivery is not implemented or validated.

Next bounded step: notification service prototype using the already-declared flutter_local_notifications dependency. First inspect its installed API and native configuration, then persist scheduling results independently from reminder intent, reconcile on launch/resume/account switch, cancel stale device identifiers, and show permission/delivery status. Keep notification dismissal separate from task completion. Native Android/iPhone checks and timezone/quiet-hour decisions remain required before claiming reliable delivery. Do not start sync or AI in that step.


Implemented: the owner explicitly confirmed expanding this project into the full connected app. The current deliverable is its local core: Today, Inbox, Projects, Planner and More, capture-to-task clarification, editable tasks with explicit completion/cancellation/reopening, preparation checklists, project notes/bugs/ideas/decisions with related-entry links, editable plan blocks and fixed appointments, personal-time blocks, persistent Focus, daily flexible routines, custom life areas and basic recorded-activity reflection. These are working local features, not completion of the whole backlog.

Shared records: original captures remain unchanged. One capture or project entry can create one linked task in this version. Today, Projects, Planner and Focus reference that task ID. A plan move/removal never changes its deadline or status. Focus completion changes the linked task only through the explicit “Finish and complete task” action; partial/blocked outcomes do not complete it. Finished focus and routine records retain their recorded life area when current task/routine categories change.

Architecture: Flutter widgets → ChangeNotifier models → repositories → SQLite, schema version 4. Version 1 captures migrate without loss; schema 2 adds workspace entities, and schema 3 adds project entries/source links and historical life-area snapshots; schema 4 adds one persisted reminder per task. Optional Supabase Auth is initialized from `dart-define` values, uses PKCE and platform secure storage, and selects an account-scoped local database. Native Navigator routes and constructor injection are sufficient here. See IMPLEMENTATION.md and SUPABASE_GOOGLE_SETUP.md for the code guide and setup walkthrough.

Current product defaults (implementation choices, pending feedback): routines recur daily by the current device date, with text windows and smaller alternatives; “Later” leaves that day pending. Planner uses device-local input and stored UTC instants. Focus timer time continues across backgrounding/restart until explicitly paused/finished; it is described as timer time, not proven uninterrupted activity. Routines do not currently schedule notifications. Quiet Hours and reminders use the device's current timezone; the broader travel/home-zone and recurrence policy remains unresolved.

Validation: analysis passes; capture regressions, migration/shared-record tests and connected UI tests pass. See VALIDATION.md for the exact latest counts and build result. Five phone-size destinations were rendered with synthetic data and visually inspected. Android SDK remains missing, so Android compilation and real-phone behavior remain unverified. App identifiers and release signing are still generated defaults.

Not implemented: broader preferences, server ownership, cloud sync/backup, notification snoozing, advanced recurrence/timezone policy, AI, voice and integrations. Quiet Hours, Reminder Defaults, and native notification scheduling are implemented locally but still need device acceptance. These remaining areas stay in the backlog. Email/Google authentication, secure session storage and local account isolation are implemented, but local-record adoption/migration and the outbound sync queue still need design before cloud data is connected. Unsaved form text and unfinished focus-note edits remain memory-only until the relevant save/finish action.

Remaining pilot work: owner walkthrough of the connected local app and native-device validation, then device reminder prototype and preferences. Android SDK setup is needed for Android checks. Configure and exercise the optional account slice using SUPABASE_GOOGLE_SETUP.md, then resolve pilot phones, single/multi-device expectations, account adoption and budget before cloud implementation. Full daily-use pilot acceptance remains pending; basic reflection does not yet include planned-versus-recorded comparisons or saved weekly reviews.

## Visual review access — 7 September 2026

The owner requested the Lovable design review before implementation. Attempted to open `https://focus-space-nexus.lovable.app`: the web reader could not open the URL, no connected browser was available, and native Safari access reported that Computer Use permissions were not granted. No reference screens were inspected, so F02 was left pending at that time and no visual findings were claimed. This access attempt is historical: the owner later chose to skip Lovable and authorized an original implementation, superseding the review dependency.

## Change log

| Date | Change | Basis |
| --- | --- | --- |
| 2026-09-08 | Completed in-app reminder controls and pending list; fixed Focus reminder cleanup; recorded incremental handoff | Owner requested one feature at a time |
| 2026-09-09 | Added persisted Quiet Hours settings and notification rescheduling with boundary, persistence, and duplicate-prevention tests; added task Snooze choices that replace the next reminder without changing task state or deadline | Owner requested one feature at a time |
| 2026-09-09 | Added persisted Reminder Defaults with planned-time creation, explicit override/no-reminder protection, boundary tests, and Quiet Hours compatibility | Owner requested one feature at a time |
| 2026-09-07 | Expanded into the connected local app with shared tasks, projects, planning, Focus, routines and life-area reflection | Owner explicitly chose to expand this project into the full app |
| 2026-09-07 | Created initial documentation set | Supplied proposal and owner's planning request |
| 2026-09-07 | Confirmed Flutter, both mobile platforms, and design-only use of Lovable | Owner clarification; stack recommendation revised |
| 2026-09-07 | Authorized original UI and implemented the first local capture slice | Owner chose to skip Lovable and begin implementation |
| 2026-09-07 | Reviewed owner-created Flutter starter; analysis and counter widget test passed; refreshed project status | Owner requested review before implementation |

For future changes, record decision, status, reason, and affected documents. Do not label a recommendation accepted until the owner's instructions support that status.
