# Flutter ARM64 Android Build Environment

Build Flutter Android applications directly on ARM64 Linux environments such as:

- Debian 12 ARM64
- Termux + PRoot
- ARM64 Linux containers
- ARM64 single-board computers

This project provides a tested configuration for building Flutter Android
APK and AAB packages on ARM64 Linux.

## Why This Project Exists

Flutter's Android build process normally expects Android build tools such as
AAPT2 to match the host architecture.

On ARM64 Linux, some Android SDK Build Tools packages may contain x86-64
executables. Those binaries cannot run natively on an ARM64 Linux userspace.

This setup uses a native ARM64 AAPT2 binary and configures Gradle to use it:

    android.aapt2FromMavenOverride

The result is a working Flutter Android release build environment on ARM64.

## Tested Environment

The current tested environment:

- Debian GNU/Linux 12 (bookworm)
- ARM64 / aarch64
- Termux + PRoot
- Flutter 3.27.4
- Dart 3.6.2
- OpenJDK 17
- Gradle 8.3
- Android Gradle Plugin 8.1.0
- Android SDK
- ARM64 AAPT2
- Flutter Android target: android-arm64

## Important: ARM64 Target

For ARM64-only Flutter Android builds, explicitly specify:

    --target-platform android-arm64

Example:

    flutter build apk --release --target-platform android-arm64

For an Android App Bundle:

    flutter build appbundle --release --target-platform android-arm64

This is important when the goal is to produce an ARM64-only Flutter application.

## Build Verification

Create a new Android Flutter project:

    flutter create --platforms=android test_app

Enter the project:

    cd test_app

Build an ARM64 APK:

    flutter build apk --release --target-platform android-arm64

Build an ARM64 AAB:

    flutter build appbundle --release --target-platform android-arm64

The generated files are:

    build/app/outputs/flutter-apk/app-release.apk

    build/app/outputs/bundle/release/app-release.aab

## Verify APK ABI

You can inspect the native libraries inside the APK:

    unzip -l build/app/outputs/flutter-apk/app-release.apk | grep 'lib/'

For an ARM64-only build, the expected Flutter native libraries are under:

    lib/arm64-v8a/

For example:

    lib/arm64-v8a/libapp.so
    lib/arm64-v8a/libflutter.so

## ARM64 AAPT2

The important part of this setup is the ARM64 AAPT2 binary.

Gradle is configured with:

    android.aapt2FromMavenOverride=/path/to/arm64/aapt2

The provided installation script expects the binary at:

    $HOME/prebuilt-binary/arm64/aapt2

The binary must be an ARM64 Linux executable.

Check it with:

    file $HOME/prebuilt-binary/arm64/aapt2

Expected architecture:

    ARM aarch64

## Installation Script

The included `install.sh` does not blindly replace the existing Flutter
or Android SDK installation.

It checks:

1. Host architecture
2. Java 17
3. Flutter 3.27.4
4. Android SDK
5. ARM64 AAPT2
6. Gradle configuration

Then it configures:

    $HOME/.gradle/gradle.properties

with:

    android.aapt2FromMavenOverride=$HOME/prebuilt-binary/arm64/aapt2

Run:

    chmod +x install.sh
    ./install.sh

The script is designed to configure an existing environment rather than
delete and reinstall the entire Android/Flutter toolchain.

## Flutter Version

This repository was tested with:

    Flutter 3.27.4

Other Flutter versions may work, but they have not been verified as part
of this setup.

## Java

Java 17 is required by the tested configuration.

Check:

    java -version

Expected:

    openjdk version "17..."

## Gradle

The tested project uses:

    Gradle 8.3

The Android Gradle Plugin version used by the test project is:

    8.1.0

## Security

Do not commit private credentials or signing files to this repository.

The repository ignores common sensitive files such as:

- `.env`
- `.env.*`
- `key.properties`
- `*.jks`
- `*.keystore`
- `*.p12`
- `*.pfx`
- `*.pem`
- `*.key`
- `google-services.json`
- `GoogleService-Info.plist`

It also ignores generated build directories and local Android configuration.

Before pushing a project to GitHub, always inspect:

    git status --short

and verify that no private credentials, signing keys, tokens, or API keys
are being committed.

## Included Test Project

The `test_app` directory contains a minimal Flutter Android project used
to verify the ARM64 build configuration.

It is included as a reproducible build test.

## Current Build Result

The tested ARM64 environment successfully produced:

    APK
    AAB

The APK contained:

    lib/arm64-v8a/libapp.so
    lib/arm64-v8a/libflutter.so

This confirms that the Flutter application was compiled for the ARM64
Android ABI.

## Limitations

This project does not provide a complete replacement for Android Studio.

Android Studio can still be useful for:

- Android project inspection
- SDK management
- Visual debugging
- Logcat
- Device management
- Android development tools

The purpose of this repository is specifically to provide a working
ARM64 Linux Flutter Android build environment.

## Termux / Wi-Fi Debugging

When Android debugging is configured separately, an Android device can
be connected over Wi-Fi using ADB.

This makes it possible to use Flutter development workflows such as:

    flutter devices

    flutter run

and hot reload without requiring a physical USB connection.

Wi-Fi ADB configuration depends on the Android device and environment and
is not automatically configured by this repository.

## Disclaimer

This configuration is based on a tested ARM64 environment.

Android SDK, Gradle, Flutter, and Android Gradle Plugin versions can change
over time. A configuration that works with one version may require changes
with another version.

Always verify the toolchain before using it for production builds.
