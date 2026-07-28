.class public final Lcom/quietig/ThreadReels;
.super Ljava/lang/Object;
.source "ThreadReels.smali"


# Collects the reels shared in one DM conversation, so the clips viewer can be
# handed a real playlist instead of the single reel that was tapped.
#
# Injected by patch_thread_reels.sh - not part of Instagram.
#
# Called from LX/015a->A00, the function that picks a clips data source, on the
# DIRECT branch. Returning null there means "do what you did before", so every
# failure path here is a no-op rather than a crash. The whole body is wrapped in
# a catch-all for the same reason: Uri.getQueryParameter throws on opaque URIs,
# and a thread store can be in any state at all.
#
# The list is rotated so the tapped reel is first, because the viewer opens on
# index 0. Each reel then appears exactly once and the list ends - it does not
# wrap back to the beginning.
#
# On filtering by watched state: an earlier version called LX/07zq->DS9
# (getUnwatchedClipsFromThread) instead of walking the thread, to show each reel
# only once ever. That is a real filter and it works - which is the problem.
# Once you have watched a conversation's reels, DS9 returns nothing, the list
# falls below two entries, and the playlist silently disappears. Scrolling
# through a friend's reels matters more than hiding ones already seen, so the
# walk takes everything and relies on the rotation for "once each".
#
# Capped at 30: the ids go into a single clips/items/ request.


# direct methods
.method public static A00(Lcom/instagram/common/session/UserSession;Lcom/instagram/clips/intf/ClipsViewerConfig;)Ljava/util/List;
    .locals 12

    const/4 v11, 0x0

    :try_start_0
    if-eqz p0, :cond_fail

    if-eqz p1, :cond_fail

    iget-object v0, p1, Lcom/instagram/clips/intf/ClipsViewerConfig;->A0S:Lcom/instagram/clips/intf/ClipsViewerDirectData;

    if-eqz v0, :cond_fail

    iget-object v1, v0, Lcom/instagram/clips/intf/ClipsViewerDirectData;->A03:Ljava/lang/String;

    if-eqz v1, :cond_fail

    iget-object v10, p1, Lcom/instagram/clips/intf/ClipsViewerConfig;->A1o:Ljava/lang/String;

    invoke-static {p0}, LX/07zc;->A00(Lcom/instagram/common/session/UserSession;)LX/07ze;

    move-result-object v0

    if-eqz v0, :cond_fail

    new-instance v2, Lcom/instagram/model/direct/DirectThreadKey;

    invoke-direct {v2, v1}, Lcom/instagram/model/direct/DirectThreadKey;-><init>(Ljava/lang/String;)V

    invoke-interface {v0, v2}, LX/07ze;->Cne(Lcom/instagram/model/direct/DirectThreadKey;)Ljava/util/List;

    move-result-object v0

    if-eqz v0, :cond_fail

    new-instance v9, Ljava/util/ArrayList;

    invoke-direct {v9}, Ljava/util/ArrayList;-><init>()V

    new-instance v8, Ljava/util/HashSet;

    invoke-direct {v8}, Ljava/util/HashSet;-><init>()V

    invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v7

    :goto_scan
    invoke-interface {v7}, Ljava/util/Iterator;->hasNext()Z

    move-result v0

    if-eqz v0, :cond_scanned

    invoke-interface {v7}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v0

    instance-of v1, v0, LX/01lF;

    if-eqz v1, :goto_scan

    check-cast v0, LX/01lF;

    iget-object v1, v0, LX/02Rf;->A0V:LX/08au;

    sget-object v2, LX/08au;->A0W:LX/08au;

    if-eq v1, v2, :cond_is_clip

    sget-object v2, LX/08au;->A22:LX/08au;

    if-ne v1, v2, :goto_scan

    :cond_is_clip
    invoke-virtual {v0}, LX/01lF;->A0K()Lcom/google/common/collect/ImmutableList;

    move-result-object v0

    if-eqz v0, :goto_scan

    invoke-interface {v0}, Ljava/util/List;->isEmpty()Z

    move-result v1

    if-nez v1, :goto_scan

    const/4 v1, 0x0

    invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;

    move-result-object v0

    if-eqz v0, :goto_scan

    check-cast v0, LX/01oT;

    iget-object v0, v0, LX/01oT;->A1F:Ljava/lang/String;

    if-eqz v0, :goto_scan

    invoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v0

    if-eqz v0, :goto_scan

    const-string v1, "id"

    invoke-virtual {v0, v1}, Landroid/net/Uri;->getQueryParameter(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :goto_scan

    invoke-virtual {v8, v0}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :goto_scan

    invoke-virtual {v9, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    invoke-virtual {v9}, Ljava/util/ArrayList;->size()I

    move-result v0

    const/16 v1, 0x1e

    if-lt v0, v1, :goto_scan

    :cond_scanned
    if-eqz v10, :cond_sized

    invoke-virtual {v9, v10}, Ljava/util/ArrayList;->indexOf(Ljava/lang/Object;)I

    move-result v0

    if-gez v0, :cond_seed_found

    const/4 v0, 0x0

    invoke-virtual {v9, v0, v10}, Ljava/util/ArrayList;->add(ILjava/lang/Object;)V

    goto :cond_sized

    :cond_seed_found
    if-lez v0, :cond_sized

    neg-int v0, v0

    invoke-static {v9, v0}, Ljava/util/Collections;->rotate(Ljava/util/List;I)V

    :cond_sized
    invoke-virtual {v9}, Ljava/util/ArrayList;->size()I

    move-result v0

    const/4 v1, 0x2

    if-lt v0, v1, :cond_fail

    return-object v9

    :cond_fail
    return-object v11
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    move-exception v0

    const/4 v0, 0x0

    return-object v0
.end method

# Finds the DM message that carries the reel currently on screen.
#
# The reply bar is built once, from the message that was tapped, and Instagram
# hides it on every other page rather than re-point it (LX/0330->A0B bails out
# with `if-nez p1`). Both the "is it visible" test and the "what am I replying
# to" lookup in LX/0330->A0K go through the message, so resolving the message
# for the current page fixes both at once.
#
# Returns null when the reel on screen cannot be matched to a message in the
# thread - the caller then behaves exactly as stock. That matters: it is the
# reason the bar is not shown for a reel we cannot identify, instead of being
# shown and quietly reacting to the wrong one.
.method public static A01(LX/0330;)LX/01lF;
    .locals 9

    const/4 v8, 0x0

    :try_start_0
    if-eqz p0, :cond_fail

    iget-object v0, p0, LX/0330;->A0a:Lcom/instagram/common/session/UserSession;

    if-eqz v0, :cond_fail

    iget-object v1, p0, LX/0330;->A0Z:Lcom/instagram/clips/model/ClipsReplyBarData;

    if-eqz v1, :cond_fail

    iget-object v1, v1, Lcom/instagram/clips/model/ClipsReplyBarData;->A03:Lcom/instagram/model/direct/DirectThreadKey;

    if-eqz v1, :cond_fail

    invoke-static {p0}, LX/0330;->A02(LX/0330;)LX/015h;

    move-result-object v2

    if-eqz v2, :cond_fail

    iget-object v2, v2, LX/015h;->A0T:Lcom/instagram/feed/media/Media;

    if-eqz v2, :cond_fail

    invoke-virtual {v2}, Lcom/instagram/feed/media/Media;->getId()Ljava/lang/String;

    move-result-object v7

    if-eqz v7, :cond_fail

    invoke-static {v0}, LX/07zc;->A00(Lcom/instagram/common/session/UserSession;)LX/07ze;

    move-result-object v0

    if-eqz v0, :cond_fail

    invoke-interface {v0, v1}, LX/07ze;->Cne(Lcom/instagram/model/direct/DirectThreadKey;)Ljava/util/List;

    move-result-object v0

    if-eqz v0, :cond_fail

    invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v6

    :goto_scan
    invoke-interface {v6}, Ljava/util/Iterator;->hasNext()Z

    move-result v0

    if-eqz v0, :cond_fail

    invoke-interface {v6}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v5

    instance-of v0, v5, LX/01lF;

    if-eqz v0, :goto_scan

    check-cast v5, LX/01lF;

    iget-object v1, v5, LX/02Rf;->A0V:LX/08au;

    sget-object v2, LX/08au;->A0W:LX/08au;

    if-eq v1, v2, :cond_is_clip

    sget-object v2, LX/08au;->A22:LX/08au;

    if-ne v1, v2, :goto_scan

    :cond_is_clip
    invoke-virtual {v5}, LX/01lF;->A0K()Lcom/google/common/collect/ImmutableList;

    move-result-object v0

    if-eqz v0, :goto_scan

    invoke-interface {v0}, Ljava/util/List;->isEmpty()Z

    move-result v1

    if-nez v1, :goto_scan

    const/4 v1, 0x0

    invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;

    move-result-object v0

    if-eqz v0, :goto_scan

    check-cast v0, LX/01oT;

    iget-object v0, v0, LX/01oT;->A1F:Ljava/lang/String;

    if-eqz v0, :goto_scan

    invoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v0

    if-eqz v0, :goto_scan

    const-string v1, "id"

    invoke-virtual {v0, v1}, Landroid/net/Uri;->getQueryParameter(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :goto_scan

    invoke-virtual {v7, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :goto_scan

    return-object v5

    :cond_fail
    return-object v8
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    move-exception v0

    const/4 v0, 0x0

    return-object v0
.end method
