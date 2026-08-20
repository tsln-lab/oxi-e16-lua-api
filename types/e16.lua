---@meta
--- Editor-only stubs for the OXI E16 Lua scripting API (API 1.2.0).
--- Transcribed from OXI Instruments' "OXI E16 Lua Scripting API Guide v1.2.0",
--- which supersedes section 6 of "The OXI E16 Manual" (pp. 85-109).
---
--- This file is never uploaded to the device — it exists so the language server
--- knows the globals the firmware injects.
---
--- Conventions:
---   * All indices are 1-based: encoders 1-16, pages 1-12.
---   * Values are stored internally as 14-bit integers (0-16383). A managed
---     control maps that to the l/h range from its assignment; the mapped
---     result is what `enc.scaled` gives you.
---   * MIDI output port 0 means "all outputs"; MIDI channels are 0-15.
---   * Numeric arguments accept floats. The firmware truncates toward zero when
---     storing into an integer field, and clamps to the endpoint's range, so
---     calculated values need no math.floor().

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

---Event payload passed to `controller.onEncoderPress`.
---@class Encoder
---@field id integer     The destination's script_id, from its `--@assign id=`
---@field index integer  Encoder position on the page (1-16)
---@field page integer   Current page (1-12)
---@field value integer  Internal 14-bit value (0-16383)
---@field scaled integer Output value mapped to the destination's l/h range

---Event payload passed to `controller.onEncoderTurn`.
---Adds the two fields that only exist for turn events.
---@class EncoderTurn : Encoder
---@field increment integer Raw physical turn direction and speed, normally +/-1, 2, 4 or 8. An independent input signal, not the provenance of `value`: it is 0 when no physical increment exists, e.g. on a group slave turn.
---@field is_held boolean   RESERVED — the firmware always sets this to false. Held-turn detection is not implemented; branching on it always takes the false path.

---Properties settable via `controller.set` / `setByIndex` / `setControls`.
---`v`, `l`, `h`, `manual` and `accel` are stored per turn destination; `n` writes
---the encoder's single shared label, so both destinations always show the same one.
---@class ControlProps
---@field v integer?        Destination's stored internal value (0-16383)
---@field l integer?        Lower bound of the output range
---@field h integer?        Upper bound of the output range
---@field n string?         Shared encoder label (writes to control.abbr, max 4 chars)
---@field manual boolean?   If true, the script owns the value; firmware won't auto-increment
---@field accel AccelMode?  Acceleration mode
---@field i integer?        Script ID — documented in API 1.0.0 as honoured only by `setControls`, and dropped from the 1.2.0 property table entirely.

---One entry in a batched `leds.update` call: {script_id, value, color?}.
---@alias LedBatchEntry [integer, integer, integer?]

--------------------------------------------------------------------------------
-- controller — control configuration, page index, encoder & sysex callbacks
--------------------------------------------------------------------------------

-- Callbacks are declared as @field rather than defined as functions, so that assigning
-- them in a script is not flagged as a duplicate definition.

---@class E16Controller
---@field onEncoderTurn fun(enc: EncoderTurn) Called when a turn destination receives a value update. Since API 1.2.0 this includes ordinary controls, not only script-assigned ones, and internal sources such as recorder playback, Random and group moves. For managed destinations it fires after the value is stored and only when the mapped output changes; for manual ones it fires first, carrying the currently stored value.
---@field onEncoderPress fun(enc: Encoder) Called when a script-assigned encoder is pressed. `enc` has no `increment` or `is_held`. There is no release event.
---@field onSysex fun(bytes: integer[]) Called on incoming SysEx. `bytes` includes the 0xF0 and 0xF7 framing bytes.
controller = {}

---Set one property on every Script turn destination carrying this script ID,
---across all pages and both destinations. A direct setter, not a simulated turn:
---it does not trigger another `onEncoderTurn`.
---@param id integer Script ID from the destination's assignment
---@param key string Property name — see ControlProps
---@param value number|string|boolean
---@overload fun(id: integer, props: ControlProps)
function controller.set(id, key, value) end

---Set one property on TURN DESTINATION 1 of a control, addressed by page and
---encoder position. Destination 2 is not reachable this way — use `controller.set`
---when the exact destination matters, especially with destination swapping.
---@param page integer  Page index (1-12)
---@param index integer Encoder position on that page (1-16)
---@param key string    Property name — see ControlProps
---@param value number|string|boolean
---@overload fun(page: integer, index: integer, props: ControlProps)
function controller.setByIndex(page, index, key, value) end

---Bulk-configure all 16 encoders on the current page.
---Array position maps to encoder index (1-16).
---
---UNVERIFIED on API 1.2.0: the guide mentions this function once in passing but
---gives it no signature, and states that unlisted functions do not exist. This
---signature is the 1.0.0 one. Prefer `set` / `setByIndex`.
---@param controls ControlProps[]
function controller.setControls(controls) end

---@return integer page Current page index (1-based)
function controller.getPage() end

--------------------------------------------------------------------------------
-- page — header title, lifecycle callbacks
--------------------------------------------------------------------------------

---@class E16Page
---@field onInit fun() Called once after the script loads and the Lua environment is ready.
---@field onPageChange fun(previous_page: integer, new_page: integer) Called on page switch, 1-based. LED and label overlays are keyed by physical position and NOT cleared automatically — do it here.
---@field onVarChange fun(name: string) Called when the firmware changes a registered variable. NOT called for `var.set`.
page = {}

---Set the header text at the top of the screen. Max 15 characters.
---Redrawn immediately and kept across page changes until `page.resetTitle`.
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

---Send a MIDI Program Change message. (API 1.2.0)
---@param output integer  MIDI output port (0 = all outputs)
---@param channel integer MIDI channel (0-15)
---@param program integer Program number (0-127)
function midi.sendPC(output, channel, program) end

---Send a generic MIDI message. (API 1.2.0)
---@param output integer  MIDI output port (0 = all outputs)
---@param channel integer MIDI channel (0-15)
---@param status integer  Complete status byte INCLUDING its channel nibble — 0x90 is Note On on channel 1
---@param data1 integer   First data byte
---@param data2 integer   Second data byte
function midi.sendMidi(output, channel, status, data1, data2) end

---Send a raw SysEx message. Maximum 128 bytes per call.
---@param output integer  MIDI output port (0 = all outputs)
---@param bytes integer[] Full message including the 0xF0 start and 0xF7 end bytes
function midi.sendSysex(output, bytes) end

--------------------------------------------------------------------------------
-- leds — LED ring override
--------------------------------------------------------------------------------

leds = {}

---Take ownership of the LED ring for every CURRENT-PAGE Script destination with
---this script ID, and draw it. The firmware stops drawing those rings until
---`leds.reset`.
---
---CHANGED IN API 1.2.0: the first argument is a SCRIPT ID, not an encoder
---position — `leds.updateByIndex` is the old behaviour. Note that `leds.reset`
---still takes a position.
---@param id integer     Script ID from the destination's `--@assign`
---@param value integer  Ring fill amount (0-16383, where 16383 is a full ring)
---@param color integer? Color rotation (0-100), defaults to 0. Clamped, not rejected.
---API 1.0.0 documented this as a 0-15 palette index and the palette measured on that
---firmware was not a hue ramp; what 0-100 renders as on 1.2.0 is unverified.
---@overload fun(batch: LedBatchEntry[])
function leds.update(id, value, color) end

---As `leds.update`, but addressed by physical encoder position. (API 1.2.0)
---@param index integer  Encoder position (1-16)
---@param value integer  Ring fill amount (0-16383)
---@param color integer? Color rotation (0-100), defaults to 0
---@overload fun(batch: LedBatchEntry[])
function leds.updateByIndex(index, value, color) end

---Hand the LED ring back to the firmware, which resumes drawing it from the
---control's internal value on the next render. Takes a POSITION, not a script ID.
---@param index integer Encoder position (1-16)
function leds.reset(index) end

--------------------------------------------------------------------------------
-- slots — screen label override
--------------------------------------------------------------------------------

slots = {}

---Override the label shown under an encoder. Max 4 characters displayed;
---longer strings are truncated. Takes precedence over the configured label and
---over the firmware's numeric readout, until `slots.reset`.
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
---@return any value Typed per registration: integer for "int", number for "float",
---boolean for "bool". `nil` if the name was never registered.
---Deliberately `any` rather than a union — a union makes every call site a type error
---the moment the value is used in arithmetic or passed to a typed parameter, and the
---real type is only knowable from the matching `var.register` call.
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

--------------------------------------------------------------------------------
-- system — periodic script updates (API 1.2.0)
--------------------------------------------------------------------------------

---@class E16System
---@field update fun() Called every `setUpdateRate` milliseconds once polling is enabled. Takes no arguments. If it raises an error the firmware silently disables periodic updates for the script.
system = {}

---Set the interval for `system.update()`. Valid intervals are 20-1000 ms;
---anything outside that range, including 0, disables periodic updates.
---@param milliseconds integer
function system.setUpdateRate(milliseconds) end
