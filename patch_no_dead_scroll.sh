#!/usr/bin/env bash
#
# Stop the reel viewer scrolling onto a page that will never load.
#
#   bash patch_no_dead_scroll.sh <decompiled-tree>
#
# script.sh blanks the discovery endpoints, so when the viewer asks for more
# reels nothing arrives. The viewer does not know that: it has already put a
# placeholder page on the end of the list, so you can swipe onto a black screen
# that spins forever. This makes the pager stop at the last real reel instead.
#
# Verified against Instagram 430.0.0.53.80. Bytecode edit, tied to one build's
# obfuscated names; verifies before touching anything.
#
# --- What the placeholder is ------------------------------------------------
#
# LX/05DB (ClipsViewerAdapter, per its retained redex name) appends an item
# built by LX/06o5->A00() whenever it thinks more is coming. That item's type is
# LX/04LC->A0I, whose enum name is literally GHOST; A0H is DISMISSIBLE_GHOST.
# Those are the extra pages.
#
# --- Where this patches, and why there ---------------------------------------
#
# LX/02QJ is the ViewPager2 adapter (LX/00IQ->A0V, handed to the pager by
# LX/05DB->A09). Its getItemCount() - a name that survived obfuscation - returns
# the item list size. Trailing ghosts are inside that count, and a ViewPager2
# cannot scroll past getItemCount().
#
# Patching the count rather than the insertion means:
#   - real items keep their indices, so nothing else has to change;
#   - the ghost still exists for any code that looks for it;
#   - and when a page genuinely does arrive, the list grows and the pager
#     grows with it, so ordinary pagination is untouched.
#
# The last point is the one that matters: loading the next page is driven by
# LX/04UF through LX/06DU on page change, not by the ghost scrolling into view.
# Hiding the ghost therefore removes the dead page without removing paging.

set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] || { printf 'usage: bash patch_no_dead_scroll.sh <decompiled-tree>\n' >&2; exit 2; }
[ -d "$tree" ] || { printf 'No such directory: %s\n' "$tree" >&2; exit 2; }

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

marker='QUIETIG-NO-DEAD-SCROLL'

# A decompiled Instagram is ~180k files, and on phone storage a single 'find'
# over it costs minutes. Every class we want sits at a known path inside *some*
# smali_classesN directory, so glob those rather than walking the tree.
locate_one() {
    local m
    for m in "$tree"/smali*/"$1"; do
        [ -f "$m" ] && { printf '%s\n' "$m"; return 0; }
    done
    return 1
}

###############################################################################
# Locate
###############################################################################

adapter="$(locate_one 'X/02QJ.smali')"
[ -n "$adapter" ] || die "X/02QJ.smali not found under $tree.
The clips pager adapter moved - this Instagram version is not supported."

say "Pager adapter: ${adapter#$tree/}"

if grep -q "$marker" "$adapter"; then
    say "Already patched - nothing to do."
    exit 0
fi

###############################################################################
# Verify
###############################################################################

grep -qF '.method public final getItemCount()I' "$adapter" \
    || die "getItemCount() is missing from ${adapter#$tree/} - it was obfuscated away."

grep -qF '.locals 4' "$adapter" \
    || die "Unexpected register declarations in ${adapter#$tree/}."

anchor_a='    invoke-interface {v0}, Ljava/util/List;->size()I'
anchor_b='    move-result v1'
anchor_c='    iget-boolean v0, v2, LX/00IQ;->A0t:Z'

body="$(awk '
    index($0, ".method public final getItemCount()I") == 1 { inm = 1 }
    inm { print }
    inm && index($0, ".end method") == 1 { exit }
' "$adapter")"

[ -n "$body" ] || die "Could not extract getItemCount() from ${adapter#$tree/}."

printf '%s' "$body" | grep -qF 'LX/00IQ;->A0l:Ljava/util/List;' \
    || die "getItemCount() no longer reads the item list (LX/00IQ->A0l) - it was restructured."
printf '%s' "$body" | grep -qF "$anchor_c" \
    || die "getItemCount() no longer reads LX/00IQ->A0t - it was restructured."
printf '%s' "$body" | grep -qF '.locals 4' \
    || die "getItemCount() no longer declares .locals 4 - refusing to guess which registers are free."

# The ghost item type, and the item class carrying it.
item="$(locate_one 'X/015h.smali')"
[ -n "$item" ] || die "X/015h.smali (the clips viewer item) not found."
grep -qF '.field public final A0R:LX/04LC;' "$item" \
    || die "LX/015h->A0R:LX/04LC; is gone - cannot tell a ghost item from a real one."

kind="$(locate_one 'X/04LC.smali')"
[ -n "$kind" ] || die "X/04LC.smali (the item type enum) not found."
grep -qF '"GHOST"' "$kind" \
    || die 'The GHOST item type is missing from X/04LC.smali - placeholder pages work differently now.'
grep -qF '.field public static final enum A0I:LX/04LC;' "$kind" \
    || die "LX/04LC->A0I is gone - the ghost constant moved."
grep -qF '.field public static final enum A0H:LX/04LC;' "$kind" \
    || die "LX/04LC->A0H is gone - the dismissible-ghost constant moved."

say "Confirmed: GHOST placeholder pages are still counted by getItemCount()."

###############################################################################
# Apply
###############################################################################
# Inserted between the size() result and the existing A0t check:
#
#     :trim  if size <= 0 -> done
#            last = list.get(size - 1)
#            if !(last instanceof LX/015h) -> done
#            if last.A0R != GHOST && != DISMISSIBLE_GHOST -> done
#            size--                       and go round again
#
# .locals goes 4 -> 6 to get two scratch registers. v0..v3 all carry live values
# at this point (v1 the running count, v2 the holder, v3 the trace token), and
# raising .locals only renumbers the parameter registers, which smali does for
# us. The loop handles a run of several placeholders, not just one.

tmp="$(mktemp)"

awk -v marker="$marker" -v a="$anchor_a" -v b="$anchor_b" -v c="$anchor_c" '
    index($0, ".method public final getItemCount()I") == 1 { inm = 1; print; next }

    inm && !bumped && $0 == "    .locals 4" {
        print "    .locals 6"
        bumped = 1
        next
    }

    inm && !done && $0 == a { seen_size = 1; print; next }
    inm && seen_size && $0 == b { seen_res = 1; print; next }

    inm && seen_res && !done && $0 == c {
        print "    # " marker ": placeholder pages are not scrollable"
        print "    :quietig_trim"
        print ""
        print "    if-lez v1, :quietig_trimmed"
        print ""
        print "    iget-object v4, v2, LX/00IQ;->A0l:Ljava/util/List;"
        print ""
        print "    add-int/lit8 v5, v1, -0x1"
        print ""
        print "    invoke-interface {v4, v5}, Ljava/util/List;->get(I)Ljava/lang/Object;"
        print ""
        print "    move-result-object v4"
        print ""
        print "    instance-of v5, v4, LX/015h;"
        print ""
        print "    if-eqz v5, :quietig_trimmed"
        print ""
        print "    check-cast v4, LX/015h;"
        print ""
        print "    iget-object v4, v4, LX/015h;->A0R:LX/04LC;"
        print ""
        print "    sget-object v5, LX/04LC;->A0I:LX/04LC;"
        print ""
        print "    if-eq v4, v5, :quietig_drop"
        print ""
        print "    sget-object v5, LX/04LC;->A0H:LX/04LC;"
        print ""
        print "    if-ne v4, v5, :quietig_trimmed"
        print ""
        print "    :quietig_drop"
        print "    add-int/lit8 v1, v1, -0x1"
        print ""
        print "    goto :quietig_trim"
        print ""
        print "    :quietig_trimmed"
        print $0
        done = 1
        next
    }

    { print }

    inm && index($0, ".end method") == 1 { inm = 0 }

    END { exit !(done && bumped) }
' "$adapter" > "$tmp"

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    rm -f "$tmp"
    die "Could not place the edit inside getItemCount() - nothing was modified."
fi

hits="$(grep -cF "$marker" "$tmp")"
[ "$hits" = "1" ] || { rm -f "$tmp"; die "Patch applied $hits times, expected 1 - aborting."; }

mv "$tmp" "$adapter"

say "Patched. The viewer stops at the last real reel instead of a dead page."
say "If reels stop paging anywhere in the app, rebuild with --no-dead-scroll-fix."
