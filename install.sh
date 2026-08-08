#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Flutter ARM64 Android Build Environment
# Ubuntu/Debian ARM64 + Termux PRoot
#
# Fully self-contained installer.
# Does NOT use an existing Flutter / Android SDK / Gradle setup.
# ============================================================

FLUTTER_VERSION="3.27.4"
JAVA_MAJOR="17"

ANDROID_API="35"
ANDROID_BUILD_TOOLS="35.0.1"

# ARM64 replacement for Google's x86_64 Android native build tools.
# Published by Commit451/android-arm-build-tools.
ARM_BUILD_TOOLS_VERSION="35.0.1"
ARM_BUILD_TOOLS_TAG="platform-tools-${ARM_BUILD_TOOLS_VERSION}"

FLUTTER_ROOT="${HOME}/.local/flutter-${FLUTTER_VERSION}"
ANDROID_SDK_ROOT="${HOME}/.local/android-sdk"
DOWNLOAD_DIR="${HOME}/.cache/arm64-flutter-setup"

GRADLE_DIR="${HOME}/.gradle"
GRADLE_PROPERTIES="${GRADLE_DIR}/gradle.properties"

FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

ANDROID_CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip"

ARM_BUILD_TOOLS_BASE="https://github.com/Commit451/android-arm-build-tools/releases/download/${ARM_BUILD_TOOLS_TAG}"

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo
    echo "==> $*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Platform check
# ------------------------------------------------------------

info "Checking platform"

[ "$(uname -s)" = "Linux" ] || die "Linux is required."

case "$(uname -m)" in
    aarch64|arm64)
        ;;
    *)
        die "This installer targets Linux ARM64/aarch64. Detected: $(uname -m)"
        ;;
esac

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Distribution: ${PRETTY_NAME:-unknown}"
fi

echo "Architecture: $(uname -m)"

# ------------------------------------------------------------
# Root warning
# ------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    echo
    echo "WARNING:"
    echo "Running Flutter as root is not recommended."
    echo "For a normal installation, run this script as your regular user."
    echo
fi

# ------------------------------------------------------------
# Package installation
# ------------------------------------------------------------

info "Installing required system packages"

command_exists apt-get || die "apt-get is required on Ubuntu/Debian."

apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    file \
    git \
    unzip \
    xz-utils \
    tar \
    wget \
    zip \
    openjdk-17-jdk \
    libc6 \
    libstdc++6

# ------------------------------------------------------------
# Java
# ------------------------------------------------------------

info "Checking Java 17"

JAVA_BIN="$(command -v java)"

JAVA_VERSION="$(
    "$JAVA_BIN" -version 2>&1 |
    sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' |
    head -n1
)"

[ "$JAVA_VERSION" = "$JAVA_MAJOR" ] ||
    die "Java 17 is required. Detected Java ${JAVA_VERSION:-unknown}."

JAVA_HOME_DETECTED="$(
    dirname "$(dirname "$(readlink -f "$JAVA_BIN")")"
)"

export JAVA_HOME="$JAVA_HOME_DETECTED"

echo "JAVA_HOME=$JAVA_HOME"

# ------------------------------------------------------------
# Directory layout
# ------------------------------------------------------------

info "Creating isolated installation directories"

mkdir -p \
    "$HOME/.local" \
    "$DOWNLOAD_DIR" \
    "$GRADLE_DIR"

# ------------------------------------------------------------
# Flutter
# ------------------------------------------------------------

info "Installing Flutter ${FLUTTER_VERSION}"

FLUTTER_ARCHIVE="${DOWNLOAD_DIR}/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ ! -f "$FLUTTER_ARCHIVE" ]; then
    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        "$FLUTTER_URL" \
        -o "$FLUTTER_ARCHIVE"
fi

if [ ! -d "$FLUTTER_ROOT" ]; then
    TMP_FLUTTER="${HOME}/.local/flutter-install-$$"

    rm -rf "$TMP_FLUTTER"
    mkdir -p "$TMP_FLUTTER"

    tar -xJf "$FLUTTER_ARCHIVE" -C "$TMP_FLUTTER"

    [ -d "$TMP_FLUTTER/flutter" ] ||
        die "Flutter archive did not contain the expected flutter directory."

    mv "$TMP_FLUTTER/flutter" "$FLUTTER_ROOT"

    rm -rf "$TMP_FLUTTER"
fi

FLUTTER_BIN="${FLUTTER_ROOT}/bin/flutter"

[ -x "$FLUTTER_BIN" ] ||
    die "Flutter executable not found: $FLUTTER_BIN"

FLUTTER_ACTUAL="$(
    "$FLUTTER_BIN" --version 2>&1 |
    grep -m1 '^Flutter ' || true
)"

echo "$FLUTTER_ACTUAL"

echo "$FLUTTER_ACTUAL" |
    grep -q "Flutter ${FLUTTER_VERSION}" ||
    die "Installed Flutter version does not match ${FLUTTER_VERSION}."

# ------------------------------------------------------------
# PATH
# ------------------------------------------------------------

info "Configuring user PATH"

BASHRC="${HOME}/.bashrc"

PATH_BLOCK_START="# >>> arm64-flutter-setup >>>"
PATH_BLOCK_END="# <<< arm64-flutter-setup <<<"

if ! grep -qF "$PATH_BLOCK_START" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<PATH_EOF

${PATH_BLOCK_START}
export FLUTTER_ROOT="${FLUTTER_ROOT}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export JAVA_HOME="${JAVA_HOME}"
export PATH="\$FLUTTER_ROOT/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
${PATH_BLOCK_END}
PATH_EOF
fi

export FLUTTER_ROOT
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"

export PATH="$FLUTTER_ROOT/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

# ------------------------------------------------------------
# Android Command-Line Tools
# ------------------------------------------------------------

info "Installing Android SDK Command-Line Tools"

CMDLINE_ARCHIVE="${DOWNLOAD_DIR}/commandlinetools-linux.zip"
CMDLINE_TMP="${DOWNLOAD_DIR}/cmdline-tools-extract"

if [ ! -f "$CMDLINE_ARCHIVE" ]; then
    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        "$ANDROID_CMDLINE_URL" \
        -o "$CMDLINE_ARCHIVE"
fi

rm -rf "$CMDLINE_TMP"
mkdir -p "$CMDLINE_TMP"

unzip -q -o "$CMDLINE_ARCHIVE" -d "$CMDLINE_TMP"

mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"

    mv \
        "$CMDLINE_TMP/cmdline-tools" \
        "$ANDROID_SDK_ROOT/cmdline-tools/latest"
fi

rm -rf "$CMDLINE_TMP"

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

[ -x "$SDKMANAGER" ] ||
    die "sdkmanager was not installed correctly."

# ------------------------------------------------------------
# Android SDK licenses
# ------------------------------------------------------------

info "Accepting Android SDK licenses"

yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Android SDK packages
# ------------------------------------------------------------

info "Installing Android SDK packages"

"$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" \
    "platform-tools" \
    "platforms;android-${ANDROID_API}" \
    "build-tools;${ANDROID_BUILD_TOOLS}"

# ------------------------------------------------------------
# ARM64 build-tools
# ------------------------------------------------------------

info "Installing ARM64 Android build-tools"

ARM_DEST="${ANDROID_SDK_ROOT}/build-tools/${ANDROID_BUILD_TOOLS}"

[ -d "$ARM_DEST" ] ||
    die "Android build-tools directory was not created: $ARM_DEST"

for TOOL in aapt2 aidl zipalign split-select; do

    info "Downloading ARM64 ${TOOL}"

    TMP_TOOL="${ARM_DEST}/.${TOOL}.arm64.tmp"

    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        "${ARM_BUILD_TOOLS_BASE}/${TOOL}" \
        -o "$TMP_TOOL"

    chmod +x "$TMP_TOOL"

    file "$TMP_TOOL" | grep -Eqi \
        'ARM aarch64|ARM64|AArch64' ||
        die "${TOOL} is not an ARM64 binary."

    mv "$TMP_TOOL" "${ARM_DEST}/${TOOL}"

done

# ------------------------------------------------------------
# Verify ARM64 tools
# ------------------------------------------------------------

info "Verifying ARM64 build-tools"

file "${ARM_DEST}/aapt2"
file "${ARM_DEST}/aidl"
file "${ARM_DEST}/zipalign"
file "${ARM_DEST}/split-select"

"${ARM_DEST}/aapt2" version | head -n1 || true

# ------------------------------------------------------------
# Gradle AAPT2 override
# ------------------------------------------------------------

info "Configuring isolated Gradle AAPT2 override"

mkdir -p "$GRADLE_DIR"

touch "$GRADLE_PROPERTIES"

AAPT2_LINE="android.aapt2FromMavenOverride=${ARM_DEST}/aapt2"

if grep -q '^android\.aapt2FromMavenOverride=' "$GRADLE_PROPERTIES"; then
    sed -i \
        "s|^android\.aapt2FromMavenOverride=.*|${AAPT2_LINE}|" \
        "$GRADLE_PROPERTIES"
else
    printf '\n%s\n' "$AAPT2_LINE" >> "$GRADLE_PROPERTIES"
fi

# ------------------------------------------------------------
# Flutter Android configuration
# ------------------------------------------------------------

info "Configuring Flutter Android"

"$FLUTTER_BIN" config \
    --android-sdk "$ANDROID_SDK_ROOT"

# ------------------------------------------------------------
# Flutter doctor
# ------------------------------------------------------------

info "Running Flutter doctor"

"$FLUTTER_BIN" doctor -v || true

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

info "Final verification"

echo
echo "Flutter:"
"$FLUTTER_BIN" --version | head -n4

echo
echo "Java:"
java -version 2>&1 | head -n1

echo
echo "Android SDK:"
echo "$ANDROID_SDK_ROOT"

echo
echo "AAPT2:"
file "${ARM_DEST}/aapt2"

echo
echo "Gradle override:"
grep '^android\.aapt2FromMavenOverride=' "$GRADLE_PROPERTIES"

echo
echo "============================================================"
echo " ARM64 Flutter Android environment installed successfully"
echo "============================================================"
echo
echo "Flutter:"
echo "  $FLUTTER_BIN"
echo
echo "Android SDK:"
echo "  $ANDROID_SDK_ROOT"
echo
echo "ARM64 AAPT2:"
echo "  ${ARM_DEST}/aapt2"
echo
echo "Reload your shell:"
echo "  source ~/.bashrc"
echo
echo "Then verify:"
echo "  flutter doctor -v"
echo
echo "ARM64 APK:"
echo "  flutter build apk --release --target-platform android-arm64"
echo
echo "ARM64 AAB:"
echo "  flutter build appbundle --release --target-platform android-arm64"
echo
