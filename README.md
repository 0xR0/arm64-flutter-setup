# Flutter ARM64 Android Build Environment

Single-command Flutter setup for **Termux + PRoot Ubuntu** on ARM64 Android.

```bash
curl -fsSL https://raw.githubusercontent.com/0xR0/arm64-flutter-setup/master/install.sh | bash
```

That's it. The installer:

1. Installs `proot-distro` and Ubuntu (if missing).
2. Enters the Ubuntu proot and installs OpenJDK 17, Flutter 3.27.4, Android SDK 35.
3. Replaces the x86-64 build-tools binaries (`aapt2`, `aidl`, `zipalign`, `split-select`)
   with native ARM64 builds and configures Gradle via
   `android.aapt2FromMavenOverride`.
4. Adds `flutter`, `dart`, and `flutter-shell` wrappers to your Termux `~/.bashrc`
   so you can call `flutter` directly from Termux — the wrapper transparently
   forwards the command into the Ubuntu proot with the current directory bound in.
5. Builds a debug APK and copies it to `/sdcard/Download/verify_app-debug.apk`
   as an end-to-end check.

The script is **idempotent** — re-running it skips anything already installed.
It does not touch a pre-existing Debian PRoot.

## Requirements

- Android device with Termux
- Storage permission granted to Termux (`termux-setup-storage`)
- Working internet connection

## Usage after install

Open a new shell (or `source ~/.bashrc`):

```bash
flutter --version
flutter create ~/projects/hello
cd ~/projects/hello
flutter build apk --debug --target-platform android-arm64
```

The APK is written into `build/app/outputs/flutter-apk/` inside the project.

To enter the Ubuntu shell directly:

```bash
flutter-shell
```

## How the wrappers work

The Termux `flutter` / `dart` functions call `proot-distro login ubuntu` with
your current working directory bind-mounted into the proot. If you're inside
`$HOME`, Termux `$HOME` is mounted at `/host-home`; if you're outside, the
current directory is mounted at `/host-project`. The wrapper then runs the
real Flutter binary from inside the Ubuntu environment.

Effect: from your perspective, `flutter` "just works" in Termux without ever
having to type `proot-distro login` yourself.

## Why ARM64 AAPT2

Google ships the Android SDK build tools as x86-64 binaries. On ARM64 Linux
they cannot run natively. This setup swaps them with ARM64 builds from
[`Commit451/android-arm-build-tools`](https://github.com/Commit451/android-arm-build-tools)
and points Gradle at the replacement via `~/.gradle/gradle.properties`:

```
android.aapt2FromMavenOverride=$HOME/.local/android-sdk/build-tools/35.0.1/aapt2
```

## Tested Environment

| Component | Version |
|-----------|---------|
| Host      | Termux + PRoot Ubuntu (ARM64) |
| Flutter   | 3.27.4 |
| Dart      | 3.6.2 |
| Java      | OpenJDK 17 |
| Android SDK | API 35, build-tools 35.0.1 |
| Target    | `android-arm64` (debug) |

## What works / doesn't work

- **Debug APK build**: works. Debug uses JIT so it runs natively on ARM64.
- **Release APK build**: **not currently working**. Google only publishes
  `linux-x64` `gen_snapshot` binaries for Android AOT compilation. There is no
  native ARM64 host-side `gen_snapshot` for Android targets, and running the
  x86-64 one under user-mode QEMU produces a Dart VM `dedup_instructions`
  product-mode mismatch at runtime.

For release builds you currently need an x86-64 host (or a working
`qemu-x86_64` wrapper that matches the Dart VM product-mode expectations).

## Layout inside Ubuntu proot

```
~/.local/flutter-3.27.4/         # Flutter SDK
~/.local/android-sdk/            # Android SDK
~/.cache/arm64-flutter-setup/    # Downloaded archives
~/.gradle/gradle.properties      # AAPT2 override
```

## Uninstall

Inside the Ubuntu proot:

```bash
rm -rf ~/.local/flutter-3.27.4 ~/.local/android-sdk ~/.cache/arm64-flutter-setup
sed -i '/# >>> arm64-flutter-setup >>>/,/# <<< arm64-flutter-setup <<</d' ~/.bashrc
```

In Termux:

```bash
sed -i '/# >>> arm64-flutter-setup >>>/,/# <<< arm64-flutter-setup <<</d' ~/.bashrc
proot-distro remove ubuntu     # optional — removes the whole distro
```

## Wi-Fi Debugging (ADB)

For `flutter run` and hot reload over Wi-Fi:

```bash
pkg install android-tools
adb connect <phone-ip>:<port>
adb devices
```

Enable **Wireless debugging** in Android Developer options first.

## Security

Never commit private credentials or signing files. `.gitignore` excludes:
`.env`, `.env.*`, `key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.pfx`,
`*.pem`, `*.key`, `google-services.json`, `GoogleService-Info.plist`, and
common build directories.

Before pushing, run:

```bash
git status --short
```
