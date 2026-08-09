---
title: "leds"
description: "Take over the LED rings, including the measured 16-colour palette."
---

By default the firmware draws each ring from the control's internal value. Override it to
show quantized steps, a custom color, or an independent visualization.

## `leds.update(index, value [, color])`

| Param | Range | Note |
|---|---|---|
| `index` | 1–16 | Encoder position |
| `value` | 0–16383 | Ring fill; 16383 = full ring |
| `color` | 0–15 | Optional, defaults to 0 |

**Calling this takes ownership** — the firmware stops drawing that ring until `leds.reset`.

## Palette (measured on hardware, 2026-08-09)

`color` is a **discrete palette, not a hue ramp** — the sequence is not monotonic
(purple, four blues, pink, yellows, peaches, red, pink, magenta, blue, cyan, green).

The control editor's 0–100 "color spectrum" (manual p.21) is **also not a hue ramp**.
The figure is **11 discrete swatches at 10-step intervals**, not a gradient — extracted
from the PDF's vector fills as 11 equal-width rectangles in a row:

| Setting | 0 | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 100 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Swatch | `#5A58FF` | `#60DBFF` | `#BBFAFE` | `#D6C3FF` | `#75FF42` | `#FCABFF` | `#EF004C` | `#CB37FF` | `#5EF3FF` | `#93FF00` | `#70FFA1` |
| | blue | cyan | pale cyan | lavender | green | pale pink | red | purple | cyan | yellow-green | mint |

**The two scales cannot be a simple resampling of each other: the editor figure shows
11 colors, the Lua index has 16.** Nor do their contents line up — the Lua palette is
heavy on blues (five of sixteen) while the figure has one blue and three cyans. Treat
them as separate palettes until proven otherwise.

Two caveats on the figure: the manual never says whether the setting accepts only those
11 labelled values or all 101, and printed CMYK swatches approximate LED output poorly,
so the hex values above are indicative of hue only.

Pick colors from the measured table below by index; do not compute them from the 0–100
setting.

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

Measured with [`led_color_probe.lua`](../led_color_probe.lua); all 16 entries confirmed.

**A third of the palette is blue.** Indices 1, 2, 3, 4 and 13 are all blues, and 5 and 11
are both pinks — seven of sixteen entries fall into two clusters. The reliably distinct
set is **0, 7, 9, 10, 12, 14, 15** (purple, yellow, peach, red, magenta, cyan, green),
plus one blue and one pink. That is **nine usable colors**, not sixteen — worth knowing
before designing a page that color-codes more than nine things.

```lua
-- Show 4 discrete steps on encoder 15
local step = (enc.scaled * 4) // 128
if step > 3 then step = 3 end
leds.update(15, step * 16383 // 3)
```

## `leds.reset(index)`

Hands the ring back; the firmware resumes drawing from the control's internal value on the
next render.
