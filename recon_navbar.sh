#!/usr/bin/env bash
#
# Locate the bottom-navigation / Reels-tab code in a decompiled Instagram tree.
#
#   bash recon_navbar.sh [ig_plain]
#
# Writes a bounded, pasteable report to recon_navbar.txt. This does not patch
# anything - it only tells you where to look. Instagram is obfuscated by R8, so
# class names are mostly meaningless (X/0aB.smali); the leverage comes from
# string constants and resource names, which survive obfuscation.
#
# NOTE: build_termux.sh decompiles with -r (resources left raw) because the
# endpoint patch does not need them. Removing the Reels *button* probably does.
# For this work, decompile without -r:
#
#   java -jar apktool.jar d -f -o ig_full YOUR_INSTAGRAM.apk
#   bash recon_navbar.sh ig_full

# Deliberately not -e/-pipefail: grep exits 1 on no matches and head closes
# pipes early, both of which are normal here. An empty section is a result.
set -u

tree="${1:-ig_plain}"
report="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/recon_navbar.txt"
cap=25   # max lines kept per section, so the report stays pasteable

[ -d "$tree" ] || { printf 'No such directory: %s\n' "$tree" >&2; exit 1; }

exec >"$report" 2>&1

printf '=== navbar recon: %s ===\n' "$tree"
printf 'smali files: %s\n' "$(find "$tree" -name '*.smali' 2>/dev/null | wc -l)"
printf 'resources decoded: %s\n\n' "$([ -d "$tree/res" ] && echo yes || echo 'NO - re-decompile without -r')"

section() { printf '\n----- %s -----\n' "$1"; }

###############################################################################
# 1. Class files whose names survived obfuscation
###############################################################################
# Instagram's design-system classes (Igds*) are often kept, and they are the
# closest thing to a stable anchor into the tab bar.

section "class files named like a nav bar"
find "$tree" -name '*.smali' \( \
        -iname '*BottomNavigation*' -o \
        -iname '*TabBar*' -o \
        -iname '*MainTab*' -o \
        -iname '*NavigationBar*' \
    \) 2>/dev/null | head -"$cap"

###############################################################################
# 2. Tab identifier strings
###############################################################################
# Tabs are usually keyed by short string constants for analytics/logging. These
# are the highest-value leads: they name the tab even when the class does not.

section "tab identifier string constants"
grep -rhoE '"(clips|reels)[a-z_]*(tab|button|icon)[a-z_]*"' "$tree" \
    --include='*.smali' 2>/dev/null | sort | uniq -c | sort -rn | head -"$cap"

section "generic tab constants (for comparison - shows the naming scheme)"
grep -rhoE '"[a-z_]*tab[a-z_]*"' "$tree" \
    --include='*.smali' 2>/dev/null | sort | uniq -c | sort -rn | head -"$cap"

###############################################################################
# 3. Files that mention both the nav bar and clips
###############################################################################
# A file referencing both is a strong candidate for where the tab list is built.

section "files referencing both navigation and clips/reels"
# Candidates come from BOTH the path and the contents: R8 keeps the hint in
# one or the other, rarely both.
{
    find "$tree" -name '*.smali' \( -iname '*BottomNavigation*' -o -iname '*TabBar*' \
        -o -iname '*MainTab*' -o -iname '*NavigationBar*' \) 2>/dev/null
    grep -rl -iE 'bottomnavigation|navigationbar|tabbar' "$tree" --include='*.smali' 2>/dev/null
} | sort -u | xargs -r grep -l -iE 'clips|reels' 2>/dev/null | head -"$cap"

###############################################################################
# 4. Resource names (only if decompiled without -r)
###############################################################################

if [ -d "$tree/res" ]; then
    section "drawable/id resources naming reels or clips"
    find "$tree/res" \( -iname '*clips*' -o -iname '*reels*' \) 2>/dev/null | head -"$cap"

    section "string resources naming reels"
    grep -rhoE '<string name="[^"]*(reels|clips)[^"]*"' "$tree/res" 2>/dev/null | head -"$cap"
fi

###############################################################################
# 5. Boolean gates
###############################################################################
# The cleanest patch target is a method that decides whether the tab is shown.
# Look for feature-flag style strings near clips/reels.

section "feature-flag style strings mentioning clips/reels tab visibility"
grep -rhoE '"[a-z0-9_.]*(show|enable|is)[a-z0-9_.]*(clips|reels)[a-z0-9_.]*"' "$tree" \
    --include='*.smali' 2>/dev/null | sort -u | head -"$cap"

printf '\n=== end of report ===\n'
