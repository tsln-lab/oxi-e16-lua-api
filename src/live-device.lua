-- Ableton Live — device and mixer control for the OXI E16.
--
-- Pairs with the Live Remote Script in `ableton/OXI_E16/`. Live abbreviates names to the
-- 4 characters the E16 screen allows and pushes name + value to the sixteen encoders over
-- SysEx; turning an encoder sends the value back.
--
-- What the sixteen encoders mean depends on the E16 PAGE, which is the device's own mode
-- mechanism, so no toggle had to be invented:
--
--   page 1  the selected device's parameters, in order
--   page 2+ the mixer, four tracks per page as vertical strips -- volume, pan, send A,
--          send B down each column. Page 3 is the next four tracks, and so on.
--
-- Every message the E16 sends carries its page, so Live always knows what a slot means
-- and a page change cannot be misread as a value change.
--
-- Drop the same sixteen assignments onto every page you want to use. Sharing script IDs
-- across pages is deliberate: `controller.set` writes to every destination holding an ID,
-- so one repaint covers all of them, and only the page you are looking at is visible
-- anyway. Each page change triggers a fresh repaint for that page.
--
-- Why SysEx in both directions: `controller.onSysex` is the ONLY inbound callback the
-- firmware offers. Incoming CC and notes never reach a script, so parameter names and
-- values can only arrive as SysEx — and once SysEx is the return path, using it outbound
-- too keeps one framing for both. It also means the Live side needs no MIDI map: Live
-- forwards SysEx to a control surface unconditionally, while CC has to be registered
-- with `forward_midi_cc` in `build_midi_map` before the script ever sees it.
--
-- Display strategy: `controller.set` does both halves, and nothing else is needed.
--
--   set "n" -> the label under the encoder (`dis=0` stops the firmware painting a
--              numeric readout over it)
--   set "v" -> the internal 14-bit value, which the firmware draws as the LED ring
--
-- It is addressed by script ID and searches every page, so it works from `onInit` --
-- before any encoder has been touched, and whatever page the user is looking at.
--
-- `slots.update` cannot do the label half: it takes an encoder POSITION, which a script
-- only learns from `enc.index` on a turn, so it cannot paint a control nobody has touched.
-- `leds.update` could do the ring half since 1.2.0 (it takes a script ID now, not a
-- position), but there is no reason to: writing "v" is needed anyway so the next turn
-- continues from the right place, the firmware draws the ring from it for free, and
-- taking the ring over would mean owning it until an explicit `leds.reset` -- on the
-- current page only, where `controller.set` reaches every page.
--
-- Net effect: no position dependency, no page dependency, and no overlay to tear down in
-- `onPageChange`. Parameter slot N is script ID N.
--
-- Build with: mise exec -- lua build.lua

--@assign id=1  abbr="P1"  name="Param 1"  l=0 h=127 dis=0
--@assign id=2  abbr="P2"  name="Param 2"  l=0 h=127 dis=0
--@assign id=3  abbr="P3"  name="Param 3"  l=0 h=127 dis=0
--@assign id=4  abbr="P4"  name="Param 4"  l=0 h=127 dis=0
--@assign id=5  abbr="P5"  name="Param 5"  l=0 h=127 dis=0
--@assign id=6  abbr="P6"  name="Param 6"  l=0 h=127 dis=0
--@assign id=7  abbr="P7"  name="Param 7"  l=0 h=127 dis=0
--@assign id=8  abbr="P8"  name="Param 8"  l=0 h=127 dis=0
--@assign id=9  abbr="P9"  name="Param 9"  l=0 h=127 dis=0
--@assign id=10 abbr="P10" name="Param 10" l=0 h=127 dis=0
--@assign id=11 abbr="P11" name="Param 11" l=0 h=127 dis=0
--@assign id=12 abbr="P12" name="Param 12" l=0 h=127 dis=0
--@assign id=13 abbr="P13" name="Param 13" l=0 h=127 dis=0
--@assign id=14 abbr="P14" name="Param 14" l=0 h=127 dis=0
--@assign id=15 abbr="P15" name="Param 15" l=0 h=127 dis=0
--@assign id=16 abbr="P16" name="Param 16" l=0 h=127 dis=0

local SYX   = 0x7D   -- SysEx ID 0x7D: reserved for non-commercial use
local OUT   = 0      -- 0 = all outputs
local SLOTS = 16
local BLANK = "-"    -- label for a slot the device has no parameter for

-- Encoders are declared l=0 h=127, so `enc.scaled` is 0..127 and one detent is one step.
-- 127 * 129 == 16383 exactly, so scaling by STEP maps a full encoder sweep onto the full
-- 14-bit range the protocol carries. See the docs page for why h is not 16383.
local STEP = 129

-- Live -> E16
local CMD_DEVICE = 0x01  -- device name, for the header
local CMD_PARAM  = 0x02  -- slot, value, name — a full slot refresh
local CMD_VALUE  = 0x03  -- slot, value — parameter moved in Live
local CMD_CLEAR  = 0x04  -- Live disconnected

-- E16 -> Live
local CMD_SET   = 0x10   -- slot, value — encoder turned here
local CMD_HELLO = 0x11   -- send me the current device

-- Read ASCII bytes from `from` up to the byte before the closing 0xF7.
local function text(b, from)
    local s = ""
    for i = from, #b - 1 do
        s = s .. string.char(b[i])
    end
    return s
end

local function blank_all()
    for id = 1, SLOTS do
        controller.set(id, { n = BLANK, v = 0 })
    end
end

local function hello(page)
    midi.sendSysex(OUT, { 0xF0, SYX, CMD_HELLO, page or 1, 0xF7 })
end

function page.onInit()
    page.setTitle("Live")
    blank_all()
    -- The E16 may well come up after Live has already sent its state, so ask rather than
    -- wait. The Remote Script answers a hello with a full refresh for that page.
    hello(controller.getPage())
end

function controller.onEncoderTurn(enc)
    -- Since API 1.2.0 this fires for ordinary controls too, not just the ones our
    -- assignments claim -- and also for recorder playback, Random and group moves. An
    -- ordinary control has no meaningful `enc.id`, so acting on one would send a stranger's
    -- value to Live under some other parameter's slot. Range-check before trusting it: the
    -- test covers `nil` and `0`, the two plausible values for an unclaimed control.
    --
    -- What it cannot cover is a stale id that happens to land in 1..16 -- open question 3
    -- has not settled which of the three the firmware actually reports. Until it does,
    -- keep ordinary CC controls off this script's page.
    local id = enc.id
    if not id or id < 1 or id > SLOTS then return end

    -- The page travels with the value. Slot 3 is a device parameter on page 1 and a
    -- track's pan on page 2, so a turn that arrived before Live processed the page change
    -- would otherwise be applied to the wrong thing entirely.
    local v = enc.scaled * STEP
    midi.sendSysex(OUT,
        { 0xF0, SYX, CMD_SET, enc.page or 1, id - 1, v // 128, v % 128, 0xF7 })
end

function controller.onSysex(b)
    if b[2] ~= SYX then return end
    local cmd = b[3]

    if cmd == CMD_PARAM or cmd == CMD_VALUE then
        -- Validate before indexing. A truncated message — or a foreign device that
        -- also uses 0x7D — would otherwise read past the end, and `nil` arithmetic throws
        -- straight out of the callback. Both commands carry slot, hi, lo, so both need
        -- at least F0 SYX cmd slot hi lo F7.
        if #b < 7 then return end
        local id = b[4] + 1
        if id < 1 or id > SLOTS then return end
        local v = b[5] * 128 + b[6]
        if cmd == CMD_PARAM then
            controller.set(id, { v = v, n = text(b, 7) })
        else
            controller.set(id, "v", v)
        end
    elseif cmd == CMD_DEVICE then
        page.setTitle(text(b, 4))
    elseif cmd == CMD_CLEAR then
        page.setTitle("No Live")
        blank_all()
    end
    -- CMD_SET and CMD_HELLO are ours, outbound only. Ignoring them means a MIDI loopback
    -- cannot make the script talk to itself.
    --
    -- Nor can a value from Live: 1.2.0 states that `controller.set` is a direct setter and
    -- does not raise `onEncoderTurn`, so writing a value here cannot bounce back out as a
    -- CMD_SET. The echo suppression that matters is all on the Live side.
end

function page.onPageChange(previous, current)
    -- Nothing to tear down — no slots or leds overlays are ever installed, and those are
    -- what leak across pages, being keyed by physical position rather than by page.
    -- Telling Live the new page is the whole mode switch: it rebinds and sends a full
    -- refresh, which repaints all sixteen labels and values for whatever this page shows.
    hello(current)
end
