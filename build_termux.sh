#!/usr/bin/env bash
#
# On-device build helper for HealthyIG (Termux / Android).
#
#   bash build_termux.sh --check          # report what is installed, build nothing
#   bash build_termux.sh                  # find an apk in ~/storage/downloads and build
#   bash build_termux.sh path/to/ig.apk   # build a specific apk
#
# apktool is NOT in the Termux package repos. It is a Java jar - this script
# finds it on PATH, next to itself as apktool.jar, or downloads the latest
# release from GitHub. Override with:  APKTOOL_JAR=/path/to/apktool.jar
#
# See README.md for the full walkthrough.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$repo_dir/ig_plain"
keystore="$repo_dir/healthyig.jks"
store_pass="password"

say()  { printf '\n>> %s\n' "$*"; }
warn() { printf '\n!! %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

###############################################################################
# Locate apktool
###############################################################################
# Sets $APKTOOL to a full command prefix, e.g. "java -jar /path/apktool.jar".

resolve_apktool() {
    if [ -n "${APKTOOL_JAR:-}" ]; then
        [ -f "$APKTOOL_JAR" ] || die "APKTOOL_JAR is set but not a file: $APKTOOL_JAR"
        APKTOOL="java -jar $APKTOOL_JAR"
        return 0
    fi

    # A real apktool wrapper on PATH (rare on Termux, normal on desktop Linux)
    if command -v apktool >/dev/null 2>&1; then
        APKTOOL="apktool"
        return 0
    fi

    local jar
    for jar in "$repo_dir/apktool.jar" "${PREFIX:-/usr}/share/apktool.jar"; do
        if [ -f "$jar" ]; then
            APKTOOL="java -jar $jar"
            return 0
        fi
    done

    return 1
}

download_apktool() {
    command -v curl >/dev/null 2>&1 || die "curl is needed to download apktool. Run: pkg install -y curl"

    say "apktool not found - fetching the latest release from GitHub ..."

    local url
    url="$(curl -fsSL https://api.github.com/repos/iBotPeaches/Apktool/releases/latest \
        | grep -o 'https://[^"]*apktool[^"]*\.jar' | head -1)" || true

    if [ -z "$url" ]; then
        die "Could not determine the apktool download URL.
Download the latest apktool_x.y.z.jar manually from
  https://github.com/iBotPeaches/Apktool/releases
save it as apktool.jar in $repo_dir, then re-run this script."
    fi

    curl -fL --progress-bar -o "$repo_dir/apktool.jar" "$url" \
        || die "Download failed. Fetch $url manually and save it as $repo_dir/apktool.jar"

    APKTOOL="java -jar $repo_dir/apktool.jar"
    say "apktool saved to $repo_dir/apktool.jar"
}

###############################################################################
# Locate aapt2
###############################################################################
# apktool ships prebuilt aapt/aapt2 binaries for x86_64 Linux. Those cannot
# execute on aarch64 Android, so on Termux we must hand apktool the native
# aapt2 from the aapt2 package. On a desktop the bundled one is fine.

resolve_build_args() {
    # Only -f is common to every apktool version. Note that -r is a decode-only
    # flag - passing it to 'b' fails with "Unrecognized option: -r".
    BUILD_ARGS=(-f)

    local aapt2_bin build_help
    aapt2_bin="$(command -v aapt2 2>/dev/null || true)"
    build_help="$($APKTOOL b --help 2>&1 || true)"

    if [ -n "$aapt2_bin" ]; then
        BUILD_ARGS+=(--aapt "$aapt2_bin")
        # apktool 2.x needs --use-aapt2 to treat --aapt as an aapt2 binary.
        # 3.x uses aapt2 unconditionally and rejects the flag.
        if printf '%s' "$build_help" | grep -q -- '--use-aapt2'; then
            BUILD_ARGS+=(--use-aapt2)
        fi
        say "Using native aapt2: $aapt2_bin"
    else
        warn "aapt2 not found. apktool will fall back to its bundled binary, which
   does not run on Android (aarch64). If the rebuild step fails with an
   'aapt' or 'exec format' error, install it with:  pkg install -y aapt2"
    fi
}

###############################################################################
# Environment probe (--check)
###############################################################################

probe() {
    printf '\n=== HealthyIG build environment ===\n\n'
    printf '%-12s %s\n' "arch:" "$(uname -m)"
    printf '%-12s %s\n' "termux:" "$([ -n "${PREFIX:-}" ] && echo "yes ($PREFIX)" || echo "no")"

    local t
    for t in java keytool apksigner aapt2 aapt zipalign curl git; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '%-12s %s\n' "$t:" "$(command -v "$t")"
        else
            printf '%-12s %s\n' "$t:" "MISSING"
        fi
    done

    if resolve_apktool; then
        printf '%-12s %s\n' "apktool:" "$APKTOOL"
    else
        printf '%-12s %s\n' "apktool:" "MISSING (will be downloaded on build)"
    fi

    if [ -d "$HOME/storage/downloads" ]; then
        printf '%-12s %s\n' "downloads:" "ok"
        printf '\nCandidate apks in Downloads:\n'
        find -L "$HOME/storage/downloads" -maxdepth 2 -type f \
            \( -iname "*instagram*.apk*" -o -iname "ig.apk" \) 2>/dev/null \
            | sed 's/^/  /' || true
    else
        printf '%-12s %s\n' "downloads:" "MISSING (run termux-setup-storage)"
    fi

    printf '\nFree space here: %s\n\n' "$(df -h "$repo_dir" | awk 'NR==2 {print $4}')"
}

###############################################################################
# Arguments
###############################################################################

resume=0
positional=()

for arg in "$@"; do
    case "$arg" in
        --check|-c) probe; exit 0 ;;
        --resume)   resume=1 ;;
        -*)         die "Unknown option: $arg" ;;
        *)          positional+=("$arg") ;;
    esac
done

###############################################################################
# 1. Locate the input apk
###############################################################################

input_apk="${positional[0]:-}"

if [ "$resume" -eq 1 ]; then
    [ -d "$work_dir" ] || die "--resume needs an existing decompiled tree at $work_dir.
Run without --resume to decompile from scratch."
    say "Resuming from the existing decompiled tree: $work_dir"
    say "(skipping decompile and patching - they are already done)"
else
    if [ -z "$input_apk" ]; then
        say "No apk given, searching ~/storage/downloads ..."
        if [ ! -d "$HOME/storage/downloads" ]; then
            die "~/storage/downloads not found. Run 'termux-setup-storage' first, or pass the apk path as an argument."
        fi
        # Newest matching apk wins. -L because ~/storage/downloads is a symlink.
        input_apk="$(find -L "$HOME/storage/downloads" -maxdepth 2 -type f \
            \( -iname "*instagram*.apk" -o -iname "ig.apk" \) -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)"
    fi

    [ -n "$input_apk" ] || die "Could not find an Instagram apk. Pass it explicitly: bash build_termux.sh /path/to/ig.apk"
    [ -f "$input_apk" ] || die "File not found: $input_apk"

    case "$input_apk" in
        *.apkm|*.xapk|*.apks)
            die "'$input_apk' is a bundle format. apktool cannot read it - download the plain .apk (arm64-v8a, nodpi) from APKMirror."
            ;;
    esac

    say "Using input apk: $input_apk"
fi

###############################################################################
# 2. Check tooling
###############################################################################

missing=()
for tool in java apksigner keytool; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [ "${#missing[@]}" -gt 0 ]; then
    printf '\nMissing required tools: %s\n' "${missing[*]}" >&2
    printf 'On Termux, install them with:\n\n  pkg install -y openjdk-17 apksigner aapt2\n\n' >&2
    printf 'Note: apktool is NOT a Termux package - this script fetches the jar itself.\n\n' >&2
    exit 1
fi

resolve_apktool || download_apktool
say "apktool command: $APKTOOL"

resolve_build_args

# zipalign is optional - the apk installs without it, it is only an optimisation.
if command -v zipalign >/dev/null 2>&1; then
    have_zipalign=1
else
    have_zipalign=0
    say "zipalign not found - skipping the alignment step (the apk will still install)."
fi

###############################################################################
# 3. Decompile
###############################################################################

if [ "$resume" -eq 0 ]; then
    say "Decompiling (this is the slow part - expect several minutes)..."
    rm -rf "$work_dir"
    $APKTOOL d -r -f -o "$work_dir" "$input_apk"
fi

###############################################################################
# 4. Patch the endpoints
###############################################################################
# script.sh patches every file under its own directory, so it is copied into
# ig_plain and run from there. That keeps the patch off the repo's own files
# (README.md and friends contain the same endpoint strings).

if [ "$resume" -eq 0 ]; then
    say "Patching endpoints with script.sh ..."
    cp "$repo_dir/script.sh" "$work_dir/script.sh"
    ( cd "$work_dir" && bash ./script.sh )
    rm -f "$work_dir/script.sh"
fi

###############################################################################
# 5. Rebuild, align, sign
###############################################################################

say "Rebuilding the apk ..."
if ! $APKTOOL b "${BUILD_ARGS[@]}" "$work_dir"; then
    die "Rebuild failed.
If the error mentions aapt / 'exec format error' / 'cannot execute binary file',
apktool tried to use its bundled x86 aapt. Install the native one and retry:

  pkg install -y aapt2

If the process was killed with no error message, the phone ran out of RAM.
There is no on-device workaround for that - the rebuild needs a PC.

The decompiled tree is left in place, so you can retry just this step with:
  bash build_termux.sh --resume"
fi

built=""
[ -n "$input_apk" ] && built="$work_dir/dist/$(basename "$input_apk")"
[ -n "$built" ] && [ -f "$built" ] || built="$(find "$work_dir/dist" -maxdepth 1 -name '*.apk' | head -1)"
[ -f "$built" ] || die "apktool did not produce an apk in $work_dir/dist"

out="$repo_dir/install.apk"
rm -f "$out"

if [ "$have_zipalign" -eq 1 ]; then
    say "Aligning ..."
    zipalign -p -f 4 "$built" "$out"
else
    cp "$built" "$out"
fi

if [ ! -f "$keystore" ]; then
    say "Generating a signing key (first run only) ..."
    keytool -genkeypair -v -keystore "$keystore" -alias key0 -keyalg RSA \
        -keysize 2048 -validity 10000 \
        -storepass "$store_pass" -keypass "$store_pass" \
        -dname "CN=HealthyIG, O=Android, C=IT"
fi

say "Signing ..."
apksigner sign --ks "$keystore" --ks-pass "pass:$store_pass" \
    --v1-signing-enabled true --v2-signing-enabled true \
    --v3-signing-enabled false --min-sdk-version 21 "$out"

apksigner verify --print-certs "$out" >/dev/null && say "Signature verified."

###############################################################################
# 6. Hand the file back to the user
###############################################################################

if [ -d "$HOME/storage/downloads" ]; then
    cp "$out" "$HOME/storage/downloads/HealthyIG-install.apk"
    say "Done. Copied to Downloads as HealthyIG-install.apk"
    say "Uninstall the official Instagram, then open that file to install."
else
    say "Done: $out"
fi
