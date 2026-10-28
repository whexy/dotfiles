---
name: iphone-use-setup
description: Choose the iPhone that iPhone Use drives in this session and bring its WebDriverAgent back when it does not answer. Use before the first phone tool in a conversation, and when pua_ready reports pua_unreachable, not_ready or phone_locked.
---

# Connect a phone

Each phone runs WebDriverAgent on its own, listening only on its Tailscale
address; no computer stays attached. A session starts with no phone selected.

1. Call `pua_phones`. Ask the user which phone to use, unless they named one in
   this conversation. Never pick one yourself.
2. Call `pua_select_phone` with their answer, then `pua_ready`.

`pua_setup` and `pua_doctor` are unavailable here, and xcodebuild is never part
of this flow.

## When the phone does not answer

`pua_phones` shows `answering: false`, or `pua_ready` fails with
`pua_unreachable` or `not_ready`:

1. Call `pua_launch_phone` once. It works only on a Mac paired with the phone
   and reports so elsewhere.
2. If it fails, tell the user what it reported and the fix that matches:
   - The phone is locked, or iOS asks for the passcode to allow UI automation:
     the user unlocks it or enters the passcode.
   - Tailscale is off on the phone: the user turns it on.
   - No paired Mac here: the user runs `iphone-wda launch <phone>` on one.
3. After the user acts, call `pua_ready` again.

`phone_locked` from `pua_ready` needs only the user to unlock the phone; ask,
then call `pua_ready` again.
