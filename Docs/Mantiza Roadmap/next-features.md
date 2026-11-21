# Next features: research and plan (2026-11-21)

What to add to Mantiza next, in order, and why. Based on what Mantiza does today and on research into
2026 phone agents, AI gadgets, iOS 27 and the StickS3's hardware. Sources are at the end.

Rules that still apply to all of it: users get only the app, its widget and the StickS3, with
Developer Mode off; public iOS APIs only; our own code.

## The main finding

The StickS3 has far more hardware than Mantiza uses. Today it is only the iPhone's mouse and keyboard.
It also has [S1][S2]:

| Part | What it is | Used today? |
|---|---|---|
| Microphone | MEMS mic, ES8311 audio chip | No |
| Speaker | 1 W speaker with amplifier | No |
| Screen | 1.14-inch colour, 135 × 240 | Only basic status |
| Motion sensor | BMI270, 6-axis | No |
| Infrared | IR transmitter and receiver (like a TV remote) | No |
| Battery | 250 mAh | Yes |

## Top 5, in the order to build them

### 1. Press to talk on the StickS3
Hold the button, speak, let go: the task runs. The StickS3's microphone sends the audio to the app over
Bluetooth, the iPhone turns it into text (Apple's speech recognition, on the phone), and the result
sound plays on the StickS3's speaker.

- **Why:** the biggest 2026 trend in AI gadgets is a small clip-on with one big talk button and the
  AI living on the phone [S3][S4][S5]. We already have the hardware; this makes the StickS3
  something people carry, not just a mouse.
- **To check first:** Bluetooth bandwidth for compressed 16 kHz speech (expected fine), and that the
  app can run speech recognition while it is in the background.

### 2. The StickS3 screen as the task remote
- Shows the task as it runs ("Opening WhatsApp… step 3").
- Shows approval questions ("Pay ₹240 on Swiggy?"); its buttons answer yes / no.
- Shake to stop (motion sensor).
- **Why:** today an approval needs the phone, whose screen is busy with the task.

### 3. TV and AC by infrared
"Turn on the TV", "AC to 24": the StickS3 sends the infrared code.
- Learns any remote: point the old remote at the StickS3 once and press the button.
- **Why:** something no phone assistant does, and nearly free: the parts are already in the StickS3.
- Note from M5Stack: turn the speaker's amplifier off while receiving infrared [S2].

### 4. Apple's on-device model as a third brain
iOS 27 lets apps send images (screenshots) to Apple's on-device model [S6][S7][S8]. Uses:
- simple steps with no internet
- private screens (chats) never leave the phone; research questions sending phone screenshots to
  the cloud at all [S9]
- easy steps at no cost

It works alongside the two brains (Luna Decisions, Gemini 3.5 Flash-Lite); it doesn't replace them.
Apple warns the on-device model changes with iOS updates, so prompts need checking after each [S8].

### 5. Scheduled tasks
"Every morning at 8: read my calendar and play my playlist."
- Works today through the user's own Shortcuts automation: Time of Day → Open URL →
  `mantiza://run?q=...` (Mantiza already handles this link). It doesn't need the App Intents index we
  haven't written.
- In the app: a "Schedules" page that makes the link for the user and explains the two taps in
  Shortcuts.
- **Why:** Android and Chinese "AI phones" are moving to agents that act across apps on their own
  [S10][S11].

## Good practice to add

| What | Why |
|---|---|
| **Remember facts about the user**: "Mom = Asha Jagtap", the usual Swiggy order, home and work addresses. Editable in Device. | Phone agents barely remember anything across sessions [S12]. Mantiza already learns *how* to do things (routines, app notes); this adds *who and what*. |
| **Check the outcome on every route** | The 2026 surveys name outcome checking as the key safety practice [S13][S14]. Mantiza checks alarms, the flashlight and app opening; the AI screen route still trusts the AI's "done". |
| **Update the StickS3 from the app** over Bluetooth | Customers can't plug it into a PC. Every hardware product needs this. |
| **Hindi and Hinglish by voice** | Users in India will speak this way; Apple's speech recognition supports Hindi on the phone. |

## Not now

**An always-listening StickS3.** It's popular with AI pendants, but it raises consent and privacy
questions about recording people nearby [S15], and the 250 mAh battery wouldn't last. Press to talk
gets most of the value.

## Suggested order

1. Press to talk (#1) and the StickS3 screen as task remote (#2), together: both are mostly
   StickS3 firmware plus a small part of the app.
2. TV and AC by infrared (#3).
3. Apple's on-device model (#4).
4. Scheduled tasks (#5), facts about the user, then the rest of the good-practice list.

## Sources

- [S1] [M5Stack StickS3 docs](https://docs.m5stack.com/en/core/sticks3)
- [S2] [CNX Software: StickS3 with speaker and mic](https://www.cnx-software.com/2026/01/23/m5stack-sticks3-esp32-s3-mini-iot-dev-kit-features-1-14-inch-color-display-speaker-and-mic-for-voice-interaction/), [Core Electronics: StickS3](https://core-electronics.com.au/m5sticks3-esp32-s3-mini-iot-development-kit.html)
- [S3] [TechCrunch: AI wearables and gadgets, 2026-10](https://techcrunch.com/2026/10/25/the-hottest-ai-wearables-and-gadgets-you-should-know-about)
- [S4] [eWeek: Motorola's AI necklace, CES 2026](https://www.eweek.com/news/motorola-ai-wearable-ces-2026/)
- [S5] [The Gadgeteer: best AI wearables 2026](https://the-gadgeteer.com/2026/05/05/best-ai-wearables-2026/)
- [S6] [Apple: analysing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting.md)
- [S7] [Apple: WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/)
- [S8] [Apple: Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels.md)
- [S9] [arXiv 2604.17817: phone agents and screenshots](https://arxiv.org/html/2604.17817)
- [S10] [Android Developers Blog: the intelligent OS, 2026-02](https://android-developers.googleblog.com/2026/02/the-intelligent-os-making-ai-agents.html)
- [S11] [Computerworld: AI agents in China's phones](https://www.computerworld.com/article/4203560/how-ai-in-china-is-killing-smartphone-apps.html)
- [S12] [MemGUI-Bench: memory of mobile GUI agents](https://arxiv.org/html/2602.06075v1)
- [S13] [FITEE 2026: survey of GUI agents' execution, verification and risk](https://journal.hep.com.cn/fitee/EN/10.1631/ENG.ITEE.2026.0103)
- [S14] [OS-Sentinel, ACL 2026](https://aclanthology.org/2026.acl-long.431.pdf)
- [S15] [Analytics Insight: AI pendants and conversations](https://www.analyticsinsight.net/artificial-intelligence/ai-pendants-can-remember-your-conversations)
