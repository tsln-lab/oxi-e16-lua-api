-- Shared engine for "stepped selector" scripts.
--
-- A stepped selector is a parameter the synth exposes over a full 0-127 CC range but
-- only responds to a handful of discrete values. Declaring the assignment as
-- `l=0 h=<count-1>` makes the firmware quantize for us, so `enc.scaled` arrives as the
-- option index with one detent per option.
--
-- A per-synth script supplies the assignments and a PARAMS table, then calls
-- stepped_install(). Everything below is identical across synths.
--
-- This file is inlined by build.lua, not require()d — the device has no module system.

local P          -- PARAMS, indexed by script id
local TITLE

-- Output port and MIDI channel are scene variables so one script can drive a second
-- instrument from a second scene without being re-uploaded. Edit them on the device at:
-- control editor -> Scene tab -> Script Variables.
--
-- `channel` is stored 1-16 as a player would say it and converted to the 0-15 the
-- firmware wants at send time. `output` is a port index where 0 means all outputs.
local function out_port()
    return var.get("output") or 0
end

local function out_channel()
    local ch = var.get("channel") or 1
    if ch < 1 then ch = 1 elseif ch > 16 then ch = 16 end
    return ch - 1
end

-- Labels need both mechanisms, because they win in different situations:
--
--   controller.set(id, "n", ...)  addresses the control by script id, so it works at
--                                 onInit when we know the ids but not yet which encoder
--                                 each parameter was dropped on.
--
--   slots.update(index, ...)      needs the encoder position, only known from enc.index
--                                 on a turn, and stays script-owned from then on.
-- The CC value to send for option `i`.
--
-- Some synths document exactly which values a selector responds to (the Korg NTS-1 lists
-- them), in which case the parameter supplies `vals`. Others document only the option
-- names and leave the CC mapping unstated. For those, omit `vals` and this sends the
-- MIDPOINT of option i's band, assuming the synth divides 0-127 into equal bands.
--
-- Midpoints rather than boundaries on purpose: they are the values furthest from any
-- rounding disagreement about where one option ends and the next begins.
local function cc_value(p, i)
    if p.vals then return p.vals[i] end
    return ((2 * i - 1) * 128) // (2 * #p.labels)
end

local function show(id, index, i)
    local label = P[id].labels[i]
    controller.set(id, "n", label)
    if index then
        slots.update(index, label)
    end
end

---Wire up the callbacks for a stepped-selector script.
---@param params table One entry per script id: { cc, labels, vals? }. Omit `vals` to send
---evenly-spaced band midpoints instead of documented values.
---@param title string Page header, max 15 characters
local function stepped_install(params, title)
    P, TITLE = params, title

    function page.onInit()
        page.setTitle(TITLE)

        -- The default only seeds the first time; re-registering is a silent no-op, so
        -- re-uploading the script never clobbers what the user set.
        var.register("channel", "int", 1)
        var.register("output", "int", 0)

        -- Park every selector on its first option so the label and the stored value
        -- agree from the start.
        --
        -- Deliberately does NOT send the CC: that would overwrite whatever the synth is
        -- actually set to, every time the scene loads. Device and synth may disagree
        -- until you touch a knob.
        for id = 1, #P do
            controller.set(id, "v", 0)
            show(id, nil, 1)
        end
    end

    function controller.onEncoderTurn(enc)
        local p = P[enc.id]
        if not p then return end

        -- l=0 h=n-1 means enc.scaled IS the option index, zero-based.
        local i = enc.scaled + 1
        midi.sendCC(out_port(), out_channel(), p.cc, cc_value(p, i))
        show(enc.id, enc.index, i)
    end

    function page.onPageChange()
        -- Overlays are not cleared automatically, so drop them all on the way in.
        -- Safe because `show` mirrors every label into the control's own abbr, and
        -- `dis=0` on the assignments stops the firmware painting numbers over it.
        for i = 1, 16 do
            slots.reset(i)
        end
    end
end
