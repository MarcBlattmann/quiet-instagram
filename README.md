# Instagram without the distractions

A patched Instagram build with Reels, Explore and reel chaining disabled.
Your following feed, stories, DMs and profiles all work normally.

It works by decompiling the official apk, blanking the API endpoints that
serve the addictive surfaces, and rebuilding it. Nothing is added - only
removed.

| Blocked | Kept |
|---|---|
| Reels tab | Home feed |
| Explore grid | Stories |
| Reel chaining | DMs |
| Suggested reels | Profiles and search |
| | Reels friends send you |

Tested against Instagram 430.0.0.53.80 (arm64-v8a).

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

The endpoint patches are string replacements and survive updates. The nav-bar
patch is bytecode and is tied to one build's obfuscated names - if those move,
the build warns, skips that step and still produces a working apk. Run
`bash recon_navbar.sh ig_full` to find the new names when that happens.

## Which endpoints get blocked

Edit `script.sh` to change what is disabled. Each line blanks one API path;
comment a line out to let that surface work again. The home feed
(`feed/timeline`) is commented out, which is why the feed loads here.

Note that `feed/timeline` also carries "Suggested for you" posts and ads -
that comes with having a real feed.

## Credit

Forked from [HealthyIG](https://github.com/AlessandroBonomo28/HealthyIG) by
Alessandro Bonomo. The original `script.sh` approach is by
[breakthescroll.com](https://breakthescroll.com/).

Apache 2.0 - see `LICENSE.md`.
