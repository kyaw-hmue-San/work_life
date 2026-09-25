# Supabase and Google sign-in setup

The app can run as a guest workspace without account configuration. Account sign-in is enabled only when both `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are supplied at build or run time.

## 1. Create the Supabase project

1. Create a project in the Supabase dashboard.
2. Open **Project Settings → API**.
3. Copy the project URL and publishable key. Older projects may label the public key `anon`; never copy a `service_role` or `sb_secret_` key into the app.
4. In **Authentication → Providers**, enable **Email**. Decide whether email confirmation is required; the app supports confirmed and confirmation-pending sign-ups.

The example files are `config/supabase.example.json` and `config/.env.example`. They are documentation only and contain no usable credentials. Copy `.env.example` to `config/.env` for local use; the local file is ignored by git.

## 2. Configure Google OAuth

1. In Google Cloud Console, create or select a project.
2. Configure the OAuth consent screen and add pilot users as test users while the app is in testing.
3. Create a web OAuth client ID. Use its client ID and secret in Supabase under **Authentication → Providers → Google**.
4. In Supabase **Authentication → URL Configuration**, add this redirect URL:

   `https://<project-ref>.supabase.co/auth/v1/callback`

5. Keep the app callback in Supabase's additional redirect URLs:

   `com.worklife.app://auth-callback`

The app uses PKCE and opens Google in the external browser. It accepts only a callback with the `com.worklife.app` scheme, `auth-callback` host, and a PKCE `code` (or an OAuth error). It rejects implicit-flow access or refresh tokens in the URI.

## 3. Run with account configuration

From the Flutter project directory:

```sh
cd /Users/rioo/projects/work_life/work_life/config             
set -a
source .env
set +a

cd ..
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

For a release build, pass the same two defines to the build command used for the target platform. Do not commit them to source control, shared shell history, screenshots, or issue reports. The publishable key is intended for a client; server secrets are not.

## 4. Verify the first sign-in

1. Open **More → Account**.
2. Test email sign-up and confirm the email on the same device. Then sign in.
3. Test **Continue with Google** and complete the browser flow. Returning to the app should show the account email.
4. Sign out, confirm the guest notes return, then sign in as another account and confirm the first account's records are not visible.
5. Test password reset and recovery before treating the setup as ready for a pilot.

The current account slice isolates local databases and stores the Supabase session and PKCE values in platform secure storage. It does not yet provide cloud backup, sync, server-side data ownership, export, or deletion. Those remain separate implementation work.

## Troubleshooting

- **Accounts are not available in this build:** one or both `dart-define` values were omitted, or the configuration was rejected. Rebuild with the URL and public key.
- **Google returns to the browser:** check the Supabase redirect URLs and confirm the app was rebuilt with the callback registration in the current native project.
- **Google provider is unavailable:** enable Google under Supabase **Authentication → Providers** and verify its web client credentials.
- **Email sign-in is rejected:** confirm the address, password, and email-confirmation setting. The Account screen exposes resend and reset actions.
- **Session restoration fails:** the app keeps the local workspace available and reports secure-storage problems in Account. Retry sign-in on the same device.