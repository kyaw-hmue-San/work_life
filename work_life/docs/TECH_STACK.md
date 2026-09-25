# Technology recommendation

Updated 7 September 2026. Confirmed direction: Flutter for both Android and iPhone. The owner wants to learn through the project and has chosen an original UI without using Lovable. The connected local app uses sqflite 2.4.3 and path 1.9.1, with sqflite_common_ffi 2.4.2+1 for database tests. Other supporting libraries and backend choices below remain recommendations.

## Recommended stack

| Layer | Choice | Reason and tradeoff |
| --- | --- | --- |
| Mobile | Flutter with Dart | Matches the owner's preference; shared app with platform-specific testing |
| UI | Flutter widgets, ThemeData and shared design tokens | Build an original calm design as reusable Flutter components |
| Navigation | Native Navigator routes now; go_router remains proposed | Current routes need no extra package; assess deep links when reminders are implemented |
| State and dependencies | ViewModels with ChangeNotifier and constructor injection implemented | Explicit data flow without another package; provider remains an optional future choice |
| Local database | SQLite through sqflite | Durable offline records and SQL learning; migrations and sync need explicit work |
| Cloud | Supabase Postgres, Auth, supabase_flutter | Relational data and account access policies |
| Privileged server | Supabase Edge Functions using TypeScript | Keep AI keys and later integration credentials off the phone |
| Reminders | flutter_local_notifications with timezone support | Local scheduled reminders, actions, and platform-specific configuration |
| AI | Server-side provider adapter; model/provider chosen later | Evaluate real pilot cases, latency, correction effort, and budget |
| Testing | flutter_test and integration_test, plus database access tests | Unit, widget, and connected device workflows |
| Delivery | Flutter Android/iOS builds; CI added after a working slice | Avoid premature infrastructure; validate both platforms early |

The proposed organization follows Flutter's separation of UI and data responsibilities. Use repositories for persistence and ViewModels for presentation logic; add shared domain services where scheduling and task transitions would otherwise be duplicated. Flutter documents ChangeNotifier as one option and recommends go_router for many apps. These are appropriate starting choices for learning, not a claim that other state libraries are wrong. [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) · [go_router](https://pub.dev/packages/go_router)

Flutter's SQLite guide uses sqflite for local persistence. Supabase provides a Flutter integration guide. Combining them still requires an explicit synchronization design; adding a cloud SDK does not implement the protocol in ARCHITECTURE.md. [SQLite guide](https://docs.flutter.dev/cookbook/persistence/sqlite) · [Supabase Flutter guide](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)

Use ownership policies on every user-owned cloud table. Server-side functions can broker AI requests and later integrations without exposing privileged credentials in the application. [Row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security) · [Edge Functions](https://supabase.com/docs/guides/functions)

## What to learn in sequence

1. Dart: types, null safety, classes, collections, Futures, Streams, and error handling.
2. Flutter: widgets, layout, navigation, forms, themes, and accessibility.
3. State flow: a screen calls a ViewModel, which uses a repository; updates return to the UI.
4. SQL and local storage: tables, relationships, transactions, migrations, and durable capture.
5. Device reminders and timezones: permissions, scheduling, actions, and failure states.
6. Backend fundamentals: authentication, ownership policies, synchronization, and recovery.
7. AI integration: server requests, output validation, editable drafts, and cost limits.

Learn through small connected features rather than building every screen at once. Start with capture, local persistence, and retrieval. Keep explanations of new concepts in development notes; avoid putting technical implementation details into the app's user flow.

## Feasibility work before expanding

**Offline sync:** Prototype interrupted uploads, duplicate retries, conflicts, and deletions. Decide whether to maintain the proposed small sync protocol or evaluate a dedicated solution. Robust multi-device editing is not automatically provided by SQLite plus Supabase.

**Reminders:** Test permissions, actions, rescheduling, recurrence, timezone changes, app termination, and operating-system restrictions on both real Android and iPhone devices. The notification package documents platform-specific setup and limitations, including scheduling constraints. Do not rely on an always-running Dart timer or promise guaranteed delivery. [flutter_local_notifications documentation](https://pub.dev/packages/flutter_local_notifications)

**Quality:** Use Flutter's unit, widget, and integration test layers, with real-device checks for behaviors a widget test cannot establish. [Flutter testing](https://docs.flutter.dev/testing/overview)

## Alternatives and deferred choices

React Native/Expo is a viable shared mobile approach, but Flutter now matches the owner's explicit direction. A web wrapper offers little advantage here because source reuse is not wanted. Separate native apps would add maintenance work for this small pilot.

The local app uses ChangeNotifier with constructor injection; revisit Riverpod or Bloc only if state complexity creates a concrete need. Consider a higher-level SQLite library if typed queries or migrations become difficult, but do not add multiple competing persistence layers. Keep AI provider selection open until the core app is useful.

## Cost and version policy

Estimate hosting/database, distribution, AI, later transcription, and support after pilot size and monthly budget are known. Verify current prices before any paid commitment. Do not promise free production operation or a delivery date.

Choose compatible stable Flutter/Dart and package versions when implementation begins; commit the application lockfile and document actual toolchain versions. The owner-created starter was reviewed with installed Flutter 3.47.2 stable and Dart 3.13.2 on 7 September 2026; `pubspec.lock` is present. The initial review added no packages; the subsequent authorized implementation added SQLite and its test adapter. One Flutter application and a small backend remain the proposed starting architecture.
