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
`{1, 5, 9, 13}`. Each column is one track — sends at the top, then pan, fader at the
bottom:

| Row | Encoders | Control |
|---|---|---|
| Top | 1–4 | Send A — labelled from the return track |
| | 5–8 | Send B |
| | 9–12 | Pan |
| Bottom | 13–16 | Volume — labelled with the track name |

The order is a plain list in `_mixer_slots`, so moving a control is reordering a line.

### Ring colours

Each column is tinted with its track's colour in Live, so a strip reads as one track. This
is the one place the script takes a ring over: colour is only reachable through
`leds.update`, which **owns** the ring until an explicit `leds.reset`
([leds](/oxi-e16-lua-api/api/leds/)). Three consequences, all handled in
`src/live-device.lua`:

- The script draws those rings itself on every value change *and* every turn — the
  firmware has stopped drawing them, so a turn would otherwise move nothing.
- Every ring is handed back on the way out of a mixer page. Overlays are keyed by physical
  position and survive a page change, so a colour left behind reappears under whatever
  occupies that encoder next.
- `leds.reset` takes a **position** where `leds.update` takes an **ID**, so giving a ring
  back relies on assignment *N* sitting on encoder *N*. That is the documented setup, but
  colour is the only feature that depends on it.

Device pages send no colour and leave the rings to the firmware, so nothing is owned there.

:::note[The colour mapping, and why it snaps]
API 1.2.0 redefines `color` as a **0–100 rotation**, replacing 1.0.0's 0–15 palette index.
Scrubbing the range on hardware confirms it behaves like a real hue wheel, so mapping RGB
to hue is right in kind ([open question 1](/oxi-e16-lua-api/open-questions/)).

What the same test showed is that **stepping is perceptually uneven** — some single steps
jump, some are invisible. So `e16_color()` does not send the hue directly: it snaps to
`COLOR_ANCHORS` (8) evenly spaced values, because telling two tracks apart matters more
here than reproducing either one exactly. Live's 70 track colours land on eight distinct
rings. Raise the constant for finer distinctions, lower it if any two still read alike.

`TRACK_COLORS = False` disables the feature and returns every ring to the firmware.

**Desaturated tracks keep the firmware's ring.** Live's track palette has 70 entries, of
which 13 are too close to grey for a hue to mean anything and 5 are pure grey — and every
grey has a hue of exactly 0, so mapping them anyway would paint a grey track *red*. Below
`MIN_SATURATION` the mapping returns `NO_COLOR` and that ring is left alone. Checked
against the palette in the decompiled scripts (`Akai_Force_MPC/live_colors.py`).
:::

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

:::caution[`ableton.v2` routes SysEx only to registered elements — subscribe to `received_midi`]
`ableton.v2`'s `ControlSurface` dispatches SysEx to registered control elements and
discards anything else with a `Got unknown sysex message` warning in Log.txt.
`receive_midi_chunk` does *not* fall through to `receive_midi`, so a script that registers
no elements — as this one does deliberately — receives nothing at all: the messages arrive,
Live logs them, and the handler never runs.

The supported hook is the `received_midi` event. `SimpleControlSurface` declares
`__events__ = ('received_midi', 'disconnect')`, and **both** `_do_receive_midi` and
`_do_receive_midi_chunk` fire it before dispatching:

```python
self.add_received_midi_listener(self._on_received_midi)

def _on_received_midi(self, *midi_bytes):   # separate arguments, not one sequence
    ...
```

Better than overriding the entry points, for three reasons:

- both the single-message and chunked paths reach it, with no duplication;
- the base class's `component_guard()` still wraps the handling, so parameter writes are
  batched and MIDI-map rebuilds suppressed — an override skips that;
- `process_midi_bytes` warns only when `received_midi_listener_count()` is zero, so
  registering a listener is exactly what silences the log spam.

Verified against the decompiled Live 12 scripts
([gluon/AbletonLive12_MIDIRemoteScripts](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts),
`ableton/v2/control_surface/control_surface.py`), after the behaviour was first observed on
hardware 2026-08-20.
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
| `0x12` | page, slot, increment | Encoder turned, by this much |
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

## Relative, not absolute

The encoders are `manual=true` and report **how far they were turned**, not where they
ended up. Live decides what one increment is worth. Three things follow.

**Resolution stops being a wire problem.** An absolute value has to fit in MIDI data bytes;
an increment does not, so the step is a free choice. A continuous parameter crosses its
range in `CONTINUOUS_STEPS` (256) increments — twice the old resolution — while the E16's
acceleration still sends ±8 on a fast turn, keeping a full sweep at roughly 32 quick
detents. [Open question 12](/oxi-e16-lua-api/open-questions/), on how a detent's step size
relates to `l`/`h`, stops mattering here: the script never uses `enc.scaled`.

**Stepped parameters land cleanly.** One increment is one option, so a five-way selector
takes five detents rather than scrubbing through a range.

**Nothing jumps.** An absolute encoder and a parameter can disagree — after automation
moves it, or on switching pages — and the next touch snaps the value to wherever the knob
happened to be. A relative encoder has no position of its own to disagree with.

The cost is that nothing moves until Live answers, roughly one 100 ms tick. In manual mode
the firmware maintains no value, so both the value and the ring come back over the wire.

Live's own scripts scale sensitivity per parameter too, but those numbers feed Live's
internal relative-CC handling rather than a value delta, so they are not reusable here.
The structure is borrowed — continuous versus stepped, a fine-grain factor — the numbers
are not, and this does not claim to match Push's feel.

## Feedback and flooding

Two problems, both handled on the Live side.

**Stepped parameters.** `parameter.is_quantized` does not catch everything: some devices
have parameters that step without declaring it — Glue Compressor's Ratio, Attack and
Release among them. Live's own scripts carry a table of the exceptions keyed by
`device.class_name`, vendored here from `ableton/v3/live/util.py`, and it is consulted
alongside the declared flag when deciding whether to round.

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
- **Sixteen parameters, in Live's curated order.** Raw `device.parameters` order is close
  to arbitrary on a large device, so the page uses Live's own hand-picked banks — the
  eight-per-device that Push shows — taking them in order, then appending whatever is left
  so no encoder is wasted. Devices with no curated bank keep raw order. The on/off switch
  at `parameters[0]` is dropped either way (`SKIP_PARAMS`).

  The banks are **imported from the running Live**, not copied into this repo:

  ```python
  from ableton.v3.control_surface.default_bank_definitions import BANK_DEFINITIONS
  ```

  The script runs inside Live, so the table is right there — always matching the installed
  version, and none of Ableton's data is redistributed. Missing on older installs, where
  the fallback is raw order.

  Bank entries are matched against `parameter.original_name`, not `name`: **mapping a rack
  macro renames it**, so a mapped `Macro 1` reports something like `Frequency` and would
  miss its own bank entry — pushing every mapped macro out of the curated order and behind
  the unmapped ones. Live's own bank resolution matches on `original_name` for the same
  reason. Labels still come from `name`, so a mapped macro reads as what Live shows.

  **Renames follow automatically**, by two routes. The device's `parameters` list is the
  documented signal — it is what Live's own components watch, and nothing finer — and it
  fires when a device's shape changes, a rack gaining macros or a Simpler becoming a
  Sampler. Alongside it the script attaches a `name` listener to each bound parameter,
  which catches a plain rename. **No Live script listens to a parameter's name**, so
  whether `DeviceParameter` supports it is unverified; attaching costs nothing and is
  skipped with a note under `DEBUG` if the method is absent. Check Log.txt for
  `cannot listen for name` to find out which route is doing the work. Beyond the first sixteen there is still no device banking;
  page changes could select banks, since `onPageChange` already fires a resync. The mixer
  banks four tracks per page, so that limit only bites on devices.
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
