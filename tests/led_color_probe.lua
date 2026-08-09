-- LED color probe for the OXI E16.
--
-- Answers open question 3 in docs/src/content/docs/open-questions.md: leds.update() documents `color`
-- as an index 0-15, while the control editor's color setting is a 0-100 spectrum
-- (manual p.21). The manual never reconciles the two.
--
-- This lights encoder N with color index N-1, so the entire 0-15 range is visible
-- at once. Load it into a spare scene and read the rings left to right, top row
-- first: encoder 1 = color 0 ... encoder 16 = color 15.
--
-- Encoder 1 also scales the fill of every ring, so you can check whether color
-- rendering changes with fill amount (it should not).

--@assign id=1 abbr="FILL" name="Ring Fill" desc="Ring fill % applied to every probe ring" l=0 h=100

local FULL_RING = 16383
local fill_pct = 75

local function paint()
    local fill = fill_pct * FULL_RING // 100
    for i = 1, 16 do
        leds.update(i, fill, i - 1)
        slots.update(i, tostring(i - 1))
    end
    page.setTitle("Colors " .. fill_pct .. "%")
end

function page.onInit()
    paint()
end

function controller.onEncoderTurn(enc)
    if enc.id == 1 then
        fill_pct = enc.scaled
        paint()
    end
end

function page.onPageChange(prev, curr)
    -- Overlays are not cleared automatically (docs section 11, item 2).
    -- Release every ring and label, then retake them on the new page.
    for i = 1, 16 do
        leds.reset(i)
        slots.reset(i)
    end
    paint()
end
