---
title: "Open questions"
description: "Questions the manual does not settle, and what it would take to answer each."
---

Things the manual does not settle. Resolve by testing on hardware before relying on them.

1. **Lua `output` port numbering.** `0` = all outputs is documented. Whether `1`/`2` map
   to Port A/B is not stated anywhere.
2. **`dis` — resolved 2026-08-09, as far as it is observable.** Setting `dis` suppresses
   the numeric readout; omitting it lets the firmware draw numbers over the label. `dis=4`
   gives a bipolar ring, eight values give a unipolar ring, seven blank it ([Assignments (--@assign)](/oxi-e16-lua-api/assignments/)).
   Not observable, and probably not worth chasing: which numeric scale (127 / 100 / 1000 /
   9999) a given value denotes — on a script control no number is ever drawn once `dis` is
   set, so the distinction has no visible effect.
   **Working conclusion: on a script control, `dis` affects only LED ring rendering** —
   `4` is bipolar, eight values are unipolar, seven blank the ring. The scale distinctions
   (127 / 100 / 1000 / 9999) appear to have no visible effect there.
   Remaining sub-question: whether the readout suppression is per-control or per-scene —
   put a plain CC control on a spare encoder **inside the script's scene** and turn it.
   Numbers appear → per-control. Nothing → attaching a script suppresses readouts
   scene-wide, which would be a significant gotcha for mixed pages.
3. **LED colors — mostly resolved 2026-08-09.** All 16 palette entries are measured on
   hardware ([leds](/oxi-e16-lua-api/api/leds/)), and color is independent of `value` — rings hold their color across the
   full fill sweep. One piece still open: **how the 0–15 Lua index relates to the editor's
   0–100 setting**, if at all. The editor figure shows 11 colors against Lua's 16, and the
   two sets do not match in content, so they are probably separate palettes rather than
   two resolutions of one. Settling it needs a probe that sets a control's editor color
   and finds which Lua index renders identically. Also unresolved: whether the editor
   setting accepts all 101 values or only the 11 labelled steps.
4. **Script size limit.** 4000 bytes (p.88) vs 8000/8192 (p.87). See [Execution model](/oxi-e16-lua-api/execution-model/).
5. **Per-scene variable capacity.** Registrations past the limit are silently dropped, but
   the limit is never given.
6. **`accel` beyond 6.** Whether the large-step modes are reachable with higher `accel`
   values, or not at all from Lua.
