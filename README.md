# Instagram without the distractions

A patched Instagram build with the endless surfaces taken out and the
conversation left in. Your following feed, stories, DMs and profiles all work
normally.

It decompiles the official apk, blanks the API endpoints that serve the
addictive surfaces, patches a few things in bytecode, and rebuilds.

Tested against Instagram 430.0.0.53.80 (arm64-v8a).

## Features

**Taken out**

| | |
|---|---|
| Explore grid | The whole discovery tab |
| Reel chaining | No "next reel" after one you opened |
| Suggested reels | Including the ones seeded into other surfaces |
| Reels tab | The button is gone from the nav bar - `--keep-reels-tab` puts it back |

**Kept**

Home feed, stories, DMs, profiles, search, and the reels friends send you.

**Added**

These are the parts that do more than the stock app, not less. All three are on
by default and each has an off switch.

| Feature | What it does | Off switch |
|---|---|---|
| [Reels in DMs](#reels-in-dms) | Open a reel a friend sent and keep scrolling to see the rest from that conversation, instead of backing out and tapping each one | `--no-thread-reels` |
| [A reaction bar that follows you](#the-reaction-bar-follows-the-reel) | The bar at the bottom stays with the reel on screen, and replies and emoji reactions land on the reel you are actually watching | `--no-reply-bar-fix` |
| [No dead scrolling](#no-dead-scrolling) | The viewer stops at the last real reel instead of letting you swipe onto a page that spins forever | `--no-dead-scroll-fix` |

The endpoint blanking is version-agnostic - it only rewrites strings. The three
added features are bytecode edits tied to one build's obfuscated class names, so
each patch script verifies every assumption it depends on and refuses to patch
rather than produce an apk that quietly behaves as before.

## Reels in DMs

Out of the box, tapping a reel a friend sent you opens a viewer holding
exactly that one reel. Swiping up does nothing. Five reels from the same
person means backing out and tapping in five times.

This build fixes that: open one and keep scrolling, and you get the rest of
the reels from that conversation.

Instagram does ship a route for this - a data source that pages a thread's
reels through `clips/direct_thread_clips/` - but it is dead in the shipped
build, and simply switching it back on does not work. It needs the server to
answer an endpoint the stock app never calls, and it needs a *primary* data
source alongside it, which here is the discovery feed this build blanks.

So the playlist is built on the phone instead. An injected class walks the
conversation's own message store for every reel in it and rotates the list so
the reel you tapped is first. The viewer is then handed that list through
`LX/0aNJ` - the same data source Instagram uses for its own "reels from your
saved collection" surfaces - which loads them from `clips/items/`, an ordinary
endpoint this build leaves alone.

Nothing depends on a server feature flag. If the walk comes back empty, the
viewer behaves exactly as it did before.

Each reel appears once per pass: the list is rotated rather than looped, so it
starts at the reel you tapped and ends.

Not done: reels you have already watched are still in the list. Filtering them
out works, and that is the problem - Instagram's own "unwatched clips" walk
returns nothing once you have been through a conversation, so the playlist
deletes itself the second time you use it.

```bash
bash build_termux.sh --no-thread-reels
```

## The reaction bar follows the reel

Stock Instagram builds the bar at the bottom from the message you tapped, and
hides it on every other reel - reasonably, since normally there is no other reel
for it to belong to. With a playlist there is.

`patch_reply_bar.sh` looks up the message behind whatever reel is on screen and
uses it three ways: to decide the bar belongs there, to target a typed reply,
and to target an emoji reaction. Those last two are separate code paths in
Instagram and identify the reel differently, which is worth knowing if this ever
needs redoing - patching one leaves the other landing on the wrong reel.

If a reel cannot be matched to a message in the conversation, the bar is hidden
for it rather than shown and quietly aimed at something else.

```bash
bash build_termux.sh --no-reply-bar-fix
```

## No dead scrolling

Blanking the discovery endpoints has a visible side effect: the viewer has
already put a placeholder page on the end of the list before it finds out that
nothing is coming. You can swipe onto a black screen that spins forever.

`patch_no_dead_scroll.sh` makes the pager stop at the last real reel. Those
placeholders have a type whose name survived obfuscation - `GHOST` - so the
pager's `getItemCount()` can simply not count them.

It only hides pages, so paging itself is untouched: the next page is requested
on page change, not when a placeholder scrolls into view, and when one genuinely
arrives the pager grows with the list.

```bash
bash build_termux.sh --no-dead-scroll-fix   # leave the dead page scrollable
```

`recon_thread_reels.md` has the full trace for all three: the classes, the
switches, the registers, and - just as usefully - the approaches that looked
right, were built, and had to be reverted.

## Build it

Everything runs on the phone itself in [Termux](https://f-droid.org/packages/com.termux/)
(install from F-Droid, not the Play Store).

```bash
pkg install -y git openjdk-17 apksigner aapt2 curl
termux-setup-storage
```

Download the Instagram apk from APKMirror - **arm64-v8a**, and the **APK**
variant, not BUNDLE or XAPK. Leave it in Downloads.

```bash
git clone https://github.com/MarcBlattmann/quiet-instagram.git
cd quiet-instagram
bash build_termux.sh --check    # verify the toolchain first
bash build_termux.sh
```

The result lands in Downloads as `HealthyIG-install.apk`. Uninstall the
official Instagram first, then open it to install.

Budget 30-60 minutes and ~8 GB free. Run `termux-wake-lock` in a second
session so Android doesn't suspend it. On phones with 4 GB RAM or less the
rebuild step may run out of memory, which has no on-device workaround.

If the rebuild fails after decompiling, `bash build_termux.sh --resume`
retries just that step instead of starting over.

The Reels button is removed from the bottom navigation bar by default. Pass
`--keep-reels-tab` to leave it in place.

## Keep the signing key

`healthyig.jks` is generated on the first build. Back it up. Signing a later
build with a different key makes Android treat it as a different app, forcing
an uninstall and losing your local data.

## Updating to a new Instagram version

Download the new apk from APKMirror into Downloads and run `bash
build_termux.sh` again. It picks up the newest Instagram apk it finds.

The endpoint patches are string replacements and survive updates. The four
bytecode patches - the nav bar and the three features above - are tied to one
build's obfuscated names.

If those names move, the nav-bar patch warns, skips itself and still produces a
working apk; run `bash recon_navbar.sh ig_full` to find the new ones. The three
feature patches stop the build instead, because a half-applied bytecode edit is
worse than none. Rebuild with the matching `--no-*` flag to get an apk out while
you re-locate them, and see `recon_thread_reels.md` for what each one anchors to.

## Which endpoints get blocked

Edit `script.sh` to change what is disabled. Each line blanks one API path;
comment a line out to let that surface work again. The home feed
(`feed/timeline`) is commented out, which is why the feed loads here.

Note that `feed/timeline` also carries "Suggested for you" posts and ads -
that comes with having a real feed.

Two paths deliberately stay open: `clips/direct_thread_clips/` and
`clips/items/`. They are what makes scrolling through a friend's reels work,
and neither returns anything you were not already sent. Blanking `clips/`
wholesale would take them out along with everything else.

## Credit

Forked from [HealthyIG](https://github.com/AlessandroBonomo28/HealthyIG) by
Alessandro Bonomo. The original `script.sh` approach is by
[breakthescroll.com](https://breakthescroll.com/).

Apache 2.0 - see `LICENSE.md`.
