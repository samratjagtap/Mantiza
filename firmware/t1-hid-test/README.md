# T1 test firmware: StickS3 as an iPhone mouse + keyboard

Phase 0, test **T1** from the [v2 plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md): does the StickS3 work as a **Bluetooth LE mouse + keyboard** for an iPhone (AssistiveTouch pointer)?

**Pass condition (from the plan):** the pointer reaches any point accurately; English typing works **including capitals and symbols**; ⌘V pastes.

## What the firmware does
- Shows up on Bluetooth as **"Mantiza T1"** (a mouse + keyboard).
- **Side button (KEY2):** select the next test. **Front button (KEY1):** run the selected test.
- Screen: connection status, battery %, test list, the last action and how long it took.
- USB serial commands for exact moves (Part E).

Built and checked to compile with: PlatformIO, `espressif32@6.12.0` (Arduino core 2.0.17), M5Unified 0.2.29, NimBLE-Arduino 1.4.3.

---

## Part A: install the tools (one time, ~10 minutes)
1. Open **VS Code**.
2. Press **Ctrl+Shift+X** (Extensions), search **PlatformIO IDE**, click **Install**. Restart VS Code if it asks.
3. **File → Open Folder…** and choose exactly `C:\Users\PC\Desktop\mantiza\mantiza\firmware\t1-hid-test` (the folder that contains `platformio.ini`). **Opening a parent folder (like `Desktop\mantiza`) will not work:** PlatformIO only shows its buttons when the opened folder is the project folder.
4. If VS Code asks "Do you trust the authors of the files in this folder?", click **Yes, I trust the authors**.
5. Wait while PlatformIO sets up (see the bottom status bar). The first time can take a few minutes.
6. Check it worked: the **bottom blue bar** now shows small icons including **✓ (Build)** and **→ (Upload)**, and the **left sidebar** has an **ant/alien-head icon (PlatformIO)**.

## Part B: put the firmware on the StickS3
1. Connect the StickS3 to the PC with a **USB-C cable that carries data** (some cables only charge).
2. In VS Code, click the **→ (Upload)** arrow in the bottom blue bar. It builds, then uploads.
   - **Other way (if you can't see the arrow):** click the **PlatformIO ant icon** in the left sidebar → **Project Tasks → m5stack-sticks3 → General → Upload**.
   - The StickS3 appears on Windows as **"USB Serial Device (COMx)"**; PlatformIO finds the port by itself.
3. **If upload fails** ("No serial data received", "Failed to connect"): put the StickS3 in **download mode**. Keep USB connected, **press and hold the side power button** until the green LED inside flashes (StickS3.pdf page 6). Then click Upload again.
4. After upload, **single-click the side power button** to restart (single click = power on / reset).
5. The screen should show **"Mantiza T1"** and **"Waiting..."**.

## Part C: pair with your iPhone
1. iPhone: **Settings → Accessibility → Touch → AssistiveTouch** → turn **On**.
2. Same screen: **Devices → Bluetooth Devices** → tap **Mantiza T1** → **Pair**.
3. The StickS3 screen changes to **"Connected"** (green), and a round grey pointer appears on the iPhone.
4. Keyboard layout: **Settings → General → Keyboard → Hardware Keyboard** → set **English** to **U.S.** (this menu appears only while a keyboard is connected).
5. Note your **Tracking Speed** (Settings → Accessibility → Touch → AssistiveTouch → Tracking Speed). Pointer distances depend on it, so keep it the same during the test.

## Part D: run the tests
Side button = next test, front button = run it. Fill the results table below as you go.

| # | Test | How | What to look for |
|---|---|---|---|
| 1 | Corner reset | Run it | Pointer goes to the **top-left corner** |
| 2 | Square 200 | Run "Corner reset" first, then this | Pointer draws a square and **comes back to the same spot**. Note the square's size on screen |
| 3 | Click | Move the pointer over an app icon (serial `m` command or Square test), then run | The app **opens** |
| 4 | Long press | Pointer on a home-screen icon, then run | The **long-press menu** appears |
| 5 | Scroll | Open Settings, then run | The list **scrolls** |
| 6 | Type text | Open **Notes**, tap into a note (on the phone), then run | Exactly `Hello Mantiza! ABC xyz 123 @#?` appears. **Check capitals and symbols** (a known risk) |
| 7 | Paste Cmd+V | Copy some text on the iPhone, tap into a note, then run | The text is **pasted** with **no paste permission pop-up** |
| 8 | Home Cmd+H? | Open any app, then run | Experimental: does it go to the **Home Screen**? (Yes or no; both are useful answers) |

## Part E: exact moves from the PC (optional)
1. In VS Code, click the **plug icon (Serial Monitor)** in the bottom bar.
2. Type a command and press Enter:

| Command | Does |
|---|---|
| `r` | Corner reset (top-left) |
| `m 100 300` | Move right 100, down 300 (counts, not pixels) |
| `s 10 0 20` | Send one step of (10, 0) twenty times |
| `c` | Click |
| `l 1000` | Long press for 1000 ms |
| `w -3` | Scroll down 3 |
| `t Hi there` | Type "Hi there" |
| `p` | Paste (⌘V) |
| `h` | ⌘H |
| `help` | List commands |

**Measuring pointer accuracy:** run `r`, then `m 100 0` several times. Each time, note where the pointer is on screen. If the same command always moves the same distance, the pointer is predictable, which is what we need.

---

## Results
Date: **2026-11-02** · iPhone model: ____ · iOS version: ____ · Tracking Speed: ____

**Overall: PASS.** All 8 on-device tests worked as expected on the first run.

| # | Test | Pass / Fail | Notes (what happened) |
|---|---|---|---|
| 1 | Corner reset | ✅ Pass | |
| 2 | Square 200 (back to start?) | ✅ Pass | |
| 3 | Click | ✅ Pass | |
| 4 | Long press | ✅ Pass | |
| 5 | Scroll | ✅ Pass | |
| 6 | Type text (capitals? symbols?) | ✅ Pass | Capitals and symbols typed correctly, so the known Bluetooth risk did not show up |
| 7 | Paste ⌘V (no pop-up?) | ✅ Pass | |
| 8 | Home ⌘H | ✅ Pass | Goes to the Home Screen |
| – | `m 100 0` repeated: same distance each time? | Not tested yet | |
| – | Reconnects after StickS3 restart without re-pairing? | Not tested yet | |
| – | Reconnects after iPhone lock/unlock? | Not tested yet | |

**Upload note (first flash):** the first upload failed with `Write timeout` because the StickS3 was still running its factory firmware (USB ID `303A:832B`), and the upload tool can't reset that into download mode. Fix: enter download mode by hand (Part B step 3). After that upload, the StickS3 **stayed in download mode** (blank screen) even after a USB reset, until it was **fully powered off and on**. Later uploads should work without the button, because this firmware uses the USB mode the upload tool can reset (`303A:1001`).

## Troubleshooting
| Problem | Try |
|---|---|
| "Mantiza T1" not in the Bluetooth Devices list | Single-click the side power button to restart the StickS3; make sure the screen says "Waiting..." |
| Paired before but now won't connect | iPhone: Settings → Bluetooth → Mantiza T1 → **Forget This Device**, then pair again (Part C) |
| Connected, but no pointer | Check AssistiveTouch is **On** |
| Wrong characters when typing | Check the hardware keyboard layout is **U.S.** (Part C step 4). If capitals or symbols still fail, **write it down**: this is a known Bluetooth risk we are testing |
| Upload fails | Use download mode (Part B step 3); try another USB-C cable |
| Blank screen after a successful upload | The StickS3 is still in download mode. Unplug USB, **power it fully off** (long-press the side button), then turn it on again |

## Not in this test (later)
- Commands from the Mantiza iPhone app over Bluetooth (test **T2**).
- Absolute ("go to this exact point") pointer mode.
