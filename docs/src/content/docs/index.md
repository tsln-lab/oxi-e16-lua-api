---
title: OXI E16 Lua Scripting API
description: "Firmware API reference for OXI E16 Lua scripts, transcribed from OXI's official documentation and corrected against hardware."
---

**API version 1.2.0.** Condensed from OXI Instruments' *OXI E16 Lua Scripting API Guide
v1.2.0*, which supersedes section 6 of
[*The OXI E16 Manual*](https://drive.google.com/file/d/1yZn1i96nRkosn2o6eDlj5wzuErPQEe9N/view?usp=sharing).
The manual is still the source for everything outside the API — control anatomy, ports,
special functions — on [Device context](/oxi-e16-lua-api/device-context/).

Machine-readable stubs of the same API live in `types/e16.lua` — keep the two in sync.

Findings marked with a date were **measured on hardware** and, in a few places, correct
what the documentation says.

## What changed in 1.2.0

- **[`system`](/oxi-e16-lua-api/api/system/) is a new global** — `system.setUpdateRate(ms)`
  plus a `system.update()` tick. The API finally has a timer.
- **[`leds.update`](/oxi-e16-lua-api/api/leds/) takes a script ID, not an encoder index**,
  and `color` is now a 0–100 rotation. `leds.updateByIndex` is the old behaviour, and both
  gained batch forms. **This silently breaks 1.0.0 scripts.**
- **[`enc.is_held` is always `false`](/oxi-e16-lua-api/callbacks/)** — declared reserved. The
  hold-and-turn idea built on it does not work.
- **[`midi.sendPC` and `midi.sendMidi`](/oxi-e16-lua-api/api/midi/)** join `sendCC` and
  `sendSysex`.
- **[`onEncoderTurn` fires for ordinary controls too](/oxi-e16-lua-api/callbacks/)**, not
  just script-assigned ones, and only when the *mapped* value changes.
- **The script size limit is 8000 bytes**, settled — see
  [Execution model](/oxi-e16-lua-api/execution-model/).

## Start here

- [Execution model](/oxi-e16-lua-api/execution-model/) — managed vs manual controls, 14-bit values, the
  memory limit that shapes large editors.
- [Assignments](/oxi-e16-lua-api/assignments/) — the `--@assign` directives that declare your parameters.
- [Callbacks](/oxi-e16-lua-api/callbacks/) — the seven functions the firmware calls, and what they carry.
- [Gotchas](/oxi-e16-lua-api/gotchas/) — read before writing anything; these are the traps that fail
  silently.
- [Patterns](/oxi-e16-lua-api/patterns/) — stepped option selectors, and what to do now that
  hold-and-turn is off the table.

## The seven globals

| Object | Purpose |
|---|---|
| [`controller`](/oxi-e16-lua-api/api/controller/) | Configure controls, read page index, attach encoder/SysEx callbacks. |
| [`page`](/oxi-e16-lua-api/api/page/) | Set the header title, attach init / page-change / var-change callbacks. |
| [`midi`](/oxi-e16-lua-api/api/midi/) | Send CC, Program Change, generic MIDI, and SysEx messages. |
| [`leds`](/oxi-e16-lua-api/api/leds/) | Take over LED rings from the firmware. |
| [`slots`](/oxi-e16-lua-api/api/slots/) | Override the text labels shown under each encoder. |
| [`var`](/oxi-e16-lua-api/api/var/) | Declare and read persistent script variables. |
| [`system`](/oxi-e16-lua-api/api/system/) | Configure and receive periodic script updates. |

## Two rules worth knowing up front

1. **Put `dis=0` on every `--@assign`.** Without it the firmware paints a numeric readout
   over your label whenever the encoder moves. See [Assignments](/oxi-e16-lua-api/assignments/).
2. **For a fixed set of options, declare `l=0 h=<count-1>`** and let the firmware quantize
   — `enc.scaled` then arrives as the option index, one detent per option.

[Open questions](/oxi-e16-lua-api/open-questions/) lists what the documentation does not settle, and what
it would take to answer each.
