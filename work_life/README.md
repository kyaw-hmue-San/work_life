# Work–life balance app

Routine Minimum / Normal / Strong levels are implemented locally (12 September 2026). One routine has optional effort descriptions and one daily completion record; level selection is manual. See [Routine levels](docs/ROUTINE_LEVELS.md).

Minimal first-run onboarding is implemented (10 September 2026): Welcome → Life Areas → Reminder Preference. New workspaces see setup; existing databases migrate as returning users. Skip preserves settings; workspace reset returns to Welcome. See [Onboarding behavior and persistence](docs/ONBOARDING.md).

Export and Delete Local Data (9 September 2026): implemented for the current workspace in More → Settings → Data. Version 1 JSON includes persisted product records and settings, excluding authentication and device bookkeeping. Confirmed reset cancels notifications before transactional cleanup, retains account identity, resets preferences, and refreshes Inbox. See [Local data format and reset policy](docs/LOCAL_DATA.md). Native file sharing and notifications still need physical-device acceptance.

Flutter workspace for a mobile app that helps people capture ideas, keep commitments, plan realistically, focus, and protect health, relationships, and rest. Product name is undecided. The owner chose Flutter for Android and iPhone, with learning as a project goal.

Status: connected offline-first app with Today, Inbox, Projects, Planner, Focus, routines, weekly review, exercise progress, reminders, backup restore, schedule-image import and native AI proposals. SQLite remains the working database. Signed-in workspaces use durable, incremental Supabase synchronization with tombstones, retries and account ownership; guest mode stays local. Apply the included Supabase migration before multi-device testing. Production AI uses an authenticated Edge Function. Native notifications and cloud sync are automated-tested but still need live deployment and physical-device acceptance.

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

Android build tools are installed under `.tooling/`; see [Android setup](docs/ANDROID_SETUP.md). Automated checks do not prove notification delivery, OAuth callbacks, image picking, or sharing on a real phone. See [Validation](docs/VALIDATION.md) for product acceptance checks.


## Run the app

Create your private environment file once:

```sh
cd /Users/rioo/projects/work_life/work_life
test -f config/.env || cp config/.env.example config/.env
```

Add your Supabase project URL, publishable key, and deployed AI proxy URL to `config/.env`. Keep `AIMLAPI_KEY` only as an explicitly enabled local-debug option. Do not add a Supabase secret/service-role key. Then list devices and run:

```sh
/Users/rioo/flutter/bin/flutter devices
sh tool/run_with_env.sh -d DEVICE_ID
```

The configured build opens on real-account sign-in. A new account gets onboarding automatically. For an existing account, open **More → Run onboarding again**; this replays setup without deleting records. Offline guest mode is available only from the secondary button on the sign-in screen.

Run automated checks with:

```sh
/Users/rioo/flutter/bin/flutter analyze --no-pub
/Users/rioo/flutter/bin/flutter test --no-pub
```

For Android device setup, APK builds, and notification acceptance, use [Android setup](docs/ANDROID_SETUP.md). For email/Google provider and callback setup, use [Supabase/Google setup](docs/SUPABASE_GOOGLE_SETUP.md). The generated web/Windows/Linux scaffolds are not supported by the current storage implementation. Physical iPhone signing still requires your Apple development team.

Production AI calls use the authenticated Supabase Edge Function in `supabase/functions/ai-proxy`; provider credentials remain server-side. Direct AIMLAPI access is disabled in release builds even if a key is accidentally supplied. Deploy the function and set its `AIMLAPI_KEY` secret before production validation.
