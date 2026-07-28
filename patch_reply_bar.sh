#!/usr/bin/env bash
#
# Keep the reply bar on the reel you are actually watching.
#
#   bash patch_reply_bar.sh <decompiled-tree>
#
# Depends on patch_thread_reels.sh having installed com/quietig/ThreadReels.
# Verified against Instagram 430.0.0.53.80.
#
# --- The behaviour ----------------------------------------------------------
#
# Open a reel from a DM and the bar is there. Scroll to the next one and it is
# gone. That is deliberate in stock Instagram: the bar belongs to the message
# you tapped, and when the viewer only ever held that one reel there was no
# other page for it to belong to.
#
# --- Where it happens -------------------------------------------------------
#
# LX/0330 is the reply bar controller. LX/05WZ stubs out every method of the
# page-lifecycle interface LX/0Jek except FK7(II), so FK7 is the page-change
# hook, and it calls LX/0330->A0B(position).
#
# A0B is where the bar is set up, and three times over it does:
#
#     if-nez p1, :cond_13      ->  LX/05WZ->A0T()      (hide)
#     ...                          LX/05WZ->A0U()      (show)
#
# p1 is the page index. Position 0 shows the bar; anything else hides it.
#
# A0B has two halves, chosen by LX/0330->A0q, which the constructor computes as
# (source != BLEND) && !replyBarData.A0E && LX/09El->A00(session) - the last a
# server flag. The A0q half drives visibility from a per-position reshare store
# instead. That half cannot be the live one here: it feeds off LX/0330->A01(),
# which returns an empty list unless LX/0330->A0W is set, and A0W is only
# assigned on the play-pile path. With an empty store the bar would be hidden on
# page 0 too, and it is not. So A0q is false and the `if-nez p1` gates are what
# is hiding the bar.
#
# --- Why the send path matters too ------------------------------------------
#
# Making the bar merely visible would be worse than leaving it hidden. With A0q
# false, LX/0330->A0K - the DIRECT send path - takes its target from
# replyBarData.A07 (the tapped message's id) and .A05 (its client context), both
# fixed at launch. The bar would appear on every reel and quietly react to the
# first one.
#
# A07 is the id LX/07ze->CNI looks a message up by: CNI delegates to
# LX/01rO->A0I, which probes on LX/02Rf->A0y, which is what LX/01lF->A0o()
# returns. So the fix is to resolve the message for the reel on screen and use
# its A0y and A0s.
#
# --- The patch --------------------------------------------------------------
#
# com/quietig/ThreadReels->A01 walks the thread for the message whose shared
# media id matches the media the viewer is currently showing.
#
#   1. In A0B, the two `if-nez p1` gates that hide the bar only apply when that
#      lookup fails. Reels we can place in the conversation keep the bar.
#   2. In A0K, the target message id and client context come from that message,
#      falling back to the stock fields when the lookup fails.
#
# Both changes are inert when the lookup returns null, which is also what makes
# them safe: a reel we cannot identify gets stock behaviour - no bar - rather
# than a bar wired to the wrong reel.

set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] || { printf 'usage: bash patch_reply_bar.sh <decompiled-tree>\n' >&2; exit 2; }
[ -d "$tree" ] || { printf 'No such directory: %s\n' "$tree" >&2; exit 2; }

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

marker='QUIETIG-REPLY-BAR'

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

bar="$(locate_one 'X/0330.smali')"
[ -n "$bar" ] || die "X/0330.smali not found under $tree.
The reply bar controller moved - this Instagram version is not supported."

say "Reply bar controller: ${bar#$tree/}"

if grep -q "$marker" "$bar"; then
    say "Already patched - nothing to do."
    exit 0
fi

###############################################################################
# Verify
###############################################################################

helper="$(locate_one 'com/quietig/ThreadReels.smali')"
[ -n "$helper" ] || die "com/quietig/ThreadReels is not installed.
Run patch_thread_reels.sh first - this patch calls into it."
grep -qF '.method public static A01(LX/0330;)LX/01lF;' "$helper" \
    || die "ThreadReels->A01(LX/0330;) is missing - the helper is out of date."

grep -qF '.method private final A0B(I)V' "$bar" \
    || die "LX/0330->A0B(I)V not found - the per-page update method moved."
grep -qF '.method public static final A0K(LX/0330;Ljava/lang/String;)V' "$bar" \
    || die "LX/0330->A0K not found - the DIRECT send path moved."
grep -qF '.method public final FK7(II)V' "$bar" \
    || die "LX/0330->FK7(II)V not found - the page-change hook moved."

# The two gates, and the fact that they lead to the hide call.
gate1='    if-nez p1, :cond_13'
gate2='    if-nez p1, :cond_14'
[ "$(grep -cF "$gate1" "$bar")" = "1" ] \
    || die "Expected exactly one '$gate1' in ${bar#$tree/}."
[ "$(grep -cF "$gate2" "$bar")" = "1" ] \
    || die "Expected exactly one '$gate2' in ${bar#$tree/}."
grep -qF 'invoke-virtual {p0}, LX/05WZ;->A0T()V' "$bar" \
    || die "The hide call LX/05WZ->A0T() is gone - A0B was restructured."
grep -qF 'invoke-virtual {p0}, LX/05WZ;->A0U()V' "$bar" \
    || die "The show call LX/05WZ->A0U() is gone - A0B was restructured."

# The send path's stock target fields. A07 is read in two places; the copy this
# patch rewrites is the one inside A0K just after :cond_5, which the awk below
# is scoped to - so check that shape rather than a global count.
send_block='    iget-object v5, v0, Lcom/instagram/clips/model/ClipsReplyBarData;->A07:Ljava/lang/String;'
grep -qF "$send_block" "$bar" \
    || die "The send path no longer reads ClipsReplyBarData->A07 - it was restructured."
awk '
    index($0, ".method public static final A0K(LX/0330;Ljava/lang/String;)V") == 1 { m = 1 }
    m && $0 == "    :cond_5" { c = 1; next }
    m && c { print; exit }
' "$bar" | grep -qF 'LX/0330;->A0Z:Lcom/instagram/clips/model/ClipsReplyBarData;' \
    || die "A0K's :cond_5 no longer begins by reading A0Z - the send path changed."
grep -qF '    iget-object v4, v0, Lcom/instagram/clips/model/ClipsReplyBarData;->A05:Ljava/lang/String;' "$bar" \
    || die "The send path no longer reads ClipsReplyBarData->A05."

# The fields the helper reads off the controller and the message.
grep -qF '.field public final A0a:Lcom/instagram/common/session/UserSession;' "$bar" \
    || die "LX/0330->A0a (the session) moved."
grep -qF '.field public final A0Z:Lcom/instagram/clips/model/ClipsReplyBarData;' "$bar" \
    || die "LX/0330->A0Z (the reply bar data) moved."
grep -qF '.method public static final A02(LX/0330;)LX/015h;' "$bar" \
    || die "LX/0330->A02 (current item lookup) moved - cannot tell which reel is on screen."

msg="$(locate_one 'X/02Rf.smali')"
[ -n "$msg" ] || die "X/02Rf.smali (the direct message base class) not found."
grep -qF '.field public A0y:Ljava/lang/String;' "$msg" \
    || die "LX/02Rf->A0y (message id) moved."
grep -qF '.field public A0s:Ljava/lang/String;' "$msg" \
    || die "LX/02Rf->A0s (client context) moved."

say "Confirmed: the position gates, the send path, and every field they use."

###############################################################################
# Apply
###############################################################################
# v6 is the scratch register in A0B. Its first write in that method is well
# below both gates and every read follows a write, so borrowing it here is safe.
# .locals stays 9.

tmp="$(mktemp)"

awk -v marker="$marker" -v g1="$gate1" -v g2="$gate2" '
    function keepbar(label, tag) {
        print "    # " marker ": keep the bar for a reel we can place in the thread"
        print "    invoke-static {p0}, Lcom/quietig/ThreadReels;->A01(LX/0330;)LX/01lF;"
        print ""
        print "    move-result-object v6"
        print ""
        print "    if-nez v6, :quietig_bar_" tag
        print ""
        print "    if-nez p1, " label
        print ""
        print "    :quietig_bar_" tag
    }

    !did1 && $0 == g1 { keepbar(":cond_13", "1"); did1 = 1; next }
    !did2 && $0 == g2 { keepbar(":cond_14", "2"); did2 = 1; next }

    # The DIRECT send path: aim at the reel on screen, not the one that opened
    # the viewer. Falls through to the stock fields when the lookup fails.
    !did3 && $0 == "    iget-object v0, v7, LX/0330;->A0Z:Lcom/instagram/clips/model/ClipsReplyBarData;" && seen_cond5 {
        print "    # " marker ": react to the reel on screen"
        print "    invoke-static {v7}, Lcom/quietig/ThreadReels;->A01(LX/0330;)LX/01lF;"
        print ""
        print "    move-result-object v0"
        print ""
        print "    if-eqz v0, :quietig_send_stock"
        print ""
        print "    iget-object v5, v0, LX/02Rf;->A0y:Ljava/lang/String;"
        print ""
        print "    iget-object v4, v0, LX/02Rf;->A0s:Ljava/lang/String;"
        print ""
        print "    if-eqz v5, :quietig_send_stock"
        print ""
        print "    if-nez v4, :quietig_send_ready"
        print ""
        print "    :quietig_send_stock"
        print $0
        print ""
        print "    iget-object v5, v0, Lcom/instagram/clips/model/ClipsReplyBarData;->A07:Ljava/lang/String;"
        print ""
        print "    iget-object v4, v0, Lcom/instagram/clips/model/ClipsReplyBarData;->A05:Ljava/lang/String;"
        print ""
        print "    :quietig_send_ready"
        did3 = 1
        skip_next_two = 1
        next
    }

    # Drop the two stock reads that used to follow, now emitted above.
    skip_next_two && $0 ~ /ClipsReplyBarData;->A07:Ljava\/lang\/String;$/ { next }
    skip_next_two && $0 ~ /ClipsReplyBarData;->A05:Ljava\/lang\/String;$/ { skip_next_two = 0; next }

    { print }

    # :cond_5 inside A0K is the branch taken when A0q is false.
    index($0, ".method public static final A0K(LX/0330;Ljava/lang/String;)V") == 1 { in_a0k = 1 }
    in_a0k && $0 == "    :cond_5" { seen_cond5 = 1 }
    in_a0k && index($0, ".end method") == 1 { in_a0k = 0 }

    END { exit !(did1 && did2 && did3) }
' "$bar" > "$tmp"

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    rm -f "$tmp"
    die "Could not place all three edits in ${bar#$tree/} - nothing was modified."
fi

hits="$(grep -cF "$marker" "$tmp")"
[ "$hits" = "3" ] || { rm -f "$tmp"; die "Applied $hits edits, expected 3 - aborting."; }

# The stock reads must survive exactly once each, on the fallback path.
for f in A07 A05; do
    n="$(grep -cF "ClipsReplyBarData;->$f:Ljava/lang/String;" "$tmp")"
    [ "$n" -ge 1 ] || { rm -f "$tmp"; die "The stock $f fallback was lost - aborting."; }
done

mv "$tmp" "$bar"

###############################################################################
# The emoji reactions take a different route
###############################################################################
# Typing into the composer goes through A0K, patched above. Tapping one of the
# quick emoji goes through LX/0330->A0W and out via LX/04t3->GIv, and there the
# reel is identified three times over by an LX/0E9k pulled from
# LX/0330->A03 - the reshare-store entry, which still describes the reel the
# viewer was opened on. Two edits, same helper:
#
#   * the LX/07ze->CNI lookup that produces the replied-to descriptor
#     (LX/01FH, via LX/05Kd->A00) takes our message when we have one;
#   * the message id and client context handed to GIv come from that message.
#
# 0E9k->A00 is the message id and ->A03 the client context: A0K's other branch
# reads exactly those two into the same slots that hold ClipsReplyBarData's A07
# and A05. v3 holds the controller for the whole of A0W (its only write is the
# move-object from p0 at the top), and v6/v7 are being reassigned here anyway.

grep -qF '    invoke-static {v6}, LX/05Kd;->A00(LX/01lF;)LX/01FH;' "$bar" \
    || die "The reaction path no longer builds LX/01FH from a message - it was restructured."
grep -qF 'LX/04t3;->GIv(' "$bar" \
    || die "The reaction send LX/04t3->GIv is gone - the emoji path changed."

tmp="$(mktemp)"

awk -v marker="$marker" '
    index($0, ".method public final A0W(Ljava/lang/String;Ljava/lang/String;)V") == 1 { in_a0w = 1 }

    # 1. Prefer our message when building the replied-to descriptor.
    in_a0w && $0 == "    :cond_19" { at19 = 1; print; next }
    in_a0w && at19 && $0 == "    if-eqz v8, :cond_1a" {
        print
        print ""
        print "    # " marker ": react to the reel on screen"
        print "    invoke-static {v3}, Lcom/quietig/ThreadReels;->A01(LX/0330;)LX/01lF;"
        print ""
        print "    move-result-object v6"
        print ""
        print "    if-nez v6, :quietig_react_msg"
        at19 = 0
        want_label = 1
        next
    }
    in_a0w && want_label && $0 == "    if-eqz v6, :cond_1a" {
        print "    :quietig_react_msg"
        print $0
        want_label = 0
        did1 = 1
        next
    }

    # 2. The two ids handed to GIv, after :goto_8.
    in_a0w && $0 == "    :goto_8" { seen8 = 1; print; next }
    in_a0w && seen8 && !did2 && $0 == "    iget-object v7, v9, LX/0E9k;->A00:Ljava/lang/String;" {
        print "    # " marker ": aim the reaction at that reel"
        print "    invoke-static {v3}, Lcom/quietig/ThreadReels;->A01(LX/0330;)LX/01lF;"
        print ""
        print "    move-result-object v7"
        print ""
        print "    if-eqz v7, :quietig_react_stock"
        print ""
        print "    iget-object v6, v7, LX/02Rf;->A0s:Ljava/lang/String;"
        print ""
        print "    iget-object v7, v7, LX/02Rf;->A0y:Ljava/lang/String;"
        print ""
        print "    if-eqz v7, :quietig_react_stock"
        print ""
        print "    if-nez v6, :quietig_react_ready"
        print ""
        print "    :quietig_react_stock"
        print $0
        did2 = 1
        drop_a03 = 1
        next
    }
    in_a0w && drop_a03 && $0 == "    iget-object v6, v9, LX/0E9k;->A03:Ljava/lang/String;" {
        print $0
        print ""
        print "    :quietig_react_ready"
        drop_a03 = 0
        next
    }

    { print }

    in_a0w && index($0, ".end method") == 1 { in_a0w = 0 }

    END { exit !(did1 && did2) }
' "$bar" > "$tmp"

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    rm -f "$tmp"
    die "Could not place the emoji-reaction edits in ${bar#$tree/}."
fi

hits="$(grep -cF "$marker" "$tmp")"
[ "$hits" = "5" ] || { rm -f "$tmp"; die "Applied $hits edits in total, expected 5 - aborting."; }

mv "$tmp" "$bar"

say "Patched. The reply bar follows the reel you are watching, and reacts to it."
say "If reacting misfires or the bar misbehaves, rebuild with --no-reply-bar-fix."
