---
title: "midi"
description: "Send CC, Program Change, generic MIDI, and SysEx messages."
---

Every function takes `output` first. **`0` means all outputs** — see
[The `output` argument](#the-output-argument) for what the other values probably are.
Channels are **0-based** (0–15), unlike every index in the rest of the API.

## `midi.sendCC(output, channel, cc, value)`

| Param | Range | Note |
|---|---|---|
| `output` | port index | **0 = all outputs** |
| `channel` | 0–15 | zero-based |
| `cc` | 0–127 | |
| `value` | 0–127 | |

```lua
midi.sendCC(0, 0, 74, 64)  -- CC 74, value 64, channel 1, all outputs
```

## `midi.sendPC(output, channel, program)`

**New in API 1.2.0.** Send a Program Change.

| Param | Range |
|---|---|
| `output` | port index, 0 = all |
| `channel` | 0–15 |
| `program` | 0–127 |

```lua
midi.sendPC(0, 0, 10)
```

## `midi.sendMidi(output, channel, status, data1, data2)`

**New in API 1.2.0.** Send an arbitrary channel-voice message — notes, aftertouch, pitch
bend, anything the two dedicated helpers do not cover.

| Param | Note |
|---|---|
| `output` | port index, 0 = all |
| `channel` | 0–15 |
| `status` | **Complete status byte, including its channel nibble** — `0x90` is Note On on channel 1 |
| `data1` | first data byte |
| `data2` | second data byte |

```lua
midi.sendMidi(0, 0, 0x90, 60, 100)  -- Note On, middle C, velocity 100
```

The `channel` argument and the channel nibble baked into `status` are both present and the
guide does not say which wins when they disagree. Keep them consistent — see
[Open questions](/oxi-e16-lua-api/open-questions/).

## `midi.sendSysex(output, bytes)`

`bytes` must be a table of integers **including** the `0xF0` start and `0xF7` end bytes.
**Maximum 128 bytes per call.**

```lua
midi.sendSysex(0, { 0xF0, 0x7D, 0x01, param, value, 0xF7 })
```

## The `output` argument

**`0` = all outputs is the only value either document specifies.** The 1.2.0 guide says
exactly that, four times, and stops.

It is not a Port A / Port B selector. The manual's per-destination *Output* setting
(pp. 26–33) enumerates **transport × port**, identically in all twelve control tables:

> Same as Page, **TRS1, TRS2, USB1, USB2, USB3, BLE, ALL-BLE** (all except bluetooth),
> **ALL-USB** (all except USB), Off

Page level drops *Same as Page* — there is nothing above it to inherit from — and leads
with **All**, which is where Lua's documented `0` sits. Port A and Port B are the second
axis only: they are logical ports sharing one physical output (p.18, "may be identified as
1 and 2 on some external DAWs"), so TRS1 vs TRS2 is that A/B split carried over TRS.

**Unverified hypothesis**, from the order the page-level list runs in:

| 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| All | TRS1 | TRS2 | USB1 | USB2 | USB3 | BLE | ALL-BLE | ALL-USB | Off |

:::note[Measured 2026-08-20: `0` = All and `3` = USB1]
Sending SysEx from a script on index **3** reached Ableton Live with **only USB1 enabled**
in Live's MIDI preferences, so the port was isolated rather than inferred from a global
input indicator. Index **0** arrives the same way, consistent with its documented "all
outputs". Both match the hypothesised order below.

The remaining eight entries are still untested, as are TRS and BLE — the two indices
measured here happen to be the two the guide already effectively gives you.
:::

Do not rely on the rest. `0` is the only value either document specifies —
`tests/output_port_probe.lua` does it in one button press by sending a different CC number
on each index, so every receiver identifies itself. See
[Open questions](/oxi-e16-lua-api/open-questions/).
