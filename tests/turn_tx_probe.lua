-- Outbound-turn probe for the OXI E16.
--
-- Splits the E16 -> host direction into its three links, when parameters display
-- correctly but turning an encoder changes nothing in the DAW. The display working
-- already proves the host -> E16 direction and proves script IDs resolve, so the fault is
-- in one of:
--
--   1. `onEncoderTurn` never fires, or fires with an `enc.id` the script rejects
--   2. it fires, but the E16 transmits somewhere the host is not listening
--   3. it transmits fine, and the host application is not receiving or not acting
--
-- METHOD
-- The header reports every turn *before* anything is sent, so link 1 is visible on the
-- device with no external tooling:
--
--     "7 #3 64"     -> 7th turn, enc.id = 3, enc.scaled = 64
--     "7 #nil 64"   -> the callback fires but carries no id  (open question 3)
--     unchanged     -> the callback is not firing at all
--
-- Then it sends `F0 7D 10 <id-1> <hi> <lo> F7` — the same CMD_SET the Live integration
-- sends — so whatever the header shows, the wire half is exercised too.
--
-- Encoder 16 selects which `output` index that goes to, 0-9. `0` is the documented
-- "all outputs" and is where it starts; the rest are the unverified transport list from
-- open question 7. If the host sees nothing on 0, step through the others: whichever one
-- arrives identifies the mapping, and is worth recording on the midi page.
--
-- WHAT TO REPORT
--   1. Does the header move when you turn encoders 1-15? What does it show for `#`?
--   2. Does the host receive the message, and at which OUT index?

--@assign id=1  abbr="T1"  name="Turn 1"  l=0 h=127 dis=0
--@assign id=2  abbr="T2"  name="Turn 2"  l=0 h=127 dis=0
--@assign id=3  abbr="T3"  name="Turn 3"  l=0 h=127 dis=0
--@assign id=4  abbr="T4"  name="Turn 4"  l=0 h=127 dis=0
--@assign id=5  abbr="T5"  name="Turn 5"  l=0 h=127 dis=0
--@assign id=6  abbr="T6"  name="Turn 6"  l=0 h=127 dis=0
--@assign id=7  abbr="T7"  name="Turn 7"  l=0 h=127 dis=0
--@assign id=8  abbr="T8"  name="Turn 8"  l=0 h=127 dis=0
--@assign id=16 abbr="OUT" name="Output index" desc="Which output the probe sends to" l=0 h=9 dis=0

local out = 0
local turns = 0

function page.onInit()
    page.setTitle("turn a knob")
end

function controller.onEncoderTurn(enc)
    if enc.id == 16 then
        out = enc.scaled
        page.setTitle("OUT " .. out)
        return
    end

    -- Report first, unconditionally: an id of `nil` or 0 is exactly what we are looking
    -- for, so nothing may be filtered before it reaches the screen.
    turns = turns + 1
    page.setTitle(string.format("%d #%s %s", turns, tostring(enc.id), tostring(enc.scaled)))

    local id = enc.id
    if id and id >= 1 and id <= 8 then
        local v = enc.scaled * 129
        midi.sendSysex(out, { 0xF0, 0x7D, 0x10, id - 1, v // 128, v % 128, 0xF7 })
    end
end
