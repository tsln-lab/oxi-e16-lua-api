---
title: "Global objects"
description: "The six globals the firmware injects into every script."
---

Six globals are injected by the firmware:

| Object | Purpose |
|---|---|
| `controller` | Configure controls, read page index, attach encoder/SysEx callbacks. |
| `page` | Set the header title, attach init / page-change / var-change callbacks. |
| `midi` | Send CC and SysEx messages. |
| `leds` | Take over LED rings from the firmware. |
| `slots` | Override the text labels shown under each encoder. |
| `var` | Declare and read persistent script variables. |
