---
title: "Global objects"
description: "The seven globals the firmware injects into every script."
---

Seven globals are injected by the firmware. `system` is **new in API 1.2.0**.

| Object | Purpose |
|---|---|
| `controller` | Configure controls, read page index, attach encoder/SysEx callbacks. |
| `page` | Set the header title, attach init / page-change / var-change callbacks. |
| `midi` | Send CC, Program Change, generic MIDI, and SysEx messages. |
| `leds` | Take over LED rings from the firmware. |
| `slots` | Override the text labels shown under each encoder. |
| `var` | Declare and read persistent script variables. |
| `system` | Configure and receive periodic script updates. |
