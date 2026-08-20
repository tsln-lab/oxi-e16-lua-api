---
title: "var"
description: "Per-scene variables that persist in flash across power cycles."
---

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

## `var.register(name, type, default)`

| Param | Note |
|---|---|
| `name` | identifier, **max 16 characters** |
| `type` | `"int"`, `"bool"`, or `"float"` |
| `default` | used **only** on first registration |

The first call seeds the default; **subsequent calls with the same name are a silent
no-op**, so re-running the script (hot reload) preserves the stored value.

Edge cases: registrations past the per-scene capacity are **dropped**. Re-registering an
existing name with a different type does **not** update the type — the original wins.

## `var.get(name)`

Returns the value typed appropriately (integer / boolean / float), or **`nil` if never
registered**. Fast enough for hot paths — names are interned firmware-side.

The LuaLS stub types this as `any` rather than a union of the three. A union makes every
call site a type error the moment the value is used in arithmetic or passed to a typed
parameter, and the real type is only knowable from the matching `var.register` call.
Guard the `nil` case yourself — `var.get("channel") or 1`.

## `var.set(name, value)`

Updates an already-registered variable; the value is coerced to the registered type.
No-op returning `nil` if the name was never registered.
**Does not fire `page.onVarChange`** — script writes are silent, so handlers can call it
without recursing.

## `var.delete(name)` / `var.deleteAll()`

Remove one variable (subsequent `var.get` returns `nil`) or wipe the whole store.
`deleteAll` resets to empty regardless of what was persisted.

## Full example

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
