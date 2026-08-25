---
title: "leds"
description: "Take over the LED rings. The update signature changed in 1.2.0 — it now takes a script ID."
---

By default the firmware draws each ring from the control's internal value. Override it to
show quantized steps, a custom color, or an independent visualization.

:::caution[Changed in API 1.2.0]
`leds.update` now takes a **script ID**, not an encoder position. The old index-based
behaviour moved to the new `leds.updateByIndex`. `leds.reset` still takes an **index**.
Code written against 1.0.0 that called `leds.update(enc.index, …)` now addresses a script
ID that probably belongs to a different control — or to nothing at all, in which case it
silently does nothing.

The `color` argument also changed: it is documented as a **0–100 rotation**, where 1.0.0
documented a 0–15 palette index. See [Colors](#colors) — the measured palette below
predates this and needs re-running.
:::

:::note[Observed on hardware, 2026-08-21: it behaves like a real hue wheel]
Scrubbing 0–100 one value at a time with
[`led_colour_scrub_probe.lua`](../led_colour_scrub_probe.lua): **stepping is perceptually
uneven** — some single steps jump, some are subtle, and some look identical. The overall
impression is a wheel with big jumps in it.

That is what a genuine hue rotation looks like, because hue is not perceptually uniform:
greens span a wide arc with little apparent change while red through yellow moves fast in a
narrow one. A small palette stretched over 0–100 would instead give evenly sized plateaus
and no subtle steps at all, so this argues for a rotation and against the 1.0.0-style
palette.

**Practical consequence: neighbouring values are not reliably distinguishable.** Anything
that colour-codes more than a few things should spread its colours widely around the scale
rather than trusting adjacent numbers to differ — the
[Live integration](/oxi-e16-lua-api/ableton-live/) snaps track colours to eight evenly
spaced anchors for this reason.

Still open: how many distinct colours there actually are, and where each band starts.
:::

## `leds.update(id, value [, color])`

| Param | Range | Note |
|---|---|---|
| `id` | — | **Script ID** from `--@assign` |
| `value` | 0–16383 | Ring fill; 16383 = full ring |
| `color` | 0–100 | Color rotation. Optional, defaults to 0 |

Takes ownership of the ring for every **current-page** Script destination carrying that
ID. Note the asymmetry with [`controller.set`](/oxi-e16-lua-api/api/controller/), which
searches *all* pages — `leds.update` is current-page only.

```lua
leds.update(201, 8192, 10)
```

## `leds.updateByIndex(index, value [, color])`

The same thing addressed by physical encoder position, 1–16. This is what `leds.update`
used to be.

```lua
leds.updateByIndex(15, 8192, 10)
```

## Batch forms

Both functions accept an array of entries instead of positional arguments, so a whole
page's rings can be set in one call:

```lua
leds.update({
  {201, 8192, 10},
  {204, 4096,  4},
  {205, 12000},      -- color defaults to 0
})

leds.updateByIndex({
  {1, 8192, 10},
  {3, 4096,  4},
  {4, 12000},
})
```

Entries that are not tables, or that lack numeric target and value fields, are **ignored
silently**. Values and colors are clamped to their valid ranges rather than rejected.

## `leds.reset(index)`

**Takes an encoder position, 1–16** — not a script ID, in either version of the API. Hands
the ring back; the firmware resumes drawing it from the control's internal value on the
next render.

```lua
leds.reset(15)
```

## Ownership

Once either update function targets an encoder, the script owns that physical ring in the
normal encoder view until `leds.reset`. Menus and other special views may temporarily draw
their own ring state over it.

**The override is not page-specific** — it is stored by physical position, so a ring taken
on encoder 3 stays taken on encoder 3 after a page change. Reset or replace it from
`page.onPageChange`.

Loading or clearing a script drops all LED-ring overrides, along with slot labels and the
title override.

## Colors

`color` is documented in 1.2.0 as a **0–100 rotation**, the same numeric range as the
control editor's color setting (manual p.21).

**The palette table below was measured on the pre-1.2.0 firmware**, when `color` was
documented as a 0–15 index and `leds.update` took a position. It is kept because the
observations were real, but treat it as **stale**: it says nothing about what values 16–100
now render as, and the 1.0.0 firmware may have been interpreting the argument differently
from the current one.

| Index | Color | | Index | Color |
|---|---|---|---|---|
| 0 | purple | | 8 | light peach |
| 1 | blue | | 9 | peach |
| 2 | blue, slightly darker | | 10 | red |
| 3 | blue, lighter | | 11 | pink |
| 4 | blue, lighter | | 12 | magenta |
| 5 | pink | | 13 | blue |
| 6 | light yellow | | 14 | cyan |
| 7 | yellow | | 15 | green |

Measured 2026-08-09 with `tests/led_color_probe.lua`, since updated for
the 1.2.0 signature. Colour was independent of `value` — rings held their color across the
full fill sweep, which is the one finding likely to survive.

Two things that argued against the old 0–15 index being a slice of a hue ramp still stand:
the sequence was not monotonic, and the control editor's own "color spectrum" figure is
**11 discrete swatches at 10-step intervals**, not a gradient:

| Setting | 0 | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 100 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Swatch | `#5A58FF` | `#60DBFF` | `#BBFAFE` | `#D6C3FF` | `#75FF42` | `#FCABFF` | `#EF004C` | `#CB37FF` | `#5EF3FF` | `#93FF00` | `#70FFA1` |
| | blue | cyan | pale cyan | lavender | green | pale pink | red | purple | cyan | yellow-green | mint |

Extracted from the PDF's vector fills. Printed CMYK approximates LED output poorly, so
these are indicative of hue only, and the manual never says whether the setting accepts all
101 values or only the 11 labelled steps. Now that Lua and the editor share a 0–100 range,
**re-running the probe should settle whether they are the same scale** — see
[Open questions](/oxi-e16-lua-api/open-questions/).

## Example

```lua
-- Show 4 discrete steps on the control with script ID 1
local step = (enc.scaled * 4) // 128
if step > 3 then step = 3 end
leds.update(1, step * 16383 // 3)
```
