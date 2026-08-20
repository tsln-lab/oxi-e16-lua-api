-- LED color probe for the OXI E16.
--
-- Answers open question 1 in docs/src/content/docs/open-questions.md.
--
-- API 1.2.0 documents leds.update's `color` as a 0-100 "color rotation", where 1.0.0
-- documented a 0-15 palette index. The 16-entry palette recorded in
-- docs/src/content/docs/api/leds.md was measured under the OLD firmware and needs redoing.
--
-- This probe sweeps the full 0-100 range across the sixteen rings in six passes of 16:
--
--   pass 0 -> colors  0..15      pass 3 -> colors 48..63
--   pass 1 -> colors 16..31      pass 4 -> colors 64..79
--   pass 2 -> colors 32..47      pass 5 -> colors 80..95   (+ 96..100 on pass 6, partial)
--
-- Encoder 1 selects the pass; the header shows which color range is on screen, and each
-- slot label shows that ring's color number. Read the rings left to right, top row first.
--
-- Encoder 2 scales the fill of every ring, to confirm color is still independent of fill.
--
-- NOTE: this uses leds.updateByIndex, which is the 1.2.0 name for what 1.0.0 called
-- leds.update. On 1.0.0 firmware it will not exist and nothing will light.

--@assign id=1 abbr="PASS" name="Color Pass" desc="Which block of 16 colors to show" l=0 h=6 dis=0
--@assign id=2 abbr="FILL" name="Ring Fill" desc="Ring fill % applied to every probe ring" l=0 h=100 dis=0

local FULL_RING = 16383
local MAX_COLOR = 100

local pass = 0
local fill_pct = 75

local function paint()
    local fill = fill_pct * FULL_RING // 100
    local base = pass * 16
    for i = 1, 16 do
        local color = base + i - 1
        if color <= MAX_COLOR then
            leds.updateByIndex(i, fill, color)
            slots.update(i, tostring(color))
        else
            leds.reset(i)
            slots.update(i, "-")
        end
    end
    page.setTitle(base .. "-" .. math.min(base + 15, MAX_COLOR) .. " @" .. fill_pct .. "%")
end

function page.onInit()
    paint()
end

function controller.onEncoderTurn(enc)
    if enc.id == 1 then
        pass = enc.scaled
        paint()
    elseif enc.id == 2 then
        fill_pct = enc.scaled
        paint()
    end
end

function page.onPageChange(prev, curr)
    -- Overlays are keyed by physical position and are not cleared automatically.
    -- Release every ring and label, then retake them on the new page.
    for i = 1, 16 do
        leds.reset(i)
        slots.reset(i)
    end
    paint()
end
