-- MIDI output port probe for the OXI E16.
--
-- Answers the open question in docs/src/content/docs/open-questions.md: what the `output`
-- argument to midi.sendCC / sendPC / sendMidi / sendSysex means beyond "0 = all outputs",
-- which is the only value either document specifies.
--
-- The hypothesis under test comes from the user manual's per-destination Output setting
-- (pp. 26-33), which lists the same ten options every time:
--
--     Same as Page, TRS1, TRS2, USB1, USB2, USB3, BLE, ALL-BLE, ALL-USB, Off
--
-- Page level drops "Same as Page" and leads with "All", which lines up with Lua's
-- documented 0 = all outputs. So the guess is that `output` indexes that list:
--
--     0 = All   1 = TRS1  2 = TRS2   3 = USB1     4 = USB2
--     5 = USB3  6 = BLE   7 = ALL-BLE  8 = ALL-USB  9 = Off
--
-- The range is swept to 15 rather than 9 in case there are more entries than the manual
-- lists. Note this is transport x port, NOT the Port A / Port B distinction on its own:
-- A and B share a physical output, so TRS1 vs TRS2 is that same A/B split carried on TRS.
--
--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------
--
-- 1. Load into a spare scene. Drop PORT on encoder 1's turn destination 1, SEND on
--    encoder 1's push, and SWEEP on encoder 2's push.
--
-- 2. Connect as many outputs at once as you can, each to something that displays
--    incoming CC:
--      - TRS MIDI out -> a synth or interface with a MIDI monitor
--      - USB -> a DAW or MIDI monitor app, showing ALL its MIDI input endpoints
--      - BLE -> paired and listening, if you have it
--    Anything not connected simply shows nothing, which is still a usable result.
--
-- 3. Turn MIDI Thru OFF (Conf > MIDI) so echoed input cannot be mistaken for output.
--
--------------------------------------------------------------------------------
-- RUN — the fast way
--------------------------------------------------------------------------------
--
-- PRESS encoder 2 once. It sends a DIFFERENT CC number on every output index in one
-- burst: CC 100 on output 0, CC 101 on output 1, ... CC 115 on output 15.
--
-- Then read each receiver and note which CC numbers arrived. The CC number minus 100 is
-- the output index that reached it. One press maps the whole enumeration:
--
--     TRS device shows CC 100 and CC 101  ->  0 = All (as documented), 1 = TRS1
--     DAW endpoint 2 shows CC 100 and 104 ->  4 = USB2
--     A number that arrives NOWHERE       ->  that index is Off, or unassigned
--
--------------------------------------------------------------------------------
-- RUN — the careful way
--------------------------------------------------------------------------------
--
-- TURN encoder 1 to select one index (the label shows the guessed name), then PRESS
-- encoder 1 to send CC 100 on just that output. Repeat per index. Slower, but it removes
-- any doubt about which message was which when a receiver only shows the last few events.
--
-- Record the result in docs/src/content/docs/api/midi.md and close the question.

--@assign id=1 abbr="PORT" name="Output index" desc="Which output index to test" l=0 h=15 dis=0
--@assign id=2 abbr="PORT" name="Send one" desc="Push: send CC 100 on the selected output" p=true
--@assign id=3 abbr="SWP" name="Sweep all" desc="Push: send CC 100+i on output i, for i = 0..15" p=true

local BASE_CC = 100
local MAX_OUT = 15

-- The hypothesis, for on-screen labelling only. If a label and reality disagree, reality
-- wins and this table is what needs correcting.
local NAMES = {
    [0] = "All",
    [1] = "TRS1", [2] = "TRS2",
    [3] = "USB1", [4] = "USB2", [5] = "USB3",
    [6] = "BLE",
    [7] = "A-BL", [8] = "A-US",
    [9] = "Off",
}

local out_index = 0

local function show(index)
    slots.update(index, NAMES[out_index] or ("?" .. out_index))
    page.setTitle("out " .. out_index .. " CC" .. (BASE_CC + out_index))
end

function page.onInit()
    page.setTitle("Output probe")
end

function controller.onEncoderTurn(enc)
    if enc.id ~= 1 then return end
    out_index = enc.scaled
    show(enc.index)
end

function controller.onEncoderPress(enc)
    if enc.id == 2 then
        -- One output, one known CC.
        midi.sendCC(out_index, 0, BASE_CC, 127)
        page.setTitle("sent " .. out_index)

    elseif enc.id == 3 then
        -- Every output, each with its own CC number, so the receivers self-identify.
        for i = 0, MAX_OUT do
            midi.sendCC(i, 0, BASE_CC + i, 127)
        end
        page.setTitle("swept 0-" .. MAX_OUT)
    end
end

function page.onPageChange(prev, curr)
    for i = 1, 16 do
        slots.reset(i)
    end
    page.setTitle("Output probe")
end
