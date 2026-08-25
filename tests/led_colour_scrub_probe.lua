-- LED colour scrub probe for the OXI E16.
--
-- Answers open question 1 in docs/src/content/docs/open-questions.md: API 1.2.0
-- redocuments `leds.update`'s `color` as a 0-100 "rotation", replacing the 0-15 palette
-- index of 1.0.0. The 16-entry palette recorded in docs/src/content/docs/api/leds.md was
-- measured under the OLD firmware and no longer describes what the argument does.
--
-- `tests/led_color_probe.lua` sweeps all 100 values across the sixteen rings, six at a
-- time, which is the fast way to see the whole range. This is the slow way, and the better
-- one for writing the answer down: one knob scrubs the colour of one ring, one value per
-- detent, with the number on screen. Dial through it and note where the colour changes.
--
-- METHOD
--   Encoder 1 (COL)  selects the colour, 0-100. `l=0 h=100` means one detent is one value,
--                    already clamped, so nothing is skipped on the way through.
--   Encoder 2 (SWCH) is the swatch. Its ring shows the selected colour and nothing else.
--   Encoder 3 (FILL) scales the swatch's fill, to check whether colour survives a partial
--                    ring. Under 1.0.0 colour was independent of fill; that was measured
--                    against the old palette and is worth re-confirming.
--
-- The header reads "col 42 f100" — the colour number, then the fill percentage.
--
-- All three assignments must sit on the SAME page: `leds.update` takes a script ID but
-- only reaches destinations on the current page ([leds](docs/src/content/docs/api/leds.md)).
--
-- WHAT TO REPORT
--   1. How many distinct colours are there across 0-100, and where does each one start?
--      A rotation implies a smooth hue wheel; the 1.0.0 palette was a scattered set of 16.
--   2. Do the same values look like the old 0-15 palette in any way, or is it a new scale?
--   3. Does the colour hold as FILL is reduced, or shift with it?

--@assign id=1 abbr="COL"  name="Colour"  desc="Ring colour 0-100, one per detent" l=0 h=100 dis=0
--@assign id=2 abbr="SWCH" name="Swatch"  desc="The ring showing the selected colour" l=0 h=100 dis=0
--@assign id=3 abbr="FILL" name="Fill"    desc="Swatch fill percentage" l=0 h=100 dis=0

local SWATCH   = 2       -- script ID of the swatch, which is what leds.update addresses
local FULL_RING = 16383

local colour, fill = 0, 100

local function paint()
    leds.update(SWATCH, fill * FULL_RING // 100, colour)
    page.setTitle("col " .. colour .. " f" .. fill)
end

function page.onInit()
    paint()
end

function controller.onEncoderTurn(enc)
    -- Since 1.2.0 this fires for ordinary controls too, which carry no meaningful id, so
    -- act only on the two selectors and leave everything else alone.
    if enc.id == 1 then
        colour = enc.scaled
    elseif enc.id == 3 then
        fill = enc.scaled
    else
        return
    end
    paint()
end

function page.onPageChange()
    -- leds overlays are keyed by physical position and survive a page change, so the
    -- swatch would otherwise follow whatever lands on that encoder next.
    for i = 1, 16 do
        leds.reset(i)
    end
end
