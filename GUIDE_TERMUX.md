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
pkg install -y git openjdk-17 apksigner aapt2 curl
```

**apktool is not a Termux package.** `pkg install apktool` fails with
"has no installation candidate" - it is a plain Java jar, so the build script
downloads the latest release from
[github.com/iBotPeaches/Apktool](https://github.com/iBotPeaches/Apktool/releases)
and runs it with `java -jar`. Nothing to do by hand.

If you would rather supply it yourself, drop the jar next to the script as
`apktool.jar`, or point at it with `APKTOOL_JAR=/path/to/apktool.jar`.

**Why `aapt2` matters.** apktool bundles prebuilt `aapt`/`aapt2` binaries
compiled for x86_64 Linux. Those cannot execute on an aarch64 Android phone,
so the rebuild step fails with an "exec format error" unless apktool is handed
Termux's native `aapt2`. The build script detects it and passes it through
automatically - you just need the package installed.

`zipalign` is optional. If it is unavailable, skip it - the script detects its
absence and carries on. Alignment is an optimisation, not an install
requirement.

### Check your setup before building

```bash
bash build_termux.sh --check
```

This prints exactly which tools were found, whether storage access works, which
apks it can see in Downloads, and how much space is free - without starting the
slow build. Fix anything reported as `MISSING` first.

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

## Automating rebuilds for new Instagram versions

`auto_update.sh` watches Downloads for a new Instagram apk and rebuilds
HealthyIG from it unattended. Two steps stay manual and cannot be automated on
an unrooted phone:

- **Downloading the apk.** APKMirror is Cloudflare-gated and its terms forbid
  automated downloading.
- **Installing the result.** Android requires a user tap for every install
  unless the device is rooted or the installer is a device owner.

So the loop becomes: you download the apk when you feel like it, the phone
rebuilds overnight, and you tap to install in the morning.

### Setup

```bash
pkg install -y cronie termux-api
```

Also install the **Termux:API** and **Termux:Boot** companion apps from the
same source as Termux (F-Droid). Termux:API powers the notifications and the
charging check; Termux:Boot restarts cron after a reboot.

Start cron at boot:

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-crond.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
crond
EOF
chmod +x ~/.termux/boot/start-crond.sh
```

Add the job with `crontab -e`:

```
0 3 * * * bash ~/HealthyIG---with-Feed/auto_update.sh
```

Then start cron for this session without rebooting: `crond`

### How it behaves

- Runs at 03:00 daily. On a tick with nothing new it exits in milliseconds and
  writes nothing to the log.
- A build only starts if the newest apk in Downloads differs from the last one
  built (tracked in `.last_built` as basename + byte size).
- It defers while the phone is on battery and notifies you to plug in - the
  rebuild pegs every core for hours.
- It holds a lock directory so a second tick can never start a parallel build
  and corrupt `ig_plain`.
- It takes a wake lock for the duration and releases it on exit, including on
  failure.
- You get a notification when the build starts and when the apk is ready.

### Checking on it

```bash
bash auto_update.sh --status    # newest apk, last built, lock state
tail -f auto_update.log         # watch a build in progress
bash auto_update.sh --force     # rebuild the current apk anyway
```

If a build fails, the decompiled tree is left in place - resume it with
`bash build_termux.sh --resume` rather than starting over.

### Signing key

Every rebuild is signed with `healthyig.jks`, generated on the first build.
Keep it. Signing with a different key makes Android treat the result as a
different app, forcing an uninstall and losing your local data.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Package 'apktool' has no installation candidate` | apktool is not a Termux package | Nothing to do - the build script fetches the jar itself |
| `exec format error` / `cannot execute binary file` during rebuild | apktool used its bundled x86 aapt | `pkg install -y aapt2`, then re-run |
| `Unrecognized option: -r` on rebuild | `-r` is decode-only, never valid for `b` | Fixed - pull the latest, then `bash build_termux.sh --resume` |
| Rebuild failed after a successful decompile | - | `bash build_termux.sh --resume` reuses `ig_plain` instead of decompiling again |
| `No mirror or mirror group selected` | Termux mirror not chosen | Run `termux-change-repo` and pick a nearby mirror |
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
