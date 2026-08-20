---
title: "Gotchas"
description: "The traps that cause silent bugs, ranked by likelihood."
---

Ranked by how likely they are to cause a silent bug.

1. **`leds.update` takes a script ID, not an encoder index** — changed in API 1.2.0.
   `leds.update(enc.index, …)` was correct in 1.0.0 and now addresses whatever destination
   happens to carry that ID, or nothing at all, with no error either way. Use
   `leds.updateByIndex` for position. Note the asymmetry: **`leds.reset` still takes an
   index** ([leds](/oxi-e16-lua-api/api/leds/)).
2. **`enc.is_held` is always `false`.** Documented as reserved in 1.2.0. Every branch on it
   takes the false path forever ([Callbacks](/oxi-e16-lua-api/callbacks/)).
3. **A script control's numeric readout paints over its label while turning — unless the
   assignment sets `dis`.** With no `dis` key the firmware draws a number the moment the
   encoder moves, beating `abbr` and anything written with `controller.set(id, "n", …)`.
   Adding **`dis=0`** silences it and keeps a normal unipolar ring. A `slots.update`
   overlay also beats the readout, but only once `enc.index` is known — so `dis=0` is the
   fix that works from load ([Assignments (--@assign)](/oxi-e16-lua-api/assignments/), [slots](/oxi-e16-lua-api/api/slots/)).
4. **`onEncoderTurn` fires for controls your script never claimed.** Since 1.2.0 ordinary
   controls raise it too, and so do recorder playback, Random, and group moves. A handler
   that does not check `enc.id` before acting will act on strangers
   ([Callbacks](/oxi-e16-lua-api/callbacks/)).
5. **Press events lack `increment` and `is_held`.** Reading them in
   `onEncoderPress` yields `nil`, not an error.
6. **Overlays survive page changes.** `leds` and `slots` overrides are keyed by physical
   position, not page — reset them in `page.onPageChange` or they leak onto the next page.
7. **`leds.update` is sticky.** One call permanently disables firmware drawing for that
   ring until `leds.reset`. A "temporary" override that never resets stays stuck.
8. **`enc.value` (0–16383) is not `enc.scaled` (0–`h`).** Sending `enc.value` as a MIDI
   data byte sends garbage.
9. **An error inside `system.update()` disables the tick** for the rest of the session, with
   no message. One bad frame stops the animation permanently
   ([system](/oxi-e16-lua-api/api/system/)).
10. **A duplicated script `id` writes to every destination holding it.** `controller.set`
    searches all pages and both destinations and updates all matches
    ([controller](/oxi-e16-lua-api/api/controller/)).
11. **`controller.setByIndex` only reaches destination 1.** On a control with two
    destinations, the other one is unreachable by index — address it by ID.
12. **`i` is ignored by `set()` and `setByIndex()`** — 1.0.0 documented it as `setControls`
    only, and 1.2.0 drops it from the property table entirely.
13. **`var.register` will not overwrite** an existing value or type. To change a type you
    must `var.delete` first.
14. **`var.get` on an unregistered name returns `nil`**, which propagates silently into
    arithmetic as an error much later.
15. **MIDI channel is 0-based** while every API index is 1-based. And `midi.sendMidi` wants
    the channel nibble baked into `status` as well.
