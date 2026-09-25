# Minimal first-run onboarding

Implemented 10 September 2026. Three short, scrollable screens introduce a newly created workspace:

1. **Welcome** — capture, realistic planning, focus, and room for life; Get Started or Skip setup.
2. **Life Areas** — shows Work, Study, Health, Relationships, and Rest, plus any existing custom areas. Optional custom area creation uses the same `addArea` operation as Life Map.
3. **Reminder Preference** — selects the existing five Reminder Default options; Finish enters the normal app.

All areas are permanently available in the current product and identified by their names. There is no active/inactive area model, so onboarding does not introduce selection flags or remove built-ins. Users choose relevant areas when organizing records; they are not required to use every area. Adding an existing name is idempotent. Custom additions are saved immediately and survive backing out or skipping.

There is no separate planning step: working/waking hours, planning style and a global default Focus duration are not existing settings. No new scheduling behavior is introduced. Reminder Default remains editable in Settings; custom areas remain managed through Life Map. Quiet Hours and native permission prompts are not part of onboarding.

## Storage and navigation

SQLite schema **8** adds a singleton `workspace_setup` row containing `completed`. This is routing metadata, not a second settings store. The existing WorkspaceData/WorkspaceRepository expose completion. Finish commits the existing `reminder_preferences.default_option` and completion together in one transaction. Existing explicit reminders and suppression records are untouched.

New databases initialize completion to false. Migration from versions 1–7 marks existing databases complete, preserving established users' startup experience and all existing settings/content. Completion belongs to the selected database: guest and each account workspace are independent. Authentication recovery retains its existing routing precedence.

The root workspace shows loading until SQLite is read, then onboarding or normal home; the normal navigation bar is not displayed before this decision. Completion survives reopening. Failed saves retain the screen and show an error for retry. Back changes the setup step without discarding saved records. No routing framework or dependency was added.

## Skip, reset and export

Skip marks completion without rewriting preferences or content. New workspaces therefore use the existing safe defaults; interrupted setup retains already saved custom areas. An unsaved reminder choice is not applied by Skip.

Confirmed Delete All Local Data resets completion to false within the same transaction that clears workspace content and resets settings. The retained account immediately sees Welcome after Settings closes; Skip or Finish returns to the app. Other workspaces remain untouched. Existing notification cancellation safeguards are unchanged.

JSON export remains format version 1 with unchanged product settings. The completion flag is deliberately excluded as implementation-only startup metadata; reminder settings and custom life areas remain exported normally.

## Limitations

Settings → Run setup again is available (12 September 2026). It opens current values without clearing completion or workspace content. Finish saves the chosen Reminder Default; Skip preserves the existing preference. Both return to Settings. Back at the first step closes rerun; custom area additions still save immediately and remain idempotent. Ordinary Settings and Life Map edit the same product values. No life-area activation system, working-hours preference, new Focus default, onboarding notification permission prompt, cloud functionality, or unrelated roadmap feature was added. Physical-device accessibility and notification/file-sharing acceptance remain unvalidated. Automated mobile layout checks do not replace screen-reader testing.
