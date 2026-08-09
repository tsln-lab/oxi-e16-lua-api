-- Display-mode (`dis`) probe for the OXI E16.
--
-- Answers open question 2 in docs/src/content/docs/open-questions.md: the `dis` assignment key takes an
-- integer, but the manual only ever names the display modes in words (Off, 127, 100,
-- 1000, B63 bipolar, 9999, Always on) and never gives their numeric values.
--
-- METHOD
-- Sixteen otherwise-identical controls, all l=0 h=127, differing only in `dis` (0-15).
-- On load every one is set to the same internal midpoint (8192 of 16383), so whatever
-- number each encoder displays identifies its mode:
--
--     blank    -> Off
--     ~64      -> 127 scale (the documented default)
--     ~50      -> 100 scale
--     ~500     -> 1000 scale
--     ~5000    -> 9999 scale
--     ~0 or 00 -> B63 bipolar (midpoint is zero on a -63..+64 scale)
--
-- Encoder labels read d0..d15, matching the `dis` value that produced them.
--
-- READING IT
-- 1. Drop all sixteen parameters onto the sixteen encoders, in order.
-- 2. Note what each displays while untouched. That is the whole result.
-- 3. Then turn a few. Modes that only show a value transiently vs. always ("Always on")
--    separate here: turn an encoder, wait, see whether its readout persists or clears.
--
-- This script deliberately does NOT call leds.update or slots.update — both would mask
-- the native display this probe exists to observe.
--
-- IF THE APP REJECTS THE SCRIPT
-- `dis` values above the valid range may fail to parse. Delete the assignments from the
-- bottom up (dis=15 first) until it loads, and note where it started working — that
-- boundary is itself the answer to how many modes exist.

--@assign id=1  abbr="d0"  name="dis 0"  l=0 h=127 dis=0
--@assign id=2  abbr="d1"  name="dis 1"  l=0 h=127 dis=1
--@assign id=3  abbr="d2"  name="dis 2"  l=0 h=127 dis=2
--@assign id=4  abbr="d3"  name="dis 3"  l=0 h=127 dis=3
--@assign id=5  abbr="d4"  name="dis 4"  l=0 h=127 dis=4
--@assign id=6  abbr="d5"  name="dis 5"  l=0 h=127 dis=5
--@assign id=7  abbr="d6"  name="dis 6"  l=0 h=127 dis=6
--@assign id=8  abbr="d7"  name="dis 7"  l=0 h=127 dis=7
--@assign id=9  abbr="d8"  name="dis 8"  l=0 h=127 dis=8
--@assign id=10 abbr="d9"  name="dis 9"  l=0 h=127 dis=9
--@assign id=11 abbr="d10" name="dis 10" l=0 h=127 dis=10
--@assign id=12 abbr="d11" name="dis 11" l=0 h=127 dis=11
--@assign id=13 abbr="d12" name="dis 12" l=0 h=127 dis=12
--@assign id=14 abbr="d13" name="dis 13" l=0 h=127 dis=13
--@assign id=15 abbr="d14" name="dis 14" l=0 h=127 dis=14
--@assign id=16 abbr="d15" name="dis 15" l=0 h=127 dis=15

local MIDPOINT = 8192

local function centre_all()
    for id = 1, 16 do
        controller.set(id, "v", MIDPOINT)
    end
end

function page.onInit()
    page.setTitle("dis probe")
    centre_all()
end

function page.onPageChange(prev, curr)
    -- Re-centre on every page entry so the readouts are comparable again after turning.
    centre_all()
end
