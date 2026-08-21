---
title: "Ableton Live"
description: "Driving the selected device's parameters from the E16, over a SysEx link to a Live Remote Script."
---

Two halves of one integration:

| Part | Path | Runs on |
|---|---|---|
| Device script | [`src/live-device.lua`](https://github.com/tsln-lab/oxi-e16-lua-api/blob/main/src/live-device.lua) → `scripts/live-device.lua` | the E16 |
| Remote Script | [`ableton/OXI_E16/`](https://github.com/tsln-lab/oxi-e16-lua-api/tree/main/ableton/OXI_E16) | Live (Python) |

Live abbreviates names to four characters and pushes name + value to the sixteen encoders.
The name lands on the screen, the value lands on the LED ring, and turning an encoder sends
the value back.

## Two modes, on E16 pages

Pages are the device's own mode mechanism, so no toggle had to be invented — and
`onPageChange` already fired a resync:

| Page | Shows |
|---|---|
| 1 | The selected device's parameters, in order |
| 2 | The mixer: tracks 1–4 |
| 3 | The mixer: tracks 5–8, and so on up to page 12 |

**Drop the same sixteen assignments onto every page you want to use.** Sharing script IDs
across pages is deliberate: `controller.set` writes to *every* destination holding an ID
([controller](/oxi-e16-lua-api/api/controller/)), so one repaint covers all of them, and
only the page you are looking at is visible anyway. Each page change repaints for that page.

### The mixer layout

The E16's encoders are a 4×4 grid numbered left to right, top row first, so a column is
`{1, 5, 9, 13}`. Each column is one track, in the order **Live's own mixer shows them** —
pan above the sends, sends in A-to-B order, fader at the bottom:

| Row | Encoders | Control |
|---|---|---|
| Top | 1–4 | Pan |
| | 5–8 | Send A — labelled from the return track |
| | 9–12 | Send B |
| Bottom | 13–16 | Volume — labelled with the track name |

Send labels drop Live's leading letter designator, since "A Reverb" would spend half of
four characters on a letter the row already tells you. Columns with no track are blank.

Mixer controls are `DeviceParameter`s exactly like device parameters, so reading, writing,
listening and echo suppression are shared — only the binding and labelling differ.

## Why SysEx, in both directions

**`controller.onSysex` is the only inbound callback the firmware offers**
([Callbacks](/oxi-e16-lua-api/callbacks/)). Incoming CC and notes never reach a script — the
same gap that makes MIDI clock invisible and leaves script LFOs free-running
([Patterns](/oxi-e16-lua-api/patterns/)) — so parameter names and values can only arrive as
SysEx. That part is forced, not chosen.

Using SysEx for the return path too is the choice, and it pays off on the Live side: no
MIDI map. Each CC would have to be registered with `forward_midi_cc` inside
`build_midi_map` before `receive_midi` ever saw it, and rebuilt whenever the mapping
changed. SysEx needs none of that. One framing, both directions.

:::caution[`ableton.v2` drops unregistered SysEx — override `receive_midi_chunk`]
Live delivers batched inbound MIDI to `receive_midi_chunk`, and **`ableton.v2`'s
implementation routes SysEx only to registered control elements**. Anything else is
discarded with a `Got unknown sysex message` warning in Log.txt. It does *not* fall
through to `receive_midi`.

A script like this one, which registers no control elements on purpose, therefore receives
nothing at all if it defers to the base class — the messages arrive, Live logs them, and
the handler never runs. Dispatch them yourself:

```python
def receive_midi_chunk(self, midi_chunk):
    for midi_bytes in midi_chunk:
        self.receive_midi(midi_bytes)
```

Nothing is lost by not calling the base version: with no elements there is nothing for it
to dispatch to, and queued outbound MIDI is flushed by `update_display` on Live's tick.
Measured 2026-08-20 against Live 12.
:::

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
| `0x10` | page, slot, hi, lo | Encoder turned |
| `0x11` | page | Send me this page's state |

`slot` is 0-based (script ID − 1). The E16 sends `0x11` from `onInit` and on every page
change, because it may well boot after Live has already sent its state — asking beats
waiting, and flipping pages doubles as a manual resync.

**Both E16 messages carry the page**, which is what makes the mode switch safe rather than
merely convenient. Slot 3 is a device parameter on page 1 and a track's pan on page 2, so a
turn that overtakes a page change would otherwise be applied to the wrong thing entirely.
Live drops a turn whose page does not match what it has bound, and catches up.

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

- **Live → E16 verified on hardware, 2026-08-20.** SysEx over USB reaches
  `controller.onSysex` with framing intact and `0x7D` unaltered, and Live's control-surface
  output arrives by that same path: moving a parameter in Live raised `onSysex` on the
  device, which also means device selection had bound the parameter listeners
  ([Callbacks](/oxi-e16-lua-api/callbacks/)). Not yet exercised on hardware: the display
  itself, and the **E16 → Live** direction. If something misbehaves, run
  [`tests/sysex_in_probe.lua`](https://github.com/tsln-lab/oxi-e16-lua-api/blob/main/tests/sysex_in_probe.lua)
  in a spare scene — it counts inbound messages in the header, which separates "nothing is
  arriving" from "the protocol is wrong".
- **Sixteen parameters, starting after the on/off switch.** Live puts that switch at
  `parameters[0]` on every device, and it is not worth an encoder — `SKIP_PARAMS` at the
  top of `oxi_e16.py` drops it, and setting it to `0` puts it back. Beyond that there is no
  banking, so devices with more parameters are truncated; page changes could select banks,
  since `onPageChange` already fires a resync. The mixer banks four tracks per page, so
  that limit only bites on devices.
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
  reset-to-default via Live's `parameter.default_value`, and mute or solo in mixer mode —
  `track.mute` and `track.solo` are plain booleans. Note that a per-encoder *Special*
  function consumes the push ([device context](/oxi-e16-lua-api/device-context/)).
- **Pan rings are unipolar.** `dis=4` would draw a bipolar ring, but `dis` is fixed at
  assignment time and those encoders are ordinary parameters on the device page. `dis` is
  not in the runtime property table, so it cannot be switched per page.
