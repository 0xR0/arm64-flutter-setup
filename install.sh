#!/usr/bin/env bash
# arm64-flutter-setup
#
# Single-file installer for Flutter on ARM64 Android (Termux + PRoot Ubuntu).
#
#   Termux run:
#     curl -fsSL https://raw.githubusercontent.com/0xR0/arm64-flutter-setup/main/install.sh | bash
#
#   What it does:
#     - Termux side:   installs proot-distro + Ubuntu (if missing), wires ~/.bashrc, verifies a debug APK build.
#     - Ubuntu side:   installs OpenJDK 17, Flutter, Android SDK, ARM64 AAPT2/aidl/zipalign/split-select,
#                      configures Gradle to use ARM64 AAPT2.
#
#   Idempotent: each step is skipped if the component is already present.
#   Does not touch any pre-existing Debian PRoot.
#

set -euo pipefail

# ---------------- Configuration ----------------

FLUTTER_VERSION="3.27.4"
JAVA_MAJOR="17"
ANDROID_API="35"
ANDROID_BUILD_TOOLS="35.0.1"
ARM_BUILD_TOOLS_TAG="platform-tools-35.0.1"

UBUNTU_DISTRO="ubuntu"

ANDROID_CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip"
ARM_BUILD_TOOLS_BASE="https://github.com/Commit451/android-arm-build-tools/releases/download/${ARM_BUILD_TOOLS_TAG}"

SELF_URL="${SELF_URL:-https://raw.githubusercontent.com/0xR0/arm64-flutter-setup/master/install.sh}"

# ---------------- UI helpers ----------------

_c_reset=$'\033[0m'
_c_cyan=$'\033[1;36m'
_c_green=$'\033[1;32m'
_c_yellow=$'\033[1;33m'
_c_red=$'\033[1;31m'

info() { printf '\n%s==>%s %s\n' "$_c_cyan"  "$_c_reset" "$*"; }
ok()   { printf '%s✓%s %s\n'    "$_c_green" "$_c_reset" "$*"; }
warn() { printf '%sWARN:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '\n%sERROR:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; exit 1; }

# ---------------- Environment detection ----------------

if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux/files/usr ]; then
    IN_TERMUX=1
else
    IN_TERMUX=0
fi

# ============================================================
# UBUNTU-SIDE INSTALL
# ============================================================

run_ubuntu_install() {
    info "Ubuntu ARM64 installer starting"

    [ "$(uname -s)" = "Linux" ]      || die "Linux required."
    case "$(uname -m)" in
        aarch64|arm64) : ;;
        *) die "aarch64 required, detected: $(uname -m)" ;;
    esac

    export DEBIAN_FRONTEND=noninteractive

    info "Installing base packages (apt)"
    apt-get update -qq
    apt-get install -y -qq \
        ca-certificates curl file git unzip xz-utils tar wget zip \
        openjdk-17-jdk libc6 libstdc++6

    info "Checking Java ${JAVA_MAJOR}"
    local java_bin java_ver
    java_bin="$(command -v java)"
    java_ver="$("$java_bin" -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n1)"
    [ "$java_ver" = "$JAVA_MAJOR" ] || die "Java ${JAVA_MAJOR} required (found: ${java_ver:-unknown})"
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$java_bin")")")"

    local flutter_root="${HOME}/.local/flutter-${FLUTTER_VERSION}"
    local android_sdk="${HOME}/.local/android-sdk"
    local dl_dir="${HOME}/.cache/arm64-flutter-setup"
    local gradle_dir="${HOME}/.gradle"
    local gradle_props="${gradle_dir}/gradle.properties"

    mkdir -p "$HOME/.local" "$dl_dir" "$gradle_dir"

    # -------- Flutter --------
    info "Installing Flutter ${FLUTTER_VERSION}"
    if [ ! -d "${flutter_root}/.git" ]; then
        rm -rf "$flutter_root"
        git clone --depth 1 --branch "$FLUTTER_VERSION" \
            https://github.com/flutter/flutter.git "$flutter_root"
    else
        ok "Flutter clone exists — skipping"
    fi

    local flutter_bin="${flutter_root}/bin/flutter"
    [ -x "$flutter_bin" ] || die "Flutter binary missing: $flutter_bin"

    info "Bootstrapping Flutter"
    "$flutter_bin" --version >/dev/null

    local dart_bin="${flutter_root}/bin/cache/dart-sdk/bin/dart"
    [ -x "$dart_bin" ] || die "Dart SDK missing: $dart_bin"
    file "$dart_bin" | grep -q 'ARM aarch64' || die "Non-ARM64 Dart SDK detected"

    "$flutter_bin" --version | head -n4

    # -------- PATH in Ubuntu bashrc --------
    info "Configuring Ubuntu bashrc PATH"
    local bashrc="${HOME}/.bashrc"
    local start='# >>> arm64-flutter-setup >>>'
    local end='# <<< arm64-flutter-setup <<<'
    [ -f "$bashrc" ] || touch "$bashrc"
    if ! grep -qF "$start" "$bashrc"; then
        cat >> "$bashrc" <<EOF

${start}
export FLUTTER_ROOT="${flutter_root}"
export ANDROID_SDK_ROOT="${android_sdk}"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export JAVA_HOME="${JAVA_HOME}"
export PATH="\$FLUTTER_ROOT/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
${end}
EOF
    else
        ok "Ubuntu bashrc block already present"
    fi
    export FLUTTER_ROOT="$flutter_root"
    export ANDROID_SDK_ROOT="$android_sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export PATH="${flutter_root}/bin:${android_sdk}/cmdline-tools/latest/bin:${android_sdk}/platform-tools:$PATH"

    # -------- Android cmdline-tools --------
    info "Installing Android command-line tools"
    local cmdline_zip="${dl_dir}/commandlinetools-linux.zip"
    local cmdline_tmp="${dl_dir}/cmdline-tools-extract"
    [ -f "$cmdline_zip" ] || curl -fL --retry 3 --retry-delay 2 "$ANDROID_CMDLINE_URL" -o "$cmdline_zip"

    if [ ! -d "${android_sdk}/cmdline-tools/latest/bin" ]; then
        rm -rf "$cmdline_tmp"; mkdir -p "$cmdline_tmp"
        unzip -q -o "$cmdline_zip" -d "$cmdline_tmp"
        mkdir -p "${android_sdk}/cmdline-tools"
        rm -rf "${android_sdk}/cmdline-tools/latest"
        mv "${cmdline_tmp}/cmdline-tools" "${android_sdk}/cmdline-tools/latest"
        rm -rf "$cmdline_tmp"
    else
        ok "cmdline-tools already installed"
    fi

    local sdkmanager="${android_sdk}/cmdline-tools/latest/bin/sdkmanager"
    [ -x "$sdkmanager" ] || die "sdkmanager missing"

    info "Accepting SDK licenses"
    yes | "$sdkmanager" --sdk_root="$android_sdk" --licenses >/dev/null 2>&1 || true

    info "Installing Android SDK packages"
    "$sdkmanager" --sdk_root="$android_sdk" \
        "platform-tools" \
        "platforms;android-${ANDROID_API}" \
        "build-tools;${ANDROID_BUILD_TOOLS}"

    # -------- ARM64 build-tools override --------
    local arm_dest="${android_sdk}/build-tools/${ANDROID_BUILD_TOOLS}"
    [ -d "$arm_dest" ] || die "build-tools missing: $arm_dest"

    local tool tmp needs_download=0
    for tool in aapt2 aidl zipalign split-select; do
        if ! file "${arm_dest}/${tool}" 2>/dev/null | grep -Eqi 'ARM aarch64|ARM64|AArch64'; then
            needs_download=1
            break
        fi
    done

    if [ "$needs_download" = "1" ]; then
        info "Installing ARM64 build-tools (aapt2/aidl/zipalign/split-select)"
        for tool in aapt2 aidl zipalign split-select; do
            tmp="${arm_dest}/.${tool}.arm64.tmp"
            curl -fL --retry 3 --retry-delay 2 \
                "${ARM_BUILD_TOOLS_BASE}/${tool}" -o "$tmp"
            chmod +x "$tmp"
            file "$tmp" | grep -Eqi 'ARM aarch64|ARM64|AArch64' \
                || die "${tool} is not ARM64"
            mv "$tmp" "${arm_dest}/${tool}"
        done
    else
        ok "ARM64 build-tools already installed"
    fi

    file "${arm_dest}/aapt2" "${arm_dest}/aidl" "${arm_dest}/zipalign" "${arm_dest}/split-select"

    # -------- Gradle AAPT2 override --------
    info "Writing gradle.properties AAPT2 override"
    touch "$gradle_props"
    local line="android.aapt2FromMavenOverride=${arm_dest}/aapt2"
    if grep -q '^android\.aapt2FromMavenOverride=' "$gradle_props"; then
        sed -i "s|^android\.aapt2FromMavenOverride=.*|${line}|" "$gradle_props"
    else
        printf '\n%s\n' "$line" >> "$gradle_props"
    fi

    info "Configuring Flutter android-sdk path"
    "$flutter_bin" config --android-sdk "$android_sdk" >/dev/null

    info "flutter doctor"
    "$flutter_bin" doctor -v || true

    ok "Ubuntu-side install complete"
}

# ============================================================
# TERMUX-SIDE ORCHESTRATION
# ============================================================

run_termux_setup() {
    info "Termux side: preparing proot Ubuntu environment"

    command -v proot-distro >/dev/null 2>&1 || pkg install -y proot-distro
    command -v curl         >/dev/null 2>&1 || pkg install -y curl

    if proot-distro list --installed 2>/dev/null | grep -qw "$UBUNTU_DISTRO"; then
        ok "Ubuntu proot already installed — skipping"
    else
        info "Downloading Ubuntu proot (this can take a while)"
        proot-distro install "$UBUNTU_DISTRO"
    fi

    info "Running installer inside Ubuntu proot"
    proot-distro login "$UBUNTU_DISTRO" --bind /sdcard -- \
        bash -c "curl -fsSL '${SELF_URL}' | bash"

    setup_termux_bashrc
    verify_debug_build

    printf '\n%s✓ Install complete.%s\n' "$_c_green" "$_c_reset"
    printf 'Open a new shell or run:  %ssource ~/.bashrc%s\n\n' "$_c_yellow" "$_c_reset"
    printf 'Usage (from Termux):\n'
    printf '  flutter --version\n'
    printf '  flutter create ~/projects/hello\n'
    printf '  cd ~/projects/hello\n'
    printf '  flutter build apk --debug --target-platform android-arm64\n\n'
    printf 'Ubuntu shell:  %sflutter-shell%s\n' "$_c_yellow" "$_c_reset"
}

setup_termux_bashrc() {
    info "Writing Termux ~/.bashrc wrappers"

    local bashrc="$HOME/.bashrc"
    local marker='# >>> arm64-flutter-setup >>>'

    [ -f "$bashrc" ] || touch "$bashrc"

    if grep -qF "$marker" "$bashrc"; then
        ok "bashrc block already present — skipping"
        return
    fi

    cat >> "$bashrc" <<'EOF'

# >>> arm64-flutter-setup >>>
# Wrappers that transparently forward Flutter/Dart calls into the Ubuntu proot.
# Requires: proot-distro with distro "ubuntu" installed.

_ARM64_FLUTTER_DISTRO="ubuntu"
_ARM64_FLUTTER_TERMUX_HOME="/data/data/com.termux/files/home"

_arm64_flutter_run() {
    local cmd="$1"; shift
    local pwd_abs; pwd_abs="$(pwd)"
    local args=("$@")

    if [[ "$pwd_abs" == "$_ARM64_FLUTTER_TERMUX_HOME"* ]]; then
        local rel="${pwd_abs#$_ARM64_FLUTTER_TERMUX_HOME}"
        proot-distro login "$_ARM64_FLUTTER_DISTRO" \
            --bind "$_ARM64_FLUTTER_TERMUX_HOME:/host-home" \
            --bind /sdcard \
            -- bash -lc "cd /host-home$rel && $cmd \"\$@\"" _ "${args[@]}"
    else
        proot-distro login "$_ARM64_FLUTTER_DISTRO" \
            --bind "$pwd_abs:/host-project" \
            --bind /sdcard \
            -- bash -lc "cd /host-project && $cmd \"\$@\"" _ "${args[@]}"
    fi
}

flutter()       { _arm64_flutter_run flutter "$@"; }
dart()          { _arm64_flutter_run dart    "$@"; }
flutter-shell() { proot-distro login "$_ARM64_FLUTTER_DISTRO" --bind /sdcard; }
# <<< arm64-flutter-setup <<<
EOF
    ok "bashrc updated"
}

verify_debug_build() {
    info "Verification: building a debug APK"

    proot-distro login "$UBUNTU_DISTRO" --bind /sdcard -- bash -lc '
        set -e
        [ -f ~/.bashrc ] && source ~/.bashrc || true
        mkdir -p ~/projects
        cd ~/projects
        if [ ! -d verify_app ]; then
            flutter create --platforms=android verify_app >/dev/null
        fi
        cd verify_app
        flutter build apk --debug --target-platform android-arm64
        apk="build/app/outputs/flutter-apk/app-debug.apk"
        if [ -f "$apk" ] && [ -d /sdcard/Download ]; then
            cp "$apk" /sdcard/Download/verify_app-debug.apk
            echo "APK -> /sdcard/Download/verify_app-debug.apk"
        fi
    ' || die "Debug APK build failed"

    ok "Debug APK verified"
}

# ============================================================
# Dispatch
# ============================================================

if [ "$IN_TERMUX" = "1" ]; then
    run_termux_setup
else
    run_ubuntu_install
fi
