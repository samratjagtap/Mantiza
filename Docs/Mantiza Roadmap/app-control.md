# Mantiza: Controlling iPhone Apps

_Last updated: 2026-10-27 · Related: [plan.md](plan.md#33-control-everything-except-sensitive-apps), [tech-stack.md](tech-stack.md), [Artemis plan](../Google%20Artemis%20Analysis/plan.md)_

## 1. Problem statement

Mantiza should **control the apps installed on the iPhone**: open them, tap, type, scroll and finish tasks inside them, the way a person would. Sensitive actions (payments, banking and similar) must never be done automatically. Instead, Mantiza sends a notification and waits for the user to approve.

**What we want**
- Control of apps that are on the iPhone itself, not websites in a remote or hidden browser.
- Browser tasks only when the user asks for them, e.g. "open Chrome and search for xyz", done in the browser app on the phone like any other app.
- Mantiza does not have to be an App Store app if a non-App Store route works better.
- Sensitive steps send an Approve / Cancel notification (like Grok) and never run without the user.

**Why this is hard**
- On iPhone, every app runs in a sealed box (sandbox). An app **cannot see another app's screen, cannot tap inside another app, and cannot take over again once it is in the background**.
- Android has a developer "remote control" mode (ADB) and background accessibility helpers. iPhone gives normal apps nothing like this.
- Apple does this on purpose, for privacy and security.

## 2. How Artemis does it (and why it does not carry over)

[Google Artemis](https://github.com/google/artemis) is like a robot at a desk holding an Android phone by a cable:

1. The phone is plugged into a computer by USB.
2. Through ADB, the computer takes screenshots, reads every button on screen and sends taps and typing.
3. An AI looks at the screen, decides the next step ("tap Search"), the computer sends the tap, and the loop repeats until the task is done.

It works on any app because it acts like a finger, not by asking the app for permission. iPhone has no ADB, so this needs one of the routes in section 4.

## 3. A note on "works even when the phone is off"

Assistants like Grok keep working with the phone off because the work happens **on the company's servers** (their own browser, connected accounts). They do not tap inside the apps on your phone.

To control apps *on* the iPhone, the **phone must be switched on**. It can be locked, charging or in a pocket.

## 4. Ways to tackle it

| # | Way | Controls any app? | Needs | Who it suits |
|---|---|---|---|---|
| 1 | Mac + iPhone Mirroring | Yes | A Mac (macOS 15+), same Apple ID, iPhone nearby | Mac owners |
| 2 | Apple testing tool (XCUITest / WebDriverAgent) | Yes | Developer signing, Developer Mode, a computer to start it | Us, testers, power users |
| 3 | Bluetooth "fake mouse" device | Yes | A small extra gadget (e.g. ESP32) | Experiment |
| 4 | Apple's official routes (App Intents, Shortcuts, app links) | Only what each app allows | Nothing extra | Everyone |

### Way 1: Mac + iPhone Mirroring
- iPhone Mirroring shows the iPhone screen in a window on the Mac, where it can be clicked and typed in, and it works while the iPhone is locked.
- A Mantiza program on the Mac takes screenshots of that window, the AI picks where to tap (e.g. `gemini-robotics-er`), and the program clicks there. This is the same loop as Artemis.
- **Good:** works with every app; Apple-supported; nothing special installed on the phone.
- **Limits:** a Mac must be awake and nearby; not available in the EU; only sees the screen as a picture (no button list), so it relies on the vision model and is a bit slower.

### Way 2: Apple's testing tool (XCUITest / WebDriverAgent)
- A small test helper is installed on the iPhone with a developer account (free Apple ID: re-install every 7 days; paid $99/year account: once a year).
- While running, it can **read every button and text in any app and tap, type and swipe**, over USB or Wi-Fi. This is the closest thing iPhone has to ADB, and how "Artemis for iOS" would work (it is on Google's Artemis roadmap).
- It is started from a computer, which can be a Mac, Windows or Linux (via tools like `pymobiledevice3` or `go-ios`).
- **Good:** most accurate and fastest; reads real buttons, not just screenshots.
- **Limits:** Developer Mode must be on; needs a computer to start it; iOS may stop it; cannot be offered to the general public.

### Way 3: Bluetooth "fake mouse" device
- iPhone's AssistiveTouch accepts a Bluetooth mouse, and a pointer can tap anywhere. A small board pretends to be a mouse and keyboard, and Mantiza tells it where to tap.
- Mantiza sees the screen with screen broadcasting (ReplayKit, shows a red recording indicator).
- **Good:** phone plus a small gadget, no computer.
- **Limits:** experimental, extra hardware, fiddly setup, visible pointer.

### Way 4: Apple's official routes (always tried first)
- App Intents and Shortcuts actions run real actions in apps that offer them. Since iOS 27, Siri's AI only works through App Intents, so more apps are adding them.
- App links (URL schemes, universal links) open apps straight at a screen, e.g. a search page.
- **Good:** instant, reliable, keep working when apps change their screens, App Store-safe.
- **Limits:** only covers what each app chooses to offer.

### What will not work
| Option | Why not |
|---|---|
| A normal App Store app tapping other apps | Not allowed by iOS (sandbox) |
| Background accessibility helper like Artemis's | Not allowed on iOS |
| Jailbreak | Only some iOS versions, breaks security and banking apps, not usable for normal users |
| Triggering Voice Control from an app | Not possible; only the user can use it |
| Remote / hidden browser automation | Out of scope: we only control apps on the phone |

## 5. Sensitive actions: approve by notification

In every way above, a safety check runs **before every tap**:
- **Never touched:** banking, UPI and payment apps, brokerages and crypto, password managers and authenticators, Wallet, Health, government ID apps.
- **Ask first:** placing orders, sending messages to others, anything that cannot be undone. Mantiza pauses and sends a notification with **Approve / Cancel** (e.g. "Pay ₹240 on Blinkit?") and only continues after Approve.
- Payment screens are left for the user to finish. Mantiza never stores payment details or one-time passwords.

## 6. Recommended setup

- **Mantiza iPhone app = the front end:** voice and text input, the pattern widget, live progress and approval notifications.
- **Mantiza agent on a computer = the hands:** Way 2 (WebDriverAgent) for accuracy, or Way 1 (iPhone Mirroring) for the simplest setup on a Mac.
- **Order of trying for each step:** Way 4 first (instant and reliable), then tapping through Way 1 or 2 when an app offers nothing.
- Way 3 stays an experiment for a no-computer setup.

## 7. Open questions
- Do we have a Mac? This decides whether Way 1 is available or we start with Way 2 from a Windows PC.
- Should the tap-based modes be offered to all users, or only to us and power users at first?
- How do we keep the WebDriverAgent helper running reliably (restarts, re-signing)?
