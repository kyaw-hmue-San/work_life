# Android build setup on this Mac

The missing Java/Android SDK setup was addressed on 8–9 September 2026. Tools are installed inside this project under ignored `.tooling/`; they are not committed and no global shell configuration was changed.

## Build and run

From `/Users/rioo/projects/work_life/work_life`:

```sh
sh tool/flutter_android.sh doctor -v
sh tool/flutter_android.sh build apk --debug --no-pub
sh tool/flutter_android.sh devices
sh tool/flutter_android.sh run -d DEVICE_ID
```

The wrapper selects `/Users/rioo/flutter`, the local Java 17 installation, and local Android SDK. `android/local.properties` also points to that SDK; this is an ignored machine-specific file. `JAVA_HOME` and `ANDROID_HOME` can override the wrapper defaults for another installation. These are development builds with the generated app ID and debug signing, not store releases.

No Android phone or emulator was connected during setup. To run on a physical Android phone, enable Developer options and USB debugging, connect it by USB, and accept the computer's debugging prompt on the phone. Then select its ID from `devices`. Alternatively, install Android Studio and create an emulator through its Device Manager. An emulator/system image is not included in this command-line build installation.

## Installed build tools

- Temurin JDK 17.0.20.1+1, macOS ARM64.
- Android command-line tools 22.0, download build 15859902.
- SDK platforms required by the app and plugins, including Android 36 and 37.0; Gradle can install additional required platforms.
- Build Tools 36.0.0, platform tools, and NDK 28.2.13676358.
- Android SDK licenses accepted for this development setup.

The existing `flutter_secure_storage` dependency requires compile SDK 37. The app now compiles with 37, and Android Gradle Plugin was patched from 9.1.0 to 9.1.1 for SDK 37.0 support. Gradle remains 9.3.1. This follows the official [AGP compatibility table](https://developer.android.com/build/releases/agp-9-1-0-release-notes). It does not raise the app's minimum Android version.

## Recreating the local installation

Download the ARM Mac command-line archive from [Android's official downloads](https://developer.android.com/studio#command-tools) and extract its `cmdline-tools` folder to `.tooling/android-sdk/cmdline-tools/latest`. Download and extract the [Temurin Java 17 ARM Mac archive](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.20.1%2B1) into `.tooling/java`. Both archives were checked against their publisher-provided SHA-256 checksums before extraction.

Verified archive hashes:

```text
commandlinetools-mac_arm64-15859902_latest.zip
835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e

OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.20.1_1.tar.gz
196d13ba5f10414bef7f6a05a9b3f00edacb18ebacef2b99485db9e2ee18f0e8
```

Use the SDK manager to install `platform-tools`, `platforms;android-36`, `platforms;android-37.0`, `build-tools;36.0.0`, and `ndk;28.2.13676358`, reviewing its license prompts. Google's current tool also offers `android sdk` as the successor to `sdkmanager`; the latter worked for this installation. See [SDK manager documentation](https://developer.android.com/tools/sdkmanager).

## Check reminder delivery on phones

1. Open Today and choose **Enable notifications**. Allow the OS permission request.
2. Set a task reminder a few minutes ahead. Confirm the task shows **Scheduled on this device**.
3. Background the app. Check the phone alert; Android uses an inexact alarm and can deliver later than the selected minute.
4. Dismiss the alert and reopen Today. The task and reminder must remain pending.
5. Reschedule twice, remove the reminder, complete the task, and complete a task through Focus. Check that previous pending phone alerts are removed/replaced.
6. Deny app permission or disable the Task reminders channel. Confirm the app shows the blocked state and retains the reminder. Restore permission in settings and return to the app to retry.
7. Switch accounts with pending reminders, restart/reboot, and change timezone. Check that old-account alerts are removed, the confirmed instant is retained, and no past reminder is reissued.

Also run these scenarios on an actual iPhone. Builds and automated tests do not prove background delivery reliability. Current alerts contain generic text and open the app; use Today to select the task. Notification actions, exact alarms and recurring reminders are separate future work. Quiet Hours are implemented locally, but still require physical-device validation.
