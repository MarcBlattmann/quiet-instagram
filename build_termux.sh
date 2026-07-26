#!/usr/bin/env bash
#
# On-device build helper for HealthyIG (Termux / Android).
# Run with:  bash build_termux.sh [path/to/instagram.apk]
#
# If no path is given, the script looks for an Instagram apk in
# ~/storage/downloads. See GUIDE_TERMUX.md for the full walkthrough.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$repo_dir/ig_plain"
keystore="$repo_dir/healthyig.jks"
store_pass="password"

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

###############################################################################
# 1. Locate the input apk
###############################################################################

input_apk="${1:-}"

if [ -z "$input_apk" ]; then
    say "No apk given, searching ~/storage/downloads ..."
    if [ ! -d "$HOME/storage/downloads" ]; then
        die "~/storage/downloads not found. Run 'termux-setup-storage' first, or pass the apk path as an argument."
    fi
    # Newest matching apk wins
    input_apk="$(find "$HOME/storage/downloads" -maxdepth 2 -type f \
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

###############################################################################
# 2. Check tooling
###############################################################################

missing=()
for tool in apktool apksigner keytool; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [ "${#missing[@]}" -gt 0 ]; then
    printf '\nMissing required tools: %s\n' "${missing[*]}" >&2
    printf 'Install them with:\n\n  pkg install -y apktool apksigner openjdk-17\n\n' >&2
    exit 1
fi

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

say "Decompiling (this is the slow part - expect several minutes)..."
rm -rf "$work_dir"
apktool d -r -f -o "$work_dir" "$input_apk"

###############################################################################
# 4. Patch the endpoints
###############################################################################
# script.sh patches every file under its own directory, so it is copied into
# ig_plain and run from there. That keeps the patch off the repo's own files
# (README.md and friends contain the same endpoint strings).

say "Patching endpoints with script.sh ..."
cp "$repo_dir/script.sh" "$work_dir/script.sh"
( cd "$work_dir" && bash ./script.sh )
rm -f "$work_dir/script.sh"

###############################################################################
# 5. Rebuild, align, sign
###############################################################################

say "Rebuilding the apk ..."
apktool b -r -f "$work_dir"

built="$work_dir/dist/$(basename "$input_apk")"
[ -f "$built" ] || built="$(find "$work_dir/dist" -maxdepth 1 -name '*.apk' | head -1)"
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
