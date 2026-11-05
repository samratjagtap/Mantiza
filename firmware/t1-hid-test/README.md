# T1 test firmware: StickS3 as an iPhone mouse + keyboard

Phase 0, test **T1** from the [v2 plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md): does the StickS3 work as a **Bluetooth LE mouse + keyboard** for an iPhone (AssistiveTouch pointer)?

**Pass condition (from the plan):** the pointer reaches any point accurately; English typing works **including capitals and symbols**; ⌘V pastes.

## What the firmware does
- Shows up on Bluetooth as **"Mantiza T1"** (a mouse + keyboard).
- **Side button (KEY2):** select the next test. **Front button (KEY1):** run the selected test.
- Screen: connection status, battery %, test list, the last action and how long it took.
- USB serial commands for exact moves (Part E).
- **T1b** (added 2026-11-03): tests starting with **"b "** come first in the menu; the T1 tests follow (the list scrolls). See [T1b](#t1b-keyboard-shortcuts-and-extra-buttons).

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
Date: **2026-11-02** · iPhone model: **iPhone 14 Plus** · iOS version: **27.2** · Tracking Speed: **max** (slider all the way right; keep it there)

**Overall: PASS.** All 8 on-device tests and all 3 extra checks worked as expected.

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
| – | `m 100 0` repeated: same distance each time? | ✅ Pass | Moves the same distance each time, so the pointer is predictable |
| – | Reconnects after StickS3 restart without re-pairing? | ✅ Pass | |
| – | Reconnects after iPhone lock/unlock? | ✅ Pass | |

**Upload note (first flash):** the first upload failed with `Write timeout` because the StickS3 was still running its factory firmware (USB ID `303A:832B`), and the upload tool can't reset that into download mode. Fix: enter download mode by hand (Part B step 3). After that upload, the StickS3 **stayed in download mode** (blank screen) even after a USB reset, until it was **fully powered off and on**. Later uploads should work without the button, because this firmware uses the USB mode the upload tool can reset (`303A:1001`).

---

## T1b: keyboard shortcuts and extra buttons
Test **T1b** from the [plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md) (section 4.4, items 7–8): can Mantiza use **keys and extra mouse buttons** instead of moving the pointer? Each one that works saves AI steps and time.

### Before you start: pair again (one time)
The T1b firmware describes itself differently to the iPhone (extra buttons, Fn key), so the old pairing no longer fits.
1. iPhone: **Settings → Bluetooth → Mantiza T1 → ⓘ → Forget This Device**.
2. Pair again: **Settings → Accessibility → Touch → AssistiveTouch → Devices → Bluetooth Devices → Mantiza T1**.
3. For tests 3–7, turn on **Full Keyboard Access**: **Settings → Accessibility → Keyboards → Full Keyboard Access**. Turn it **off** again after T1b (it draws a focus box around items).

### Tests on the device
Side button = next test, front button = run it.

| # | Menu name | Before running | What to look for |
|---|---|---|---|
| 1 | b Search Notes | Be on the Home Screen or in any app | ⌘+Space opens Search, types "Notes", presses Enter → **Notes opens**. Note the time shown on the device |
| 2 | b Type+Return | Open Messages, a chat **with yourself**, tap the text box | Types "Mantiza T1b test" and presses Return → is the message **sent**, or does it only add a new line? |
| 3 | b Tab (FKA) | Full Keyboard Access on | A **focus box** moves to the next item |
| 4 | b Fn+H Home | Full Keyboard Access on, open any app | **Home Screen**? (Fn is experimental: it may not work from our device) |
| 5 | b Fn+C Control | Full Keyboard Access on | **Control Center** opens? |
| 6 | b Fn+N Notific. | Full Keyboard Access on | **Notification Center** opens? |
| 7 | b Fn+Up Switcher | Full Keyboard Access on | **App Switcher** opens? |
| 8 | b Button 4 | See "Extra buttons" below | The action you assigned happens |
| 9 | b Button 5 | See "Extra buttons" below | The action you assigned happens |

### Extra buttons (tests 8–9)
1. iPhone: **AssistiveTouch → Devices → Mantiza T1 → Customize Additional Buttons…**
2. When the iPhone asks you to press a button on the device, select **b Button 4** on the StickS3 and press the front button.
3. Pick an action, e.g. **App Switcher**. Repeat for **Button 5** (e.g. **Notification Center**).
4. Run tests 8 and 9: does the action happen?

### If Fn doesn't work: remap the commands (serial)
Full Keyboard Access lets you change its shortcuts. **Settings → Accessibility → Keyboards → Full Keyboard Access → Commands** → pick e.g. **Home** → it asks you to press the new keys. Then send a combination from the Serial Monitor (Part E), for example `k ctrl+alt+h`. Then check that `k ctrl+alt+h` goes Home.

New serial commands: `k <combo>` (e.g. `k cmd+space`, `k enter`, `k tab+h`, `k fn+c`, `k ctrl+alt+h`), `K <ms> <combo>` (hold the keys for a while, e.g. while the iPhone is waiting for keys) and `b <1-8>` (mouse button). Type `help` for the full list.

### T1b results
Date: **2026-11-03** · iPhone 14 Plus · iOS 27.2

**Overall: mostly PASS.** Search, Return, Tab and extra buttons work. The Fn/🌐 key from our device is **ignored** by the iPhone, so the default Full Keyboard Access shortcuts (Fn+H, Fn+C, Fn+N, Fn+↑) don't work. Next: remap them.

| # | Test | Works? | Notes |
|---|---|---|---|
| 1 | ⌘+Space → type → Enter opens the app | ✅ | |
| 2 | Return sends in Messages | ✅ | |
| 3 | Tab moves focus (Full Keyboard Access) | ✅ | |
| 4 | Fn+H → Home | ❌ | Nothing happens |
| 5 | Fn+C → Control Center | ❌ | Nothing happens |
| 6 | Fn+N → Notification Center | ❌ | Nothing happens |
| 7 | Fn+↑ → App Switcher | ❌ | Nothing happens |
| 8 | Button 4 can be assigned + works | ✅ | Action: |
| 9 | Button 5 can be assigned + works | ✅ | Action: |
| – | Remapped command (e.g. `k ctrl+alt+h`) works | Not tested yet | |
| – | T1 tests still work after the update | ✅ | |

## T2: commands from the iPhone app
Test **T2** from the [plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md): can the Mantiza app send commands to the device **while iOS uses the same device as its mouse + keyboard**, even when the app is in the background?

The firmware adds a private **command channel** (a second Bluetooth service). The test app [apps/phase0-test](../../apps/phase0-test/) writes the same text commands as the serial port (`m 200 0`, `t hello`, …) and the device answers (`pong 3`, `ask 5`, `ok …`).

### Before you start
1. **Pair again** (the device's Bluetooth layout changed): **Settings → Bluetooth → Mantiza T1 → ⓘ → Forget This Device**. Then **AssistiveTouch → Devices → Bluetooth Devices → Mantiza T2**.
2. Install the **Mantiza Test** app (Claude builds it with xtool, [Windows setup](../../Docs/Setup/windows-xtool-setup.md)). Allow **Bluetooth** when it asks.

### The tests
| # | Where | Do | Pass |
|---|---|---|---|
| T2a | App | Check **Device: Ready ✅** and **Found by**, then tap **Ping ×10** | All 10 come back; note avg and max ms |
| T2b | App | **Move pointer in a square**. Tap the text box, then **Type "Hello from the app"** | Pointer moves; the text appears in the box |
| T2c | StickS3 | Pick **2 Auto ask 5s**, press front. Leave the app (Home Screen, use other apps) for **5 minutes**. Then lock the phone for 1 minute | Bottom line **A answered/sent** keeps rising with the app in the background. Note what happens while locked |
| T2d | App | **Start heartbeat**, then leave the app for 1 minute | The device's **B** number: does it keep rising, or stop? (Stopping is expected: an app can't run its own timer in the background. Mantiza would rely on T2c-style asks, or on screen capture keeping it awake, T3) |

On the device: **App:on** (top right) = the app is listening. Bottom line: `A answered/sent last-ms  B beats`.

### T2 results
Date: ____ · iPhone 14 Plus · iOS ____

| # | Test | Result | Notes |
|---|---|---|---|
| T2a | Found by / Ready | | Found by: |
| T2a | Ping ×10 | | avg ___ ms, max ___ ms |
| T2b | Pointer square from the app | | |
| T2b | Typing from the app | | |
| T2c | Asks answered in the background (5 min) | | A ___ / ___ |
| T2c | While locked | | |
| T2d | App heartbeat in the background | | Stopped after ___ |
| – | Mouse still works normally with the app linked | | |

## Troubleshooting
| Problem | Try |
|---|---|
| App says "Command channel not found" | The iPhone remembers the old layout: Forget **Mantiza T1/T2** in Bluetooth settings, pair again, then tap **Connect again** |
| App stays "Not connected" / "Scanning…" | Check the device shows **Connected** (paired as mouse first), then tap **Connect again** |
| "Mantiza T1" not in the Bluetooth Devices list | Single-click the side power button to restart the StickS3; make sure the screen says "Waiting..." |
| Paired before but now won't connect | iPhone: Settings → Bluetooth → Mantiza T1 → **Forget This Device**, then pair again (Part C) |
| Connected, but no pointer | Check AssistiveTouch is **On** |
| Wrong characters when typing | Check the hardware keyboard layout is **U.S.** (Part C step 4). If capitals or symbols still fail, **write it down**: this is a known Bluetooth risk we are testing |
| Upload fails | Use download mode (Part B step 3); try another USB-C cable |
| Blank screen after a successful upload | The StickS3 is still in download mode. Unplug USB, **power it fully off** (long-press the side button), then turn it on again |

## Not in this test (later)
- Absolute ("go to this exact point") pointer mode.
