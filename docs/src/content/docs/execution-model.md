---
title: "Execution model"
description: "How scripts run on the device: managed vs manual controls, 14-bit values, memory limits."
---

- The E16 has **16 encoders, 12 pages, 16 scenes**. A scene may load one Lua script.
- The script reacts to encoder turns/presses, incoming SysEx, page changes, variable edits,
  and — since API 1.2.0 — a **periodic tick**. It can send MIDI, set the screen header,
  override encoder labels, and drive the LED rings.
- **All API indices are 1-based**: encoders 1–16, pages 1–12. Firmware converts internally.
- MIDI **channels are 0-based** (0–15) and **output port 0 means "all outputs"** — these
  do *not* follow the 1-based rule.
- Scripts are created, edited and uploaded with the OXI App.

## Managed vs manual controls

Every script-type encoder is one or the other:

| Mode | Declared by | Who owns the value |
|---|---|---|
| **Managed** (default) | nothing | The firmware calculates and stores the new value, *then* calls your handler with the result in `enc.value` / `enc.scaled`. You can still overwrite it with `controller.set`. |
| **Manual** | `manual=true` in the assignment, or the `manual` prop at runtime | The firmware calculates and stores nothing. The handler gets the raw `enc.increment` **plus the destination's currently stored value** in `enc.value` / `enc.scaled`, and writes the result back with `controller.set(id, "v", …)`. |

**Manual mode affects value processing only.** It does not suppress the configured encoder
label, and it does not stop the script controlling the screen or the LED ring. It does mean
the firmware's own ring drawing goes stale, because nothing is updating the internal value —
either call `leds.update` yourself or write the value back with `controller.set`.

## Value representation

Internally every value is a **14-bit integer, 0–16383**. For a control with a range like
`l=0 h=127`, the firmware maps the internal value into that range and exposes the result as
`enc.scaled`. The unmapped internal value is `enc.value`.

**Numeric arguments accept floats.** Every numeric API argument takes Lua integers or
floating-point numbers; when the firmware stores into an integer-backed field it truncates
the fraction toward zero, and it clamps to the range wherever the endpoint defines one. So
calculated values go straight in — no `math.floor` scattered through the script.

## Script size and memory

- The App minifies before upload (LuaSrcDiet, extended for Lua 5.3/5.4 operators
  `// << >> & | ~` and the `<const>` / `<close>` attributes). Comments and `--@assign`
  directives are stripped and do **not** count toward the limit.
- **The limit is 8000 bytes** of uploaded size — settled by the 1.2.0 guide, which
  documents the editor's live counter as `uploaded-size / 8000`, red and save-blocking
  when over. The old manual's contradictory 4000-byte figure (p.88) is superseded.
- A ⚠ beside the counter means minification failed, which almost always means a real
  Lua syntax error. The device will not run it either — fix the syntax.
- **Large editors:** big Lua tables cost substantial memory. For hundreds of parameters,
  pack per-parameter data into a **single string literal as a fixed-stride byte table**
  and read fields arithmetically with `string.byte` instead of walking nested tables. One
  string replaces dozens of table objects and lookup stays fast.

## Scripts in the App

- The **Scripts tab** creates, edits and deletes scripts, like the scene tab.
- The **script panel** in the control editor picks which script a scene uses and is where
  assignments are dragged onto encoders. Scripts can also be edited and created from here.
- Downloading a scene back from the device matches the script **by name** against the local
  library. If it is not found the dropdown shows red — assignments and source are only
  available when the script exists locally, because neither is stored on the device.

## Runtime version

Lua **5.4** (the minifier handles `<const>` / `<close>`, which are 5.4 features).

## On-device debugging

Set the control-view **Hold** menu to *Lua Debug* (page view → hold `[Shift]` → Knob 3).
Holding `[Shift]` in control view then shows incoming diagnostic information.
The setting is saved per scene. (Manual p.10)
