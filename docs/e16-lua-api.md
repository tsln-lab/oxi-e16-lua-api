# OXI E16 — Lua Scripting API Reference

Condensed from *The OXI E16 Manual*, section 6 (pp. 85–109), plus p.10 (debug mode).
API version 1.0.0. Source PDF: `OXI E16 - User Manual.pdf`.

This is the authoritative reference for this project. Machine-readable stubs of the same
API live in [`types/e16.lua`](../types/e16.lua) — keep the two in sync.

---

## 1. Execution model

- The E16 has **16 encoders, 12 pages, 16 scenes**. A scene may load one Lua script.
- The script reacts to encoder turns/presses, incoming SysEx, and page changes; it can
  send MIDI, set the screen header, override encoder labels, and drive the LED rings.
- **All API indices are 1-based**: encoders 1–16, pages 1–12. Firmware converts internally.
- MIDI **channels are 0-based** (0–15) and **output port 0 means "all outputs"** — these
  do *not* follow the 1-based rule.
- Scripts are created, edited and uploaded with the OXI App.

### Managed vs manual controls

Every script-type encoder is one or the other:

| Mode | Declared by | Who owns the value |
|---|---|---|
| **Managed** (default) | nothing | Firmware increments the value, *then* calls your handler. You read `enc.scaled`, send MIDI, update the display — but you do not control the value. |
| **Manual** | `manual=true` in the assignment, or `manual` prop at runtime | Your script owns the value entirely. The firmware passes the raw `enc.increment` and changes nothing. You apply, quantize, or ignore it. |

### Value representation

Internally every value is a **14-bit integer, 0–16383**. For a managed control with a
range like `l=0 h=127`, the firmware maps the internal value into that range and exposes
the result as `enc.scaled`. The unmapped internal value is `enc.value`.

### Script size and memory

- The App minifies before upload (LuaSrcDiet, extended for Lua 5.3/5.4 operators
  `// << >> & | ~` and the `<const>` / `<close>` attributes). Comments and `--@assign`
  directives are stripped and do **not** count toward the limit.
- The editor shows a live `uploaded-size / 8000` counter; red blocks saving.
  (The manual states a 4000-byte limit on p.88 and 8000/8192 on p.87 — it is
  internally inconsistent. Treat ~4000 as the safe target.)
- A ⚠ beside the counter means minification failed, which almost always means a real
  Lua syntax error. The device will not run it either — fix the syntax.
- **Large editors:** big Lua tables cost substantial memory. For hundreds of parameters,
  pack per-parameter data into a **single string literal as a fixed-stride byte table**
  and read fields arithmetically with `string.byte` instead of walking nested tables.

### Runtime version

Lua **5.4** (the minifier handles `<const>` / `<close>`, which are 5.4 features).

### On-device debugging

Set the control-view **Hold** menu to *Lua Debug* (page view → hold `[Shift]` → Knob 3).
Holding `[Shift]` in control view then shows incoming diagnostic information.
The setting is saved per scene. (Manual p.10)

---

## 2. Assignments (`--@assign`)

Comment directives at the top of the script that declare the parameters it exposes.
The App parses them and shows the parameters in a drag-and-drop panel; you drop them onto
encoder turn destination 1, turn destination 2, or push.

Assignments are **optional** — controls can be wired by hand in the editor instead — but
they are the standard way to declare the initial setup.

```lua
--@assign id=1 abbr="AR"   name="Attack"    desc="Attack Rate"    l=0 h=31
--@assign id=2 abbr="D1R"  name="Decay 1"   desc="Decay 1 Rate"   l=0 h=31 accel=2
--@assign id=3 abbr="Wave" name="Waveform"  desc="Waveform"       l=0 h=3  manual=true
--@assign id=5 abbr="FX"   name="FX Swap"   desc="FX Turn"        l=0 h=127 d=1 g=1 swap=true
--@assign id=6 abbr="FX"   name="FX Push"   desc="FX Push Toggle" p=true g=1
```

| Key | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | int | **yes** | — | Script ID. Identifies the control in callbacks as `enc.id`. |
| `abbr` | string | * | — | On-device encoder label, max 4 chars. If omitted, derived from the first 4 chars of `name`. |
| `name` | string | * | — | Display name in the App's parameter list. If omitted, falls back to `abbr`. |
| `desc` | string | no | — | Description shown in the App only, never on the device. |
| `l` | int | no | `0` | Lower bound of the output range. |
| `h` | int | no | `127` | Upper bound of the output range. |
| `d` | int | no | `1` | Destination slot, 1 or 2. A control can have two turn destinations. |
| `g` | int | no | — | Group number. Same-group parameters are presented together and can be dropped onto an encoder as a unit. |
| `swap` | bool | no | `false` | Push swaps between destination 1 and 2. |
| `manual` | bool | no | `false` | Manual mode — script owns the value. |
| `accel` | int | no | `3` | Acceleration mode (see table below). |
| `p` | bool | no | `false` | This parameter is a **push** action rather than a turn action. |
| `dis` | int | no | — | Display mode. **Set `dis=0` on script controls** — omitting it lets the firmware paint a numeric readout over your label while the encoder moves. See below. |

\* At least one of `abbr` or `name` is required.

**Label caveat:** each encoder has only one label. When two turn destinations share an
encoder (`d=1` and `d=2` with `swap=true`), the App uses the `abbr` of whichever parameter
was dropped last. Give both assignments the same `abbr`.

### Acceleration modes (`accel`)

| Value | Mode | Effect |
|---|---|---|
| 0 | Div8 | Slowest — resolution divided by 8 |
| 1 | Div4 | Resolution divided by 4 |
| 2 | Div2 | Resolution divided by 2 |
| 3 | Acc0 | **Default** — normal, no acceleration |
| 4 | Acc1 | Light acceleration |
| 5 | Acc2 | Medium acceleration |
| 6 | Acc3 | Fastest |

---

## 3. Global objects

Six globals are injected by the firmware:

| Object | Purpose |
|---|---|
| `controller` | Configure controls, read page index, attach encoder/SysEx callbacks. |
| `page` | Set the header title, attach init / page-change / var-change callbacks. |
| `midi` | Send CC and SysEx messages. |
| `leds` | Take over LED rings from the firmware. |
| `slots` | Override the text labels shown under each encoder. |
| `var` | Declare and read persistent script variables. |

---

## 4. Callbacks

Functions **you define** on the global objects; the firmware calls them.

### `page.onInit()`

Called once after the script loads and the Lua environment is ready. Use it to set the
title, initialise state, register variables, and request data from external gear.

```lua
function page.onInit()
  page.setTitle("Synth Edit")
  midi.sendSysex(0, {0xF0, 0x7D, 0x02, 0xF7})  -- request current values
end
```

### `controller.onEncoderTurn(enc)`

Called when a script-assigned encoder is turned. `enc` fields:

| Field | Type | Description |
|---|---|---|
| `enc.id` | int | The control's script ID |
| `enc.index` | int | Encoder position on the page (1–16) |
| `enc.page` | int | Current page (1–12) |
| `enc.increment` | int | Raw turn direction and speed: ±1, ±2, ±4 or ±8 depending on turn speed |
| `enc.value` | int | Internal 14-bit value (0–16383) |
| `enc.scaled` | int | Output value mapped to the control's `l`/`h` range |
| `enc.is_held` | bool | Whether the encoder button is held down |

```lua
function controller.onEncoderTurn(enc)
  if enc.id == 1 then
    midi.sendCC(0, 1, 74, enc.scaled)
  end
end
```

### `controller.onEncoderPress(enc)`

Called when a script-assigned encoder is pressed. `enc` carries **only**
`id`, `index`, `page`, `value`, `scaled` — **no `increment`, no `is_held`.**

### `controller.onSysex(bytes)`

Called when the E16 receives a SysEx message. `bytes` is a table of raw integer byte
values **including** the `0xF0` and `0xF7` framing bytes.

```lua
function controller.onSysex(bytes)
  if bytes[2] ~= 0x7D then return end  -- check manufacturer ID
  local msg_type = bytes[3]
  if msg_type == 0x11 then
    local param = bytes[4]
    local value = bytes[5]
  end
end
```

### `page.onPageChange(previous_page, new_page)`

Called when the user switches pages. Both arguments are 1-based page indices.

**LED and label overlays are NOT cleared automatically on page change.** Tear down the
old page's overlays and build the new page's here.

```lua
function page.onPageChange(prev, curr)
  for i = 1, 16 do
    leds.reset(i)
    slots.reset(i)
  end
  if curr == 1 then
    for i = 1, 16 do slots.update(i, my_labels[i]) end
  end
end
```

### `page.onVarChange(name)`

Called when the **firmware** changes a registered variable — typically the user editing it
via the device's variable menu. `name` is the registered variable name (string).

**Not** called for script-initiated `var.set`, so a handler can write variables without
recursing.

---

## 5. `controller` — control configuration

Controls are addressed two ways:

- **By script ID** — the primary method. Uses the `id` from the assignment and searches
  across all pages, regardless of where the control sits.
- **By index** — page index + encoder position on that page.

### `controller.set(id, key, value)` / `controller.set(id, props)`

Set properties on a control by its script ID.

```lua
controller.set(1, "v", 8192)
controller.set(1, {l=0, h=63, n="Cutoff"})
```

### `controller.setByIndex(page, index, key, value)` / `controller.setByIndex(page, index, props)`

Set properties by page and encoder position.

```lua
local pg = controller.getPage()
controller.setByIndex(pg, 1, "v", 8192)
controller.setByIndex(pg, 1, {l=0, h=127, manual=true})
```

### `controller.setControls(controls)`

Bulk-configure all 16 encoders on the current page. Array position maps to encoder index 1–16.

```lua
controller.setControls({
  {i=1, n="AR",  l=0, h=31},
  {i=2, n="D1R", l=0, h=31},
  {i=3, n="D2R", l=0, h=31},
  {i=4, n="RR",  l=1, h=15},
})
```

### `controller.getPage()`

Returns the current page index (1-based).

### Property reference

| Field | Type | Description |
|---|---|---|
| `v` | int | Internal value (0–16383). Sets the control's current value. |
| `l` | int | Lower bound of the output range |
| `h` | int | Upper bound of the output range |
| `n` | string | Display label (writes to `control.abbr`, max 4 chars) |
| `manual` | bool | If true, script owns the value; firmware won't auto-increment |
| `accel` | int | Acceleration mode (0=Div8 … 3=Acc0 default … 6=Acc3) |
| `i` | int | Script ID — **only works in `setControls()`**, not `set()`/`setByIndex()` |

---

## 6. `midi` — output

### `midi.sendCC(output, channel, cc, value)`

| Param | Range | Note |
|---|---|---|
| `output` | port index | **0 = all outputs** |
| `channel` | 0–15 | zero-based |
| `cc` | 0–127 | |
| `value` | 0–127 | |

```lua
midi.sendCC(0, 0, 74, 64)  -- CC 74, value 64, channel 1, all outputs
```

### `midi.sendSysex(output, bytes)`

`bytes` must be a table of integers **including** the `0xF0` start and `0xF7` end bytes.
**Maximum 128 bytes per call.**

```lua
midi.sendSysex(0, { 0xF0, 0x7D, 0x01, param, value, 0xF7 })
```

---

## 7. `leds` — LED rings

By default the firmware draws each ring from the control's internal value. Override it to
show quantized steps, a custom color, or an independent visualization.

### `leds.update(index, value [, color])`

| Param | Range | Note |
|---|---|---|
| `index` | 1–16 | Encoder position |
| `value` | 0–16383 | Ring fill; 16383 = full ring |
| `color` | 0–15 | Optional, defaults to 0 |

**Calling this takes ownership** — the firmware stops drawing that ring until `leds.reset`.

#### Palette (measured on hardware, 2026-08-09)

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

### `leds.reset(index)`

Hands the ring back; the firmware resumes drawing from the control's internal value on the
next render.

---

## 8. `slots` — screen labels

By default each encoder shows its 4-character `abbr`.

### `slots.update(index, text)`

`index` 1–16. **Max 4 characters displayed** — longer strings are truncated.

### `slots.reset(index)`

Removes the override, reverting to `control.abbr`.

### Label precedence (measured 2026-08-09)

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
never drawn at all (§2), so `controller.set(id, "n", …)` alone is enough to keep a control
labelled with text — no overlay, no `enc.index`, nothing to reset. Reach for the overlay
when the text must change per encoder *position* rather than per script ID.

**An overlay never expires on its own.** The callback set is complete — `onInit`,
`onEncoderTurn`, `onEncoderPress`, `onSysex`, `onPageChange`, `onVarChange` — and none of
them is a timer or tick. A script cannot tell that turning has stopped, so a label cannot
revert "after a moment". It only changes when something else calls `slots.update` or
`slots.reset`. Patterns that work instead: clear the previous overlay when a *different*
encoder is turned (so only the last-touched control shows transient text), clear on
`onEncoderPress`, or clear on `onPageChange`.

---

## 9. `var` — persistent variables

Persistent script state stored **in flash**. Unlike Lua locals (recreated on reload) and
module-scope tables (destroyed when the Lua VM dies on scene exit), variables survive
scene exits and power cycles.

- Each variable has a **name** and a **type** (`"int"`, `"bool"`, `"float"`), fixed at
  registration.
- Variables are **per scene** — two scenes can each have a `"cutoff"` without interfering.
- The store is loaded from flash **before the script runs**, so persisted values are
  already present when `page.onInit` is called.
- The user edits them at runtime via the device's variable menu
  (control editor → Scene tab → *Script Variables*).

### `var.register(name, type, default)`

| Param | Note |
|---|---|
| `name` | identifier, **max 16 characters** |
| `type` | `"int"`, `"bool"`, or `"float"` |
| `default` | used **only** on first registration |

The first call seeds the default; **subsequent calls with the same name are a silent
no-op**, so re-running the script (hot reload) preserves the stored value.

Edge cases: registrations past the per-scene capacity are **dropped**. Re-registering an
existing name with a different type does **not** update the type — the original wins.

### `var.get(name)`

Returns the value typed appropriately (integer / boolean / float), or **`nil` if never
registered**. Fast enough for hot paths — names are interned firmware-side.

### `var.set(name, value)`

Updates an already-registered variable; the value is coerced to the registered type.
No-op returning `nil` if the name was never registered.
**Does not fire `page.onVarChange`** — script writes are silent, so handlers can call it
without recursing.

### `var.delete(name)` / `var.deleteAll()`

Remove one variable (subsequent `var.get` returns `nil`) or wipe the whole store.
`deleteAll` resets to empty regardless of what was persisted.

### Full example

```lua
function page.onInit()
  var.register("channel", "int",   1)
  var.register("base_cc", "int",   20)
  var.register("scale",   "float", 1.0)
  var.register("muted",   "bool",  false)
  page.setTitle("Voices")
  refresh()
end

function refresh()
  slots.update(13, "ch:" .. var.get("channel"))
  slots.update(14, "cc:" .. var.get("base_cc"))
  slots.update(15, string.format("x%.1f", var.get("scale")))
  slots.update(16, var.get("muted") and "MUTE" or "LIVE")
end

function controller.onEncoderTurn(enc)
  if var.get("muted") then return end
  if enc.id >= 1 and enc.id <= 4 then
    local v = math.floor(enc.scaled * var.get("scale"))
    if v < 0   then v = 0   end
    if v > 127 then v = 127 end
    midi.sendCC(0, var.get("channel"), var.get("base_cc") + (enc.id - 1), v)
  end
end

function page.onVarChange(name)
  refresh()
end
```

---

## 10. `page` — header

### `page.setTitle(text)`

Sets the header text at the top of the screen. **Max 15 characters.**

### `page.resetTitle()`

Reverts to the default header (scene name + page name).

---

## 11. Gotchas

Ranked by how likely they are to cause a silent bug.

1. **A script control's numeric readout paints over its label while turning — unless the
   assignment sets `dis`.** With no `dis` key the firmware draws a number the moment the
   encoder moves, beating `abbr` and anything written with `controller.set(id, "n", …)`.
   Adding **`dis=0`** silences it and keeps a normal unipolar ring. A `slots.update`
   overlay also beats the readout, but only once `enc.index` is known — so `dis=0` is the
   fix that works from load (§2, §9).
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

---

## 12. Device context a script runs inside

Not part of the Lua API, but it determines what your script is actually driving.
From manual sections 2.5–2.17, 4.4, 5.2.

### Control anatomy

Every encoder has **three destinations**: turn destination 1, turn destination 2, and
push. Destination 2 is unavailable if destination 1 is `Off`. This is why assignments have
`d=1` / `d=2` and `swap=true` — `swap` makes the push toggle which turn destination is live.

### MIDI ports (p.18)

- The E16 exposes **Port A and Port B**, each with 16 channels. They are separate logical
  ports that **share the same physical output**; DAWs may show them as 1 and 2.
- Port and channel can be set **at page level** (applies to all controls on the page) or
  **per control destination**, which overrides the page setting.
- In Lua, `output` `0` means all outputs. The manual does not state which integers map to
  Port A / Port B — see §13.

### Encoder Mode — the device has modes Lua cannot reach

The on-device *Mode* setting offers: `Div8` `Div4` `Div2`, `Acc0`–`Acc3`,
**`LSp2` `LSp4` `LSp6`** (large step — advances in 2/4/6 increments), and a default of
`Scene` (inherit the scene's acceleration setting).

The Lua `accel` range is documented as **0–6 = Div8 … Acc3 only**. The large-step modes
and `Scene` inheritance appear to have no Lua equivalent. To use large-step behaviour,
configure the control in the editor rather than from script, or use `manual=true` and do
the stepping yourself.

### Display scale (`dis`) — values not documented

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

### Script controls show labels, not values (observed 2026-08-09)

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

### Bi-polar is display-only (p.43)

Bipolar mode shows −63…+64 on screen and the LED ring instead of 0…127. **The physical
output is unchanged** — still 0–127. A script reading `enc.scaled` gets the normal range
regardless of the bipolar setting.

### Special functions compete with script pushes

The *Special* per-encoder setting can be: `Off`, Snapshot Morph, Looper Capture, Looper
Playback, Random, or Swap Destination. Several of these consume the **push** action. An
encoder assigned a special function is not available for a script push action
(`p=true`) — check this first when a push handler never fires.

### Instrument Definitions are the non-script path (p.76)

Predefined CC maps for specific external gear, downloadable via the OXI App, selected per
destination. **If the goal is plain CC mapping with proper parameter names, an instrument
definition does it with no script at all.** Reach for Lua when you need SysEx, custom
logic, or persistent state. Instrument definitions are not user-editable on the device,
and the E16 must be restarted after transferring them.

### Scene and page model

- 16 scenes × 12 pages × 16 encoders. **A script belongs to a scene**, and its variables
  are per-scene.
- Scene settings include a scene-wide `Accel` default, plus *Script Variables* and
  *Erase Script*.
- Scenes have a `Reload` command — reloads the saved scene from device memory, which is
  the on-device way to re-run a script.

### Debugging aids

| Tool | Where | Use |
|---|---|---|
| Lua Debug | Control-view Hold menu → set via page view, hold `[Shift]`, Knob 3 | Hold `[Shift]` in control view to see script diagnostics. Saved per scene. |
| MIDI Input Monitor | `Conf > MIDI > MIDI Monitor` | Shows the last 3 incoming messages with connection + channel. Clock traffic can flood it. |
| MIDI Thru | `Conf > MIDI` | Echoes input to the other outputs — turn off to avoid confusing feedback while testing SysEx. |

---

## 13. Open questions

Things the manual does not settle. Resolve by testing on hardware before relying on them.

1. **Lua `output` port numbering.** `0` = all outputs is documented. Whether `1`/`2` map
   to Port A/B is not stated anywhere.
2. **`dis` — resolved 2026-08-09, as far as it is observable.** Setting `dis` suppresses
   the numeric readout; omitting it lets the firmware draw numbers over the label. `dis=4`
   gives a bipolar ring, eight values give a unipolar ring, seven blank it (§2).
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
   hardware (§7), and color is independent of `value` — rings hold their color across the
   full fill sweep. One piece still open: **how the 0–15 Lua index relates to the editor's
   0–100 setting**, if at all. The editor figure shows 11 colors against Lua's 16, and the
   two sets do not match in content, so they are probably separate palettes rather than
   two resolutions of one. Settling it needs a probe that sets a control's editor color
   and finds which Lua index renders identically. Also unresolved: whether the editor
   setting accepts all 101 values or only the 11 labelled steps.
4. **Script size limit.** 4000 bytes (p.88) vs 8000/8192 (p.87). See §1.
5. **Per-scene variable capacity.** Registrations past the limit are silently dropped, but
   the limit is never given.
6. **`accel` beyond 6.** Whether the large-step modes are reachable with higher `accel`
   values, or not at all from Lua.
