---
title: "slots"
description: "Override the text under an encoder, and how label precedence works."
---

By default each encoder shows the shared 4-character `abbr` from its control configuration
— **including Script controls in manual mode**, which does not suppress the label.

## `slots.update(index, text)`

`index` 1–16. **Max 4 characters displayed** — longer strings are truncated.

## `slots.reset(index)`

Removes the override, reverting to `control.abbr`.

## Label precedence (measured 2026-08-09)

Three things compete for the text under an encoder. Highest wins:

1. **`slots.update` overlay** — beats everything, including the numeric readout, and stays
   owned by the script until `slots.reset`.
2. **The firmware's numeric readout** — drawn while the encoder is moving. Paints over
   `abbr`.
3. **`control.abbr`** — from the assignment, or written at runtime with
   `controller.set(id, "n", ...)`.

This matters because the two script-side mechanisms are addressed differently:
`controller.set` takes a **script ID**, so it works in `page.onInit` before any encoder has
been touched; `slots.update` takes an **encoder position**, which a script only learns from
`enc.index` when a turn arrives.

The practical recipe for a control whose label should always read as text:

```lua
local function show(id, index, label)
    controller.set(id, "n", label)          -- correct at rest, works before first touch
    if index then slots.update(index, label) end  -- suppresses the readout, needs enc.index
end
```

Consequence: the **first** turn of each encoder can still flash the numeric readout, because
the overlay is only installed once `enc.index` is known. There is no API for looking up
which encoder holds a given script ID, so this cannot be pre-empted.

**Simpler alternative: `dis=0`.** If the assignment sets `dis`, the numeric readout is
never drawn at all ([Assignments (--@assign)](/oxi-e16-lua-api/assignments/)), so `controller.set(id, "n", …)` alone is enough to keep a control
labelled with text — no overlay, no `enc.index`, nothing to reset. Reach for the overlay
when the text must change per encoder *position* rather than per script ID.

**An overlay never expires on its own.** It changes only when something calls
`slots.update` or `slots.reset` again.

Until API 1.2.0 that made "show the value while turning, then revert" impossible: every
callback was driven by a user action, so a script could not tell that turning had *stopped*.
**[`system.update()`](/oxi-e16-lua-api/api/system/) closes that gap** — a tick can count
down and reset the label itself:

```lua
--@assign id=1 abbr="Cut" name="Cutoff" l=0 h=127 dis=0

local HOLD_TICKS = 40          -- 40 x 25 ms = 1 s
local countdown, slot = 0, nil

function page.onInit()
  system.setUpdateRate(25)
end

function controller.onEncoderTurn(enc)
  if enc.id ~= 1 then return end
  midi.sendCC(0, 0, 74, enc.scaled)
  slots.update(enc.index, tostring(enc.scaled))
  slot, countdown = enc.index, HOLD_TICKS
end

function system.update()
  if countdown == 0 then return end
  countdown = countdown - 1
  if countdown == 0 then
    slots.reset(slot)          -- back to "Cut"
  end
end
```

This gets a 4-character label doing both jobs — parameter name at rest, live value while
moving — which the `dis` readout cannot do without painting over the label permanently.
The tick is unverified on hardware; the timing is a plain counter, so a slow tick just means
a longer revert.

Event-driven alternatives that need no timer: clear the previous overlay when a *different*
encoder is turned (so only the last-touched control shows transient text), clear on
`onEncoderPress`, or clear on `onPageChange`.
