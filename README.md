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

## Keep the signing key

`healthyig.jks` is generated on the first build. Back it up. Signing a later
build with a different key makes Android treat it as a different app, forcing
an uninstall and losing your local data.

## Rebuild automatically on new versions

`auto_update.sh` watches Downloads for a newer apk and rebuilds unattended.

```bash
pkg install -y cronie termux-api
crontab -e
```

```
0 3 * * * bash ~/quiet-instagram/auto_update.sh
```

To survive reboots, install the Termux:Boot app and add:

```bash
mkdir -p ~/.termux/boot
printf '#!%s/bin/sh\ntermux-wake-lock\ncrond\n' "$PREFIX" > ~/.termux/boot/start-crond.sh
chmod +x ~/.termux/boot/start-crond.sh
```

It only builds when the apk in Downloads differs from the last one built, waits
until the phone is charging, and notifies you when the result is ready.
Check it with `bash auto_update.sh --status` or `tail -f auto_update.log`.

Downloading the apk and installing the result stay manual - APKMirror blocks
automated downloads, and Android requires a tap to install without root.

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
