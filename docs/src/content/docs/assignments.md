---
title: "Assignments (--@assign)"
description: "The --@assign comment directives that declare a script's parameters, and every key they accept."
---

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
| `id` | int | **yes** | — | Script ID. Identifies this **turn destination or push action** in callbacks as `enc.id`. |
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

**An `id` names a destination, not an encoder.** Destination 1 and destination 2 of the same
encoder may carry different IDs, and every ID-based API call resolves to the destination
holding that ID — **all of them, if more than one does**. Reusing an ID across pages is a
deliberate way to move several controls at once; reusing it by accident is action at a
distance. See [controller](/oxi-e16-lua-api/api/controller/).

Assignment directives are ordinary Lua comments, so they are stripped before upload and
**do not count toward the 8000-byte script limit**. Declare as many as the script needs.

## Acceleration modes (`accel`)

| Value | Mode | Effect |
|---|---|---|
| 0 | Div8 | Slowest — resolution divided by 8 |
| 1 | Div4 | Resolution divided by 4 |
| 2 | Div2 | Resolution divided by 2 |
| 3 | Acc0 | **Default** — normal, no acceleration |
| 4 | Acc1 | Light acceleration |
| 5 | Acc2 | Medium acceleration |
| 6 | Acc3 | Fastest |
