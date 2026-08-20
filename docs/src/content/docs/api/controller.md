---
title: "controller"
description: "Configure controls by script ID or position, and read the current page."
---

Controls are addressed two ways:

- **By script ID** — the primary method. Uses the `id` from the assignment and searches
  across all pages, regardless of where the control sits.
- **By index** — page index + encoder position on that page.

## A script ID names a destination, not an encoder

**Clarified in API 1.2.0.** A Script ID belongs to a *destination assignment*, not to the
physical encoder as a whole. Destination 1 and destination 2 of one encoder may carry
different IDs. Three consequences:

- ID-based calls locate and modify the destination carrying that ID.
- If several destinations share an ID, the call applies to **all of them**. That is a usable
  feature — one `controller.set` can move a value on every page it appears on — but it is
  also how a stray duplicate ID produces action at a distance.
- `v`, `l`, `h`, `manual` and `accel` are stored **per destination**. `n` is not: it writes
  the encoder's single shared label, so both destinations always show the same one.

## `controller.set(id, key, value)` / `controller.set(id, props)`

Set properties on every Script turn destination with the given ID, across all pages and
both destinations.

```lua
controller.set(1, "v", 8192)
controller.set(1, {l=0, h=63, n="Cutoff"})
```

**It is a direct setter, not a simulated encoder turn — it does not trigger another
`onEncoderTurn`.** So writing a value back from inside the handler cannot recurse.

## `controller.setByIndex(page, index, key, value)` / `controller.setByIndex(page, index, props)`

Set properties on **turn destination 1** of a control, by page and encoder position.
Destination 2 is not reachable this way — use `controller.set(id, …)` when the exact
destination matters, especially on controls that use destination swapping.

```lua
local pg = controller.getPage()
controller.setByIndex(pg, 1, "v", 8192)
controller.setByIndex(pg, 1, {l=0, h=127, manual=true})
```

## `controller.setControls(controls)`

Bulk-configure all 16 encoders on the current page. Array position maps to encoder index
1–16.

```lua
controller.setControls({
  {i=1, n="AR",  l=0, h=31},
  {i=2, n="D1R", l=0, h=31},
  {i=3, n="D2R", l=0, h=31},
  {i=4, n="RR",  l=1, h=15},
})
```

:::caution[Undocumented in 1.2.0]
The 1.2.0 guide names `setControls` once, in passing, as a way to configure controls at
runtime — but gives it no section, no signature and no argument description, and its
property table omits the `i` key entirely. The guide also states that anything it does not
list does not exist. The signature above is the 1.0.0 one and is **unverified against the
new firmware**; prefer `set` / `setByIndex`, which are fully specified.
:::

## `controller.getPage()`

Returns the current page index (1-based).

## Property reference

| Field | Type | Description |
|---|---|---|
| `v` | int | Destination's stored internal value (0–16383) |
| `l` | int | Lower bound of the output range |
| `h` | int | Upper bound of the output range |
| `n` | string | The encoder's **shared** label (writes to `control.abbr`, max 4 chars) |
| `manual` | bool | If true, script owns the value; firmware won't auto-increment |
| `accel` | int | Acceleration mode (0=Div8 … 3=Acc0 default … 6=Acc3) |
| `i` | int | Script ID — 1.0.0 documented this as honoured **only** by `setControls`. Dropped from the 1.2.0 property table |

Numeric arguments accept floats as well as integers; the firmware truncates toward zero
when storing into an integer field and clamps to the endpoint's range. Calculated values
can be passed straight in without `math.floor`.
