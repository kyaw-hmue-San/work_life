# Work–life balance app

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](docs/ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](docs/ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](docs/LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

Flutter workspace for a mobile app that helps people capture ideas, keep commitments, plan realistically, focus, and protect health, relationships, and rest. Product name is undecided. The owner chose Flutter for Android and iPhone, with learning as a project goal.

Status: connected local app with Today, Inbox, Projects, Planner, Focus, daily routines, basic life-area reflection, Quiet Hours, Reminder Defaults, and an optional Supabase account slice. Captures, tasks, plans, reminders, and settings are saved in SQLite. Native device notifications are implemented and automated-tested, but still need physical-device acceptance; cloud sync and AI remain future backlog work. See [Implementation guide](docs/IMPLEMENTATION.md) and [Supabase/Google setup](docs/SUPABASE_GOOGLE_SETUP.md).

## Read in this order

1. [AGENTS.md](AGENTS.md): instructions for an IDE assistant working here.
2. [Product requirements](docs/PRODUCT.md): purpose, scope, and user journeys.
3. [Technology recommendation](docs/TECH_STACK.md): proposed stack, alternatives, and sources.
4. [Architecture and data](docs/ARCHITECTURE.md): shared records, offline behavior, and boundaries.
5. [Delivery backlog](docs/BACKLOG.md): staged work with acceptance criteria.
6. [Validation](docs/VALIDATION.md): meaningful checks for the pilot.
7. [Decisions and project state](docs/DECISIONS.md): what is known, proposed, and unresolved.
8. [Proposal transcript](docs/PROPOSAL_REFERENCE.md): original proposal content for reference.

## Using this with an IDE assistant

Give the assistant this folder and ask it to read AGENTS.md first. If your IDE does not load that file automatically, reference it explicitly. Keep these documents in version control with the eventual application. Update the decision log whenever an agreed decision changes.

Example planning prompt:

> Read AGENTS.md, README.md, and docs/DECISIONS.md. Review the relevant requirements. Help me resolve the next planning decision. Distinguish confirmed requirements from your recommendations and do not start implementation in this task.

## Development checks

The SDK is at `/Users/rioo/flutter`; `flutter` and `dart` may not be on the shell PATH. On 21 September 2026, these commands passed using the existing dependencies:

```sh
/Users/rioo/flutter/bin/flutter analyze --no-pub
/Users/rioo/flutter/bin/flutter test --no-pub
```

Analysis found no issues and all 77 tests passed. Android build tools are now installed under `.tooling/`; see [Android setup](docs/ANDROID_SETUP.md). No Android or iPhone device or emulator was available during this review, and current native builds and phone behavior remain unverified. See [Validation](docs/VALIDATION.md) for product acceptance checks.


## Run the app

```sh
/Users/rioo/flutter/bin/flutter pub get
/Users/rioo/flutter/bin/flutter run
```

Select an Android device/emulator or iOS simulator/device. The app saves captures locally. With the Supabase defines, email and Google account sign-in are available, but cloud backup and syncing are not connected yet. The generated web/Windows/Linux scaffolds are not supported by the current storage setup. Physical iPhone signing still needs configuration. See [Supabase/Google setup](docs/SUPABASE_GOOGLE_SETUP.md) before testing real sign-in.
