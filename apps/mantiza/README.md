# Mantiza app (iPhone)

The real Mantiza app: you type what you want, and Mantiza does it on the iPhone through the Mantiza device. This is Phase 1 of the [plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md). The test app for Phase 0 is [phase0-test](../phase0-test/README.md).

## How a task runs
1. **Plan:** the big brain turns the request into a subtask: which app, the goal, the exact text to type, and whether it needs your OK.
2. **Eyes on:** if screen sharing is off, the app shows Apple's picker and the device clicks "Share Entire Screen". Sharing then stays on between tasks.
3. **Open the app** with the keyboard: Home, Search, the app's name, Enter. No AI is needed.
4. **Per step:**
   - Wait until the screen stops changing.
   - Read the text on screen with Apple's on-phone text recognition.
   - Draw numbered boxes around the text.
   - Ask the fast brain what to do: tap box N, tap an icon, type, scroll, or done.
   - If the fast brain is unsure, or the target is an icon with no text, the big brain finds the spot on the screenshot.
   - The device taps or types.
5. **Safety:**
   - Before a risky tap (send, pay, delete…), Mantiza asks you. The question appears as a notification with Approve / Don't buttons (long-press the banner), and in the Task tab.
   - Mantiza stops if a tap doesn't change the screen twice.

| Part | What |
|---|---|
| Fast brain | OpenAI GPT-6 Luna Decisions. It uses `OPENAI_API_KEY` if set, otherwise OpenRouter (`OPENROUTER_API_KEY`) |
| Big brain | Gemini 3.5 Flash-Lite through Google AI Studio (`GEMINI_API_KEY`) |
| Eyes | ScreenCaptureKit + Apple Vision text recognition |
| Hands | The Mantiza device as a Bluetooth mouse and keyboard ([firmware](../../firmware/t1-hid-test/README.md)) |

These choices come from the [brain bench](../../tools/brain-bench/README.md).

## First-time setup on the iPhone
1. **Pair the device:** Settings → Bluetooth.
2. **Turn on AssistiveTouch:** Settings → Accessibility → Touch → AssistiveTouch. Set **Tracking Speed** to the highest.
3. **Open Mantiza** and allow Bluetooth and notifications.
4. **Device tab:**
   - Check that it says **Ready ✅**.
   - Tap **Calibrate pointer**. It takes about 10 s; don't touch the screen.
   - Tap **Start** under Eyes, and the device presses the share button.
5. **Task tab:** type a request and tap **Go**.

## Keys
The keys are in `C:\Users\PC\.mantiza\keys.env`, outside the repo. `scripts/make_secrets.py` copies them into `Sources/Mantiza/Secrets.swift`, which is in `.gitignore`.

**Development only:** this puts the keys inside the app on your own phone. Before anyone else gets the app, the keys move to a small key server (plan, section 4.3).

## Build and install (Windows, through WSL)
You need the [xtool setup](../../Docs/Setup/windows-xtool-setup.md), the iPhone bridge running, and the phone unlocked.
```
cd /mnt/c/Users/PC/Desktop/mantiza/Mantiza/apps/mantiza
sh scripts/build.sh
```

## Known gaps (next steps)
- **Device screen status and approve/cancel buttons:** needs a firmware update. For now, approval is on the phone.
- **The device's own "4 Share screen" menu item** still searches for "Mantiza Test" (the test app). Update the firmware to open "Mantiza".
- **Scrolling direction** and **typing non-English text** aren't handled yet. Hindi comes later, by paste.
- **The "Share Entire Screen" spot** is scaled from the 14 Plus. On other iPhones it should be measured once.
- **Learned workflows**, the **widget** and **voice** are Phase 2.
