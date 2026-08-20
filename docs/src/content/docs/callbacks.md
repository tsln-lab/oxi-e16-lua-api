---
title: "Callbacks"
description: "The seven callbacks the firmware calls, and the payloads they carry."
---

Functions **you define** on the global objects; the firmware calls them.

## `page.onInit()`

Called once after the script loads and the Lua environment is ready. Use it to set the
title, initialise state, register variables, enable periodic updates, and request data from
external gear.

```lua
function page.onInit()
  page.setTitle("Synth Edit")
  midi.sendSysex(0, {0xF0, 0x7D, 0x02, 0xF7})  -- request current values
end
```

## `controller.onEncoderTurn(enc)`

Called when a **turn destination receives a value update**. A physical turn is the normal
source, but recorder playback, the Random special function, group moves, and other internal
value processing also fire it.

:::note[Widened in API 1.2.0]
It is no longer limited to script-assigned encoders — **ordinary controls fire it too**. A
script on the scene can therefore observe every encoder on the page, not just the ones its
assignments claim. For an ordinary control there is no meaningful `enc.id`; identify it by
`enc.page` and `enc.index`.
:::

With two destinations enabled, each destination is handled independently. With Change
Destination enabled, only the active one is handled.

**When it fires depends on the mode:**

| Control | Timing | What `value`/`scaled` hold |
|---|---|---|
| Ordinary, or managed Script | *after* the value is stored, and **only when the mapped output value changes** | the newly committed value |
| Manual Script | *before* any automatic value change | the currently stored value |

That "only when the mapped output changes" rule is useful rather than annoying: on a
control declared `l=0 h=4`, several detents of physical movement produce one callback per
option, not one per detent.

| Field | Type | Description |
|---|---|---|
| `enc.id` | int | Script ID for a Script destination. Not meaningful for ordinary controls |
| `enc.index` | int | Encoder position on the page (1–16) |
| `enc.page` | int | Current page (1–12) |
| `enc.increment` | int | Raw physical turn direction and speed, normally ±1, ±2, ±4 or ±8. **An independent input signal, not the provenance of `enc.value`** — it is `0` when no physical increment exists, e.g. on a group slave turn |
| `enc.value` | int | Internal 14-bit value (0–16383) |
| `enc.scaled` | int | `enc.value` mapped to this destination's `l`/`h` range |
| `enc.is_held` | bool | **Reserved; currently always `false`.** See below |

```lua
function controller.onEncoderTurn(enc)
  if enc.id == 1 then
    midi.sendCC(0, 1, 74, enc.scaled)
  end
end
```

:::danger[`enc.is_held` does not work]
1.2.0 documents it as *"reserved for held-turn detection; currently always `false`"*. Any
branch on it takes the false path, always, with no error. **Hold-and-turn cannot be
implemented this way** — see [Patterns](/oxi-e16-lua-api/patterns/) for what to do instead.
:::

## `controller.onEncoderPress(enc)`

Called when a script-assigned encoder is pressed. `enc` carries **only**
`id`, `index`, `page`, `value`, `scaled` — **no `increment`, no `is_held`.**

There is no release event.

## `controller.onSysex(bytes)`

Called when the E16 receives a SysEx message. `bytes` is a table of raw integer byte
values **including** the `0xF0` and `0xF7` framing bytes.

:::tip[Confirmed on hardware, 2026-08-20]
**SysEx sent from a computer over USB does reach the script.** Neither document says which
input `onSysex` listens on, and nothing else in the API can carry data inbound — this is
the only callback that receives MIDI at all, which is why incoming clock is invisible to a
script ([Patterns](/oxi-e16-lua-api/patterns/)).

Measured with [`sysex_in_probe.lua`](../sysex_in_probe.lua), sending
`F0 7D 01 48 69 F7` from a host SysEx utility:

- The message arrives, and successive messages accumulate — the script's counter went 1, 2.
- `bytes` **does** include the framing, as documented: a four-data-byte message reports
  `#bytes == 6`, so `bytes[2]` is the manufacturer ID and `bytes[3]` the first payload byte.
- `0x7D` survives the trip unaltered, so dispatching on the ID byte works.

Still unmeasured: whether the other transports in the `output` list — TRS, BLE — deliver
inbound SysEx too. Only USB has been tried.
:::

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

**LED and label overlays are NOT cleared automatically on page change.** They are stored by
physical encoder position, not by page, so an override left on encoder 3 reappears on
encoder 3 of the new page. Tear down the old page's overlays and build the new page's here.

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

## `system.update()`

**New in API 1.2.0.** Called periodically once `system.setUpdateRate(ms)` has enabled
polling, at 20–1000 ms intervals. Takes no arguments.

This is the only callback not driven by a user action — it is what makes animation,
timeouts and reverting labels possible. **If it raises an error the firmware disables
periodic updates for the script**, silently. See [`system`](/oxi-e16-lua-api/api/system/).

```lua
function page.onInit()
  system.setUpdateRate(20)
end

function system.update()
  -- roughly every 20 ms
end
```
