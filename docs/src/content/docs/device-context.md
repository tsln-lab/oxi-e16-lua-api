---
title: "Device context"
description: "What a script runs inside: control anatomy, ports, special functions, debugging aids."
---

Not part of the Lua API, but it determines what your script is actually driving.
From manual sections 2.5–2.17, 4.4, 5.2.

## Control anatomy

Every encoder has **three destinations**: turn destination 1, turn destination 2, and
push. Destination 2 is unavailable if destination 1 is `Off`. This is why assignments have
`d=1` / `d=2` and `swap=true` — `swap` makes the push toggle which turn destination is live.

## MIDI ports (p.18)

- The E16 exposes **Port A and Port B**, each with 16 channels. They are separate logical
  ports that **share the same physical output**; DAWs may show them as 1 and 2.
- Port and channel can be set **at page level** (applies to all controls on the page) or
  **per control destination**, which overrides the page setting.
- In Lua, `output` `0` means all outputs. The manual does not state which integers map to
  Port A / Port B — see [Open questions](/oxi-e16-lua-api/open-questions/).

## Encoder Mode — the device has modes Lua cannot reach

The on-device *Mode* setting offers: `Div8` `Div4` `Div2`, `Acc0`–`Acc3`,
**`LSp2` `LSp4` `LSp6`** (large step — advances in 2/4/6 increments), and a default of
`Scene` (inherit the scene's acceleration setting).

The Lua `accel` range is documented as **0–6 = Div8 … Acc3 only**. The large-step modes
and `Scene` inheritance appear to have no Lua equivalent. To use large-step behaviour,
configure the control in the editor rather than from script, or use `manual=true` and do
the stepping yourself.

## Display scale (`dis`) — values not documented

The on-device *Display* setting controls how the encoder scale is shown:

`Off` (blank) · `standard` · `127` (default) · `100` · `1000` (for CC14) · `B63`
(bipolar ±) · `9999` (for CC14 / high-res) · `Always on` (value always shown)

The manual prints "B63 bipolar +/-" **twice** in this list, in all three places it appears
(pp. 26, 27, 28) — a typo in the source, so one entry is an unknown bipolar variant.

**The `dis` assignment key takes an int, but the manual never gives the mapping from these
labels to integers.**

Partial hardware result, 2026-08-09, via [`dis_mode_probe.lua`](../dis_mode_probe.lua) —
sixteen controls identical but for `dis`, all parked at the same internal midpoint:

| `dis` | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LED ring | uni | uni | uni | uni | **bi** | — | — | — | uni | — | uni | uni | uni | — | — | — |

`uni` = fills from one end · `bi` = fills outward from centre · `—` = dark

**`dis=4` renders the ring bipolar** — the only value of the sixteen that does. That is
almost certainly the **B63** mode from the label list. It also explains why `dis=4` first
read as dark: the probe parks every control at the internal midpoint, and a bipolar ring
at its centre has zero deflection, so nothing lights until you turn it.

The other seven dark values (5, 6, 7, 9, 13, 14, 15) are *not* bipolar, so they are dark
for a different reason — most likely the **Off** display mode, or unassigned values
degrading to it.

This is unexpected — `dis` is documented as a *display* setting, and the script never
touches `leds`. It is **not** a parse failure: all sixteen labels render on screen, so the
App accepted every `dis` value from 0 to 15 and configured all sixteen controls. Whatever
the eight dark rings mean, `dis` is reaching the firmware and affecting ring rendering.

**No numeric readout appears for any of the sixteen values.**

**Confirmed 2026-08-09: setting `dis` at all suppresses the numeric readout.** An
assignment with **no** `dis` key draws a number over the label while the encoder moves;
adding `dis=0` to the same assignment removes it. Verified by adding `dis=0` to the eight
selectors in `scripts/nts-1.lua`, which eliminated the first-turn number flash outright.

So on a script control `dis` has two observable effects — it silences the readout, and it
picks the ring style. Which numeric *scale* a given value would select (127 / 100 / 1000 /
9999) is unobservable from a script control, because no number is ever drawn to read.

**`dis=0` is the useful default for script controls**: no readout, normal unipolar ring.

## Script controls show labels, not values (observed 2026-08-09)

**Settled 2026-08-09.** A script control's readout behaviour depends entirely on whether
its assignment sets `dis`:

| Assignment | At rest | While turning |
|---|---|---|
| no `dis` key | `abbr` | **numeric readout**, painted over the label |
| `dis=0` (or any `dis`) | `abbr` | `abbr` — no number, ever |

An earlier reading of the `dis` probe concluded that script controls never show a numeric
value. That was wrong; every assignment in the probe set `dis`, which is what silenced
them. Confirmed both ways: the NTS-1 script showed numbers with no `dis` key and stopped
as soon as `dis=0` was added.

**Practical rule: put `dis=0` on script assignments** unless you specifically want the
firmware drawing numbers. It costs nothing, keeps a normal unipolar ring, and makes the
label you set the label the user sees.

**Consequence for scripts: assume the user cannot see your control's value unless you draw
it.** Push it yourself with `slots.update`, which gives you 4 characters — enough for
`0`–`9999`, a short name, or a state word like `MUTE`, but not both at once.

## Bi-polar is display-only (p.43)

Bipolar mode shows −63…+64 on screen and the LED ring instead of 0…127. **The physical
output is unchanged** — still 0–127. A script reading `enc.scaled` gets the normal range
regardless of the bipolar setting.

## Special functions compete with script pushes

The *Special* per-encoder setting can be: `Off`, Snapshot Morph, Looper Capture, Looper
Playback, Random, or Swap Destination. Several of these consume the **push** action. An
encoder assigned a special function is not available for a script push action
(`p=true`) — check this first when a push handler never fires.

## Instrument Definitions are the non-script path (p.76)

Predefined CC maps for specific external gear, downloadable via the OXI App, selected per
destination. **If the goal is plain CC mapping with proper parameter names, an instrument
definition does it with no script at all.** Reach for Lua when you need SysEx, custom
logic, or persistent state. Instrument definitions are not user-editable on the device,
and the E16 must be restarted after transferring them.

## Scene and page model

- 16 scenes × 12 pages × 16 encoders. **A script belongs to a scene**, and its variables
  are per-scene.
- Scene settings include a scene-wide `Accel` default, plus *Script Variables* and
  *Erase Script*.
- Scenes have a `Reload` command — reloads the saved scene from device memory, which is
  the on-device way to re-run a script.

## Debugging aids

| Tool | Where | Use |
|---|---|---|
| Lua Debug | Control-view Hold menu → set via page view, hold `[Shift]`, Knob 3 | Hold `[Shift]` in control view to see script diagnostics. Saved per scene. |
| MIDI Input Monitor | `Conf > MIDI > MIDI Monitor` | Shows the last 3 incoming messages with connection + channel. Clock traffic can flood it. |
| MIDI Thru | `Conf > MIDI` | Echoes input to the other outputs — turn off to avoid confusing feedback while testing SysEx. |
