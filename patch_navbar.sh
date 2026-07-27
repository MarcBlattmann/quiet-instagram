#!/usr/bin/env bash
#
# Remove the Reels button from Instagram's bottom navigation bar.
#
#   bash patch_navbar.sh <decompiled-tree>
#
# Unlike script.sh (which blanks API endpoint strings and is version-agnostic),
# this edits bytecode and IS tied to a specific build's obfuscated names. It
# verifies everything it depends on before touching anything, and fails loudly
# rather than silently producing an apk with the tab still present.
#
# Verified against Instagram 430.0.0.53.80.
#
# --- What it patches -------------------------------------------------------
#
# LX/00TJ;->A04(UserSession, boolean) builds the tab list that feeds both the
# nav buttons and the ViewPager2. It loops indices 0..4, resolves each to a
# name via LX/00TK;->A04, converts that to a tab object via LX/00TL;->A01,
# dedups, and adds. We compare the name against "clips" and jump to the loop's
# increment label, so the Reels tab never enters the list.
#
# Patching here rather than at the 17 read sites keeps buttons and pager
# consistent - filtering only the visible buttons would leave a 5-page pager
# behind 4 buttons and desync the indices.

set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] || { printf 'usage: bash patch_navbar.sh <decompiled-tree>\n' >&2; exit 2; }
[ -d "$tree" ] || { printf 'No such directory: %s\n' "$tree" >&2; exit 2; }

say()  { printf '\n>> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

###############################################################################
# Locate the factory class
###############################################################################

target="$(find "$tree" -path '*/X/00TJ.smali' -print -quit 2>/dev/null)"
[ -n "$target" ] || die "X/00TJ.smali not found under $tree.
The tab-list factory moved or was renamed - this Instagram version is not supported.
Re-run recon_navbar.sh to find the new location."

say "Tab factory: ${target#$tree/}"

###############################################################################
# Idempotency
###############################################################################

if grep -q 'HEALTHYIG-NAVBAR-PATCH' "$target"; then
    say "Already patched - nothing to do."
    exit 0
fi

###############################################################################
# Verify our assumptions before editing
###############################################################################
# Each of these is a thing the patch depends on. If any moved, the edit would
# either not apply or apply in the wrong place, so bail instead.

method_re='^\.method public final A04\(Lcom/instagram/common/session/UserSession;Z\)Ljava/util/List;'

grep -qE "$method_re" "$target" \
    || die "A04(UserSession, boolean) not found in ${target#$tree/} - obfuscated names have shifted."

body="$(awk "/$( printf '%s' "$method_re" | sed 's|/|\\/|g' )/,/^\.end method/" "$target")"

printf '%s' "$body" | grep -q 'LX/00TK;->A04(Lcom/instagram/common/session/UserSession;I)Ljava/lang/String;' \
    || die "The name-resolution call is missing from A04 - loop structure changed."
printf '%s' "$body" | grep -q ':cond_2' \
    || die "Loop label :cond_2 is missing from A04 - cannot place the skip branch."

# The name we match on must still exist in the id->name mapping, or we would
# emit a comparison that never fires and silently do nothing.
tk="$(find "$tree" -path '*/X/00TK.smali' -print -quit 2>/dev/null)"
[ -n "$tk" ] || die "X/00TK.smali not found - cannot confirm the tab name."
grep -q 'const-string/jumbo v3, "clips"' "$tk" \
    || die 'The "clips" tab name is not in X/00TK.smali - the identifier changed.'

say 'Verified: A04 loop, :cond_2 label, and the "clips" identifier all present.'

###############################################################################
# Apply
###############################################################################
# Inserted after the name lands in v0, before it is converted to a tab object:
#
#     const-string/jumbo v1, "clips"
#     invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
#     move-result v1
#     if-nez v1, :cond_2
#
# v1 is safe scratch: it is dead at this point (its next write is the
# move-result-object immediately below), and on the branch-taken path it is
# never read again before being reassigned next iteration. .locals stays 4.

tmp="$(mktemp)"

awk -v mre="$method_re" '
    { print }

    !inm && $0 ~ mre { inm = 1; next }

    inm && !done {
        if ($0 ~ /LX\/00TK;->A04\(Lcom\/instagram\/common\/session\/UserSession;I\)Ljava\/lang\/String;/) {
            armed = 1
            next
        }
        if (armed && $0 ~ /move-result-object v0/) {
            print ""
            print "    # HEALTHYIG-NAVBAR-PATCH: skip the Reels tab"
            print "    const-string/jumbo v1, \"clips\""
            print ""
            print "    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z"
            print ""
            print "    move-result v1"
            print ""
            print "    if-nez v1, :cond_2"
            print ""
            armed = 0
            done  = 1
            next
        }
    }

    inm && /^\.end method/ { inm = 0 }

    END { if (!done) exit 1 }
' "$target" > "$tmp"

if [ $? -ne 0 ] || ! grep -q 'HEALTHYIG-NAVBAR-PATCH' "$tmp"; then
    rm -f "$tmp"
    die "Insertion point not found inside A04 - nothing was modified."
fi

# Exactly one insertion, or something matched more than we intended.
count="$(grep -c 'HEALTHYIG-NAVBAR-PATCH' "$tmp")"
[ "$count" = "1" ] || { rm -f "$tmp"; die "Patch applied $count times, expected 1 - aborting."; }

mv "$tmp" "$target"

say "Patched - the Reels tab will not be built."
say "If the app crashes on launch, the smali edit is at fault: delete the tree and rebuild without --hide-reels-tab."
