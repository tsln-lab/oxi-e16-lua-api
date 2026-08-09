---
title: "Gotchas"
description: "The traps that cause silent bugs, ranked by likelihood."
---

Ranked by how likely they are to cause a silent bug.

1. **A script control's numeric readout paints over its label while turning — unless the
   assignment sets `dis`.** With no `dis` key the firmware draws a number the moment the
   encoder moves, beating `abbr` and anything written with `controller.set(id, "n", …)`.
   Adding **`dis=0`** silences it and keeps a normal unipolar ring. A `slots.update`
   overlay also beats the readout, but only once `enc.index` is known — so `dis=0` is the
   fix that works from load ([Assignments (--@assign)](/oxi-e16-lua-api/assignments/), [slots](/oxi-e16-lua-api/api/slots/)).
2. **Press events lack `increment` and `is_held`.** Reading them in
   `onEncoderPress` yields `nil`, not an error.
3. **Overlays survive page changes.** `leds` and `slots` overrides are not cleared
   automatically — reset them in `page.onPageChange` or they leak onto the next page.
4. **`leds.update` is sticky.** One call permanently disables firmware drawing for that
   ring until `leds.reset`. A "temporary" override that never resets stays stuck.
5. **`enc.value` (0–16383) is not `enc.scaled` (0–`h`).** Sending `enc.value` as a MIDI
   data byte sends garbage.
6. **`i` is ignored by `set()` and `setByIndex()`** — it only works in `setControls()`.
7. **`var.register` will not overwrite** an existing value or type. To change a type you
   must `var.delete` first.
8. **`var.get` on an unregistered name returns `nil`**, which propagates silently into
   arithmetic as an error much later.
9. **MIDI channel is 0-based** while every API index is 1-based.
