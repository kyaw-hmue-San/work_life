# Pilot validation plan

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
