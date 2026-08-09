---
title: "Callbacks"
description: "The six callbacks the firmware calls, and the payloads they carry."
---

Functions **you define** on the global objects; the firmware calls them.

## `page.onInit()`

Called once after the script loads and the Lua environment is ready. Use it to set the
title, initialise state, register variables, and request data from external gear.

```lua
function page.onInit()
  page.setTitle("Synth Edit")
  midi.sendSysex(0, {0xF0, 0x7D, 0x02, 0xF7})  -- request current values
end
```

## `controller.onEncoderTurn(enc)`

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

## `controller.onEncoderPress(enc)`

Called when a script-assigned encoder is pressed. `enc` carries **only**
`id`, `index`, `page`, `value`, `scaled` — **no `increment`, no `is_held`.**

## `controller.onSysex(bytes)`

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

## `page.onPageChange(previous_page, new_page)`

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

## `page.onVarChange(name)`

Called when the **firmware** changes a registered variable — typically the user editing it
via the device's variable menu. `name` is the registered variable name (string).

**Not** called for script-initiated `var.set`, so a handler can write variables without
recursing.
