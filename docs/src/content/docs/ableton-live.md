---
title: "Ableton Live"
description: "Driving the selected device's parameters from the E16, over a SysEx link to a Live Remote Script."
---

Two halves of one integration:

| Part | Path | Runs on |
|---|---|---|
| Device script | [`src/live-device.lua`](https://github.com/tsln-lab/oxi-e16-lua-api/blob/main/src/live-device.lua) → `scripts/live-device.lua` | the E16 |
| Remote Script | [`ableton/OXI_E16/`](https://github.com/tsln-lab/oxi-e16-lua-api/tree/main/ableton/OXI_E16) | Live (Python) |

Live follows whichever device is selected, abbreviates each parameter name to four
characters, and pushes name + value to the sixteen encoders. The name lands on the screen,
the value lands on the LED ring, and turning an encoder sets the parameter back in Live.

## Why SysEx, in both directions

**`controller.onSysex` is the only inbound callback the firmware offers**
([Callbacks](/oxi-e16-lua-api/callbacks/)). Incoming CC and notes never reach a script — the
same gap that makes MIDI clock invisible and leaves script LFOs free-running
([Patterns](/oxi-e16-lua-api/patterns/)) — so parameter names and values can only arrive as
SysEx. That part is forced, not chosen.

Using SysEx for the return path too is the choice, and it pays off on the Live side: Live
hands a control surface every SysEx message it receives, unconditionally, whereas each CC
has to be registered with `forward_midi_cc` inside `build_midi_map` before `receive_midi`
ever sees it. One framing, no MIDI map, nothing to rebuild when the mapping changes.

## Why `controller.set` does the whole display

Two properties cover both halves, and both are addressed by **script ID**, so they work from
`onInit` — before any encoder has been touched, and whatever page the user is looking at:

| Call | Effect |
|---|---|
| `controller.set(id, "n", label)` | the four characters under the encoder |
| `controller.set(id, "v", value)` | the internal 14-bit value — which the firmware *already* draws as the ring |

Neither overlay API is a better fit. `slots.update` cannot do the label half at all: it
takes an encoder **position**, which a script only learns from `enc.index` on a turn, so it
cannot paint a control nobody has touched yet ([slots](/oxi-e16-lua-api/api/slots/)) — and a
display that only appears after you fiddle with it is not a display.

`leds.update` *could* do the ring half, since [1.2.0 changed it to take a script
ID](/oxi-e16-lua-api/api/leds/) rather than a position. There is still no reason to use it.
Writing `"v"` is needed anyway so the next turn continues from where Live actually is, the
firmware draws the ring from that value for free, and taking the ring over means owning it
until an explicit `leds.reset` — on the **current page only**, where `controller.set`
reaches every page.

So: no position dependency, no page dependency, and nothing to tear down in `onPageChange`
— which is exactly where overlays leak, being keyed by physical encoder position rather
than by page. Parameter slot *N* is script ID *N*.

Every assignment carries `dis=0`, without which the firmware paints a numeric readout over
the parameter name the moment you turn ([Assignments](/oxi-e16-lua-api/assignments/)).

## Turns from controls the script never claimed

Since API 1.2.0 `onEncoderTurn` fires for **ordinary controls too**, and for recorder
playback, the Random special function and group moves. An ordinary control has no meaningful
`enc.id`, so a handler that trusts it acts on strangers
([Gotchas](/oxi-e16-lua-api/gotchas/)) — here, sending someone else's value to Live under
whatever parameter slot the stray id happened to name.

The handler range-checks first, which covers `nil` and `0`, the two plausible values for an
unclaimed control:

```lua
local id = enc.id
if not id or id < 1 or id > SLOTS then return end
```

What that cannot cover is a **stale** id landing inside 1–16, and
[open question 3](/oxi-e16-lua-api/open-questions/) has not settled which of the three the
firmware actually reports. Until it does, keep ordinary CC controls off this script's page.

## Setup

**Live** — copy the `OXI_E16` folder into your User Library:

| OS | Path |
|---|---|
| macOS | `~/Music/Ableton/User Library/Remote Scripts/OXI_E16` |
| Windows | `%USERPROFILE%\Documents\Ableton\User Library\Remote Scripts\OXI_E16` |

Restart Live, then in **Preferences → Link, Tempo & MIDI** set a Control Surface slot to
**OXI_E16** with the E16 as both Input and Output. Needs Live 11 or later (Python 3).

**E16** — build with `mise exec -- lua build.lua`, upload the generated
`scripts/live-device.lua` in the OXI App, and drop parameters `Param 1`–`Param 16` onto
encoders 1–16. The built script is about 1.6 KB of the 8000-byte budget.

Select a device in Live. The header shows the device name and the encoders show its
parameters.

## Protocol

Every message is `F0 7D <command> … F7`. `0x7D` is the SysEx ID reserved for
non-commercial use. Values are 14-bit, split MSB-first into two 7-bit bytes
(`v >> 7`, `v & 0x7F`), because SysEx data bytes cannot have the top bit set.

**Live → E16**

| Cmd | Payload | Meaning |
|---|---|---|
| `0x01` | name (≤15 ASCII) | Device name, for the header |
| `0x02` | slot, hi, lo, name (≤4 ASCII) | Full slot refresh — sent 16 at a time |
| `0x03` | slot, hi, lo | A parameter moved in Live |
| `0x04` | — | Live disconnected; the E16 shows `No Live` |

**E16 → Live**

| Cmd | Payload | Meaning |
|---|---|---|
| `0x10` | slot, hi, lo | Encoder turned |
| `0x11` | — | Send me the current device |

`slot` is 0-based (script ID − 1). The E16 sends `0x11` from `onInit` and on every page
change, because it may well boot after Live has already sent its state — asking beats
waiting, and flipping pages doubles as a manual resync.

Neither side acts on its own outbound commands, so a MIDI loopback cannot make the script
talk to itself. Nor can an inbound value: 1.2.0 states that `controller.set` is a direct
setter and **does not raise `onEncoderTurn`**
([controller](/oxi-e16-lua-api/api/controller/)), so writing a value from Live cannot bounce
straight back out as a turn.

## Resolution

The assignments declare `l=0 h=127`, so `enc.scaled * 129` covers the full 14-bit range
exactly (`127 × 129 = 16383`). That matches ordinary MIDI resolution — fine for a filter
sweep, coarse for a long delay time.

The wire protocol is 14-bit throughout, so **Live → E16** is already high-resolution:
automation moves the ring smoothly regardless. Only the encoder's own output is quantized to
128 steps, and whether anything finer is reachable at all depends on
[open question 12](/oxi-e16-lua-api/open-questions/) — how a detent's step size relates to
the declared range. If the step turns out to be a fixed internal amount, raising `h` buys no
extra distinct values and 128 steps is simply what a script-side encoder gives you.

## Feedback and flooding

Two problems, both handled on the Live side.

**Echo.** Setting a parameter fires Live's own value listener, which would push the value
straight back. The script records what the controller asked for and drops the echo if the
value is unchanged. When Live *snaps* the value — quantized parameters do — the encoded
result differs, the correction is sent, and the ring shows where the parameter actually
landed. The suppression is exact rather than time-based, so there is no window in which a
real move gets swallowed.

**Flooding.** Parameter listeners only mark a slot dirty; messages go out from
`update_display`, Live's ~100 ms tick. Sending from the listener instead would put a SysEx
message on the wire for every automation frame of every visible parameter.

The E16 direction needs no equivalent, because a managed control's callback fires **only
when the mapped output value changes** ([Callbacks](/oxi-e16-lua-api/callbacks/)) — at most
128 messages for a full sweep, not one per detent. If it ever does,
[`system.update()`](/oxi-e16-lua-api/api/system/) can now coalesce turns onto a tick.

## Limits and what is not done yet

- **Unverified on hardware.** Whether SysEx sent over USB reaches `controller.onSysex` at
  all, and on which transport, is
  [open question 11](/oxi-e16-lua-api/open-questions/). Run
  [`tests/sysex_in_probe.lua`](https://github.com/tsln-lab/oxi-e16-lua-api/blob/main/tests/sysex_in_probe.lua)
  first — it counts inbound messages in the header, so it separates "the link is dead"
  from "the protocol is wrong".
- **First 16 parameters only.** No banking. Devices with more parameters are truncated;
  page changes could select banks, since `onPageChange` already fires a resync.
- **Names, not values.** An encoder has one 4-character label, so the name is on the screen
  and the value is on the ring. Since 1.2.0 it could do both:
  [`slots`](/oxi-e16-lua-api/api/slots/) documents a `system.update()` countdown that shows
  a value while turning and reverts to the label afterwards. Worth pairing with Live's
  `str_for_value`, which would put a real `2.5k` or `-12` on the screen instead of a raw
  0–127 — at the cost of a per-value string on the wire and an overlay to tear down on page
  change.
- **Selected device, not the blue hand.** Live's "appointed device" is a separate
  mechanism; this follows the device you click.
- **No press actions.** `p=true` assignments plus `onEncoderPress` would give
  reset-to-default, using Live's `parameter.default_value`.
