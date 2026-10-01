# Pilot validation plan

## Real-device reliability pass — 1 October 2026

- Notification reconciliation no longer opens a native permission prompt as a
  hidden side effect. Saving a reminder first persists the in-app intent, then
  presents a Work Life explanation before one explicit iOS/Android request.
- Permission handling distinguishes not-requested, allowed, provisional,
  denied, and unsupported behavior. Denied iPhone users receive an explanation
  and an Open Settings action. Returning from Settings refreshes authorization
  and reschedules without changing reminder intent.
- The permission-request bookkeeping key was versioned so an older broken
  installation cannot incorrectly suppress the corrected one-time request.
  Foreground presentation keeps `FlutterAppDelegate` as the notification-center
  delegate after plugin startup.
- Backup and export are distinct: versioned JSON is retained for restoration;
  Markdown provides a readable report; CSV provides task rows for spreadsheet
  use. No database-wide PDF/CSV duplication was added.
- Schedule images are requested at a maximum 1800 px and JPEG quality 85 to
  reduce full-resolution phone-photo upload while retaining timetable text.
  The request remains single-shot, cancellable, retry-safe, and bounded by the
  existing 35-second app / 30-second proxy timeouts.
- Import status now follows real callbacks: Preparing image → Uploading and
  reading timetable → Building editable schedule → Ready for review. A
  long-provider warning does not pretend that another pipeline stage started.
- Debug logs record picker/native resize, image read, input/Base64 bytes,
  encoding, combined upload/backend/provider time, response bytes, parse and
  proposal time, route-render total, and the proxy `Server-Timing` breakdown.
  The Edge Function emits separate authentication, provider, and total values.
- `/Users/rioo/flutter/bin/flutter analyze`: passed with no issues.
- `/Users/rioo/flutter/bin/flutter test`: all 160 tests passed.
- iOS device build passed for `com.kyawhmuesan.worklife.dev`.
- The updated debug app was signed, installed, and launched on Rioooo’s iPhone
  (`00008030-001C395C1A3A202E`, iOS 27.0). Wireless Flutter attachment was then
  lost; this proves deployment/startup, not permission-button interaction or a
  delivered foreground/background banner.
- Still requires a person on the phone: save a future reminder, observe the Work
  Life rationale and native prompt, choose Allow, background/terminate the app,
  and observe the alert. Then deny/reset permission and verify Open Settings.
  Also import a real timetable while attached and record the emitted stage
  numbers. Redeploy the changed `ai-proxy` first to receive server-side timing.

## Multi-device synchronization — 27 September 2026

- SQLite schema v14 adds a durable coalescing outbox, remote revision metadata,
  incremental checkpoint and trigger suppression for downloaded transactions.
- Supabase migration adds owner-bound workspaces, RLS-protected versioned
  records, mutation receipts and an authenticated idempotent write RPC.
- Deterministic fake-remote tests use independent device databases and cover
  create/update/completion, first-sync local/remote merge, project/task links,
  stable checklist IDs, offline restart, bounded retry, lost responses,
  duplicate prevention, remote deletion, stale-device tombstone protection,
  reminder intent without delivery bookkeeping, and workspace isolation.
- Authenticated startup, resume, local mutation, Inbox capture and manual retry
  trigger sync. Guest workspaces remain local. Settings exposes safe sync state.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub`: all 110 tests passed, including nine focused sync
  tests.
- iOS simulator debug build: passed for `com.worklife.app`.
- Android release AAB build: passed; produced a 56.6 MB unsigned validation
  artifact.
- `git diff --check`: passed.
- Live Supabase deployment and physical multi-device acceptance remain external;
  automated tests do not prove production networking or OS lifecycle delivery.

## Production continuation checkpoint — 26 September 2026

LAST COMPLETED:

- AI capture classification routes standalone tasks, projects, routines,
  reminders, and planning requests into native editable approval screens.
- Existing-project AI review shows ADD, CHANGE, MOVE, REMOVE, and UNCHANGED
  operations with per-item acceptance/editing and atomic/idempotent apply.
- Date-only deadlines generate deterministic 9:00 AM local reminders adjusted
  by Reminder Defaults, while explicit reminders, suppression, planned times,
  Quiet Hours, snooze, stable IDs, completion, and reset remain authoritative.
- Production AI calls use an authenticated Supabase Edge Function. Release
  builds cannot use a compiled direct provider key.
- Android/iOS identifiers and permission configuration are release-oriented;
  Android release never falls back to debug signing.

CURRENT VERIFIED STATE:

- Flutter analyzer: no issues.
- Flutter tests: all 101 passed.
- iOS simulator debug build: passed for `com.worklife.app`.
- Android release AAB build: passed, 56.4 MB, intentionally unsigned because
  no private upload keystore was supplied.

CURRENT WORKING AREA:

- Clean implementation checkpoint; no intentionally partial refactor.

SUBSEQUENTLY COMPLETED:

- Offline-first multi-device Supabase workspace synchronization/remote backup
  is implemented and validated in the 27 September checkpoint above.

EXTERNAL BLOCKERS:

- Deploy `supabase/functions/ai-proxy` and configure its server-side
  `AIMLAPI_KEY`.
- Supply Android upload keystore and Apple Team/profile/certificates.
- External validation required: physical device unavailable in this
  environment. Validate notifications, snooze actions, reboot/force-close,
  OAuth callback, photo picker, accessibility, and lifecycle behavior on both
  Android and iPhone.

## Current implementation checkpoint — 25 September 2026

- Added daily/weekly reminder recurrence with schema version 10 migration, resume-time next-occurrence advancement, snooze compatibility, and export/restore support.
- Added exercise routine templates and seven-day exercise progress in Life Map.
- Added focus presets (15/25/50 minutes plus task default) and weekly focus outcome history.
- Added weekly review metrics for focus, routines, exercise, and life areas.
- Added paste-based version-1 JSON backup restore with dependency-ordered workspace reconstruction.
- Added an offline capture-assistant fallback that suggests task/question/reflection/idea handling without modifying original text.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub`: all 77 tests passed.
- `sh tool/flutter_android.sh build apk --release --no-pub`: passed; produced `build/app/outputs/flutter-apk/app-release.apk`.
- Current environment exposes macOS and Chrome only; no Android emulator, iPhone simulator, physical phone, or wireless device is available. OS notification delivery, reboot/force-close behavior, screen-reader behavior, native sharing/restore sheets, and release signing remain unverified.

## Routine levels — 12 September 2026

- `flutter analyze --no-pub`: passed, no issues found.
- `flutter test --no-pub`: all 76 tests passed (70 previous tests plus six routine-level tests).
- Covered: persistence/reopening, all three valid completion levels, same-day replacement/idempotency, later/skipped/unknown history, definition edits preserving recorded level/area, rejecting undefined Strong, v8 migration preserving legacy outcomes/onboarding, additive version-1 export, reset cleanup, shared Today/Routines completion, creation/editing without duplicate routines.
- Initial UI tests needed scroll settlement, the actual Save routine label, and keyboard dismissal; final checks pass.
- Simulator inspection found the user's iPhone workspace still at schema 7, explaining why the newer implementation was not present there. Native update validation is recorded separately when complete. Physical-device behavior remains unvalidated.


## Minimal first-run onboarding — 10 September 2026

- `flutter analyze --no-pub`: passed, no issues found.
- `flutter test --no-pub`: 70 tests passed, including six new onboarding tests and the updated reset interaction test.
- Verified new/returning startup routing without a home flash, completion and skip persistence, independent account/workspace state, v7 migration preservation, transactional failure rollback, custom area idempotency, existing Reminder Default reuse, retained explicit reminders/suppression, reset eligibility, immediate navigation, and scrolling through all three steps at 390 × 844 with 200% text size.
- Existing regression fixtures explicitly represent returning workspaces; dedicated new-workspace tests initialize incomplete setup. The reset UI test now proceeds through Skip before verifying the original capture reuse/account-isolation assertions.
- Initial tests caught a misplaced routing check, which was corrected. Scroll test targeting was corrected for nested TextField scrollables. Final checks pass.
- No native build, physical-device accessibility, screen-reader, notification, or sharing validation was performed. See ONBOARDING.md for behavior and limitations.


## Export and Delete Local Data — 9 September 2026

- Completed an existing partial implementation; no SQLite migration or dependency addition.
- `flutter analyze --no-pub`: **passed, no issues found**.
- `flutter test --no-pub`: **64 tests passed**. Eight new tests supplement the existing export/reset checks. The focused export/reset run passed all 10 selected tests.
- Coverage includes all persisted export categories, exact special-character text, nulls, UTC/date-only fields, relationships and stable IDs, deterministic snapshots, exclusion of device/auth fields, actual populated SQLite reset/reopen/reuse, transaction rollback, notification cancellation failure/retry, in-flight scheduling, account-switch cancellation guards, confirmation/cancel/progress/errors, retained account/other-workspace isolation, Inbox refresh, and file-delivery arguments/bytes.
- Existing Quiet Hours, Reminder Defaults, suppression, explicit reminder, Snooze, completion/cancellation, notification identity and migration regressions remain passing.
- Initial checks found an existing unused test import and a new missing-braces lint; both were corrected. Final analyzer result is recorded above.
- Physical Android/iPhone notification behavior, native sharing/save sheets, and native builds were not validated in this slice. See LOCAL_DATA.md for acceptance steps and limitations.


## Quiet Hours — 9 September 2026

- Added persisted, account-local Quiet Hours with enabled state, start time, and end time in More → Settings.
- Start is inclusive and end is exclusive. Same-day and cross-midnight windows are supported; equal start/end means no quiet period.
- A reminder inside the window is scheduled at the window's end in the device's current local timezone. The stored UTC reminder intent, task status, and deadline are unchanged.
- Existing OS schedules are replaced when the policy changes, using the existing stable notification IDs and payload reconciliation; repeated reconciliation does not duplicate alerts.
- Automated policy, persistence, rescheduling, migration, and regression tests pass. No physical-device notification test was performed, so OS behavior across force-close, reboot, timezone/DST changes, and permission restrictions remains unverified. Routine notifications are not currently scheduled by the app.

## In-app reminders — 8 September 2026

- `flutter analyze --no-pub`: passed with no issues after completing the previously missing reminder methods in the test repository and fixing two new brace lints.
- `flutter test --no-pub`: all 27 tests passed, including the existing capture/account/workspace regressions.
- New checks cover reminder save failure/retry, confirmed rescheduling without duplication, cancelling an edit, removal without changing the task/deadline, Today visibility after the reminder time and after opening/returning, and explicit completion clearing reminders. SQLite checks cover reopen persistence, invalid-time rejection without losing existing intent, inactive-task rejection, and Focus completion versus partial/blocked cleanup.
- Flutter initially required approved SDK cache access; checks then ran successfully. No dependencies were installed or added.
- No native builds or phone tests ran in this step. OS notifications, dismissal, permissions, and timezone/DST transitions remain unverified; these tests do not complete V02–V05.

## Snooze — 9 September 2026

- Added task-level Snooze choices for 10 minutes, 30 minutes, 1 hour, and Tomorrow.
- Snooze preserves the reminder ID, task status, and deadline while replacing the reminder's next scheduled time.
- Repeated snoozes replace the existing device schedule through the existing notification reconciliation; no duplicate alerts are created.
- Completing or cancelling the task continues to remove the snoozed reminder.
- Policy, identity, replacement, and notification idempotency tests pass. Physical Android/iPhone notification behavior remains unverified.

## Reminder Defaults — 9 September 2026

- Added a persisted typed preference with five options: none, at scheduled time, 10 minutes before, 30 minutes before, and 1 hour before.
- A default is applied only when an active task receives a future Planner time and has no existing or explicitly suppressed reminder. Existing reminders are not rewritten when the preference changes.
- Explicit reminder saves clear suppression and take priority. Removing a reminder records explicit no-reminder intent so later plan edits do not recreate it.
- Date-only deadlines and unscheduled tasks do not manufacture a clock time. Previous-calendar-day subtraction, including 00:15 minus 30 minutes, is covered.
- Automated persistence, offset, override, suppression, existing-data safety, and Quiet Hours compatibility tests pass. Physical-device notification behavior remains unverified.

Status: connected local-core automated checks and iOS simulator build pass. Native-device acceptance and the wider pilot scenarios remain incomplete. Earlier sections below preserve the previous-stage test history.

## Starter baseline — 7 September 2026

- Toolchain: Flutter 3.47.2 stable, Dart 3.13.2.
- `/Users/rioo/flutter/bin/flutter analyze --no-pub`: passed, no issues.
- `/Users/rioo/flutter/bin/flutter test --no-pub`: passed, one counter increment widget test.
- The initial sandboxed command could not write Flutter SDK cache metadata; rerunning with approved SDK cache access succeeded. No dependencies were added.
- Android/iOS builds, device launches, signing, and all product scenarios below remain unverified. A passing counter test establishes only the starter baseline.

## Critical scenarios

| ID | Scenario | Expected result |
| --- | --- | --- |
| V01 | Save form capture offline, terminate app, reopen | Original text and confirmed deadline remain |
| V02 | Dismiss notification | Task remains open and visible in pending list |
| V03 | Snooze twice, then complete task | Latest reminder replaces previous ones; future reminders cancelled |
| V04 | Block notification permission | App explains status and still shows pending commitments |
| V05 | Change timezone; exercise recurrence through DST | Documented wall-clock policy applied without duplicate occurrences |
| V06 | Link bug, later idea, next action, and Focus | Shared task and source links remain; duration carries over |
| V07 | End Focus partial or blocked; restart during session | Outcome and elapsed activity persist; task is not falsely completed |
| V08 | Move plan block next to fixed appointment | No duplicate task or silent appointment/deadline change |
| V09 | Interrupt upload after server commits, then retry | One logical change applied once |
| V10 | Edit same item on two devices; delete while other is offline | Conflict preserved or resolved explicitly; no silent loss or resurrection |
| V11 | Switch accounts and attempt foreign record access | Local isolation and server ownership checks deny access |
| V12 | Export then request deletion | Export is usable; documented current-workspace reset and retained account behavior verified |
| V13 | AI proposes uncertain date; reject or edit draft | Source preserved, no invented active deadline |
| V14 | Accept AI draft twice or retry after disconnect | Exactly one set of active records |
| V15 | Compare Insights with known activity and gaps | Totals match; gaps are shown as missing information |
| V16 | AI unavailable or request fails | Capture and tasks remain useful; retry does not lose input |

V13–V14 and the AI-specific part of V16 apply in stage three. Stage two must already work without an AI service.

## Test allocation

Use domain tests for state transitions, recurrence, duration accounting, and draft acceptance. Use integration tests for local transactions, sync idempotency, conflicts, deletion, and database ownership. Use component tests for important interactions and error states. Use real-device flows for notifications, background/terminated states, and account lifecycle.

Record device model, OS version, app build, timezone, permissions, steps, expected result, actual result, and evidence. Test on each supported platform. Include accessibility text scaling, screen-reader navigation, contrast, and useful new-user empty states. Do not equate a simulator pass with device reminder reliability.

## Pilot feedback

Measure baseline before selecting success targets. Review missed commitments, capture effort, rescheduling behavior, useful focus sessions, recovered ideas, and whether planning leaves room for personal life. Keep feedback and findings dated; do not present these proposed checks as completed tests.

## Day Architect implementation — 28 September 2026

- Added schema v17 persistence and sync triggers for recurring schedules, per-date cancellation/time/move exceptions, and planning preferences; schedule context is filtered by weekday and semester bounds.
- Schedule-image weekday parsing and the editable proposal path support saving selected timetable items as weekly commitments with a chosen date range. Settings supports add/edit/remove, fixed weekdays/times/date ranges/location, cancellation/time-change exceptions, and planning preferences. Onboarding links to this setup as optional.
- `DayContextBuilder` and `WeekContextBuilder` tests cover date-specific classes, exceptions, semester boundaries, preference context, and Monday-to-Sunday structure. SQLite and fake-remote sync checks cover durable sync queue entries; backup round-trip covers new records.
- Proposal application retains approval/idempotency, protects locked/fixed blocks, supports selected remove operations, and validates wake/bed boundaries, focused-work cutoff, recurring commitments, transition buffers, overlaps, and approximate daily capacity. Lifestyle blocks do not create tasks.
- Final validation: `/Users/rioo/flutter/bin/flutter analyze --no-pub` passed with no issues; `/Users/rioo/flutter/bin/flutter test --no-pub --reporter compact` passed all 117 tests; `git diff --check` passed. Widget tests emitted an existing onboarding off-screen tap warning, but the suite passed.
- Not validated here: real AIMLAPI/provider output, physical Android/iPhone behavior, Android release signing, live Supabase migration application, and actual two-device Supabase exchange. Apply both sync migrations to the project before remote sync of Day Architect entities.

## Day Architect post-implementation audit — 28 September 2026

- Reproduced and fixed proposal-safety defects: negative clock components could normalize to a different wall time; MOVE/CHANGE could lack a stable Planner ID; a changed block could lose its Task link; and partial acceptance could overlap a rejected/untouched flexible block. Regression tests now require strict clock ranges, stable identities, preserved task links, and overlap/capacity validation against retained Planner blocks.
- Reproduced and fixed recurrence-exception ambiguity. Exceptions now require an existing schedule and a real occurrence inside its date range, reject cancellation mixed with move/time data, and require complete valid time pairs when changing an occurrence.
- Reproduced and fixed sync retry starvation: one delayed outbox row no longer hides later mutations that are ready to upload.
- Reproduced and fixed recovery gaps: restore now parses all optional Day Architect/settings sections before clearing local records, restores explicit reminder suppressions, and rejects suppressions with no matching task. A malformed optional section is tested to leave existing local records intact.
- Added a representative v14 → v17 upgrade test proving an existing Task and sync outbox record survive while Day Architect defaults/tables are created. Capacity overload now includes configured transition time.
- `/Users/rioo/flutter/bin/flutter analyze --no-pub`: passed with no issues.
- `/Users/rioo/flutter/bin/flutter test --no-pub`: passed all 125 tests. The existing large-text onboarding tap warning is still emitted; it does not fail the suite.
- `sh tool/flutter_android.sh build appbundle --release --no-pub`: passed; produced `build/app/outputs/bundle/release/app-release.aab` (57.1 MB). Gradle emitted an SDK XML tooling-version warning, but compilation completed.
- `/Users/rioo/flutter/bin/flutter build ios --simulator --debug --no-pub --no-codesign`: passed; produced `build/ios/iphonesimulator/Runner.app`.
- Still external: deployed Supabase migrations/RLS behavior, live AIMLAPI output, actual two-device cloud exchange, physical-device notifications/timezone behavior, and production signing/store distribution.

## Final Day Architect hardening — 28 September 2026

- Schedule proposals generated from app context now carry deterministic, date-scoped base fingerprints. Approval recomputes them inside the SQLite transaction, rejects stale Planner/task/recurrence state before any write, and presents a native regenerate/cancel explanation. Unrelated records outside the planning context do not invalidate the proposal.
- Backup replacement now executes as one SQLite transaction, including relationships, Planner blocks, Focus/routines, reminders and suppressions, recurring schedules/exceptions, and settings. An injected failure after deletion and several inserts proves domain rows and trigger-generated outbox changes roll back to the original workspace. Notification reconciliation remains after a successful model change, so a failed database restore does not first cancel the original OS schedule.
- Added historical v15 and v16 fixtures using their actual older Day Architect table shapes. Both upgrade to v17 while preserving core records, recurrence data, preferences, foreign keys, sync state/outbox, and one set of sync triggers.
- Planning-preference sync now persists the fields changed locally, uploads patches, preserves pending local fields when remote state arrives, and merges preference JSON in the checked Supabase RPC. Independent edits converge; same-field conflicts use deterministic last-server-arrival-wins.
- The large-text onboarding warning represented an off-screen test hit target at 200% scaling. The test now centers the actual scroll target before tapping; all onboarding tests pass without warning suppression.
- Code-level timezone audit replaced 24-hour `Duration(days: …)` arithmetic with local calendar constructors for recurring/day/week/calendar iteration. Recurring wall-clock values remain date-only/time-only strings. Physical DST and travel-zone behavior is still external validation.
- `/Users/rioo/flutter/bin/flutter analyze --no-pub`: passed with no issues.
- `/Users/rioo/flutter/bin/flutter test --no-pub`: passed all 133 tests without the previous onboarding hit-test warning.
- `git diff --check`: passed.
- `sh tool/flutter_android.sh build appbundle --release --no-pub`: passed; produced `build/app/outputs/bundle/release/app-release.aab` (57.2 MB). The existing non-fatal SDK XML tooling-version warning remains.
- `/Users/rioo/flutter/bin/flutter build ios --simulator --debug --no-pub --no-codesign`: passed; produced `build/ios/iphonesimulator/Runner.app`.
- Still external: deployed Supabase migrations/RLS, live AIMLAPI responses, real two-device Supabase exchange, physical Android/iPhone notification and timezone/DST behavior, and production signing/store distribution.

## Plan My Week — 28 September 2026

- Weekly context tests cover Monday normalization, a September/October boundary, compact shared task data, planned dates, temporary user constraints, seven fingerprints, recurring exceptions, and capacity data.
- Native proposal widget coverage verifies a seven-day grouped review, open-day states, editable cards, selection controls, and no raw JSON.
- Repository coverage verifies a transactional cross-day move, two split sessions linked to one stable Task, seven-date stale protection, idempotent normal persistence, and rejection of work scheduled after its deadline. Existing partial-acceptance, overlap, fixed-block, sleep/cutoff, capacity, stale and rollback tests remain active.
- `/Users/rioo/flutter/bin/flutter analyze`: passed with no issues.
- `/Users/rioo/flutter/bin/flutter test`: passed all 137 tests.
- `git diff --check`: passed.
- `sh tool/flutter_android.sh build appbundle --release`: passed; produced `build/app/outputs/bundle/release/app-release.aab` (57.3 MB). The existing non-fatal SDK XML tooling-version warning remains.
- `/Users/rioo/flutter/bin/flutter build ios --simulator`: passed; produced `build/ios/iphonesimulator/Runner.app`.
- Still external: live AIMLAPI weekly output quality, deployed Supabase migrations/RLS and real two-device exchange, physical-device notifications/timezone/DST/accessibility, and production signing/store submission.


## First capture slice — 7 September 2026

- `flutter analyze --no-pub`: passes without issues.
- `flutter test --no-pub`: all five tests pass. Real temporary SQLite database close/reopen preserves exact original text, IDs and timestamps; retry does not duplicate; blank text is rejected. Widget checks cover capture/search/detail/rebuild, retained draft after save failure, load retry, whitespace-only input, and small-screen large-text layout.
- Initial checks found two lint issues and widget-test frame/viewport problems; corrected and rerun successfully.
- `flutter build ios --simulator --debug --no-pub`: passes.
- `flutter build apk --debug --no-pub`: blocked before compilation because Flutter reports no Android SDK. No SDK was found at the usual user locations and `android/local.properties` has no `sdk.dir`. Android SDK setup is required; no APK was produced.
- Still required on Android and iPhone: save in airplane mode, force-close and reopen, verify original Unicode/multiline text, search and detail, keyboard interaction and screen-reader navigation. Automated database reopening is not a native process-restart test.
- No UI screenshots or real-device interaction were inspected in this implementation session. Notifications, sync, account isolation, tasks, AI, and wider pilot checks remain unimplemented/unverified.


## Connected local core — 7 September 2026

- `flutter analyze --no-pub`: passes with no issues after final app changes.
- `flutter test --no-pub`: full run passed 13 tests; an additional overnight/calendar validation regression was then added and `flutter test test/workspace_repository_test.dart --no-pub` passed all seven repository tests. Across these runs all 14 current tests passed (five capture checks, seven workspace repository checks, two connected widget checks).
- Covered: version 1 capture migration, duplicate conversion prevention, exact source retention, shared task completion, plan move/removal without deadline/status mutation, fixed appointment preservation, overnight visibility, invalid calendar dates, focus exclusivity/pause/reopen/partial/completed outcomes, bug → idea → task → focus references, historical area snapshots, per-day routine retry semantics and unknown gaps.
- Connected widget journey: saved capture → edited task → selected project → original-note detail → explicit completion → matching project task state. Navigation was exercised at phone size with enlarged text. Existing capture error/retry checks continue passing.
- `flutter test tool/render_review.dart --no-pub`: passes; rendered Today, Inbox, Projects, Planner and More at 390 × 844 using synthetic records. All five final PNGs in `build/review/` were visually inspected. This is a Flutter test render, not evidence of a native phone launch. The first renderer attempt stalled on test-clock/font/filesystem work and was stopped; moving that work into the appropriate asynchronous test context fixed it. Icon fonts were explicitly loaded for the final screenshots.
- `flutter build ios --simulator --debug --no-pub`: final build passes, producing `build/ios/iphonesimulator/Runner.app`.
- Android was not rebuilt in this expansion because the previously established missing SDK is unresolved. No physical device, screen reader, notification delivery or native process-restart test ran.

Before pilot use, exercise the IMPLEMENTATION.md journey on both phones: airplane-mode saves, force-close/reopen, active/paused Focus recovery, keyboard/large-text forms, cancelled/completed task behavior and app resume across midnight. Validate device clock changes, timezone changes, and daylight-saving gaps/repeated local times before claiming timezone reliability. Schema migration tests do not establish platform notification or secure-account behavior.
