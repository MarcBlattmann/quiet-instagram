# Recon: reels in DMs, and the page that never loads

Notes behind `patch_thread_reels.sh` and `patch_no_dead_scroll.sh`, against
Instagram 430.0.0.53.80. Class names are R8-obfuscated and will differ on other
builds; string constants, package paths, and the `__redex_internal_original_name`
fields are what survive.

---

## Part 1 - scrolling through the reels a friend sent

### The problem

Tapping a reel in a DM opens a clips viewer holding one item. Swiping up ends
the viewer instead of advancing.

### First attempt, and why it failed

Instagram ships `LX/0aNS`, a data source that pages one thread's reels:

    GET clips/direct_thread_clips/?thread_id=..&limit=6&media_cursor_timestamp_ms=..

`LX/015a->A00(...)` picks a data source by switching on
`ClipsViewerSource.ordinal()`. `DIRECT` is ordinal 11 and is the only source with
its own branch (`:pswitch_30`). That branch reaches `LX/0aNS` when three things
hold:

| condition | where it comes from | value |
|---|---|---|
| `directData.A03` (thread id) non-null | `DirectThreadKey.A00` | set |
| `directData.A09` (`isMsysThread`) **false** | literal `0` in both DM launchers | false |
| `config.A2D` (`enableClipsDualPagination`) true | nothing ever sets it | **false** |

The second reads backwards on purpose: `LX/03Bx->A10(o)` is
`Boolean.FALSE.equals(o)`, so the branch wants `isMsysThread == false`.

`A2D` is dead because `LX/01Tj` - the config builder - has no field for it and
moves a shared zero register into constructor parameter 161:

    const/16 v150, 0x0
    ...
    move/from16 v177, v150     # v177 is p161 -> A2D

So v1 of the patch forced `A2D` on in the constructor. **It changed nothing on
device.** Two dependencies were outside our control:

1. the server has to answer `clips/direct_thread_clips/` for this account, on a
   code path the stock app never runs; and
2. "dual pagination" means a *secondary* source alongside a primary one, and the
   primary here is `LX/015e` - `ClipsDiscoverDataSource` - whose endpoints this
   build blanks. A secondary source layered on a dead primary never gets asked.

### What works instead

Build the list on the client and hand it over explicitly.

`LX/0aNJ` implements `LX/0lhp` and is already used for `DIRECT_CROSS_APP_SAVES`
(ordinal 208) and `DIRECT_ICEBREAKER` (207) via `:pswitch_32`. Give it a `List`
of media ids and:

- `C18` (first page) JSON-encodes the list and calls
  `ClipsApiUtilHelper->A03`, which is `clips/items/` with param `clips_media_ids`
  - an ordinary endpoint `script.sh` does not blank;
- `DGa` (later pages) delegates to the wrapped source.

### Three follow-on behaviours, and the flags behind them

**The reply bar following the current reel: solved, see `patch_reply_bar.sh`.**
`LX/05WZ` stubs every method of the page-lifecycle interface `LX/0Jek` except
`FK7(II)`, which makes `FK7` the page-change hook; it calls `LX/0330->A0B(pos)`.
`A0B` sets the bar up and three times over does `if-nez p1, :cond_1x` where the
target is `LX/05WZ->A0T()` (hide) and the fall-through is `A0U()` (show). Page 0
gets a bar, nothing else does.

`A0B` has two halves selected by `LX/0330->A0q`. The other half drives
visibility from a per-position reshare store, and cannot be the live one here:
it is fed by `LX/0330->A01()`, which returns empty unless `LX/0330->A0W` is set,
and `A0W` is only assigned on the play-pile path - so the bar would be missing on
page 0 too. It is not, so `A0q` is false.

Visibility alone is not enough - a bar shown on every reel while still aimed at
the first one is worse than no bar. There are **two** send paths and they
identify the reel differently:

- **Typing in the composer** goes through `LX/0330->A0K`, which with `A0q` false
  reads `ClipsReplyBarData.A07` (message id) and `.A05` (client context), both
  fixed at launch.
- **Tapping a quick emoji** goes through `LX/0330->A0W` and out via
  `LX/04t3->GIv`, and takes the reel from an `LX/0E9k` returned by
  `LX/0330->A03` - the reshare-store entry - three separate times: the
  `LX/07ze->CNI` lookup that builds the replied-to descriptor (`LX/01FH`, via
  `LX/05Kd->A00`), and the two id strings passed to `GIv`.

Patching only `A0K` fixes typed replies and leaves emoji reactions landing on
the reel the viewer was opened on - which is exactly what happened on the first
attempt. `0E9k->A00` is the message id and `->A03` the client context: `A0K`'s
other branch reads those two into the same slots that hold `A07` and `A05`.

The id itself is the one `LX/07ze->CNI` looks messages up by - `CNI` ->
`LX/01rO->A0I` probes on `LX/02Rf->A0y`, which is what `LX/01lF->A0o()` returns
- and `A05`/`0E9k->A03` is the matching client context, `LX/02Rf->A0s`. So
resolving the *message* behind the reel on screen serves visibility and both
send paths from one lookup.

**An earlier attempt via the play-pile flag: reverted, do not retry this way.** `LX/04p0->A01` decides whether the reply bar belongs on screen, and
for `DIRECT` it returns true when `isPlayPile` is set. *Play pile* is Instagram's
own name for a DM viewer showing several reels instead of one - see
`DirectInboxPlayPileButtonHolder` - so it looked like exactly the state this
patch creates. Setting `ClipsViewerDirectData.A0B` **makes reacting to a reel
crash the app.**

Why: the flag is threaded into the reply bar controller `LX/0330` as its last
constructor argument, where it becomes `A0p`. In `LX/0330->A0W` - the send path -
`A0p` selects a branch that works from an `LX/0E9k` taken out of `A0C`, the play
pile list. `A0C` starts as `ImmutableList.of()` and is only replaced, in
`onViewCreated`, by `LX/0330->A01()`, which needs `ClipsReplyBarData.A0A` to
resolve to a thread via `LX/07ze->DJj`. When that lookup comes up empty the list
stays empty, and the reaction path reads off the end of it.

So the flag is not a switch for "the bar follows the reel" - it is a switch into
a whole second implementation whose data this build never assembles. The cause of
the bar being tied to the opened reel is still unknown; `LX/04p0->A01` and
`->A02` are both config-level and return the same answer for every item, so
whatever hides it is elsewhere.

**Nothing may load after the playlist: attempted, reverted.**
`ClipsViewerConfig.A2x` (`shouldForceDisableTailLoads`) gates the load-more path
in `LX/04UF` at :7287, :8875 and :4767, so setting it for DM configs looked like
a stronger guarantee than hiding the placeholder after the fact. It is stronger
than intended: the `A2x` test at :8875 sits at the top of the block that kicks
the *first* load off, not just later ones, so the playlist never loaded at all
and the viewer fell back to the single reel. `patch_no_dead_scroll.sh` handles
the dead page on its own; leave `A2x` alone.

**Each reel once: attempted, reverted.** `LX/07zq->DS9` filters to unwatched
clips - it drops anything in `direct_reels_watched_set`, anything with three
impressions in `direct_reels_impression_map`, and anything you sent - so calling
it instead of walking `Cne` looked like a free way to show each reel only once.
The filter works, which is exactly the problem: those sets really are populated,
so once a conversation has been watched `DS9` returns nothing, the list falls
below the two-entry minimum, and the playlist silently vanishes. Being able to
scroll matters more than hiding what you have seen. The rotation already gives
"once each" within a single pass.

Both of these were shipped in the same build, which made the report ("cannot
scroll any more") ambiguous between them - change one thing per build.

The ingredients for the list are all reachable:

| need | call |
|---|---|
| thread store | `LX/07zc->A00(UserSession)LX/07ze;` |
| thread key from an id | `DirectThreadKey-><init>(Ljava/lang/String;)V` |
| unwatched reels in the thread | `LX/07ze->DS9(DirectThreadKey)Ljava/util/ArrayList;` |
| the shared media | `LX/01lF->A0K()` first element, an `LX/01oT` |
| its media id | `id` query param of `LX/01oT->A1F` |

`DS9`'s retained name is `DirectThreadStoreImpl.getUnwatchedClipsFromThread`. It
walks `Cne(threadKey)`, keeps clip shares (`LX/02Rf->A0V` is `LX/08au->A0W` or
`->A22`) that somebody else sent, and drops the watched ones. Calling it beats
reimplementing it.

### The patch

An injected class, `com/quietig/ThreadReels` (source in `smali/ThreadReels.smali`),
does the walk and returns a `List` - or null, which means "behave as before".
Its whole body is inside a `catch Ljava/lang/Throwable;` because
`Uri.getQueryParameter` throws on opaque URIs and a thread store can be in any
state; failure has to degrade, not crash.

The list is rotated so the tapped reel is index 0, because the viewer opens
there. Scrolling then runs through the conversation and wraps, so you see all of
them wherever you started. `java.util.Collections.rotate` does this in one call.

`LX/015a`'s `:pswitch_30` gets a prologue: call the helper, and if it returned a
list, wrap the default source in `LX/0aNJ` and jump to `:goto_1` - the shared
"return this data source" exit that every other branch already uses.

Registers at that point in `LX/015a->A00`: `v14` is the `UserSession` (written
once, at line 16), `v15` the `ClipsViewerConfig` (line 34), `v18` the lazy
default source (line 112). `v0`, `v1`, `v2` are branch-local scratch - every
branch writes them before reading, and `v2` is the output register `:goto_1`
casts and returns.

The old `A2D` edit is stripped by the script if present. It is not merely
redundant now - `A2D` also switches on dual-pagination merging in `LX/04UF`,
`LX/0Bmp` and `LX/0FEl`, which would fight the playlist.

---

## Part 2 - not scrolling onto a page that never loads

### Where the extra page comes from

`LX/05DB` - `ClipsViewerAdapter`, per its retained redex name - appends an item
built by `LX/06o5->A00()` whenever it believes more content is coming. It logs
the decision as `addClipsItems: count=.., shouldAddGhostItem=..`.

That item's type is `LX/04LC->A0I`. Decoding the enum's `<clinit>` gives the
names: `A0I` is `GHOST` and `A0H` is `DISMISSIBLE_GHOST`. Those are the pages you
can swipe onto. With the discovery endpoints blanked nothing ever replaces them,
so they spin forever.

### Why `getItemCount` is the right place

`LX/02QJ` is the `ViewPager2` adapter: built in `LX/00IQ` and stored at
`LX/00IQ->A0V`, handed to the pager by `LX/05DB->A09()`. Its `getItemCount()`
kept its name through obfuscation and is simply `A0l.size()` (with an unrelated
`Integer.MAX_VALUE` branch for looping carousels, guarded by `A0t`, which also
drives a `rem-int` in the bind method - that is the carousel mode, not this one).

A `ViewPager2` cannot scroll past `getItemCount()`. Trailing ghosts are inside
that count, so subtracting them is exactly the stop the user wants.

Patching the count rather than the insertion keeps real items at their existing
indices, leaves the ghost in place for any code that looks for it, and - the
part that matters - does not disable pagination. Loading the next page is driven
by `LX/04UF` through `LX/06DU` on page change, not by the ghost scrolling into
view, so when a page genuinely arrives the list grows and the pager grows with
it.

### The patch

Between the `size()` result and the existing `A0t` check, walk backwards off the
end while the last item is an `LX/015h` whose `A0R` is `GHOST` or
`DISMISSIBLE_GHOST`, decrementing the count. A loop, not a single decrement,
because nothing guarantees only one placeholder.

`.locals` goes 4 -> 6 for two scratch registers; `v0`-`v3` are all live there
(`v1` the running count, `v2` the holder, `v3` a trace token). Raising `.locals`
only renumbers parameter registers, which smali handles.

---

## Verifying without a device

`apktool.jar` bundles the smali assembler. Assembling a patched class catches
bad registers, bad instruction formats and dangling labels:

```java
DexBuilder db = new DexBuilder(new Opcodes(36));
new SmaliBuilder(36).buildFile(new File(path), db);   // brut.androlib.smali.SmaliBuilder
```

Both patches, the injected class, and the reverted config class all assemble.
That proves the bytecode is well-formed. It does not prove the server answers
`clips/items/` for an arbitrary list of media ids - that is the one link only a
device can close.

## Endpoints that must stay unblanked

`script.sh` blanks endpoint strings. These must survive:

- `clips/items/` - hydrates the media id list. **Required.**
- `clips/direct_thread_clips/` - the unused server route from Part 1, kept in
  case it ever starts answering.
