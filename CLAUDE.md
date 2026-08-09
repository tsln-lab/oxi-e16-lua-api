# e16

Lua scripts for the **OXI E16** MIDI controller. Scripts run on the device firmware, are
uploaded via the OXI App, and are constrained by tight memory limits.

## Before writing or reviewing any E16 Lua code

Read the API reference in [`docs/src/content/docs/`](docs/src/content/docs/) — the full
firmware API (six globals: `controller`, `page`, `midi`, `leds`, `slots`, `var`),
transcribed from section 6 of the official manual and corrected against hardware. These
Markdown files are the authoritative source for this project; do not guess at API surface.

Start with `gotchas.md` — it lists the traps that cause silent bugs. Then the page for
whatever you are touching: `assignments.md`, `callbacks.md`, or `api/<global>.md`.
`open-questions.md` records what is still unverified; do not present anything there as
settled.

## Layout

| Path | Purpose |
|---|---|
| `docs/src/content/docs/` | **API reference — authoritative.** Plain Markdown, one page per topic |
| `docs/` | Astro Starlight project wrapping those pages — config, deps, build output |
| `scripts/*.lua` | Device scripts — the actual deliverables |
| `tests/*.lua` | Hardware probes that answer entries in `open-questions.md` |
| `types/e16.lua` | `---@meta` LuaLS stubs of the API, for editor completion |
| `.luarc.json` | Points the language server at `types/`, declares the firmware globals |
| `mise.toml` | Pins Lua for the local syntax checker (not the device runtime) |
| `.github/workflows/deploy-docs.yml` | Builds and publishes `docs/` to GitHub Pages on push to `main` |

`docs/` is both the Astro project root and the home of the reference. Content lives only
in `docs/src/content/docs/`; everything else there is scaffolding. `docs/CLAUDE.md` and
`docs/AGENTS.md` are Astro's own template instructions, not project rules.

`types/e16.lua` and the pages in `docs/src/content/docs/` describe the same API —
**change both together.**

Cross-page links must be absolute **and include the base path**:
`/oxi-e16-lua-api/api/slots/`. The site deploys to GitHub Pages as a project site, so
everything is served under `/oxi-e16-lua-api/`, and Astro does **not** prefix links
written in Markdown. A link missing the prefix 404s in production while looking fine in a
casual read. Run a build and check for dead links after editing:

```bash
cd docs && npm run build
grep -rho 'href="/oxi-e16-lua-api/[a-z0-9/-]*/"' dist | sort -u \
  | sed 's|href="/oxi-e16-lua-api||;s|"||' \
  | while read u; do [ -f "dist${u}index.html" ] || echo "DEAD $u"; done
```

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
cd docs && npm run dev                   # preview the docs site
cd docs && npm run build                 # render to docs/dist/
```

Use the `mise exec --` form: `mise.toml` pins Lua for this directory, but a bare `luac`
is not on PATH in a non-interactive shell.

There is no way to run device scripts locally — the firmware globals do not exist
off-device, and nothing simulates the encoders. Syntax check plus the language server are
the only automated verification available.

Everything else has to be confirmed on hardware. When a question can only be answered that
way, write a probe in `tests/`, tell the user exactly what to look at, and record the
result on the relevant page under `docs/src/content/docs/` — do not guess, and do not try
to answer it from the manual, which is silent on all the remaining open questions.
