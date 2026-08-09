---
title: "slots"
description: "Override the text under an encoder, and how label precedence works."
---

By default each encoder shows its 4-character `abbr`.

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

**An overlay never expires on its own.** The callback set is complete — `onInit`,
`onEncoderTurn`, `onEncoderPress`, `onSysex`, `onPageChange`, `onVarChange` — and none of
them is a timer or tick. A script cannot tell that turning has stopped, so a label cannot
revert "after a moment". It only changes when something else calls `slots.update` or
`slots.reset`. Patterns that work instead: clear the previous overlay when a *different*
encoder is turned (so only the last-touched control shows transient text), clear on
`onEncoderPress`, or clear on `onPageChange`.
