# HealthyIG: Building on the phone itself (Termux)

The main guides assume a Linux or WSL desktop. This one covers building
entirely on an Android phone using [Termux](https://termux.dev), with no PC
involved.

> **Reality check before you start.** apktool has to decompile and reassemble
> the whole Instagram app on the phone's CPU. Budget **~30-60 minutes** and
> **6-8 GB of free storage**. On devices with 4 GB RAM or less the rebuild
> step may run out of memory and fail. If it does, there is no workaround on
> device - you need a PC for that step.

---

## 1. Install Termux

Install from **F-Droid** or **GitHub releases**, *not* the Play Store - the
Play Store build is abandoned and its package repos no longer work.

- F-Droid: https://f-droid.org/packages/com.termux/
- GitHub: https://github.com/termux/termux-app/releases

Open it and set up storage access so Termux can reach your Downloads folder:

```bash
termux-setup-storage
```

Accept the Android permission prompt when it appears.

---

## 2. Install the toolchain

```bash
pkg update -y
pkg install -y git apktool apksigner openjdk-17
```

`zipalign` is optional. If `pkg install zipalign` finds nothing, skip it -
the build script detects its absence and carries on. Alignment is an
optimisation, not an install requirement.

---

## 3. Get the Instagram apk

In your phone's browser, download the base apk from APKMirror:

- Architecture **arm64-v8a**, DPI **nodpi**
- File type must be **APK** - `.apkm`, `.xapk`, and `.apks` bundles cannot be
  read by apktool. On APKMirror the download page states the type; pick the
  entry that says "APK" rather than "BUNDLE".

Leave it in your Downloads folder. The build script finds it automatically.

---

## 4. Clone this branch and build

```bash
git clone -b claude/instagram-apk-home-feed-a9kp95 \
  https://github.com/MarcBlattmann/HealthyIG---with-Feed.git
cd HealthyIG---with-Feed
bash build_termux.sh
```

That single command decompiles, applies `script.sh`, rebuilds, signs, and
drops **`HealthyIG-install.apk`** into your Downloads folder.

If it cannot find the apk on its own, point it at the file directly:

```bash
bash build_termux.sh ~/storage/downloads/instagram-430.apk
```

Keep the screen awake while it runs - Android will not kill Termux, but
watching the log tells you whether it is progressing or stuck.

---

## 5. Install

1. Uninstall the official Instagram (including any "Dual App" / "Private
   Space" clone), otherwise the install fails on a signature conflict.
2. Open **HealthyIG-install.apk** from your Downloads via the Files app.
3. Allow "install from unknown sources" for the Files app if prompted.
4. If Play Protect warns about an unverified app, tap **More details** →
   **Install anyway**.

---

## 6. Re-running later

`healthyig.jks` is generated on the first build and reused afterwards.
**Keep it.** Signing a future build with a different key means Android treats
it as a different app and you have to uninstall and lose your local app data
first. Back it up somewhere off the phone.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Could not find an Instagram apk` | Storage permission missing | Run `termux-setup-storage`, or pass the path as an argument |
| `is a bundle format` | Downloaded `.apkm`/`.xapk`/`.apks` | Re-download the plain APK variant |
| Rebuild killed with no error | Out of RAM | No on-device fix - use a PC for this step |
| `No space left on device` | Decompiled tree is large | Free up space, or `rm -rf ig_plain` and retry |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Wrong architecture | Download the arm64-v8a variant |
| `App not installed` | Old Instagram still present | Uninstall it for **all** users first |

---

## What this branch changes

The `feed/timeline` replacement in `script.sh` is commented out, so the normal
following feed loads. Reels, reel chaining, and Explore stay blocked exactly
as upstream.

Note that `feed/timeline` also carries Meta's "Suggested for you" posts and
inline ads - restoring it restores those too. It is the real feed, not a
following-only feed.
