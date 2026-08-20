---
title: "page"
description: "Set and reset the screen header."
---

## `page.setTitle(text)`

Sets the header text at the top of the screen. **Max 15 characters.**

The override is redrawn immediately and **survives page changes** — it stays until
`page.resetTitle()`. Unlike LED and slot overrides, there is nothing to tear down per page,
so a title set in `page.onInit` is correct everywhere.

Loading or clearing a script drops the title override together with all LED-ring and
slot-label overrides.

## `page.resetTitle()`

Reverts to the default header (scene name + page name).

## Callbacks

`page` also carries [`onInit`, `onPageChange` and `onVarChange`](/oxi-e16-lua-api/callbacks/).
