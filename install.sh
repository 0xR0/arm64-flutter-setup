#!/usr/bin/env bash
set -euo pipefail

# Flutter ARM64 Android Build Environment
# Debian ARM64 / Termux PRoot

FLUTTER_VERSION="3.27.4"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
PREBUILT_DIR="${HOME}/prebuilt-binary/arm64"
AAPT2_PATH="${PREBUILT_DIR}/aapt2"

echo "=========================================="
echo " Flutter ARM64 Android Build Environment"
echo "=========================================="

# --------------------------------------------------
# 1. Architecture
# --------------------------------------------------

if [ "$(uname -m)" != "aarch64" ]; then
    echo "ERROR: This setup requires ARM64/aarch64."
    echo "Detected: $(uname -m)"
    exit 1
fi

echo
echo "[1/6] Architecture"
echo "ARM64 / aarch64: OK"

# --------------------------------------------------
# 2. Root warning
# --------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    echo
    echo "WARNING: Running as root."
    echo "Flutter recommends running without root privileges."
fi

# --------------------------------------------------
# 3. Required commands
# --------------------------------------------------

echo
echo "[2/6] Checking required commands..."

for cmd in file grep sed mkdir java; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing command: $cmd"
        exit 1
    fi
done

echo "Required commands: OK"

# --------------------------------------------------
# 4. Java
# --------------------------------------------------

echo
echo "[3/6] Checking Java..."

JAVA_VERSION="$(java -version 2>&1 | head -1 || true)"
echo "$JAVA_VERSION"

if ! echo "$JAVA_VERSION" | grep -q '17\.'; then
    echo "ERROR: Java 17 is required."
    exit 1
fi

echo "Java 17: OK"

# --------------------------------------------------
# 5. Flutter + Android SDK
# --------------------------------------------------

echo
echo "[4/6] Checking Flutter..."

FLUTTER_BIN="/opt/flutter/bin/flutter"

if [ ! -x "$FLUTTER_BIN" ]; then
    echo "ERROR: Flutter not found:"
    echo "  $FLUTTER_BIN"
    echo
    echo "Install Flutter separately, then run this script again."
    exit 1
fi

FLUTTER_ACTUAL="$("$FLUTTER_BIN" --version 2>&1 | grep -m1 '^Flutter ' || true)"

echo "$FLUTTER_ACTUAL"

if ! echo "$FLUTTER_ACTUAL" | grep -q "Flutter ${FLUTTER_VERSION}"; then
    echo "ERROR: Expected Flutter ${FLUTTER_VERSION}."
    exit 1
fi

echo "Flutter ${FLUTTER_VERSION}: OK"

echo
echo "Checking Android SDK..."

if [ ! -d "$ANDROID_SDK_ROOT" ]; then
    echo "ERROR: Android SDK not found:"
    echo "  $ANDROID_SDK_ROOT"
    exit 1
fi

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"

echo "Android SDK: $ANDROID_SDK_ROOT"

# --------------------------------------------------
# 6. ARM64 AAPT2 + Gradle configuration
# --------------------------------------------------

echo
echo "[5/6] Checking ARM64 AAPT2..."

if [ ! -x "$AAPT2_PATH" ]; then
    echo "ERROR: ARM64 AAPT2 not found:"
    echo "  $AAPT2_PATH"
    exit 1
fi

if ! file "$AAPT2_PATH" | grep -q 'ARM aarch64'; then
    echo "ERROR: AAPT2 is not an ARM64 binary."
    file "$AAPT2_PATH"
    exit 1
fi

echo "AAPT2:"
file "$AAPT2_PATH"

echo
echo "[6/6] Configuring Gradle..."

GRADLE_DIR="$HOME/.gradle"
GRADLE_PROPERTIES="$GRADLE_DIR/gradle.properties"

mkdir -p "$GRADLE_DIR"
touch "$GRADLE_PROPERTIES"

if grep -q '^android\.aapt2FromMavenOverride=' "$GRADLE_PROPERTIES"; then
    sed -i \
        "s|^android\.aapt2FromMavenOverride=.*|android.aapt2FromMavenOverride=${AAPT2_PATH}|" \
        "$GRADLE_PROPERTIES"
else
    printf '\nandroid.aapt2FromMavenOverride=%s\n' \
        "$AAPT2_PATH" >> "$GRADLE_PROPERTIES"
fi

echo
echo "=========================================="
echo " Setup configuration complete"
echo "=========================================="

echo
echo "Flutter:"
"$FLUTTER_BIN" --version 2>&1 | grep -m1 '^Flutter ' || true

echo
echo "Android SDK:"
echo "$ANDROID_SDK_ROOT"

echo
echo "ARM64 AAPT2:"
echo "$AAPT2_PATH"

echo
echo "Gradle AAPT2 override:"
grep '^android\.aapt2FromMavenOverride=' "$GRADLE_PROPERTIES"

echo
echo "Test Flutter:"
echo "  flutter doctor -v"

echo
echo "ARM64 APK:"
echo "  flutter build apk --release --target-platform android-arm64"

echo
echo "ARM64 AAB:"
echo "  flutter build appbundle --release --target-platform android-arm64"
