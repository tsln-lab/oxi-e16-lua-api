---
title: "controller"
description: "Configure controls by script ID or position, and read the current page."
---

Controls are addressed two ways:

- **By script ID** — the primary method. Uses the `id` from the assignment and searches
  across all pages, regardless of where the control sits.
- **By index** — page index + encoder position on that page.

## `controller.set(id, key, value)` / `controller.set(id, props)`

Set properties on a control by its script ID.

```lua
controller.set(1, "v", 8192)
controller.set(1, {l=0, h=63, n="Cutoff"})
```

## `controller.setByIndex(page, index, key, value)` / `controller.setByIndex(page, index, props)`

Set properties by page and encoder position.

```lua
local pg = controller.getPage()
controller.setByIndex(pg, 1, "v", 8192)
controller.setByIndex(pg, 1, {l=0, h=127, manual=true})
```

## `controller.setControls(controls)`

Bulk-configure all 16 encoders on the current page. Array position maps to encoder index 1–16.

```lua
controller.setControls({
  {i=1, n="AR",  l=0, h=31},
  {i=2, n="D1R", l=0, h=31},
  {i=3, n="D2R", l=0, h=31},
  {i=4, n="RR",  l=1, h=15},
})
```

## `controller.getPage()`

Returns the current page index (1-based).

## Property reference

| Field | Type | Description |
|---|---|---|
| `v` | int | Internal value (0–16383). Sets the control's current value. |
| `l` | int | Lower bound of the output range |
| `h` | int | Upper bound of the output range |
| `n` | string | Display label (writes to `control.abbr`, max 4 chars) |
| `manual` | bool | If true, script owns the value; firmware won't auto-increment |
| `accel` | int | Acceleration mode (0=Div8 … 3=Acc0 default … 6=Acc3) |
| `i` | int | Script ID — **only works in `setControls()`**, not `set()`/`setByIndex()` |
