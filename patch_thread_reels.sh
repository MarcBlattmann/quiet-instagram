#!/usr/bin/env bash
#
# Scroll through every reel a friend sent you, from inside the reel viewer.
#
#   bash patch_thread_reels.sh <decompiled-tree>
#
# Tapping a reel in a DM opens a viewer holding one item. Swiping up does
# nothing, so watching five reels from one person means backing out and tapping
# in five times. This turns that viewer into a playlist of the conversation.
#
# Verified against Instagram 430.0.0.53.80. Like patch_navbar.sh, and unlike
# script.sh, this edits bytecode and IS tied to one build's obfuscated names.
# It verifies everything it depends on and fails loudly rather than producing an
# apk that silently behaves as before.
#
# --- The first attempt, and why it was wrong --------------------------------
#
# Instagram ships LX/0aNS, a data source that pages a thread's reels through
# clips/direct_thread_clips/, and LX/015a selects it on the DIRECT branch when
# config.A2D (enableClipsDualPagination) is true. That flag is dead in the
# shipped build, so v1 of this patch forced it on. It changed nothing.
#
# That route needs the server to answer clips/direct_thread_clips/ for this
# account, and it needs the "dual pagination" machinery in LX/04UF to consult
# the secondary source at all - which it only does alongside a working primary
# source, and this build blanks the discovery endpoints the primary uses. Two
# unverifiable dependencies, both outside our control.
#
# --- What this does instead -------------------------------------------------
#
# Build the playlist on the client and hand it to the viewer as a plain list.
#
# LX/0aNJ is a data source Instagram already uses for DIRECT_CROSS_APP_SAVES and
# DIRECT_ICEBREAKER: give it a List of media ids and its first page is
# clips/items/?clips_media_ids=[...], an ordinary endpoint this build does not
# blank. Later pages delegate onward.
#
# So: an injected class (com/quietig/ThreadReels) walks the thread's own message
# store, collects the media id of every reel share in the conversation, and
# rotates it so the tapped reel is first. LX/015a's DIRECT branch then wraps
# that list in LX/0aNJ. Nothing depends on a server feature flag - if the list
# comes back null, the branch runs exactly as it did before.

set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] || { printf 'usage: bash patch_thread_reels.sh <decompiled-tree>\n' >&2; exit 2; }
[ -d "$tree" ] || { printf 'No such directory: %s\n' "$tree" >&2; exit 2; }

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper_src="$repo_dir/smali/ThreadReels.smali"

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

marker='QUIETIG-THREAD-REELS'

# A decompiled Instagram is ~180k files, and on phone storage a single 'find'
# over it costs minutes - this script needs a dozen lookups. Every class we want
# sits at a known path inside *some* smali_classesN directory, so glob the
# twenty top-level directories instead of walking the tree.
locate_one() {
    local m
    for m in "$tree"/smali*/"$1"; do
        [ -f "$m" ] && { printf '%s\n' "$m"; return 0; }
    done
    return 1
}

###############################################################################
# Locate everything
###############################################################################

picker="$(locate_one 'X/015a.smali')"
[ -n "$picker" ] || die "X/015a.smali not found under $tree.
The clips data-source picker moved - this Instagram version is not supported."

config="$(locate_one 'com/instagram/clips/intf/ClipsViewerConfig.smali')"
[ -n "$config" ] || die "ClipsViewerConfig.smali not found under $tree."

direct="$(locate_one 'com/instagram/clips/intf/ClipsViewerDirectData.smali')"
[ -n "$direct" ] || die "ClipsViewerDirectData.smali not found under $tree."

[ -f "$helper_src" ] || die "Missing $helper_src - the injected helper class is part of this repo."

# The helper must land in the same smali_classesN directory as its caller, so it
# compiles into the same dex.
dex_dir="$(dirname "$(dirname "$picker")")"
helper_dst="$dex_dir/com/quietig/ThreadReels.smali"

say "Data-source picker: ${picker#$tree/}"

###############################################################################
# Undo v1 of this patch if it is present
###############################################################################
# v1 forced ClipsViewerConfig.A2D on. That is now both unnecessary - the branch
# below returns before A2D is ever read - and unhelpful, because A2D also turns
# on dual-pagination merging in LX/04UF that would fight the playlist.

v1_tag='play the whole thread, not one reel'

if grep -qF "$v1_tag" "$config"; then
    say "Removing the superseded A2D edit from ${config#$tree/} ..."
    tmp="$(mktemp)"
    awk -v tag="$v1_tag" '
        index($0, tag) > 0 { skipping = 1; next }
        # The label on its own line ends the block. Matching the bare name would
        # also match the if-eqz that branches to it, and stop stripping early.
        skipping && $0 ~ /^[[:space:]]*:quietig_thread_reels_end[[:space:]]*$/ { skipping = 0; next }
        skipping { next }
        { print }
    ' "$config" > "$tmp"
    grep -qF "$v1_tag" "$tmp" && { rm -f "$tmp"; die "Failed to strip the old edit from ${config#$tree/}."; }
    grep -qF 'iput-boolean v0, p0, Lcom/instagram/clips/intf/ClipsViewerConfig;->A2D:Z' "$tmp" \
        || { rm -f "$tmp"; die "Stripping the old edit removed too much from ${config#$tree/}."; }
    mv "$tmp" "$config"
fi

# --- Undo the play-pile edit if a previous build applied it -----------------
# Setting ClipsViewerDirectData.A0B made the reply bar controller take its
# play-pile branch, which indexes a list (LX/0330->A0C) that is only filled when
# a thread lookup inside LX/0330->A01 succeeds. When it does not, reacting to a
# reel dereferences nothing and the app dies. The flag needs state this build
# never builds - do not set it.

if grep -qF ':quietig_play_pile_end' "$direct"; then
    say "Removing the play-pile edit from ${direct#$tree/} - it crashes on reactions ..."
    tmp="$(mktemp)"
    awk '
        index($0, "a DM viewer showing a playlist is a play pile") > 0 { skipping = 1; next }
        skipping && $0 ~ /^[[:space:]]*:quietig_play_pile_end[[:space:]]*$/ { skipping = 0; next }
        skipping { next }
        { print }
    ' "$direct" > "$tmp"
    grep -qF ':quietig_play_pile_end' "$tmp" \
        && { rm -f "$tmp"; die "Failed to strip the play-pile edit from ${direct#$tree/}."; }
    grep -qF 'iput-boolean p12, p0, Lcom/instagram/clips/intf/ClipsViewerDirectData;->A0B:Z' "$tmp" \
        || { rm -f "$tmp"; die "Stripping the play-pile edit removed too much."; }
    mv "$tmp" "$direct"
fi

# --- Undo the tail-load edit if a previous build applied it -----------------
# Setting ClipsViewerConfig.A2x (shouldForceDisableTailLoads) was meant to stop
# the viewer asking for a page that can never arrive. But A2x also short-circuits
# the block in LX/04UF that kicks the first load off, so the playlist never
# loaded and the viewer fell back to the single reel. The placeholder-hiding
# patch in patch_no_dead_scroll.sh covers the dead page on its own.

if grep -qF ':quietig_no_tail_end' "$config"; then
    say "Removing the tail-load edit from ${config#$tree/} - it stopped the playlist loading ..."
    tmp="$(mktemp)"
    awk '
        index($0, "a DM playlist is complete - do not tail-load past it") > 0 { skipping = 1; next }
        skipping && $0 ~ /^[[:space:]]*:quietig_no_tail_end[[:space:]]*$/ { skipping = 0; next }
        skipping { next }
        { print }
    ' "$config" > "$tmp"
    grep -qF ':quietig_no_tail_end' "$tmp" \
        && { rm -f "$tmp"; die "Failed to strip the tail-load edit from ${config#$tree/}."; }
    grep -qF 'iput-boolean v0, p0, Lcom/instagram/clips/intf/ClipsViewerConfig;->A2x:Z' "$tmp" \
        || { rm -f "$tmp"; die "Stripping the tail-load edit removed too much."; }
    mv "$tmp" "$config"
fi

###############################################################################
# Idempotency
###############################################################################

if grep -q "$marker" "$picker" && [ -f "$helper_dst" ] \
   && cmp -s "$helper_src" "$helper_dst"; then
    say "Already patched - nothing to do."
    exit 0
fi

###############################################################################
# Verify every assumption before editing
###############################################################################
# All matches are literal (-F). Smali is full of ( ) . / $ ; and treating any of
# it as a regex is how a "verified" patch quietly checks nothing.

# 1. The list-backed data source, and its endpoint.
src_cls="$(locate_one 'X/0aNJ.smali')"
[ -n "$src_cls" ] || die "X/0aNJ.smali not found - the list-backed clips data source is gone from this build."
grep -qF '.method public constructor <init>(LX/0lhp;Ljava/util/List;)V' "$src_cls" \
    || die "LX/0aNJ no longer takes (LX/0lhp;, List) - its shape changed."

api="$(locate_one 'com/instagram/clips/api/ClipsApiUtilHelper.smali')"
[ -n "$api" ] || die "ClipsApiUtilHelper.smali not found."
grep -qF '"clips/items/"' "$api" \
    || die 'clips/items/ is missing from ClipsApiUtilHelper - the endpoint that hydrates a media id list is gone.
If script.sh blanked it, uncomment nothing and check the Reels section there.'

say "Confirmed: LX/0aNJ still loads a media id list from clips/items/."

# 2. The insertion point, and the registers we borrow there.
grep -qF ':pswitch_30' "$picker" \
    || die "The DIRECT branch label :pswitch_30 is missing from X/015a.smali."
grep -qF 'goto/16 :goto_1' "$picker" \
    || die "The shared 'return this data source' exit (:goto_1) is missing from X/015a.smali."
grep -qF 'invoke-virtual/range {v18 .. v18}, LX/03As;->getValue()Ljava/lang/Object;' "$picker" \
    || die "v18 is no longer the lazy default data source in X/015a.smali - cannot build a fallback source."
grep -qF 'move-object/from16 v14, p4' "$picker" \
    || die "v14 is no longer the UserSession in X/015a->A00 - argument order changed."
grep -qF 'move-object/from16 v15, p2' "$picker" \
    || die "v15 is no longer the ClipsViewerConfig in X/015a->A00 - argument order changed."

say "Confirmed: v14=UserSession, v15=ClipsViewerConfig, v18=default source."

# 3. Everything the injected helper reaches for. If any of these moved, the
#    helper would compile and then throw at runtime - and while it catches
#    Throwable and degrades to the old behaviour, that would be a silent no-op.
check_member() {
    local rel="$1" needle="$2" what="$3" f
    f="$(locate_one "$rel")"
    [ -n "$f" ] || die "$what: ${rel##*/} not found under $tree."
    grep -qF "$needle" "$f" || die "$what: '$needle' missing from ${f#$tree/}."
}

check_member 'X/07zc.smali' \
    '.method public static final A00(Lcom/instagram/common/session/UserSession;)LX/07ze;' \
    'thread store accessor'
check_member 'X/07ze.smali' \
    '.method public abstract Cne(Lcom/instagram/model/direct/DirectThreadKey;)Ljava/util/List;' \
    'thread message list'
check_member 'com/instagram/model/direct/DirectThreadKey.smali' \
    '.method public constructor <init>(Ljava/lang/String;)V' \
    'thread key from a thread id'
check_member 'X/01lF.smali' \
    '.method public final A0K()Lcom/google/common/collect/ImmutableList;' \
    'message media list'
check_member 'X/02Rf.smali' '.field public A0V:LX/08au;'          'message type field'
check_member 'X/08au.smali' '.field public static final enum A0W:LX/08au;' 'clip share message type'
check_member 'X/08au.smali' '.field public static final enum A22:LX/08au;' 'clip share message type'
check_member 'X/01oT.smali' '.field public A1F:Ljava/lang/String;'  'shared media url'
check_member 'com/instagram/clips/intf/ClipsViewerDirectData.smali' \
    '.field public final A03:Ljava/lang/String;' 'thread id on the viewer config'

grep -qF '.field public final A1o:Ljava/lang/String;' "$config" \
    || die "ClipsViewerConfig.A1o (sourceMediaId) is gone - cannot tell which reel was tapped."
grep -qF '.field public final A0S:Lcom/instagram/clips/intf/ClipsViewerDirectData;' "$config" \
    || die "ClipsViewerConfig.A0S (directData) is gone."

say "Confirmed: every member the injected helper calls is still present."


###############################################################################
# Apply
###############################################################################

mkdir -p "$(dirname "$helper_dst")"
cp "$helper_src" "$helper_dst"
say "Installed ${helper_dst#$tree/}"

say "Patched. Reels opened from a DM now play through the conversation."
say "If reels from DMs stop opening at all, rebuild with --no-thread-reels."
