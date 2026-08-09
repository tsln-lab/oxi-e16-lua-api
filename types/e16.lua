---@meta
--- Editor-only stubs for the OXI E16 Lua scripting API (API 1.0.0).
--- Transcribed from "The OXI E16 Manual", section 6 (Lua Scripting, pp. 85-109).
---
--- This file is never uploaded to the device — it exists so the language server
--- knows the globals the firmware injects.
---
--- Conventions from the manual:
---   * All indices are 1-based: encoders 1-16, pages 1-12.
---   * Values are stored internally as 14-bit integers (0-16383). A managed
---     control maps that to the l/h range from its assignment; the mapped
---     result is what `enc.scaled` gives you.
---   * MIDI output port 0 means "all outputs".

--------------------------------------------------------------------------------
-- Shared types
--------------------------------------------------------------------------------

---Persistent variable types, fixed at registration time.
---@alias VarType
---| '"int"'   # integer
---| '"bool"'  # boolean
---| '"float"' # floating point

---Encoder acceleration mode. 0 = Div8 (slowest), 3 = Acc0 (default), 6 = Acc3 (fastest).
---@alias AccelMode
---| 0 # Div8 - slowest
---| 1 # Div4
---| 2 # Div2
---| 3 # Acc0 - default
---| 4 # Acc1
---| 5 # Acc2
---| 6 # Acc3 - fastest

---LED ring palette index for `leds.update`. A discrete 16-entry palette, measured on
---hardware 2026-08-09 — not a hue ramp. Indices 1-4 and 13 are all blues, and 5/11 are
---both pinks, so only about nine entries are visually distinct: for controls that must be
---told apart at a glance use 0, 7, 9, 10, 12, 14, 15 plus one blue and one pink.
---@alias LedColor
---| 0  # purple
---| 1  # blue
---| 2  # blue, slightly darker
---| 3  # blue, lighter
---| 4  # blue, lighter
---| 5  # pink
---| 6  # light yellow
---| 7  # yellow
---| 8  # light peach
---| 9  # peach
---| 10 # red
---| 11 # pink
---| 12 # magenta
---| 13 # blue
---| 14 # cyan
---| 15 # green

---Event payload passed to `controller.onEncoderPress`.
---@class Encoder
---@field id integer     The control's script_id, from its `--@assign id=`
---@field index integer  Encoder position on the page (1-16)
---@field page integer   Current page (1-12)
---@field value integer  Internal 14-bit value (0-16383)
---@field scaled integer Output value mapped to the control's l/h range

---Event payload passed to `controller.onEncoderTurn`.
---Adds the two fields that only exist for turn events.
---@class EncoderTurn : Encoder
---@field increment integer Raw turn direction and speed: +/-1, 2, 4 or 8, depending on turn speed
---@field is_held boolean   Whether the encoder button is held down during the turn

---Properties settable via `controller.set` / `setByIndex` / `setControls`.
---@class ControlProps
---@field v integer?        Internal value (0-16383). Sets the control's current value.
---@field l integer?        Lower bound of the output range
---@field h integer?        Upper bound of the output range
---@field n string?         Display label (writes to control.abbr, max 4 chars)
---@field manual boolean?   If true, the script owns the value; firmware won't auto-increment
---@field accel AccelMode?  Acceleration mode
---@field i integer?        Script ID — only honoured by `setControls`, not `set`/`setByIndex`

--------------------------------------------------------------------------------
-- controller — control configuration, page index, encoder & sysex callbacks
--------------------------------------------------------------------------------

-- Callbacks are declared as @field rather than defined as functions, so that assigning
-- them in a script is not flagged as a duplicate definition.

---@class E16Controller
---@field onEncoderTurn fun(enc: EncoderTurn) Called when a script-assigned encoder is turned.
---@field onEncoderPress fun(enc: Encoder) Called when a script-assigned encoder is pressed. `enc` has no `increment` or `is_held`.
---@field onSysex fun(bytes: integer[]) Called on incoming SysEx. `bytes` includes the 0xF0 and 0xF7 framing bytes.
controller = {}

---Set one property on a control, found by its script ID across all pages.
---@param id integer Script ID from the control's assignment
---@param key string Property name — see ControlProps
---@param value number|string|boolean
---@overload fun(id: integer, props: ControlProps)
function controller.set(id, key, value) end

---Set one property on a control, addressed by page and encoder position.
---@param page integer  Page index (1-12)
---@param index integer Encoder position on that page (1-16)
---@param key string    Property name — see ControlProps
---@param value number|string|boolean
---@overload fun(page: integer, index: integer, props: ControlProps)
function controller.setByIndex(page, index, key, value) end

---Bulk-configure all 16 encoders on the current page.
---Array position maps to encoder index (1-16).
---@param controls ControlProps[]
function controller.setControls(controls) end

---@return integer page Current page index (1-based)
function controller.getPage() end

--------------------------------------------------------------------------------
-- page — header title, lifecycle callbacks
--------------------------------------------------------------------------------

---@class E16Page
---@field onInit fun() Called once after the script loads and the Lua environment is ready.
---@field onPageChange fun(previous_page: integer, new_page: integer) Called on page switch, 1-based. LED and label overlays are NOT cleared automatically — do it here.
---@field onVarChange fun(name: string) Called when the firmware changes a registered variable. NOT called for `var.set`.
page = {}

---Set the header text at the top of the screen. Max 15 characters.
---@param text string
function page.setTitle(text) end

---Revert the header to the default (scene name + page name).
function page.resetTitle() end

--------------------------------------------------------------------------------
-- midi — message output
--------------------------------------------------------------------------------

midi = {}

---Send a MIDI Control Change message.
---@param output integer  MIDI output port (0 = all outputs)
---@param channel integer MIDI channel (0-15)
---@param cc integer      Controller number (0-127)
---@param value integer   Value (0-127)
function midi.sendCC(output, channel, cc, value) end

---Send a raw SysEx message. Maximum 128 bytes per call.
---@param output integer  MIDI output port (0 = all outputs)
---@param bytes integer[] Full message including the 0xF0 start and 0xF7 end bytes
function midi.sendSysex(output, bytes) end

--------------------------------------------------------------------------------
-- leds — LED ring override
--------------------------------------------------------------------------------

leds = {}

---Take ownership of an encoder's LED ring and draw it.
---Once called, the firmware stops drawing that ring until `leds.reset`.
---@param index integer  Encoder position (1-16)
---@param value integer  Ring fill amount (0-16383, where 16383 is a full ring)
---@param color LedColor? Palette index (0-15), defaults to 0.
---A discrete palette, NOT a hue ramp. The editor's 0-100 color setting is also not a
---ramp; both index the same scattered palette family, but the mapping between the two
---is unknown. Color is independent of `value` — rings keep their color across the fill range.
function leds.update(index, value, color) end

---Hand the LED ring back to the firmware, which resumes drawing it from the
---control's internal value on the next render.
---@param index integer Encoder position (1-16)
function leds.reset(index) end

--------------------------------------------------------------------------------
-- slots — screen label override
--------------------------------------------------------------------------------

slots = {}

---Override the label shown under an encoder. Max 4 characters displayed;
---longer strings are truncated.
---@param index integer Encoder position (1-16)
---@param text string
function slots.update(index, text) end

---Remove the override and revert to the control's default label (control.abbr).
---@param index integer Encoder position (1-16)
function slots.reset(index) end

--------------------------------------------------------------------------------
-- var — persistent, per-scene script variables
--------------------------------------------------------------------------------
-- Stored in flash: survives scene exits and power cycles, and is loaded before
-- your script runs, so values are already present when page.onInit is called.
-- Variables are per-scene, so two scenes can each have a "cutoff" independently.

var = {}

---Declare a variable. The first call seeds the default; later calls with the
---same name are a silent no-op, so hot-reloading preserves the stored value.
---Re-registering an existing name with a different type does NOT change the
---type — the original wins. Registrations past the per-scene capacity are dropped.
---@param name string    Identifier, max 16 characters
---@param type VarType   Fixed at registration time
---@param default number|boolean Used only on first registration
function var.register(name, type, default) end

---Read a variable's current value, typed according to its registration.
---Fast enough for hot paths — names are interned firmware-side.
---@param name string
---@return integer|number|boolean|nil value `nil` if the name was never registered
function var.get(name) end

---Update an already-registered variable. The value is coerced to the registered
---type. No-op (returns nil) if the name was never registered.
---Does NOT fire `page.onVarChange`.
---@param name string
---@param value number|boolean
function var.set(name, value) end

---Remove a single variable. `var.get` returns nil until it is re-registered.
---@param name string
function var.delete(name) end

---Wipe the entire variable store for this scene.
function var.deleteAll() end
