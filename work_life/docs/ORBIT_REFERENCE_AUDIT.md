# Work Life — Orbit Reference Audit & Feature Roadmap

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](ONBOARDING.md).

> Reference product: https://focus-space-nexus.lovable.app/
>
> Purpose: Translate the useful ideas from the Orbit Life OS prototype into a practical roadmap for the existing Flutter **Work Life** app without blindly copying every screen or introducing premature complexity.

---

# 1. How to Read This Document

This audit uses four implementation decisions:

- **KEEP** — Work Life already has the core surface. Improve only where parity creates real value.
- **BORROW NOW** — Strong idea that supports pilot readiness or the core user journey.
- **BORROW NEXT** — Valuable feature, but should come after the immediate pilot-readiness work.
- **DEFER** — Interesting, but too expensive, dependent on AI/cloud/integrations, or unnecessary for the first pilot.

The known Work Life baseline from the repository audit is:

- Capture exists
- Inbox exists
- Projects exists
- Today exists
- Planner exists
- Focus exists
- Routines exists
- Life Map exists
- Local accounts exist
- Reminders exist
- Native notification scheduling exists
- Local persistence exists
- Flutter analysis previously passed
- Existing automated tests previously passed

Important rule:

> If a Work Life screen exists but the exact Orbit behavior has not been verified in source, classify it as **existing surface, parity unverified**, not “missing.”

---

# 2. Executive Recommendation

Do **not** try to recreate the Lovable site screen-for-screen.

Its strongest product ideas are:

1. Calm planning instead of guilt/streak pressure
2. Energy-aware planning
3. Minimum / Normal / Strong routine versions
4. Recovery after missed routines
5. Small fallback plans when the day collapses
6. Clear completion conditions during focus
7. Daily review that moves unfinished work forward intentionally
8. Insights based on real behavior rather than judgment

Those ideas fit the Work Life product well.

The expensive parts should stay deferred:

- AI capture interpretation
- Voice/photo capture
- Calendar integration
- Cloud sync
- Collaboration
- Advanced predictive planning

---

# 3. Page-by-Page Audit

## 3.1 Today

### Orbit behavior

The Today page acts as a command center with:

- Three priorities
- Energy check-in
- Suggested adaptive plan
- Daily timeline
- Routine progress
- Left-from-yesterday items
- Suggested next action
- Upcoming deadline
- Recent captured thoughts
- Shortcut to Focus

### Work Life status

**Existing surface: Today exists. Exact parity is unverified.**

### Decision

**KEEP + BORROW SELECTIVELY**

### Worth borrowing

#### A. Three priorities

A deliberately short daily priority list is high value.

Recommended rule:

- Up to 3 primary priorities
- Other tasks can still exist in Today
- Priorities should be visually distinguished

#### B. Energy check-in

Simple values are enough:

- Low
- Steady
- Sharp

Do not build health scoring or AI emotion detection.

Use energy as planning context only.

#### C. Left from yesterday

Useful because it makes rollover explicit instead of silently carrying tasks forever.

Possible actions:

- Move to today
- Reschedule
- Return to backlog
- Complete
- Archive/cancel if appropriate

#### D. Suggested next action

Useful after the task model has enough information such as:

- priority
- duration
- deadline
- project
- current plan

The first implementation can be deterministic rather than AI-powered.

### Not necessary now

- Complex dynamic dashboards
- Many cards just because the prototype has them

---

## 3.2 Capture

### Orbit behavior

Capture supports:

- Text
- Voice
- Photo
- Link
- Note
- Autosave to Inbox
- “Interpret” action
- Proposed life area
- Proposed project
- Proposed type
- Proposed priority
- Proposed next action
- Proposed session length
- User approval before conversion

### Work Life status

**Capture exists.**

The current roadmap already treats AI clarification, voice capture, images, links, and integrations as future work.

### Decision

**KEEP text/local capture. DEFER multimodal + AI interpretation.**

### Worth borrowing now

- “Capture first, organize later” philosophy
- Safe autosave
- Never silently turn captured text into committed work

### Worth borrowing later

A structured interpretation draft:

```text
Captured:
"Prepare seminar slides tomorrow"

Suggested:
Type: Task
Project: University Seminar
Date: Tomorrow
Duration: 30 min
Priority: Medium

[Confirm] [Edit]
```

### Defer

- Voice transcription
- Photo analysis
- Link extraction
- External AI interpretation

These should not block pilot readiness.

---

## 3.3 Inbox

### Orbit behavior

Inbox includes:

- Unreviewed
- Tasks
- Ideas
- Notes
- Archived

A captured item can be converted into:

- Task
- Project
- Routine
- Reminder
- Note
- Calendar
- Archive

It can also show:

- Related project
- Suggested action
- Review state

### Work Life status

**Inbox exists. Exact classification/conversion parity is unverified.**

### Decision

**KEEP + BORROW NEXT**

### Worth borrowing

A clear “process this capture” workflow.

Recommended first conversion set:

- Task
- Project
- Routine
- Note
- Archive

Do not add Calendar conversion until calendar integration actually exists.

Suggested actions should remain optional.

---

## 3.4 Routines

### Orbit behavior

This is one of the strongest parts of the reference product.

Each routine has:

- Minimum version
- Normal version
- Strong version
- Four-week consistency
- Weekly completion view
- “Needs a restart” state
- Gentle restart suggestion
- No streak-pressure framing

Example:

```text
Exercise

Minimum: 5 min
Normal: 30 min
Strong: 60 min
```

### Work Life status

**Routines exists. Exact support for routine levels/recovery is unverified.**

### Decision

**BORROW NEXT — HIGH VALUE**

### Recommended feature: Routine Levels

Each routine can optionally define:

- Minimum
- Normal
- Strong

A logged completion records which version was completed.

### Why it is valuable

This solves a common problem:

A user planned 30 minutes but only has 5.

Instead of recording complete failure, the minimum version still preserves progress.

### Recommended data model concept

```text
Routine
- title
- schedule
- minimumTarget
- normalTarget
- strongTarget

RoutineLog
- routineId
- date
- levelCompleted
- actualAmount
```

Exact implementation must follow the existing repository architecture.

### Recovery behavior

Avoid infinite streaks.

Prefer:

- Recent consistency
- Days completed
- Recovery after misses
- “Restart gently”

This matches the broader Work Life product tone better than punishment-based streaks.

---

# 3.5 Projects

### Orbit behavior

Projects supports:

- Board view
- List view
- Timeline view

Work is grouped into:

- Now
- Next
- Later
- Done

Items also carry types such as:

- Task
- Bug
- Idea
- Feature

### Work Life status

**Projects exists.**

### Decision

**KEEP. BORROW ONLY THE SIMPLEST USEFUL ORGANIZATION.**

### Worth borrowing

The Now / Next / Later / Done model can be useful if it fits existing project architecture.

It communicates priority more naturally than a giant undifferentiated task list.

### Defer / possibly unnecessary

Do not build Board + List + Timeline simultaneously unless users actually need all three.

The Planner already provides a time-oriented view.

A project timeline can become duplicate product surface.

Recommended first rule:

> One strong project view is better than three incomplete views.

“Side quests” is branding, not a required feature.

---

# 3.6 Adaptive Planner

### Orbit behavior

The planner considers:

- Free time
- Energy
- Deadline pressure
- Unfinished work
- Routines

It creates an ordered plan including:

- Focus blocks
- Breaks
- Exercise/routines
- End-of-day preparation

Controls include:

- Accept plan
- Adjust plan
- Make it lighter
- Add more focus time

It also explains why the plan was created and provides a fallback plan if the night collapses.

### Work Life status

**Planner exists. Adaptive parity is unverified.**

### Decision

**BORROW NEXT/LATER — MAJOR PRODUCT DIFFERENTIATOR**

### Important recommendation

Do **not** start with AI.

Build a deterministic planning engine first.

Example inputs:

```text
Available time: 120 min
Energy: Steady
Deadline within 4 days
2 unfinished tasks
1 routine due
```

Possible rules:

1. Put the nearest deadline first.
2. Cap hard-focus session length based on energy.
3. Insert a short break after long focus.
4. Include one routine if time remains.
5. Reserve a small closing block.
6. Generate a fallback version.

### Fallback plan

This is a particularly good idea.

Example:

```text
Original:
90 minutes of work

Fallback:
10 min seminar review
5 min routine
```

This can become a signature Work Life behavior.

---

# 3.7 Focus

### Orbit behavior

Focus includes:

- Current task
- Completion condition
- Timer
- Start
- Finish
- Capture idea
- Checklist
- Related notes

### Work Life status

**Focus exists. Exact support for completion conditions/checklists/related notes is unverified.**

### Decision

**KEEP + BORROW NEXT**

### High-value addition: Completion Condition

Instead of:

```text
Work on report
```

use:

```text
Finish condition:
Draft the introduction and methodology outline.
```

This gives the focus session an endpoint.

### Capture idea during focus

Useful behavior:

- Quick capture without leaving Focus
- Save idea to Inbox
- Return immediately to current session

This should reuse the existing Capture/Inbox system.

### Checklist

Useful only if it reuses task/subtask architecture.

Do not create a second checklist system inside Focus.

---

# 3.8 Insights

### Orbit behavior

Insights shows:

- Weekly focus time
- Change vs last week
- Most consistent routine
- Recovery rate
- Best productive time
- Routine consistency
- Most postponed items
- Life-area balance
- Observations
- Project progress

### Work Life status

The previous audit already identified **Insights completion** as unfinished product work.

### Decision

**BORROW LATER — AFTER EVENT DATA IS TRUSTWORTHY**

### Good metrics

- Planned vs completed tasks
- Planned vs recorded focus
- Postponement count
- Routine consistency
- Recovery after misses
- Project completion
- Life-area distribution

### Critical rule

Do not fabricate insights.

If there is not enough data:

```text
Not enough activity yet to estimate your best focus window.
```

is better than generating a fake pattern.

### Avoid

- Judgmental productivity score
- One universal “performance” number
- AI conclusions unsupported by recorded activity

---

# 3.9 Life Map

### Orbit behavior

Life Map organizes the user around areas such as:

- Health
- University
- Development
- Work
- Creativity
- Personal Growth

Each area can contain:

- Routines
- Projects
- Goals
- Recent ideas

It offers:

- Orbit view
- List view

### Work Life status

**Life Map exists. Exact parity is unverified.**

### Decision

**KEEP**

### Worth borrowing

The underlying relationship is valuable:

```text
Life Area
├── Projects
├── Routines
├── Goals
└── Captured ideas
```

This can become the structural layer connecting the rest of the application.

### Possibly unnecessary

The visual orbit itself is optional.

If an orbit visualization is expensive or difficult to use on mobile, a good list/card view is enough.

Do not prioritize visualization over product behavior.

---

# 3.10 Profile & Settings

### Orbit behavior

Settings contains:

- Display name
- Email
- Active life areas
- Wake time
- Sleep time
- Default focus session
- Planning style
- Reminder preferences
- Morning reminder
- Evening review reminder
- Routine restart reminder
- Deadline warning
- Re-run onboarding
- Open review
- Reset all data

### Work Life status

The repository audit identified **Settings and onboarding as missing/high-priority pilot work.**

### Decision

**BORROW NOW — HIGH PRIORITY**

### Recommended Work Life settings structure

```text
Settings

Profile
- Display name

Planning
- Working days
- Working hours
- Default focus duration
- Planning style

Notifications
- Quiet Hours
- Default reminder timing
- Reminder preferences

Life Areas
- Active areas

Data
- Export data
- Delete/reset local data

About
- App version
- Notification permission status
```

Do not build every reminder type at once.

---

# 3.11 Onboarding

### Orbit behavior observed

The first onboarding step asks the user which life areas matter right now.

Examples:

- Study
- Development
- Work
- Exercise
- Meditation
- Reading
- Music
- Personal Projects
- Other

### Work Life status

**Onboarding was identified as missing/high-priority.**

### Decision

**BORROW AFTER SETTINGS FOUNDATION**

### Important architecture rule

Onboarding must write to the same settings/data model used by the normal Settings screen.

Do not maintain a separate “onboarding configuration” model.

### Suggested first-run flow

1. Choose active life areas
2. Set working/waking hours
3. Configure basic reminder preference
4. Finish

Keep it short.

Do not require users to configure every feature before entering the app.

---

# 3.12 Daily Review

### Orbit behavior

Daily Review summarizes:

- Focus time
- Number of focus sessions
- Priorities completed
- Captured ideas
- Routine completion
- Postponed work
- Completed priorities
- Suggested carry-forward plan
- Morning/evening mood comparison
- Routine progress
- Reflection
- Captures still waiting in Inbox

Actions include:

- Accept tomorrow's plan
- Edit tomorrow
- Finish review

### Work Life status

The previous audit mentioned weekly review/insights completion, but a dedicated daily review was not confirmed.

### Decision

**BORROW NEXT/LATER — HIGH PRODUCT VALUE**

### Recommended first Daily Review

Keep v1 small:

```text
Today

Priorities
2 / 3 completed

Focus
1 h 45 m

Routines
3 / 5 completed

Unfinished
2 items

Reflection
[optional text]

[Move unfinished work]
[Finish day]
```

Do not build complex mood analytics initially.

### Why it matters

Daily Review closes the loop:

```text
Capture
→ Plan
→ Do
→ Review
→ Tomorrow
```

Without review, the system mostly manages input and execution but does not help the user reset intentionally.

---

# 4. Features to Borrow by Priority

## P0 — Do Before New Product Expansion

These remain the original pilot-readiness requirements:

1. Real-device notification validation
2. Documentation alignment
3. Pilot scope definition

---

# P1 — Build Now

## 1. Settings foundation

Create the minimum real Settings screen and shared settings persistence.

Do not implement the entire final settings vision in one task.

## 2. Quiet Hours

First narrow feature inside Settings.

Initial behavior:

```text
Enabled: Yes
Start: 23:00
End: 07:00
Policy: Delay normal reminders until quiet hours end
```

## 3. Reminder defaults

After Quiet Hours is stable.

## 4. Local data controls

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.


- Export
- Reset/delete local data
- Cancel pending notifications appropriately

## 5. Onboarding

Build on top of the same settings infrastructure.

---

# P2 — Strengthen the Core Experience

Recommended order:

1. Routine Minimum / Normal / Strong levels
2. Gentle routine recovery after misses
3. Focus completion condition
4. Quick Capture while focusing
5. Explicit yesterday rollover
6. Three daily priorities
7. Simple energy check-in
8. Daily Review

These features deepen the existing Work Life experience without requiring cloud services.

---

# P2/P3 — Adaptive Planning

After the underlying task/routine/history data is reliable:

1. Deterministic adaptive planner
2. “Make it lighter”
3. Fallback plan
4. Explain why the plan was chosen
5. Suggested next action

Do not require generative AI for the first adaptive planner.

---

# P3 — Insights

Build only after enough reliable history exists.

Priority insights:

1. Planned vs completed
2. Planned vs recorded focus
3. Most postponed
4. Routine consistency
5. Recovery rate
6. Project progress
7. Life-area balance
8. Productive time windows

---

# P4 — Deferred

Do not prioritize for the local pilot:

- AI capture interpretation
- Voice capture
- Photo capture
- Link intelligence
- Gmail
- Calendar integration
- Cloud sync
- Collaboration
- Advanced AI planning

---

# 5. Things Not Worth Copying Blindly

## Multiple views everywhere

Board/List/Timeline looks impressive but multiplies UI/state/testing cost.

Add a new view only when it solves a verified user problem.

## Decorative orbit visualization

Life Map relationships matter more than the orbit animation/layout.

## Too many reminder categories at once

Start with the existing reminder system + Quiet Hours + defaults.

## AI before deterministic rules

A rules-based planner is easier to test, explain, debug, and trust.

## Fake insights

Never calculate “best time,” recovery trends, or behavioral observations without adequate data.

## Guilt-based productivity mechanics

The reference product is strongest when it avoids this.

Prefer:

- recovery
- consistency
- smaller versions
- rescheduling
- realistic fallback plans

---

# 6. Recommended Product Identity for Work Life

The reference suggests a useful direction:

> Work Life should not be a system that pressures the user to do more. It should help the user decide what matters, choose a realistic version of the plan, recover when life changes, and carry unfinished work forward intentionally.

That identity can guide future feature decisions.

A feature is a strong fit when it helps one of these:

- Capture something quickly
- Clarify what it means
- Decide what matters
- Match work to available time/energy
- Focus on one finish condition
- Recover after interruption
- Review what actually happened

---

# 7. Recommended Immediate Feature

## Quiet Hours

Keep the previously selected next feature.

Why:

- Notification scheduling already exists.
- Settings is a known pilot gap.
- It has measurable behavior.
- It is easy to unit-test compared with adaptive planning.
- It improves trust immediately.
- It creates the first real Settings foundation.

Implement **only Quiet Hours** first.

After it is green, recommended next feature:

> **Routine Minimum / Normal / Strong Levels**

That is the first Orbit-inspired behavior I would add because it changes the product experience meaningfully without requiring AI or cloud infrastructure.

---

# 8. AI Coding Rule

Whenever this reference audit is given to a coding AI:

> Use it as product guidance, not as permission to implement everything.

For every development task:

1. Implement only the explicitly requested feature.
2. Inspect the repository first.
3. Reuse existing architecture.
4. Preserve current behavior.
5. Add tests.
6. Update docs.
7. Run Flutter analysis/tests.
8. Report limitations.
9. Recommend one next feature.
10. Do not implement the recommendation automatically.

---

# 9. Suggested Repository Documentation Structure

```text
work_life/
├── README.md
├── PRODUCT.md
├── BACKLOG.md
├── IMPLEMENTATION.md
├── VALIDATION.md
├── WORK_LIFE_ROADMAP.md
├── ORBIT_REFERENCE_AUDIT.md
├── pubspec.yaml
├── lib/
└── test/
```

`WORK_LIFE_ROADMAP.md` should remain the main internal roadmap.

`ORBIT_REFERENCE_AUDIT.md` should document which external product ideas are worth adopting and why.

Do not let the reference prototype become the source of truth over the actual Work Life repository and roadmap.
