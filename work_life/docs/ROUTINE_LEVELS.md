# Routine Minimum / Normal / Strong

Implemented 12 September 2026. A single daily routine supports three manually chosen completion levels:

- Minimum uses the existing smaller alternative, now labelled Minimum.
- Normal uses an optional description, falling back to the routine title.
- Strong uses an optional description and is offered when configured.

Create or edit these descriptions in the existing routine editor. Today and More → Routines share the same definitions and completion controls. Minimum and Strong are optional; no effort duration is invented. Any level counts as a valid completion. Later remains pending, Skip remains skipped, and missing days remain unknown.

SQLite schema 9 adds `normal` and `strong` text columns to `routines`. Migration preserves IDs, existing smaller alternatives, settings, onboarding completion, and history. Existing `smaller` history means Minimum and `done` means Normal; new `strong` history means Strong. RoutineRecord exposes a typed RoutineLevel and a shared completed predicate used by Life Map reflection. There remains one record per routine and device-local day: retries or choosing another level replace that record, without creating another routine or another completion count. Recorded area and level survive edits to current definitions. History does not snapshot description text, so old exact wording cannot be reconstructed after edits.

Export format 1 gains additive `normal`/`strong` routine fields and a `level` field on routine records (`minimum`, `normal`, `strong`, or null for later/skipped). Existing `alternative` and `outcome` fields remain compatible. Current-workspace reset deletes definitions and history through its existing transaction. Account isolation, onboarding reset, and notification cancellation behavior are unchanged.

Routines still do not create Planner blocks, Focus sessions, or notifications. This slice adds no automatic level selection, energy detection, restart/recovery behavior, streak redesign, or scheduling changes. Physical-device acceptance remains outstanding.

Next recommended feature: Gentle Routine Restart. Not implemented here.
