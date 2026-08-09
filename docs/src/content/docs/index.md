---
title: OXI E16 Lua Scripting API
description: "Firmware API reference for OXI E16 Lua scripts, transcribed from the official manual and corrected against hardware."
---

Condensed from [*The OXI E16 Manual*](https://drive.google.com/file/d/1yZn1i96nRkosn2o6eDlj5wzuErPQEe9N/view?usp=sharing)
— OXI Instruments' own download — section 6 (pp. 85–109), plus p.10 (debug mode).
API version 1.0.0.

Machine-readable stubs of the same API live in `types/e16.lua` — keep the two in sync.

Findings marked with a date were **measured on hardware** and, in a few places, correct
what the manual says.

## Start here

- [Execution model](/oxi-e16-lua-api/execution-model/) — managed vs manual controls, 14-bit values, the
  memory limit that shapes large editors.
- [Assignments](/oxi-e16-lua-api/assignments/) — the `--@assign` directives that declare your parameters.
- [Callbacks](/oxi-e16-lua-api/callbacks/) — the six functions the firmware calls, and what they carry.
- [Gotchas](/oxi-e16-lua-api/gotchas/) — read before writing anything; these are the traps that fail
  silently.

## The six globals

| Object | Purpose |
|---|---|
| [`controller`](/oxi-e16-lua-api/api/controller/) | Configure controls, read page index, attach encoder/SysEx callbacks. |
| [`page`](/oxi-e16-lua-api/api/page/) | Set the header title, attach init / page-change / var-change callbacks. |
| [`midi`](/oxi-e16-lua-api/api/midi/) | Send CC and SysEx messages. |
| [`leds`](/oxi-e16-lua-api/api/leds/) | Take over LED rings from the firmware. |
| [`slots`](/oxi-e16-lua-api/api/slots/) | Override the text labels shown under each encoder. |
| [`var`](/oxi-e16-lua-api/api/var/) | Declare and read persistent script variables. |

## Two rules worth knowing up front

1. **Put `dis=0` on every `--@assign`.** Without it the firmware paints a numeric readout
   over your label whenever the encoder moves. See [Assignments](/oxi-e16-lua-api/assignments/).
2. **For a fixed set of options, declare `l=0 h=<count-1>`** and let the firmware quantize
   — `enc.scaled` then arrives as the option index, one detent per option.

[Open questions](/oxi-e16-lua-api/open-questions/) lists what the manual does not settle, and what it would
take to answer each.
