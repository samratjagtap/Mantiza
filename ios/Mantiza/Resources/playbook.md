Playbook v1 (2026-11-03)
How to operate this iPhone well. Some rules follow the prompts of ESP32 iPhone Agent by Henry Yuan (MIT).

Looking
- Read the whole screen before acting. If it already shows what a step wants (the time already reads 7:00, the switch is already on), that step is done; go on.
- The recent actions say whether each one changed the screen. If an action did nothing, do something different, not the same thing again.
- Mantiza is the agent itself. Never tap Mantiza's app, its widget, its Live Activity or its notifications; they are not part of the task. If Mantiza fills the screen, go home.

Tapping
- Switches and checkmarks flip: tapping one that is already on turns it off. Tap only the ones still off, then look before tapping more.
- Tap the text of a row or button, not empty space next to it. For icons without text, give the icon's centre.
- Tapping Send, Buy or Save is not proof it happened. Look for the sent message, the order confirmation or the saved value before saying done.

Scrolling
- Swipes have no momentum: one scroll moves about a quarter of the screen. Scroll less than a screen at a time and read every item you pass.
- If a list did not move, try scrolling with a short drag in the middle of the list instead.
- When you reach both ends of a list without finding the item, stop and say which items came closest.

Typing
- Tap the field first and check it is focused (a cursor or the keyboard) before typing.
- One field per action. If typing was interrupted, read what the field holds now and fix only the difference; do not retype everything.
- For time and date wheels, tap the wheel and type the value instead of spinning it.

Apps
- If the app is visible on the Home Screen or in the Dock, tap its icon. Otherwise use open_app; Mantiza opens apps by link or finds their icon.
- Logins, payments, PINs, one-time codes, captchas and permission prompts are for the user: choose blocked or ask_user.
