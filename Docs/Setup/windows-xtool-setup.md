# Build iPhone apps on Windows with xtool

No Mac? [xtool](https://github.com/xtool-org/xtool) (open source, MIT) builds, signs and installs iPhone apps from **Windows via WSL**. It uses Apple's own iPhone SDK, unpacked from the Xcode download.

**Status:** ✅ **Works.** Checked 2026-11-05: a SwiftUI "Hello" app built in 7 seconds on Windows 11 (WSL Ubuntu 24.04), installed over USB and ran on an iPhone 14 Plus.

**Status markers:** ✅ = do it · ⚪ = optional · ⏳ = long wait

---

## What xtool can and can't do for Mantiza

| Need | xtool | Notes |
|---|---|---|
| SwiftUI app with the iOS 27 SDK | ✅ | Xcode 27.1 SDK |
| Install and run on your iPhone over USB | ✅ | Through the Apple Devices app (see the bridge below) |
| Bluetooth, background modes, entitlements | ✅ expected | Info.plist and entitlements are supported; Phase 0 tests T2 and T3 will confirm |
| App icons and images (asset catalogs) | ⚠️ | Can fail on WSL ([#310](https://github.com/xtool-org/xtool/issues/310)). Test apps don't need them |
| Home screen widget (Phase 2) | ❌ for now | Open bugs: widget comes out empty or crashes ([#313](https://github.com/xtool-org/xtool/issues/313), [#379](https://github.com/xtool-org/xtool/issues/379)) |
| TestFlight / App Store | ❌ | Needs a Mac or a cloud Mac ([MacBook setup](macbook-setup.md)) |
| Step-by-step debugger | ⚠️ limited | Use logs |

**Free Apple account:** the app stops opening after **7 days**. Run `xtool dev` again to reinstall.

---

## One-time setup (about 1 hour, mostly downloads)

### Step 1: Apple account ✅
Make a **separate Apple Account for development** at [account.apple.com](https://account.apple.com) (a Gmail `+dev` address works). Then sign in once at [developer.apple.com](https://developer.apple.com) and accept the terms.
- **Why separate:** xtool's free sign-in uses Apple's private (unofficial) APIs. Keep your main iCloud account out of it.
- Don't turn on Advanced Data Protection for it: with it on, the 2FA code may never arrive ([#407](https://github.com/xtool-org/xtool/issues/407)).
- Your iPhone stays signed in to your **main** account. The dev account is only used on the PC.

### Step 2: Windows downloads ✅ ⏳
1. **Xcode 27.1** `.xip` from [developer.apple.com/download/all](https://developer.apple.com/download/all/?q=Xcode). Download it **in the browser**. Pick the release, not a beta. The xtool guide names 27.1.
2. **Apple Devices** from the Microsoft Store.
3. **Python 3** for Windows, from [python.org](https://www.python.org/downloads/). The bridge uses it.
4. Plug in the iPhone, unlock it, tap **Trust**, and check that it shows in **Apple Devices**.
   > [!WARNING]
   > **Turn off Personal Hotspot** on the iPhone while it's connected. With hotspot on, Windows lists **no** iPhone.

### Step 3: Ubuntu 24.04 in WSL ✅
In PowerShell: `wsl --install -d Ubuntu-24.04` (skip if already installed). Then run everything below **inside Ubuntu** (`wsl -d Ubuntu-24.04`).

**Fix DNS if downloads fail** with "Could not resolve host":
```
sudo sh -c 'printf "\n[network]\ngenerateResolvConf=false\n" >> /etc/wsl.conf'
sudo rm -f /etc/resolv.conf
sudo sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'
```

**Packages:**
```
sudo apt-get update
sudo apt-get install -y usbmuxd libimobiledevice-utils libfuse2t64 socat zip curl \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
  libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev
```
(`zip` is easy to miss: without it, install fails with *Executable "zip" is not found*.)

**Swift 6.4** (via [swiftly](https://www.swift.org/install/linux/)):
```
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init --assume-yes --skip-install
. ~/.local/share/swiftly/env.sh
swiftly install 6.4 --use --assume-yes
swift --version        # Swift version 6.4.x
```

**xtool:**
```
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o xtool
chmod +x xtool && sudo mv xtool /usr/local/bin/
xtool --version        # 1.24.0 tested
```

### Step 4: Connect the iPhone to Ubuntu (the bridge) ✅
Ubuntu can't see USB devices by itself. xtool's guide suggests **usbipd** (needs admin rights). We use a simpler bridge instead: Ubuntu borrows the iPhone connection that the **Apple Devices** app already has (Apple's service on `127.0.0.1:27015`). Files: [tools/xtool-bridge/](../../tools/xtool-bridge/).

Start it from PowerShell and **leave that window open**:
```
wsl -d Ubuntu-24.04 -u root -- sh /mnt/c/Users/PC/Desktop/mantiza/Mantiza/tools/xtool-bridge/iphone-bridge.sh
```
Check from Ubuntu in a second window:
```
xtool devices          # shows: <your iPhone> [usb]: <udid>
idevicepair validate   # SUCCESS: Validated pairing ...
```

### Step 5: Sign in and install the SDK ✅ ⏳
```
cp /mnt/c/Users/PC/Downloads/Xcode_27.1.xip ~/       # faster than reading from the C: drive
xtool sdk install ~/Xcode_27.1.xip                   # ~10 min; reported to freeze at 72% on some WSL setups (#316), it didn't here
xtool auth login                                     # choose 1 (Password), then the dev account's email, password, 2FA code
swift sdk list                                       # darwin
```

### Step 6: Hello app ✅
```
mkdir -p ~/projects && cd ~/projects
xtool new HelloMantiza --skip-setup
cd HelloMantiza
sed -i 's/com.example/com.yourname/' xtool.yml        # Apple rejects com.example IDs
xtool dev                                              # build + sign + install
```
On the iPhone (first time only):
1. **Settings → Privacy & Security → Developer Mode → On** → restart → **Turn On**.
2. **Settings → General → VPN & Device Management** → the dev account → **Trust**.
3. Open the app: 🌐 **Hello, world!** ✔️

---

## Every time you work
1. Plug in and **unlock** the iPhone. Hotspot off.
2. Start the bridge (Step 4) and leave it open.
3. In Ubuntu, `cd` to the app and run `xtool dev`.

## Troubleshooting
| Problem | Fix |
|---|---|
| `Could not resolve host` in Ubuntu | DNS fix in Step 3 |
| `xtool devices` waits forever / `No device found` | Unlock the iPhone and re-plug the cable. Turn off Personal Hotspot. Check that it shows in Apple Devices. Check that the bridge window is still running |
| `Executable "zip" is not found` | `sudo apt-get install zip` |
| App won't open, "Untrusted Developer" | Step 6, item 2 |
| App stopped opening after a week | Free account limit: run `xtool dev` again |
| 2FA code never arrives | Use a dev account without Advanced Data Protection ([#407](https://github.com/xtool-org/xtool/issues/407)) |

## Sources
- [xtool repo](https://github.com/xtool-org/xtool) · [releases](https://github.com/xtool-org/xtool/releases) · [Linux/WSL install guide](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md) · [app extensions](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Appex.md)
- [Swift on Linux (swiftly)](https://www.swift.org/install/linux/)
- [libimobiledevice / usbmuxd](https://libimobiledevice.org/)
