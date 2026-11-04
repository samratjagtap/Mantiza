# MacBook setup for Mantiza

iPhone apps can only be built with Apple's **Xcode**, and Xcode only runs on a **Mac**. This guide takes a new MacBook from first boot to running a test app on your iPhone. After that we can build the Mantiza test app for Phase 0 tests **T2, T3, T4 and T12** ([plan, section 11](../Mantiza%20Roadmap/mantiza-v2-plan.md)).

**Time:** about 2–3 hours, mostly waiting for downloads (Xcode alone is several GB).

**Status markers:** ✅ = do it · ⚪ = optional · ⏳ = long wait

---

## Still choosing a Mac?
| Part | Needed | Why |
|---|---|---|
| Chip | 🔴 **Apple silicon (M1 or newer)**, required | Mantiza needs the **iOS 27 SDK** (ScreenCaptureKit on iPhone), which only comes with **Xcode 27**. Xcode 27 "will only install and run on Apple silicon Macs" and needs **macOS Tahoe 26.6** or later. **No Intel Mac can do this**, even with unofficial macOS patchers |
| Memory (RAM) | 16 GB recommended (8 GB works, slower) | Xcode + Simulator + browser fill 8 GB quickly |
| Storage | 256 GB minimum, 512 GB recommended | Xcode, the iOS tools and simulators take 50+ GB |

A used or refurbished **M1 or newer** MacBook Air or Mac mini is enough. No Mac? A rented cloud Apple-silicon Mac also works for building, but running on your own iPhone needs a cable or the same network, so a real Mac is easier.

> [!WARNING]
> **Checked 2026-11-05:** a MacBook Pro 13" 2016 (Intel, macOS Monterey 12.7.6) **can't** be used. Its newest Xcode is 14.2, which can't run apps on iPhones with iOS 17 or later, let alone iOS 27.

---

## Step 1: First start ✅
1. Turn it on and follow the setup screens. Sign in with your **Apple Account** (the same one as your iPhone is easiest).
2. **System Settings → General → Software Update** → install every update. ⏳ The newest Xcode needs a recent macOS.

## Step 2: Apple Developer account ✅
You need it to install your own apps on your iPhone.

| Type | Cost | What you get |
|---|---|---|
| **Free** (just your Apple Account) | ₹0 | Run apps on your own iPhone. **The app stops opening after 7 days**: reconnect and press Run again |
| **Paid** (Apple Developer Program) | $99 / year | Apps last a year, TestFlight to share with testers, App Store. Needed by Phase 3 (private beta) |

**Start with free.** It's enough for Phase 0. Upgrade at [developer.apple.com/programs](https://developer.apple.com/programs/) when we need testers.

## Step 3: Install Xcode ✅ ⏳
1. Open the **App Store** on the Mac, search **Xcode**, click **Get**. (Large download; can take an hour.)
2. Open Xcode once. Accept the license. When it asks which platforms to install, tick **iOS**. ⏳
3. **Xcode → Settings → Accounts → +** → **Apple Account** → sign in. This creates your free "Personal Team".

## Step 4: Get our code onto the Mac ✅
1. Open the **Terminal** app (press ⌘+Space, type `Terminal`, Enter).
2. Install Apple's command-line tools (includes **git**): type `xcode-select --install` and press Enter. If it says they're already installed, that's fine.
3. Tell git who you are (use the same name and email as on the PC; on the PC, `git config --global user.email` shows it):
   ```
   git config --global user.name "samratjagtap"
   git config --global user.email "your-github-email@example.com"
   ```
4. Download our repo and switch to our working branch, **v1**:
   ```
   cd ~/Desktop
   git clone https://github.com/samratjagtap/Mantiza.git
   cd Mantiza
   git checkout v1
   ```
   When git asks you to log in to GitHub, use a browser login or a token. Easiest: install **GitHub Desktop** or the GitHub CLI (`gh auth login`) and follow its steps.

## Step 5: Install VS Code and Claude Code ✅
So we can keep working together the same way as on the PC.
1. Download **VS Code** from [code.visualstudio.com](https://code.visualstudio.com) and drag it into **Applications**.
2. In VS Code: **Extensions (⇧⌘X)** → search **Claude Code** → **Install** → sign in.
3. **File → Open Folder…** → `Desktop/Mantiza`.

> [!NOTE]
> Claude's saved notes about how you like to work (commit to v1, explain git simply, no Claude credit in commits…) live **on the PC only**. On the Mac, Claude starts without them. Tell it to read this repo's docs, or ask it to save the same preferences again.

## Step 6: Prepare the iPhone ✅
1. Connect the iPhone to the Mac with a cable. On the iPhone, tap **Trust** and enter your passcode.
2. In Xcode: **Window → Devices and Simulators** → your iPhone should appear. Wait while it "prepares" the phone. ⏳
3. iPhone: **Settings → Privacy & Security → Developer Mode** → **On** → the phone restarts → confirm **Turn On**.
   (This option only appears after the iPhone has been connected to Xcode.)

## Step 7: Prove it works with a "Hello" app ✅
This checks the whole chain (Mac → Xcode → iPhone) before we build anything real.
1. Xcode → **File → New → Project… → iOS → App** → Next.
2. Product Name: `HelloMantiza` · Team: **your Personal Team** · Interface: **SwiftUI** → Next → save it **outside** the Mantiza repo folder (e.g. Documents).
3. At the top of Xcode, pick **your iPhone** as the run destination (not a Simulator).
4. Press **▶ Run** (⌘R).
5. The first time, the iPhone blocks the app: **Settings → General → VPN & Device Management** → your developer name → **Trust**. Press Run again.
6. "Hello, world!" appears on your iPhone. ✔️ The Mac is ready.

## Step 8 ⚪: Firmware tools on the Mac (optional)
The StickS3 firmware can stay on the Windows PC. If you want it on the Mac too: in VS Code, install the **PlatformIO IDE** extension and open `firmware/t1-hid-test` (same as [the T1 guide, Part A](../../firmware/t1-hid-test/README.md)). Macs need no USB driver for the StickS3.

---

## After setup: what we build next
Tell Claude "the Mac is ready". The next step is a small **Phase 0 test app** in this repo (not the full Mantiza app). You only open it in Xcode and press Run; each test is a button in the app.

| Test | What the test app checks | What you do |
|---|---|---|
| **T2** | The app sends commands to the StickS3 over Bluetooth **while the StickS3 is also the iPhone's mouse**, and while the app is in the background | Press "Send command", switch to another app, watch the device |
| **T3** | Screen capture (ScreenCaptureKit) **keeps running** while another app is in front for 5+ minutes; what happens on lock | Start capture, use other apps, lock the phone, then check the app's log |
| **T4** | Whether iOS asks for screen-capture permission **every time**, or a session can be reused | Start, stop and start again; note the pop-ups |
| **T12** | End-to-end timing of "Reply to Azad: I'm coming" | Needs T2, T3 and the AI tests (T8, T11) first |

Results go into the plan's Phase 0 table, the same as T1 and T1b.

## Checklist
- [ ] macOS fully updated
- [ ] Xcode installed, iOS platform downloaded, Apple Account added
- [ ] Repo cloned, on branch `v1`
- [ ] VS Code + Claude Code working
- [ ] iPhone trusted, Developer Mode on
- [ ] "Hello" app runs on the iPhone
