---
title: Patterns
description: "Recipes the documentation does not cover: stepped option selectors, two parameters on one encoder, and free-running LFOs."
---

Three things scripts are repeatedly wanted for, none of which the documentation spells out.

## Stepped selectors — one detent per option

**Verified on hardware, 2026-08-09.**

Many synths expose a selector over a full 0–127 CC range but only respond to a handful of
discrete values. The Korg NTS-1's `EG TYPE` accepts 0–127 but only acts on 0, 25, 50, 75
and 127. A plain CC knob wastes most of its travel and gives no clue which option is live.

**Let the firmware quantize.** Declare the range as the option *index* rather than the CC
value, and `enc.scaled` arrives as `0..n-1`, one detent per option, already clamped:

```lua
--@assign id=1 abbr="EG" name="EG Type" l=0 h=4 dis=0

local CC     = 14
local VALS   = { 0, 25, 50, 75, 127 }
local LABELS = { "ADSR", "AHR", "AR", "ARLP", "OPEN" }

function controller.onEncoderTurn(enc)
    if enc.id ~= 1 then return end
    local i = enc.scaled + 1          -- enc.scaled IS the option index
    midi.sendCC(0, 0, CC, VALS[i])
    slots.update(enc.index, LABELS[i])
end
```

No `manual=true`, no accumulator, no rounding. The parallel `VALS` / `LABELS` arrays are
indexed together, so the outgoing value and the on-screen name can never disagree.

The 1.2.0 guide confirms why this is efficient as well as tidy: on a managed control the
callback fires **only when the mapped output value changes**, so the several detents it
takes to cross one option produce exactly one callback and one outgoing CC.

`dis=0` matters here — without it the firmware paints a numeric readout over your label the
moment the encoder moves. See [Assignments](/oxi-e16-lua-api/assignments/).

### When the synth does not document its CC values

Korg's NTS-1 implementation chart states exactly which values each selector responds to
(`vv:0,25,50,75,127`). Many manufacturers — Sonicware among them — document only the
option *names*, leaving the CC mapping unstated.

Send the **midpoint of each option's band** rather than guessing at boundaries:

```lua
local function cc_value(n, i)      -- n options, option i (1-based)
    return ((2 * i - 1) * 128) // (2 * n)
end
-- n=4  -> 16, 48, 80, 112
-- n=10 -> 6, 19, 32, 44, 57, 70, 83, 96, 108, 121
```

If the synth divides 0–127 into equal bands — the usual implementation — midpoints are the
values furthest from any disagreement about where one option ends and the next begins, so
an off-by-one in the boundary maths cannot select the wrong option.

**To replace the guess with a measurement**, use the fact that most synths transmit the
same CCs they receive. Connect the synth's MIDI OUT to the E16's MIDI IN, turn on the
E16's **MIDI Input Monitor** (`Conf > MIDI > MIDI Monitor`), then step through the
parameter on the synth and read off the value it sends for each option. Those are the
real values; put them in a `vals` array and the assumption disappears.

## Two parameters on one encoder

:::danger[Hold-and-turn is not available]
An earlier version of this page built this on `enc.is_held`. **The 1.2.0 guide documents
`is_held` as reserved and always `false`** ([Callbacks](/oxi-e16-lua-api/callbacks/)), so a
branch on it silently takes the unheld path forever. There is also no release event, so the
button's held state cannot be reconstructed from `onEncoderPress` alone. Use press-to-latch
instead.
:::

### Without a script — Swap Destination

Every encoder already has **two turn destinations**. Configure Dest 1 and Dest 2, then
enable **Swap Destination** — the `Special` setting on the control, or `swap=true` in an
assignment. Pressing the knob flips which destination the turn drives, and the LED ring
jumps to the newly active destination's stored value.

This is press-to-*latch* rather than hold-to-*shift*, and it needs no script at all. Give
both assignments the same `abbr`, since the encoder has only one label.

### With a script — latch it yourself

Worth doing when the two parameters need different labels, different LED colors, or values
the firmware cannot compute. Toggle in `onEncoderPress`, branch in `onEncoderTurn`:

```lua
--@assign id=1 abbr="CUT" name="Cutoff / Reso" l=0 h=127 dis=0 manual=true
--@assign id=2 abbr="CUT" name="Swap param"    p=true

local CC   = { cutoff = 74, reso = 71 }
local val  = { cutoff = 64, reso = 64 }
local live = "cutoff"

function controller.onEncoderPress(enc)
    if enc.id ~= 2 then return end
    live = (live == "cutoff") and "reso" or "cutoff"
    slots.update(enc.index, (live == "reso") and "Reso" or "Cut")
    leds.update(1, val[live] * 16383 // 127, (live == "reso") and 60 or 0)
end

function controller.onEncoderTurn(enc)
    if enc.id ~= 1 then return end

    local v = val[live] + enc.increment
    if v < 0 then v = 0 elseif v > 127 then v = 127 end
    val[live] = v

    midi.sendCC(0, 0, CC[live], v)
    leds.update(1, v * 16383 // 127, (live == "reso") and 60 or 0)
end
```

Three things make this different from the stepped selector above:

1. **`manual=true` is required.** One encoder destination has one managed value. If the
   firmware maintains it, both parameters ride the same number and cannot stay independent.
   Owning the values means working from `enc.increment` and clamping by hand.
2. **`leds.update` takes the script ID** — `1`, the turn destination — not the encoder
   position, and not the push action's ID. This changed in 1.2.0; use `leds.updateByIndex`
   if you have only a position ([leds](/oxi-e16-lua-api/api/leds/)).
3. **The LED ring goes stale in manual mode**, because the firmware draws it from an
   internal value nothing is updating. Hence the explicit `leds.update`. Writing
   `controller.set(id, "v", …)` instead keeps the firmware drawing the ring, at the cost of
   converting back to the internal 14-bit scale.

The colour swap is how the user knows which parameter is live without spending the
4-character label on it. Push the value into the label as well if the ring is not enough —
see [slots](/oxi-e16-lua-api/api/slots/) for a version that reverts on a timer.

**Not verified on hardware.** The API supports every call used here, but the latch has not
been run on a device.

## LFOs and self-modulating controls

**New in API 1.2.0, and not verified on hardware.** Impossible before
[`system.update()`](/oxi-e16-lua-api/api/system/) existed — every other callback needs the
user to do something, so nothing could keep moving on its own.

Two facts make a control able to drive itself without a feedback loop:

- `system.update()` fires on a timer, 20–1000 ms.
- **`controller.set` is a direct setter, not a simulated turn — it does not raise
  `onEncoderTurn`.** Writing a control's own value from the tick therefore cannot recurse.

```lua
--@assign id=1 abbr="RATE" name="LFO Rate"   l=0 h=127 dis=0
--@assign id=2 abbr="DPTH" name="LFO Depth"  l=0 h=127 dis=0
--@assign id=3 abbr="RUN"  name="LFO On/Off" p=true
--@assign id=4 abbr="OUT"  name="LFO Output" l=0 h=127 dis=0 manual=true

local TICK, CC = 20, 74
local phase, rate, depth, centre, running = 0.0, 0.02, 64, 64, true

function page.onInit()
    page.setTitle("LFO")
    system.setUpdateRate(TICK)                  -- 50 Hz
end

function controller.onEncoderTurn(enc)
    if enc.id == 1 then
        rate = 0.002 + enc.scaled * 0.0004      -- ~0.1 Hz .. ~2.6 Hz
    elseif enc.id == 2 then
        depth = enc.scaled
    elseif enc.id == 4 then                     -- manual: the script owns this value
        centre = centre + enc.increment
        if centre < 0 then centre = 0 elseif centre > 127 then centre = 127 end
    end
end

function controller.onEncoderPress(enc)
    if enc.id ~= 3 then return end
    running = not running
    slots.update(enc.index, running and "RUN" or "OFF")
end

function system.update()
    if not running then return end
    phase = phase + rate
    if phase >= 1.0 then phase = phase - 1.0 end

    local v = centre + math.sin(phase * 6.2831853) * depth / 2
    if v < 0 then v = 0 elseif v > 127 then v = 127 end

    midi.sendCC(0, 0, CC, v)                    -- float is fine; the firmware truncates
    controller.set(4, "v", v * 16383 / 127)     -- encoder 4's ring animates itself
end
```

Encoder 4 is the self-modulating part. The tick writes its stored value, the firmware
redraws its ring from that value on the next render, and nothing calls back into the
script. Because it is `manual=true`, a user turn still works — it arrives as a raw
`enc.increment` and moves the LFO's centre while the LFO keeps running underneath.

OXI's own second showcase script does the ring half of this: encoder 5 sweeps continuously
from `system.update()` while turning it changes the sweep rate. Driving MIDI from the same
tick is a straight extension of it.

### Five limits

1. **50 Hz ceiling.** `setUpdateRate` floors at 20 ms. Past roughly 2–3 Hz the output is an
   audible staircase — 10 steps per cycle at 5 Hz. Fine for filter sweeps and slow
   movement, useless for anything approaching audio rate.
2. **No tempo sync.** There is no MIDI-input callback except `onSysex`, so incoming clock
   (`0xF8`) is invisible to the script and cannot be counted. LFOs free-run only.
3. **DIN MIDI carries about 1040 three-byte messages per second.** At 50 Hz that is roughly
   20 LFOs to saturation; four or five is comfortable, sixteen will jitter note timing.
   `output = 0` sends to every port and doubles the traffic.
4. **Nothing reads a control's value back.** To modulate around whatever the user dialled
   in, shadow it from `onEncoderTurn` — which since 1.2.0 fires for ordinary non-script
   controls too, so an unmodified CC knob can be tracked.
5. **One error inside the tick disables it permanently**, silently, for the rest of the
   session ([system](/oxi-e16-lua-api/api/system/)).

### The unresolved part

Whether `controller.setByIndex(page, index, "v", …)` makes the firmware **transmit** an
ordinary control's configured CC, or only stores the value. If it transmits, an LFO can
modulate any control on the page without knowing its CC number; if not, the script must
send every message itself. The guide never says, and its examples always send explicitly
alongside — which hints at "stores only".

`tests/write_transmit_probe.lua` settles it in about five minutes; see
[Open questions](/oxi-e16-lua-api/open-questions/).
