-- Sonicware LIVEN Ambient Ø — stepped parameters for the OXI E16.
--
-- Sources, both in ../manuals:
--   Ambient0_manual_MIDI_en.md  — the CC numbers below
--   Ambient0_manual_en_r3.md    — the option lists below
--
-- !! CC VALUES ARE ASSUMED, NOT DOCUMENTED !!
--
-- Unlike the Korg NTS-1, whose MIDI implementation spells out the exact values each
-- selector responds to, Sonicware document only the option NAMES. No `vals` are given
-- here, so lib/stepped.lua sends the midpoint of each option's band, assuming the synth
-- divides 0-127 into equal bands. That is the usual implementation and midpoints are the
-- most forgiving choice, but it is a guess until measured.
--
-- To measure it properly: the Ambient Ø transmits these CCs as well as receiving them.
-- Connect Ambient Ø MIDI OUT to E16 MIDI IN, turn on the E16's MIDI Input Monitor
-- (Conf > MIDI > MIDI Monitor), then step through a parameter's options on the synth and
-- read off the value it sends for each. Add those as `vals` and the guess disappears.
--
-- Layer parameters (CC 28+) are per-layer, addressed by MIDI channel — set the `channel`
-- scene variable to the layer you want to edit.
--
-- Build with: mise exec -- lua build.lua

--!include lib/stepped.lua

--@assign id=1  abbr="FX"   name="FX Type"        l=0 h=5  dis=0
--@assign id=2  abbr="RVB"  name="Reverb Type"    l=0 h=9  dis=0
--@assign id=3  abbr="STRC" name="Structure"      l=0 h=5  dis=0
--@assign id=4  abbr="FLTR" name="Filter Type"    l=0 h=3  dis=0
--@assign id=5  abbr="VOIC" name="Voice Mode"     l=0 h=4  dis=0
--@assign id=6  abbr="MSHP" name="Mod Shape"      l=0 h=23 dis=0
--@assign id=7  abbr="L1SH" name="LFO1 Shape"     l=0 h=23 dis=0
--@assign id=8  abbr="L1AS" name="LFO1 Assign"    l=0 h=16 dis=0
--@assign id=9  abbr="L1TR" name="LFO1 Trigger"   l=0 h=9  dis=0
--@assign id=10 abbr="L2SH" name="LFO2 Shape"     l=0 h=23 dis=0
--@assign id=11 abbr="L2AS" name="LFO2 Assign"    l=0 h=16 dis=0
--@assign id=12 abbr="L2TR" name="LFO2 Trigger"   l=0 h=9  dis=0

-- Shared option lists. Declared once and referenced from PARAMS so the three shape
-- selectors and the two assign selectors do not each carry their own copy — script
-- memory is the binding constraint on this device.
local SHAPES = {
    "SINE", "SQAR", "TRI", "SAW", "RSAW", "RND", "SRND", "LOG",
    "RLOG", "PL10", "PL25", "PL75", "PL90", "STP2", "STP3", "STP4",
    "STP5", "STP6", "STP7", "RMP+", "RMP-", "LSIN", "LTRI", "LSRN",
}

-- NOTE: L1RT and L1DP are documented as reachable from LFO2 only, and OLVL from LFO1
-- only. Both LFOs are given the full list here, so a few entries will be inert on one of
-- them. Trim per-LFO once the on-device order is confirmed.
local ASSIGNS = {
    "OFF", "TUNE", "HARM", "BAL", "PTCH", "DTFB", "L1RT", "L1DP",
    "MDRT", "MDDP", "FLCO", "FLRS", "PAN", "LVL", "-SHM", "-RVB", "OLVL",
}

local TRIGS = { "OFF", "1", "2", "3", "4", "5", "6", "7", "8", "INF" }

local PARAMS = {
    -- id 1: FX TYPE (CC 21). The manual lists six effects and no OFF entry; if the
    -- device turns out to have one, add it at the front and bump h to 6.
    { cc = 21, labels = { "DLY", "RDLY", "DRV", "CRSH", "TILT", "CHRS" } },

    -- id 2: REVERB TYPE (CC 24)
    { cc = 24, labels = { "OFF", "SM.L", "SM.M", "SM.H", "LG.L",
                          "LG.M", "LG.H", "IN.L", "IN.M", "IN.H" } },

    -- id 3: STRUCTURE (CC 28)
    { cc = 28, labels = { "DRN1", "DRN2", "PAD1", "PAD2", "ATM1", "ATM2" } },

    -- id 4: FILTER TYPE (CC 37)
    { cc = 37, labels = { "OFF", "LPF", "HPF", "BPF" } },

    -- id 5: VOICE MODE (CC 58). ARP covers twelve arpeggiator patterns selected
    -- separately with VOICE ADJ (CC 59), not from this list.
    { cc = 58, labels = { "POLY", "MONO", "LGT", "UNI", "ARP" } },

    -- id 6: MOD SHAPE (CC 34)
    { cc = 34, labels = SHAPES },

    -- ids 7-9: LFO1 SHAPE / ASSIGN / TRIG (CC 42, 43, 44)
    { cc = 42, labels = SHAPES },
    { cc = 43, labels = ASSIGNS },
    { cc = 44, labels = TRIGS },

    -- ids 10-12: LFO2 SHAPE / ASSIGN / TRIG (CC 47, 48, 49)
    { cc = 47, labels = SHAPES },
    { cc = 48, labels = ASSIGNS },
    { cc = 49, labels = TRIGS },
}

stepped_install(PARAMS, "AMBIENT0")
