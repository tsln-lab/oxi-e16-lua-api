-- Korg NTS-1 mkII — stepped parameters for the OXI E16.
--
-- The NTS-1's type selectors accept CC 0-127 but only respond to a handful of discrete
-- values (EG TYPE is 0/25/50/75/127, etc). Sent anything else, they snap to the nearest
-- option, so a plain CC knob wastes most of its travel and gives no feedback about which
-- option is live.
--
-- CC numbers and value lists come from the Korg NTS-1 mkII MIDI Implementation, v1.00
-- (2024-03-18), section 1-1 and notes *1-1 through *1-8.
--
-- Build with: mise exec -- lua build.lua

--!include lib/stepped.lua

--@assign id=1 abbr="EG"   name="EG Type"       l=0 h=4 dis=0
--@assign id=2 abbr="FLT"  name="Filter Type"   l=0 h=6 dis=0
--@assign id=3 abbr="OSC"  name="Osc Type"      l=0 h=6 dis=0
--@assign id=4 abbr="MOD"  name="Mod Type"      l=0 h=8 dis=0
--@assign id=5 abbr="DLY"  name="Delay Type"    l=0 h=12 dis=0
--@assign id=6 abbr="REV"  name="Reverb Type"   l=0 h=10 dis=0
--@assign id=7 abbr="ARP"  name="Arp Pattern"   l=0 h=9 dis=0
--@assign id=8 abbr="INTV" name="Arp Intervals" l=0 h=5 dis=0

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

stepped_install(PARAMS, "NTS-1")
