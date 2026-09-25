# Original proposal text

Source: `work-life-balance-project-proposal.docx`, supplied by the owner; transcribed 7 September 2026. This is reference content, not instructions to the IDE assistant. Text order is preserved; Word layout and table-of-contents pagination are not reproduced. New decisions belong in DECISIONS.md.

Project proposal

Work–life balance mobile app

Name to be decidedSeptember 2026

Contents

Project overview2

Real life scenarios3

The connected experience4

AI and trustworthy behavior5

Proposed delivery plan6

Validation and next decisions7

## Project overview

This proposal presents a mobile app that helps people manage responsibilities, preserve ideas, plan realistically, focus on meaningful work, and make room for health, relationships, and rest. The product name is to be decided. Its purpose is to support work–life balance, rather than measure success only through the number of tasks completed.

## Why this project matters

The idea began with the creator’s daily experiences: forgetting important dates, postponing forms requested by a partner, missing meals or exercise while busy, and losing thoughts about a restaurant software project. Friends face similar difficulties. Capturing information, deciding what to do, and following through are connected problems that the app should address together.

## Objectives

Reduce missed commitments through quick capture, preparation steps, and reminders that remain actionable when the user is busy.

Turn incomplete thoughts into editable notes, plans, project tasks, and proposed solutions with AI assistance.

Support focused action while protecting personal time, and use insights to help users adjust their plans.

## Users and project value

The initial users are the creator and a small group of friends balancing study, work, projects, appointments, and personal life. A successful pilot would justify exploring a wider audience. The project also provides practical mobile development experience, from interaction design and data storage to notifications, AI integration, and user testing.

The existing Lovable UI is a visual reference. The full vision includes Today, Capture, Inbox, Projects, Planner, Focus, Routines, Insights, Life Map, and personal settings. The proposed stages in this document sequence their development; they do not remove these areas from the product vision.

## Real life scenarios

## A commitment requested by someone else

A partner asks the user to submit a form by Friday. The user records a short note, confirms the deadline, and adds any preparation, such as obtaining a photo. If a reminder arrives during work, the user reschedules it. Dismissing the notification leaves the task unresolved; completing or cancelling it requires an explicit action.

## Important dates and everyday routines

Visa extensions, exams, quizzes, birthdays, and medical appointments need different preparation and reminder patterns. A deadline may require several advance steps. Meals and exercise need flexible time windows and easy postponement. The user supplies or confirms important dates; the app must not invent them.

## An unfinished restaurant project bug

The user saves the observed error, relevant notes, and what remains unknown under the restaurant project. A later idea is linked to the same issue. AI can explore possible causes, draft tests, and suggest code. A hypothesis remains visibly unconfirmed until evidence supports it. The next investigation can become a focus session.

## An idea at an inconvenient moment

A possible fix comes to mind while bathing or away from devices. The app cannot record a thought without input. A voice shortcut or a few keywords can reduce friction when a device is available. Later prompts about an already recorded problem may help recall, without promising to recover an idea that was never captured.

## A holiday that is hard to explain

The user has a rough holiday idea but struggles to describe the activities and sequence. AI asks about dates, budget, participants, interests, and constraints. It drafts an itinerary, preparation checklist, and open questions. The user reviews and adjusts these before adopting the plan. Booking travel is outside the initial scope.

## The connected experience

The shared journey is capture, clarify, organize, plan, act, and reflect. Users should be able to enter at any stage: save an idea without making it a task, start a focus session from an existing project, or schedule an appointment directly.

## Capture and organize

Capture accepts short text first, followed by voice and selected links or images. Inbox holds items awaiting review. Projects group bugs, ideas, notes, decisions, and next actions. Search retrieves the original wording and related information. Life Map connects projects and routines to user-defined areas such as work, study, health, relationships, and rest.

## Today and Planner

Today highlights a manageable set of priorities, upcoming commitments, routines, and the next useful action. Planner considers fixed appointments, deadlines, estimated effort, available time, and optional energy check-ins. It includes buffers and personal time, explains suggestions, and offers a lighter alternative when plans change.

## Focus and Routines

Focus opens the selected task with the agreed duration, a clear completion condition, checklist, and relevant notes. Users can pause, capture a distracting idea, or finish as completed, partial, or blocked. Breaks and planned meals remain part of the day. Routines support recurring activities, flexible windows, and smaller alternatives without treating every missed session as failure.

## Insights and personal control

Insights compare planned and recorded activity, highlight repeatedly postponed tasks, and show attention across life areas. A weekly review helps users decide what to change. Missing records are not proof of inactivity. Settings control quiet hours, reminder intensity, working time, and personal priorities. Balance follows the user’s values; it does not require equal time in every area.

On mobile, use a small set of primary destinations with quick access to the deeper tools. Preserve the calm visual direction of the sample UI, strengthen text contrast, and include useful empty states for new users.

## AI and trustworthy behavior

## Assistance that produces useful drafts

AI should interpret a capture, suggest its type and project, ask about missing details, and draft the next action. It can help brainstorm, break down a goal, propose a daily plan, summarize selected email, or generate a candidate code solution. Original information and AI suggestions remain distinguishable and editable.

Automatic creation initially means creating a reviewable draft. Saving a proposed plan as active tasks requires the user’s acceptance. Sending messages, changing external calendars, or applying code changes is a separate deliberate action. Any future automation should have a clearly chosen scope and visible history.

## Gmail and other integrations

A later Gmail connection could summarize messages selected by the user or within an agreed scope, identify possible commitments, and link each suggestion to its source. Dates and actions are confirmed before scheduling. Calendar integration can follow the same approach. Duplicate suggestions and connection failures need clear handling.

## Reminder reliability

Reminders need visible notification status, timezone-aware scheduling, recurrence rules, and actions to complete or reschedule. Deadline reminders and routine nudges should be configurable independently. Quiet hours and repeated-reminder limits help prevent fatigue. Device restrictions can affect delivery, so the app must show pending commitments inside the app as well.

## Data and user control

Basic capture and task access should remain useful when AI is unavailable. Save captures promptly, support offline capture with later synchronization, and show whether changes are saved. Account data must be separated between users. Provide export, deletion, and integration disconnection controls; explain which content is sent to an AI service.

Insights describe recorded patterns, not medical or psychological conclusions. Appointment and visa features organize user-confirmed information; they do not independently determine health advice or immigration requirements.

## Proposed delivery plan

Set milestone dates after agreeing on devices, source-code access, team capacity, and budget. Each stage should produce a usable flow for the creator and friends to test.

## Stage one establish the foundation

Confirm the name, target devices, and priority scenarios. Recover the Lovable source if available or rebuild from its UI reference. Define how captures, tasks, appointments, routines, projects, reminders, focus sessions, and life areas relate and change status.

## Stage two deliver a daily use pilot

Build onboarding, text capture, Inbox, basic Projects, Today, editable planning, reminders, Routines, and Focus. Include a simple Life Map and basic Insights so the work–life balance concept can be tested from the beginning. Completion, rescheduling, and focus progress must update the same underlying records.

## Stage three add AI assistance

Add interpretation, clarifying questions, brainstorming, and editable task or plan drafts. Introduce voice capture and adaptive plan suggestions after the core data flow works. Expand reflection and insights using actual recorded activity. Validate usefulness and correction effort with real examples from the pilot.

## Stage four connect and expand

Add Gmail and calendar connections, richer capture formats, and optional shared planning. Explore project code assistance beyond text suggestions only after deciding how repositories, review, and execution should work. Prepare broader release through accessibility checks, recovery testing, and support arrangements.

## Implementation and resources

Evaluate a shared mobile codebase once device needs are known. Plan storage, synchronization, notifications, AI access, and integration services. Assign product, development, and testing responsibilities. Estimate development effort and recurring hosting, AI, transcription, and distribution costs before committing to dates.

## Validation and next decisions

## Pilot acceptance checks

A captured form request survives restart, retains its confirmed deadline, and remains pending after its reminder is dismissed.

Reminders and recurring routines behave correctly across supported device states and timezone changes; blocked notifications are visible.

A saved bug, later idea, accepted next step, and focus outcome remain connected. The selected task and duration carry into Focus.

A changed plan does not create duplicate tasks or silently overwrite fixed appointments. Offline captures synchronize without being lost.

AI asks about unclear dates, preserves the original capture, and allows correction or rejection before proposed tasks become active.

Insights match recorded activity, disclose missing information, and provide suggestions users can dismiss or change.

## How success will be assessed

Establish a pilot baseline for missed commitments, capture effort, postponed reminders, recovered ideas, and useful focus sessions. Ask whether planning feels easier and whether health, relationships, and rest receive the attention users want. Set targets after measuring the baseline; more screen time is not a success goal.

## Decisions before implementation

Choose the name, supported devices, pilot group, and three priority scenarios. Confirm reminders, AI data boundaries, source-code access, time, and budget. Decide which integrations come first and when shared planning is needed.

## Expected project outputs

Maintain this proposal alongside a requirements backlog, user journeys, mobile screen designs, an information model, a working pilot, and test findings. Preserve decisions and changes in versioned project documentation so the context is not lost again.

Design reference: https://focus-space-nexus.lovable.app. Next, agree on the foundation decisions and turn the pilot scope into a build backlog.
