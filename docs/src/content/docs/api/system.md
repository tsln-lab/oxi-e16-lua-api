---
title: "system"
description: "Periodic script updates — the timer the API previously had no equivalent of."
---

**New in API 1.2.0.** The seventh global, and the only source of events that is not a
user action. Before it existed, a script could only run in response to a turn, a press,
incoming SysEx, a page change, or a variable edit — so anything that had to keep moving on
its own, or revert "after a moment", was impossible.

## `system.setUpdateRate(milliseconds)`

Enables periodic calls to `system.update()`.

| Argument | Effect |
|---|---|
| 20–1000 | Interval in milliseconds |
| anything else, including `0` | **Disables** periodic updates |

```lua
system.setUpdateRate(20)  -- ~50 Hz
system.setUpdateRate(0)   -- off
```

The valid range caps the fastest tick at 50 Hz. Call it from `page.onInit`.

## `system.update()`

The callback. Takes no arguments and returns nothing. Called approximately every
`setUpdateRate` milliseconds once enabled.

```lua
function system.update()
  -- animation, timeouts, polling
end
```

**If `system.update()` raises an error, the firmware disables periodic updates for the
script.** There is no automatic retry and no message — the animation simply stops. A tick
handler that indexes a table with a value that can go `nil` will silently kill itself on
the first bad frame, so keep the body defensive.

`system.update()` has no idea which page is showing. Guard it if the work is page-specific:

```lua
local home_page = 1

function page.onInit()
  home_page = controller.getPage()
  system.setUpdateRate(20)
end

function system.update()
  if controller.getPage() ~= home_page then return end
  -- ... animate
end
```

## What it makes possible

- **Animated LED rings** — sweeps, pulses, VU-style meters driven from
  [`leds`](/oxi-e16-lua-api/api/leds/) rather than from control values.
- **Transient labels that revert.** Previously a
  [`slots`](/oxi-e16-lua-api/api/slots/) overlay could only be replaced by another event;
  now a tick can count down and call `slots.reset` itself.
- **Throttling outbound MIDI.** Accumulate in `onEncoderTurn`, send at most one message per
  tick, instead of one per detent.
