# Work Life — Product Roadmap & AI Implementation Guide

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

> Purpose: This file is the long-term source of truth for AI-assisted development of the **Work Life** Flutter app.
> It separates what already exists, what still needs validation, what must be built before a pilot, and what should remain future work.

---

## 1. Product Summary

**Work Life** is a local-first productivity and personal planning app built with Flutter.

The current product already has a meaningful working core. The next stage is not to keep adding random screens. The goal is to make the core workflow reliable, configurable, recoverable, testable, and ready for real users.

### Core product journey

```text
Capture
  ↓
Inbox / Organize
  ↓
Projects / Planner / Today
  ↓
Reminder
  ↓
Focus / Routine
  ↓
Complete
  ↓
Review / Insights
```

The product should prioritize this connected journey before adding AI, integrations, or collaboration.

---

## 2. Current Verified State

The repository audit confirmed the following:

- Flutter static analysis passes.
- Existing automated tests pass.
- The application is meaningfully local-first.
- Native notification scheduling exists in the implementation.
- Some product documentation is outdated and still describes notification scheduling as future work.

### Existing product areas

- Capture
- Inbox
- Projects
- Today
- Planner
- Focus
- Routines
- Life Map
- Local accounts
- Reminders
- Native notification scheduling
- Local persistence

### Important status rule

Do not classify an existing feature as "missing" simply because product documentation is stale.

Use these states:

- **Implemented** — code exists and automated tests cover it.
- **Implemented, needs device validation** — code exists, but real-world device behavior still needs testing.
- **Missing / not implemented** — feature is not present in code.
- **Deferred** — intentionally postponed until after the pilot.

---

## 3. Product Principles

All future implementation work should follow these principles.

### 3.1 Local-first reliability

The app should continue working when internet access is unavailable.

Do not introduce a cloud dependency into a workflow that currently works locally unless the product explicitly requires it.

### 3.2 Small, complete slices

Implement one feature at a time.

Each feature should include:

- Product behavior
- Data model changes
- State management
- UI
- Validation
- Error states
- Persistence
- Automated tests
- Documentation updates

Do not create partially connected screens that are not integrated into the real user journey.

### 3.3 Preserve existing behavior

Before changing a feature:

1. Inspect the existing implementation.
2. Inspect related tests.
3. Identify current behavior.
4. Reuse existing patterns and architecture.
5. Avoid unnecessary refactors.

A new feature should not break an existing tested workflow.

### 3.4 No premature complexity

Do not introduce:

- Cloud sync
- Firebase/Supabase
- AI services
- Calendar integrations
- Gmail integrations
- Collaboration
- New state-management frameworks
- New architecture layers

unless the active feature explicitly requires them.

### 3.5 Product behavior before visual polish

Correct behavior is more important than animations, advanced styling, or decorative UI.

---

# 4. Priority Roadmap

## P0 — Pilot Readiness

These tasks should be addressed before calling the app pilot-ready.

---

### P0.1 Real-Device Notification Validation

**Status:** Implemented in code; needs real-device validation.

Validate on supported Android and iOS devices.

#### Required scenarios

- Notification fires while app is open.
- Notification fires while app is backgrounded.
- Notification fires after app is force-closed, where supported by OS behavior.
- Scheduled reminders survive expected app lifecycle behavior.
- Permission denied state is handled gracefully.
- Permission can be requested again from an appropriate UI flow.
- Tapping a notification opens the correct task or relevant destination.
- Dismissing a notification does not mark a task complete.
- Editing reminder time replaces the old schedule correctly.
- Deleting a task removes its pending reminder.
- Completing a task removes unnecessary pending reminders.
- Device timezone changes do not create incorrect duplicate reminders.
- Daylight-saving gaps or repeated times are handled predictably.
- Reboot behavior is verified on Android if relevant to the notification implementation.

#### Deliverable

Create or update a validation document containing:

- Device model
- OS version
- Test scenario
- Expected result
- Actual result
- Pass/fail
- Notes

---

### P0.2 Documentation Alignment

Update documentation so it matches the implementation.

Review at minimum:

- `PRODUCT.md`
- `BACKLOG.md`
- `IMPLEMENTATION.md`
- `VALIDATION.md`

Notification scheduling should be described as:

> Implemented locally and covered by automated tests, but still requiring real-device acceptance testing.

Do not leave contradictory feature-status descriptions across documents.

---

### P0.3 Define Pilot Scope

The initial pilot should have a deliberately small scope.

Recommended initial definition:

> **Pilot v1: local-first, single-device productivity workflow.**

Cloud sync and multi-device support should not automatically block the pilot unless they are explicitly required by the pilot users.

#### Suggested pilot journeys

**Journey 1 — Capture → Plan**

```text
Quick Capture
  ↓
Inbox
  ↓
Assign project/date
  ↓
Appears in Today / Planner
```

**Journey 2 — Plan → Reminder → Complete**

```text
Create task
  ↓
Schedule reminder
  ↓
Receive native notification
  ↓
Open task
  ↓
Complete task
```

**Journey 3 — Routine**

```text
Create routine
  ↓
Schedule recurrence
  ↓
Receive reminder
  ↓
Complete occurrence
  ↓
Next occurrence remains correct
```

These journeys should work reliably before expanding the feature surface.

---

# 5. P1 — Core Product Completion

## P1.1 First-Run Onboarding

Create a lightweight onboarding flow for new users.

Possible setup fields:

- Working days
- Working hours
- Default reminder preference
- Quiet hours
- Timezone behavior
- Primary planning preference

### Requirements

- Must be skippable where reasonable.
- Must not block use of the local app unnecessarily.
- Values must be editable later in Settings.
- Onboarding must not duplicate settings logic.

---

## P1.2 Settings

Create a central settings surface.

Suggested groups:

### Notifications

- Notifications enabled/disabled
- Default reminder timing
- Quiet hours
- Reminder behavior

### Planning

- Working hours
- Working days
- Default planning behavior

### Time

- Current timezone display
- Timezone policy if the product supports travel-aware behavior

### Data

- Export
- Delete local data
- Account/sign-out behavior

### About / diagnostics

- App version
- Local data status
- Notification permission status

---

## P1.3 Quiet Hours

**Status:** Implemented locally and automated-tested; physical-device notification behavior remains unverified.

Quiet hours prevent routine or task reminders from interrupting the user during a configured time window.

### Example

```text
Quiet hours:
23:00 → 07:00
```

A reminder scheduled inside quiet hours is delayed until quiet hours end. The stored reminder intent and associated task are unchanged. Routine notifications are not currently scheduled by the app.

Recommended first policy:

> Delay the reminder until quiet hours end, unless the reminder is explicitly marked as allowed during quiet hours.

### Edge cases

- Quiet hours cross midnight.
- Start and end are equal.
- User disables quiet hours.
- Reminder scheduled exactly at start time.
- Reminder scheduled exactly at end time.
- User edits quiet hours while reminders already exist.
- Timezone changes after reminders are scheduled.

### Required tests

- Standard same-day range.
- Cross-midnight range.
- Disabled state.
- Boundary times.
- Persistence.
- Existing reminder rescheduling after setting changes.

---

## P1.4 Snooze

**Status:** Implemented locally and automated-tested; physical-device notification behavior remains unverified.

Allow users to temporarily postpone a reminder without changing the task's primary planning date. The initial choices are 10 minutes, 30 minutes, 1 hour, and Tomorrow.

Suggested initial choices:

- 10 minutes
- 30 minutes
- 1 hour
- Tomorrow

### Rules

- Snoozing should not mark a task complete.
- Snooze should create/update only the appropriate notification.
- Repeated snoozes must not create duplicate notifications.
- Completing/deleting the task should clear the snoozed reminder.

---

## P1.5 Reminder Defaults

**Status:** Implemented locally and automated-tested; physical-device notification behavior remains unverified.

Allow configurable default reminder behavior. The preference is applied only when a task first receives a future planned time; it does not rewrite existing reminder intent.

Examples:

- No default reminder
- At task time
- 10 minutes before
- 30 minutes before
- 1 hour before

Keep initial options simple.

---

## P1.6 Export and Delete Data

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

The requirements below are reference guidance; the linked schema documents the implemented JSON-only version.

Users need control over their data.

### Export

Recommended first export format:

- JSON for full fidelity
- Optional CSV for task-oriented data later

Export should include appropriate local entities such as:

- Tasks
- Projects
- Routines
- Planner data
- Focus records
- Life Map data
- Settings

### Delete local data

Deletion must:

- Clear local persisted data.
- Remove scheduled notifications.
- Reset user-configurable local settings as defined by the product.
- Return the app to a safe initial state.

Use confirmation UI for destructive actions.

---

# 6. P2 — Reliability and Recovery

## P2.1 Cloud Backup

Cloud backup is different from full multi-device sync.

A simple backup system may be introduced before real-time sync if recovery becomes a user requirement.

Before implementation, decide:

- Provider
- Authentication model
- Encryption requirements
- Backup frequency
- Restore behavior
- Version compatibility
- Ownership rules

Do not add cloud backup automatically without a product decision.

---

## P2.2 Multi-Device Sync

Full sync should be treated as a separate major project.

Required design areas:

- Stable entity IDs
- Created/updated timestamps
- Offline change queue
- Retry behavior
- Duplicate prevention
- Conflict resolution
- Deletion/tombstone behavior
- Account ownership
- Device identity
- Sync status UI
- Error handling

### Conflict example

```text
Phone:
Task time → 17:00

Tablet:
Task time → 19:00
```

The app must have an explicit conflict policy.

Do not implement sync by simply overwriting the entire database from whichever device uploads last.

---

# 7. P2 — Insights and Review

Insights should only show data the app can measure reliably.

Possible metrics:

- Planned tasks
- Completed tasks
- Postponed tasks
- Missed tasks
- Planned focus duration
- Recorded focus duration
- Routine consistency
- Frequently postponed projects/categories

### Weekly review

Possible review content:

- Wins
- Incomplete commitments
- Most postponed tasks
- Focus summary
- Routine summary
- User-written reflection

Do not fabricate conclusions when activity data is missing.

---

# 8. P3 — Future Features

These features are intentionally deferred until the local pilot is trustworthy.

## AI clarification

Possible future behavior:

```text
User:
"Finish report sometime tomorrow"

AI draft:
Task: Finish report
Date: Tomorrow
Time: Unspecified
Project: Suggested project
```

AI output must remain editable and should never silently alter the user's plan.

## Voice capture

Convert speech into a draft task or note.

Voice input should still pass through the normal task creation and validation flow.

## Calendar integration

Potential use cases:

- Read calendar events
- Avoid scheduling conflicts
- Convert events into planning context
- Suggest focus blocks

Do not implement until authentication, ownership, and sync rules are defined.

## Gmail integration

Potential use cases:

- Convert an email into a task
- Reference an email from a project

Do not automatically import or send content without explicit user action and permissions.

## Images and links

Possible attachments:

- URLs
- Images
- Reference files

Add only after core task data remains stable.

## Shared planning

Collaboration introduces:

- Shared ownership
- Permissions
- Invitations
- Conflict handling
- Network dependence
- Activity history

Treat it as a separate product phase.

---

# 9. Product Decisions Required

Before implementation of related features, explicitly answer these questions.

## Pilot

- Is pilot v1 single-device?
- Is cloud backup required?
- Is multi-device sync required?
- Which Android/iOS versions are supported?
- What exact devices will be tested?
- Who are the pilot users?
- What are the three required acceptance journeys?

## Time and reminders

- Do routines follow the user's current timezone or a fixed home timezone?
- What happens to reminders during quiet hours?
- What happens during daylight-saving gaps?
- What happens during repeated DST times?
- What are default snooze durations?
- Can some reminders bypass quiet hours?

## Data

- What happens to unsynced data on sign-out?
- What exactly is deleted during "Delete My Data"?
- What export formats are required?
- Does account deletion also remove cloud data in future versions?

## AI

- Which data may be sent to an external AI service?
- Is AI opt-in?
- What user data must never leave the device?
- Must AI-generated task changes always require confirmation?

---

# 10. AI Development Workflow

When an AI coding assistant receives a feature task, it should follow this process.

## Step 1 — Inspect

Read:

- Relevant product docs
- Relevant implementation files
- Related models
- State/repository/service layers
- Existing tests

Do not start editing immediately.

## Step 2 — Explain current behavior

Before changing code, summarize:

- What exists
- What is missing
- What will change
- Which files are likely involved
- What assumptions are being made

## Step 3 — Implement the smallest complete feature

Avoid unrelated refactors.

Reuse existing project architecture.

## Step 4 — Add tests

Tests should cover:

- Happy path
- Important edge cases
- Persistence
- Regression behavior

## Step 5 — Validate

Run at minimum:

```bash
flutter analyze --no-pub
flutter test --no-pub
```

If those commands are not appropriate for the environment, explain why and run the closest valid equivalents.

## Step 6 — Update documentation

Update feature status and behavior in relevant markdown files.

## Step 7 — Report

Finish with:

- What changed
- Files changed
- Tests added
- Validation result
- Known limitations
- Recommended next feature

---

# 11. Definition of Done

A feature is not complete only because a screen exists.

A feature is complete when:

- Product behavior is defined.
- UI is implemented.
- State changes work.
- Persistence works where required.
- Errors/empty states are handled.
- Edge cases are considered.
- Automated tests are added.
- Existing tests still pass.
- Static analysis passes.
- Documentation reflects reality.
- No unrelated functionality was broken.

For notification-related features, real-device validation may also be required before the feature is considered pilot-accepted.

---

# 12. Recommended Immediate Implementation Order

Use this order unless a new product requirement changes priority.

1. Align notification documentation with current code.
2. Perform real-device notification acceptance testing.
3. Define and document pilot scope.
4. Validate the implemented **Quiet Hours** slice on physical devices.
5. Validate the implemented **Snooze** slice on physical devices.
6. Implement reminder defaults.
7. Build Settings around those behaviors.
8. Add first-run onboarding.
9. Add data export/delete controls.
10. Improve insights and weekly review.
11. Decide whether cloud backup is actually required.
12. Design sync only if multi-device use becomes a real requirement.
13. Add AI/integrations only after the pilot workflow is reliable.

---

# 13. Current Next Feature Recommendation

## Quiet Hours

Quiet Hours is a good next implementation slice because:

- Native notifications already exist.
- It improves user trust.
- It is small enough to implement and test independently.
- It naturally leads into Settings.
- It avoids premature cloud or AI complexity.
- It adds real product value before the pilot.

The first version should remain simple:

```text
Quiet Hours
Enabled: Yes
Start: 23:00
End: 07:00
Behavior: Delay reminder until quiet hours end
```

Do not add advanced per-project exceptions or complex notification priority levels in the first version.

---

## Final Product Direction

The project should move from:

> "Add more screens and features"

toward:

> "Make the complete Capture → Plan → Reminder → Complete → Review journey trustworthy."

A smaller reliable product is more valuable than a larger collection of partially connected features.
