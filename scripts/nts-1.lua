-- Korg NTS-1 mkII — stepped parameters for the OXI E16.
--
-- The NTS-1's type selectors accept CC 0-127 but only respond to a handful of discrete
-- values (EG TYPE is 0/25/50/75/127, etc). Sent anything else, they snap to the nearest
-- option, so a plain CC knob wastes most of its travel and gives no feedback about which
-- option is live.
--
-- The trick is to let the E16 do the quantizing. Each assignment declares l=0 h=<n-1>,
-- so `enc.scaled` arrives as the option INDEX (0..n-1), one detent per option, already
-- clamped. The script only has to look up the CC value and the label. No manual mode,
-- no accumulator, no rounding.
--
-- CC numbers and value lists come from docs/NTS-1mkII_MIDIimp.txt (section 1-1, notes
-- *1-1 through *1-8).

--@assign id=1 abbr="EG"   name="EG Type"       l=0 h=4 dis=0
--@assign id=2 abbr="FLT"  name="Filter Type"   l=0 h=6 dis=0
--@assign id=3 abbr="OSC"  name="Osc Type"      l=0 h=6 dis=0
--@assign id=4 abbr="MOD"  name="Mod Type"      l=0 h=8 dis=0
--@assign id=5 abbr="DLY"  name="Delay Type"    l=0 h=12 dis=0
--@assign id=6 abbr="REV"  name="Reverb Type"   l=0 h=10 dis=0
--@assign id=7 abbr="ARP"  name="Arp Pattern"   l=0 h=9 dis=0
--@assign id=8 abbr="INTV" name="Arp Intervals" l=0 h=5 dis=0

local OUT = 0      -- 0 = all outputs
local CHANNEL = 0  -- MIDI channel 1

-- One entry per script id. `vals` are the CC values the NTS-1 actually recognises;
-- `labels` are the same options abbreviated to the 4 characters the screen allows.
-- The two arrays are parallel and must stay the same length.
local PARAMS = {
    -- id 1: EG TYPE (CC 14)
    { cc = 14,
      vals   = { 0, 25, 50, 75, 127 },
      labels = { "ADSR", "AHR", "AR", "ARLP", "OPEN" } },

    -- id 2: FILTER TYPE (CC 42)
    { cc = 42,
      vals   = { 0, 18, 36, 54, 72, 90, 127 },
      labels = { "LP2", "LP4", "BP2", "BP4", "HP2", "HP4", "OFF" } },

    -- id 3: OSC TYPE (CC 53)
    { cc = 53,
      vals   = { 0, 18, 36, 54, 72, 90, 127 },
      labels = { "OFF", "SAW", "TRI", "SQR", "VPM", "NOIS", "WAVE" } },

    -- id 4: MOD TYPE (CC 88)
    { cc = 88,
      vals   = { 0, 14, 28, 42, 56, 70, 84, 98, 127 },
      labels = { "OFF", "CHOR", "ENSM", "PHAS", "FLAN", "SCLP", "HCLP", "FOLD", "FUZZ" } },

    -- id 5: DELAY TYPE (CC 89)
    -- NOTE: the MIDI doc lists 13 values but only 12 names, because the last entry
    -- "TAPE BPM DOUBLING" is almost certainly two options ("TAPE BPM" and "DOUBLING")
    -- with a comma lost to the line wrap. Labels 12 and 13 below assume that split —
    -- verify against the synth and fix if wrong.
    { cc = 89,
      vals   = { 0, 9, 18, 27, 36, 45, 54, 63, 72, 81, 90, 99, 127 },
      labels = { "OFF", "ST", "MONO", "PPNG", "HPF", "TAPE", "ONE",
                 "STBP", "MOBP", "PPBP", "HIBP", "TPBP", "DBLG" } },

    -- id 6: REVERB TYPE (CC 90)
    { cc = 90,
      vals   = { 0, 11, 22, 33, 44, 55, 66, 77, 88, 99, 127 },
      labels = { "OFF", "HALL", "SMTH", "AREN", "PLAT", "ROOM",
                 "ERLY", "SPCE", "RISE", "SUB", "HORR" } },

    -- id 7: ARP PATTERN (CC 117)
    { cc = 117,
      vals   = { 0, 12, 24, 36, 48, 60, 72, 84, 96, 127 },
      labels = { "UP", "DOWN", "UPDN", "DNUP", "CONV",
                 "DIV", "CVDV", "DVCV", "RAND", "STOC" } },

    -- id 8: ARP INTERVALS (CC 118)
    { cc = 118,
      vals   = { 0, 21, 42, 63, 84, 127 },
      labels = { "OCT", "MAJ", "SUS", "AUG", "MIN", "DIM" } },
}

-- Every selector shows its current option name at all times. That needs both label
-- mechanisms, because they win in different situations:
--
--   controller.set(id, "n", ...)  addresses the control by script ID, so it works at
--                                 onInit when we know the ids but not yet which encoder
--                                 each parameter was dropped on. But the firmware's own
--                                 numeric readout paints over it while the knob moves.
--
--   slots.update(index, ...)      needs the encoder position, which we only learn from
--                                 enc.index on a turn. It beats the numeric readout and
--                                 stays owned by the script from then on.
--
-- Setting `n` as well as the overlay keeps the fallback label correct if the overlay is
-- ever reset.
local function show(id, index, i)
    local label = PARAMS[id].labels[i]
    controller.set(id, "n", label)
    if index then
        slots.update(index, label)
    end
end

function page.onInit()
    page.setTitle("NTS-1")

    -- Park every selector on its first option so the label and the stored value agree
    -- from the start. Without this a control would show option 1's name while sitting on
    -- whatever value the scene had saved.
    --
    -- Deliberately does NOT send the CC: that would overwrite whatever the NTS-1 is
    -- actually set to, every time the scene loads. E16 and synth may disagree until you
    -- touch a knob.
    for id = 1, #PARAMS do
        controller.set(id, "v", 0)
        show(id, nil, 1)
    end
end

function controller.onEncoderTurn(enc)
    local p = PARAMS[enc.id]
    if not p then return end

    -- l=0 h=n-1 means enc.scaled IS the option index, zero-based.
    local i = enc.scaled + 1
    midi.sendCC(OUT, CHANNEL, p.cc, p.vals[i])
    show(enc.id, enc.index, i)
end

function page.onPageChange()
    -- Overlays are not cleared automatically, so drop them all on the way in — otherwise
    -- another page's encoders inherit NTS-1 option names at the same positions.
    --
    -- Safe to do here only because of two things: `show` mirrors every label into the
    -- control's own `abbr` via controller.set(id, "n", ...), so our selectors still read
    -- correctly once the overlay is gone; and `dis=0` on the assignments means the
    -- firmware never paints a numeric readout over that abbr while turning. Without
    -- either of those, resetting would lose the label or re-arm the number flash.
    for i = 1, 16 do
        slots.reset(i)
    end
end
