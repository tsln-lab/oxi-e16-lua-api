---
title: "midi"
description: "Send CC and SysEx messages."
---

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

## `midi.sendSysex(output, bytes)`

`bytes` must be a table of integers **including** the `0xF0` start and `0xF7` end bytes.
**Maximum 128 bytes per call.**

```lua
midi.sendSysex(0, { 0xF0, 0x7D, 0x01, param, value, 0xF7 })
```
