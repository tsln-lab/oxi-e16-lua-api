---
title: "Open questions"
description: "Questions the documentation does not settle, and what it would take to answer each."
---

Things the 1.2.0 guide does not settle. Resolve by testing on hardware before relying on
them.

## Opened or reopened by 1.2.0

1. **LED `color` is now a 0–100 rotation.** 1.0.0 documented a 0–15 palette index, and the
   measured 16-entry table on [leds](/oxi-e16-lua-api/api/leds/) was taken under that
   firmware. Unknown: what 16–100 render as, whether the Lua scale and the editor's 0–100
   color setting are now the same scale, and whether the old readings still hold at all.
   **Re-run `tests/led_color_probe.lua`** — updated for the new
   signature; it sweeps 0–100 across the sixteen rings in six passes.
   [`tests/led_colour_scrub_probe.lua`](../led_colour_scrub_probe.lua) is the slower
   companion and the better one for writing the answer down: one knob scrubs the colour of
   one ring, one value per detent, with the number on screen, so the point where each
   colour starts can be read off directly. A third knob scales the fill, to check whether
   colour survives a partial ring as it did under 1.0.0.
2. **Does writing `v` transmit?** Whether `controller.setByIndex(page, index, "v", …)`
   makes the firmware send an ordinary control's configured MIDI message, or only stores
   the value — and whether it reaches non-script controls at all. This decides whether a
   script-driven LFO can modulate a CC knob the user configured in the editor, or must
   know and send every CC itself ([Patterns](/oxi-e16-lua-api/patterns/)). The guide is
   silent and its examples always send explicitly, hinting at "stores only".
   **Probe: `tests/write_transmit_probe.lua`**, about five minutes with a loopback cable.
3. **What `enc.id` holds for an ordinary control.** `onEncoderTurn` now fires for
   non-script controls, and the guide says to identify them by `enc.page` / `enc.index`
   without saying what `id` contains — `0`, `nil`, or a stale value. A handler guarding with
   `if enc.id == 1` behaves very differently if unclaimed controls report `0` versus `nil`
   in an arithmetic comparison. Probe: one script control and one plain CC control on the
   same page, log both via a `slots.update` of `tostring(enc.id)`.
4. **Does `controller.setControls` still exist?** The guide names it once as a runtime
   configuration option but gives it no section, and states that unlisted functions do not
   exist. Its `i` key is gone from the property table. Probe: call it and see whether the
   page reconfigures.
5. **`midi.sendMidi` channel precedence.** The call takes a `channel` argument *and* a
   `status` byte that already contains a channel nibble. Which wins when they disagree is
   unstated. Probe: send `sendMidi(0, 5, 0x90, 60, 100)` and read the channel on the
   MIDI monitor of a receiving device.
6. **Whether `system.update()` can starve encoder handling.** The floor is 20 ms; the guide
   does not say what happens if the handler takes longer than the interval, or whether
   ticks are dropped or queued.

## Carried over, still open

7. **Lua `output` port numbering — reframed 2026-08-11.** `0` = all outputs is the only
   value either document gives. The question is *not* "which integer is Port A vs Port B":
   the editor's Output setting selects **transport × port** from a ten-entry list (TRS1,
   TRS2, USB1, USB2, USB3, BLE, ALL-BLE, ALL-USB, Off), and `output` almost certainly
   indexes that. The hypothesised mapping is on
   [midi](/oxi-e16-lua-api/api/midi/#the-output-argument).
   **Probe: `tests/output_port_probe.lua`** — one press sends a different CC number on each
   index, so every connected receiver identifies which index reached it. Needs at least TRS
   and USB connected to something that shows incoming CC.
   Partial result 2026-08-20: **`3` = USB1**, measured with only USB1 enabled in Ableton
   Live's MIDI preferences so the port was isolated rather than inferred; `0` reaches it
   too, as its documented "all outputs" implies
   ([midi](/oxi-e16-lua-api/api/midi/#the-output-argument)). Both match the hypothesised
   order. The other eight indices are untested, and TRS and BLE have not been tried at all.
8. **`dis` — resolved 2026-08-09, as far as it is observable.** Setting `dis` suppresses
   the numeric readout; omitting it lets the firmware draw numbers over the label. `dis=4`
   gives a bipolar ring, eight values give a unipolar ring, seven blank it ([Assignments (--@assign)](/oxi-e16-lua-api/assignments/)).
   1.2.0 still documents `dis` only as "display mode for the turn/push action" with no
   mapping, so the hardware findings remain the only source.
   Remaining sub-question: whether the readout suppression is per-control or per-scene —
   put a plain CC control on a spare encoder **inside the script's scene** and turn it.
   Numbers appear → per-control. Nothing → attaching a script suppresses readouts
   scene-wide, which would be a significant gotcha for mixed pages.
9. **Per-scene variable capacity.** Registrations past the limit are silently dropped, but
   the limit is never given.
10. **`accel` beyond 6.** Whether the large-step modes (`LSp2`/`LSp4`/`LSp6`) are reachable
   with higher `accel` values, or not at all from Lua.

## Raised by the Live integration

11. **Does SysEx over USB reach `controller.onSysex`? — resolved 2026-08-20: yes.**
   Measured with [`sysex_in_probe.lua`](../sysex_in_probe.lua). A message sent from a host
   utility arrives, successive messages accumulate, the `bytes` table includes the `0xF0` /
   `0xF7` framing as documented, and `0x7D` passes through unaltered so dispatching on the
   ID byte works. Recorded on [Callbacks](/oxi-e16-lua-api/callbacks/); it is what makes
   [Ableton Live](/oxi-e16-lua-api/ableton-live/) possible at all.
   A DAW control surface's output arrives by the same path, confirmed separately with
   Ableton Live: moving a parameter in Live raised `onSysex` on the device.
   Remaining sub-question: whether the other transports in the `output` list (question 7)
   also deliver inbound SysEx — only USB has been tried.
12. **How does a detent's step size relate to a destination's `l`/`h` range?** Two
   hypotheses, with opposite consequences for high-resolution control:
   - *The step scales to the range* — one detent is one output step, so `h=16383` needs
     16383 detents for a full sweep and is unusable.
   - *The step is a fixed internal amount* set by `accel` — so a full sweep is roughly the
     same number of detents whatever `h` is, and raising `h` past the detent count buys no
     extra distinct values, only a finer scale to express them on.

   The `accel` table describes its modes as dividing *resolution* (`Div8` = "resolution
   divided by 8"), which leans toward the second — meaning script-side 14-bit output is not
   reachable by raising `h` alone. Either way `l=0 h=127` behaves as documented; the
   question is only whether anything finer is available.
   Test: two otherwise identical controls, `h=127` and `h=16383`, and count the detents
   each needs to travel end to end. `onEncoderTurn` firing only when the mapped value
   changes ([Callbacks](/oxi-e16-lua-api/callbacks/)) makes the count easy to read off.
   Sidestepped rather than answered by the [Live integration](/oxi-e16-lua-api/ableton-live/),
   which went `manual=true` and reports `enc.increment` instead of reading `enc.scaled` —
   worth knowing that a script needing resolution has that option regardless of how this
   resolves.

## Closed by 1.2.0

- **Script size limit** — 8000 bytes. The old manual's 4000 vs 8000/8192 contradiction is
  resolved by the guide documenting the editor counter as `uploaded-size / 8000`.
- **Whether the API has any timer** — it does now: `system.update()`.
- **Whether `is_held` works** — it does not; it is reserved and always `false`.
