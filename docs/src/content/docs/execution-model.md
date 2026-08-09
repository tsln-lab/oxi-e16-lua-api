---
title: "Execution model"
description: "How scripts run on the device: managed vs manual controls, 14-bit values, memory limits."
---

- The E16 has **16 encoders, 12 pages, 16 scenes**. A scene may load one Lua script.
- The script reacts to encoder turns/presses, incoming SysEx, and page changes; it can
  send MIDI, set the screen header, override encoder labels, and drive the LED rings.
- **All API indices are 1-based**: encoders 1–16, pages 1–12. Firmware converts internally.
- MIDI **channels are 0-based** (0–15) and **output port 0 means "all outputs"** — these
  do *not* follow the 1-based rule.
- Scripts are created, edited and uploaded with the OXI App.

## Managed vs manual controls

Every script-type encoder is one or the other:

| Mode | Declared by | Who owns the value |
|---|---|---|
| **Managed** (default) | nothing | Firmware increments the value, *then* calls your handler. You read `enc.scaled`, send MIDI, update the display — but you do not control the value. |
| **Manual** | `manual=true` in the assignment, or `manual` prop at runtime | Your script owns the value entirely. The firmware passes the raw `enc.increment` and changes nothing. You apply, quantize, or ignore it. |

## Value representation

Internally every value is a **14-bit integer, 0–16383**. For a managed control with a
range like `l=0 h=127`, the firmware maps the internal value into that range and exposes
the result as `enc.scaled`. The unmapped internal value is `enc.value`.

## Script size and memory

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

## Runtime version

Lua **5.4** (the minifier handles `<const>` / `<close>`, which are 5.4 features).

## On-device debugging

Set the control-view **Hold** menu to *Lua Debug* (page view → hold `[Shift]` → Knob 3).
Holding `[Shift]` in control view then shows incoming diagnostic information.
The setting is saved per scene. (Manual p.10)
