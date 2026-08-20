-- "Does writing `v` transmit?" probe for the OXI E16.
--
-- Answers the open question in docs/src/content/docs/open-questions.md:
--
--   Does controller.setByIndex(page, index, "v", ...) make the firmware TRANSMIT that
--   control's configured MIDI message, or does it only store the value?
--
-- It matters because it decides whether a script-driven LFO can modulate an ordinary
-- CC control the user configured in the editor (see the LFO pattern), or whether the
-- script has to know and send every CC itself.
--
-- Note that setByIndex is the ONLY route to an ordinary control: controller.set searches
-- Script destinations by script ID, and an ordinary control has no script ID. The guide
-- also never says whether setByIndex reaches non-script controls at all — hence the
-- positive control below.
--
--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------
--
-- 1. Load this script into a spare scene. Drop DRIV on encoder 1's turn destination 1,
--    REF on encoder 1's push, and SCPT on encoder 2's turn destination 1.
--
-- 2. By hand in the editor, configure ENCODER 16 as an ORDINARY CC control:
--    turn type CC, controller number 100, channel 1. Do not give it a script assignment.
--
-- 3. Turn MIDI Thru OFF (Conf > MIDI) so echoed input cannot be mistaken for output.
--
-- 4. Watch the E16's output on something that shows incoming CC. Either:
--      - a DAW or synth on the other end of the cable, or
--      - the E16's own MIDI Input Monitor (Conf > MIDI > MIDI Monitor) with a physical
--        loopback cable from the E16's MIDI OUT back into its MIDI IN.
--
--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
--
-- a. PRESS encoder 1. This sends CC 101 value 127 directly with midi.sendCC.
--    If nothing arrives, the cable/monitor/channel is wrong — fix that before reading
--    anything else. This step proves the observation path works.
--
-- b. TURN encoder 1 slowly through its full range, and watch three things:
--      - CC 100 arriving at the receiver
--      - encoder 2's LED ring (a SCRIPT control written by setByIndex)
--      - encoder 16's LED ring (the ORDINARY control written by setByIndex)
--
--------------------------------------------------------------------------------
-- READING THE RESULT
--------------------------------------------------------------------------------
--
--   CC 100 arrives                        -> setByIndex TRANSMITS. LFOs can drive
--                                            ordinary controls directly.
--
--   No CC 100, but encoder 16's ring moves -> the write lands, transmit does not happen.
--                                            Scripts must send their own MIDI.
--
--   No CC 100, encoder 16's ring still,
--   encoder 2's ring moves                 -> setByIndex works but does not reach
--                                            ordinary controls at all.
--
--   Neither ring moves                     -> setByIndex is not working here; check that
--                                            the assignments landed on the right encoders.
--
-- Record the outcome on docs/src/content/docs/api/controller.md and close the question.

--@assign id=1 abbr="DRIV" name="Driver" desc="Turn to write a value into encoders 2 and 16" l=0 h=127 dis=0
--@assign id=2 abbr="DRIV" name="Reference CC" desc="Push: send a known CC directly, proving the monitor works" p=true
--@assign id=3 abbr="SCPT" name="Script target" desc="Script control written by setByIndex — positive control" l=0 h=127 dis=0

local REF_CC = 101 -- sent directly by midi.sendCC, never by a control
local FULL_RING = 16383

local MIRROR_INDEX = 2  -- encoder holding the script control (id=3)
local TARGET_INDEX = 16 -- encoder configured BY HAND as a plain CC 100 control

function page.onInit()
    page.setTitle("Write probe")
end

function controller.onEncoderTurn(enc)
    if enc.id ~= 1 then return end

    local pg = controller.getPage()
    local internal = enc.scaled * FULL_RING / 127 -- float is fine; the firmware truncates

    controller.setByIndex(pg, MIRROR_INDEX, "v", internal)
    controller.setByIndex(pg, TARGET_INDEX, "v", internal)

    page.setTitle("wrote " .. enc.scaled)
end

function controller.onEncoderPress(enc)
    if enc.id ~= 2 then return end
    midi.sendCC(0, 0, REF_CC, 127)
    page.setTitle("ref CC" .. REF_CC)
end

-- Deliberately no leds.update anywhere: both target rings must stay under firmware
-- control, because the firmware drawing them from their internal value IS the readout.

function page.onPageChange(prev, curr)
    for i = 1, 16 do
        slots.reset(i)
    end
    page.setTitle("Write probe")
end
