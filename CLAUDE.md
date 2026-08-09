# e16

Lua scripts for the **OXI E16** MIDI controller. Scripts run on the device firmware, are
uploaded via the OXI App, and are constrained by tight memory limits.

## Before writing or reviewing any E16 Lua code

Read [`docs/e16-lua-api.md`](docs/e16-lua-api.md) — the full firmware API reference
(six globals: `controller`, `page`, `midi`, `leds`, `slots`, `var`), transcribed from
section 6 of the official manual. It is the authoritative source for this project;
do not guess at API surface.

Section 11 of that document lists the gotchas that cause silent bugs — check new code
against it.

## Layout

| Path | Purpose |
|---|---|
| `docs/e16-lua-api.md` | API reference — authoritative |
| `docs/*MIDIimp.txt` | Target-synth MIDI implementation docs (CC numbers, value tables) |
| `docs/example.lua` | The manual's TX81Z example. Reference only — not our code, do not edit |
| `docs/OXI E16 - User Manual.pdf` | Source PDF the reference was transcribed from |
| `scripts/*.lua` | Device scripts — the actual deliverables |
| `tests/*.lua` | Hardware probes that answer open questions in the reference, §13 |
| `types/e16.lua` | `---@meta` LuaLS stubs of the API, for editor completion |
| `.luarc.json` | Points the language server at `types/`, declares the firmware globals |
| `mise.toml` | Pins Lua for the local syntax checker (not the device runtime) |

`types/e16.lua` and `docs/e16-lua-api.md` describe the same API — **change both together.**

Callbacks in `types/e16.lua` are declared as `@field` on a class, not defined as
functions — keep it that way when adding new callbacks. `duplicate-set-field` is also
disabled in `.luarc.json`, because firmware callbacks are meant to be assigned by scripts
and the `@field` form alone did not silence it for `controller.*`.

## Conventions

- `snake_case` for locals and functions; the firmware globals are given.
- Always `local` — a bare assignment silently creates a global.
- Target **Lua 5.4** (device runtime), not the locally installed interpreter.

## Writing device scripts

Two rules established on hardware, both non-obvious and both cheap to get wrong:

- **Put `dis=0` on every `--@assign`.** Without a `dis` key the firmware paints a numeric
  readout over your label whenever the encoder moves, so the label you set is not the
  label the user sees. `dis=0` silences it and keeps a normal unipolar ring.
- **For a parameter with a fixed set of options, declare `l=0 h=<count-1>`** and let the
  firmware quantize. `enc.scaled` then arrives as the option index, one detent per option,
  already clamped — no `manual=true`, no accumulator, no rounding. Look up the outgoing
  value and the label from parallel arrays. `scripts/nts-1.lua` is the worked example.

Encoder labels are **4 characters**, and each encoder has only one. A control cannot show
its parameter name and its current value at the same time — pick one per script.

## Checking work

```bash
mise exec -- luac -p scripts/nts-1.lua   # syntax check
```

Use the `mise exec --` form: `mise.toml` pins Lua for this directory, but a bare `luac`
is not on PATH in a non-interactive shell.

There is no way to run device scripts locally — the firmware globals do not exist
off-device, and nothing simulates the encoders. Syntax check plus the language server are
the only automated verification available.

Everything else has to be confirmed on hardware. When a question can only be answered that
way, write a probe in `tests/`, tell the user exactly what to look at, and record the
result in `docs/e16-lua-api.md` — do not guess, and do not try to answer it from the
manual, which is silent on all the remaining open questions.
