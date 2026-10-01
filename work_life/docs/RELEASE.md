# Release readiness

The production application and bundle ID is `com.worklife.app`. Keep that ID
registered consistently in Apple Developer, App Store Connect, Google Play,
and the Supabase OAuth callback configuration.

## Android signing

Release builds never fall back to the debug key. Supply either ignored
`android/key.properties` with `storeFile`, `storePassword`, `keyAlias`,
and `keyPassword`, or these CI secrets:

- `WORK_LIFE_ANDROID_KEYSTORE`
- `WORK_LIFE_ANDROID_STORE_PASSWORD`
- `WORK_LIFE_ANDROID_KEY_ALIAS`
- `WORK_LIFE_ANDROID_KEY_PASSWORD`

Without those values an unsigned release artifact can be compiled for code
validation but cannot be uploaded to Google Play.

## iOS signing

The repository includes the stable bundle ID, OAuth URL scheme, photo-library
usage description, and notification implementation. Select the real Apple
Team and provisioning profile in Xcode/CI. Certificates, profiles, and the
Team ID are private external inputs and are not stored here.

## Device acceptance

Before distribution, run the scenarios in [VALIDATION.md](VALIDATION.md) on
one physical iPhone and Android phone. Simulator builds do not establish
notification delivery, reboot recovery, permission behavior, snooze actions,
OAuth callbacks, photo picking, or lifecycle behavior.
