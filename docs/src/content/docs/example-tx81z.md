---
title: "Example: Yamaha TX81Z editor"
description: "The complete SysEx editor from the manual, reproduced with notes on what it gets right and what it predates."
---

Reproduced from [*The OXI E16 Manual*](https://drive.google.com/file/d/1yZn1i96nRkosn2o6eDlj5wzuErPQEe9N/view?usp=sharing)
section 6.13 (pp. 105–109). This is the only complete
script the manual ships, and it is the reference for how a large SysEx editor is meant to
be structured.

## What it demonstrates

- **90 parameters declared as assignments** — 86 turn controls plus 4 push toggles, so the
  App can present them for drag-and-drop rather than the user wiring each by hand.
- **Parallel lookup tables keyed by script ID.** `param_type` selects which SysEx frame to
  use, `param_num` supplies the address byte. Both are indexed by `enc.id`.
- **A mutable message template.** `vced` and `aced` are built once, then bytes 5 and 6 are
  overwritten per event — no table is allocated on the hot path.
- **Push toggles that own their own state**, with `slots.update` giving the user the only
  feedback they will get.

## Read it with four caveats

1. **No `dis` key on any assignment.** As printed, every encoder will have a numeric
   readout painted over its label the moment it moves. Add `dis=0` — see
   [Assignments](/oxi-e16-lua-api/assignments/).
2. **As printed in the manual it does not compile.** `controller.onEncoderTurn` was missing
   its closing `end`, which nests `controller.onEncoderPress` inside it — so the operator
   toggles would never fire. The version below has the `end` restored.
3. **Two 86-entry tables is the layout the manual itself warns against** for large editors.
   At this size it is fine; at JV-1080 scale, pack the per-parameter data into a
   fixed-stride string and read it with `string.byte` — see
   [Execution model](/oxi-e16-lua-api/execution-model/).
4. **It sends `enc.scaled` straight into a SysEx data byte.** Correct here only because
   every declared range tops out at 99 or less. Sending `enc.value` instead would emit
   14-bit garbage — see [Gotchas](/oxi-e16-lua-api/gotchas/).

## The script

```lua
-- Yamaha TX81Z complete editor for OXI E16
-- Per-operator params (id 1-64), voice common (65-86), op enable pushes (87-90)
-- OP4 per-operator (id 1-16)
--@assign id=1 abbr="CRS" name="OP4 Coarse" l=0 h=63
--@assign id=2 abbr="Fine" name="OP4 Fine Freq" l=0 h=15
--@assign id=3 abbr="FRng" name="OP4 Freq Range" l=0 h=7
--@assign id=4 abbr="DET" name="OP4 Detune" l=0 h=6
--@assign id=5 abbr="AR" name="OP4 Attack" l=0 h=31
--@assign id=6 abbr="D1R" name="OP4 Decay 1" l=0 h=31
--@assign id=7 abbr="D2R" name="OP4 Decay 2" l=0 h=31
--@assign id=8 abbr="RR" name="OP4 Release" l=1 h=15
--@assign id=9 abbr="D1L" name="OP4 Decay Lvl" l=0 h=15
--@assign id=10 abbr="LS" name="OP4 Level Scale" l=0 h=99
--@assign id=11 abbr="RS" name="OP4 Rate Scale" l=0 h=3
--@assign id=12 abbr="EBS" name="OP4 EG Bias Sens" l=0 h=7
--@assign id=13 abbr="KVS" name="OP4 Key Vel Sens" l=0 h=7
--@assign id=14 abbr="OUT" name="OP4 Output Level" l=0 h=99
--@assign id=15 abbr="SHFT" name="OP4 EG Shift" l=0 h=3
--@assign id=16 abbr="OSW" name="OP4 Osc Wave" l=0 h=7
-- OP3 per-operator (id 17-32)
--@assign id=17 abbr="CRS" name="OP3 Coarse" l=0 h=63
--@assign id=18 abbr="Fine" name="OP3 Fine Freq" l=0 h=15
--@assign id=19 abbr="FRng" name="OP3 Freq Range" l=0 h=7
--@assign id=20 abbr="DET" name="OP3 Detune" l=0 h=6
--@assign id=21 abbr="AR" name="OP3 Attack" l=0 h=31
--@assign id=22 abbr="D1R" name="OP3 Decay 1" l=0 h=31
--@assign id=23 abbr="D2R" name="OP3 Decay 2" l=0 h=31
--@assign id=24 abbr="RR" name="OP3 Release" l=1 h=15
--@assign id=25 abbr="D1L" name="OP3 Decay Lvl" l=0 h=15
--@assign id=26 abbr="LS" name="OP3 Level Scale" l=0 h=99
--@assign id=27 abbr="RS" name="OP3 Rate Scale" l=0 h=3
--@assign id=28 abbr="EBS" name="OP3 EG Bias Sens" l=0 h=7
--@assign id=29 abbr="KVS" name="OP3 Key Vel Sens" l=0 h=7
--@assign id=30 abbr="OUT" name="OP3 Output Level" l=0 h=99
--@assign id=31 abbr="SHFT" name="OP3 EG Shift" l=0 h=3
--@assign id=32 abbr="OSW" name="OP3 Osc Wave" l=0 h=7
-- OP2 per-operator (id 33-48)
--@assign id=33 abbr="CRS" name="OP2 Coarse" l=0 h=63
--@assign id=34 abbr="Fine" name="OP2 Fine Freq" l=0 h=15
--@assign id=35 abbr="FRng" name="OP2 Freq Range" l=0 h=7
--@assign id=36 abbr="DET" name="OP2 Detune" l=0 h=6
--@assign id=37 abbr="AR" name="OP2 Attack" l=0 h=31
--@assign id=38 abbr="D1R" name="OP2 Decay 1" l=0 h=31
--@assign id=39 abbr="D2R" name="OP2 Decay 2" l=0 h=31
--@assign id=40 abbr="RR" name="OP2 Release" l=1 h=15
--@assign id=41 abbr="D1L" name="OP2 Decay Lvl" l=0 h=15
--@assign id=42 abbr="LS" name="OP2 Level Scale" l=0 h=99
--@assign id=43 abbr="RS" name="OP2 Rate Scale" l=0 h=3
--@assign id=44 abbr="EBS" name="OP2 EG Bias Sens" l=0 h=7
--@assign id=45 abbr="KVS" name="OP2 Key Vel Sens" l=0 h=7
--@assign id=46 abbr="OUT" name="OP2 Output Level" l=0 h=99
--@assign id=47 abbr="SHFT" name="OP2 EG Shift" l=0 h=3
--@assign id=48 abbr="OSW" name="OP2 Osc Wave" l=0 h=7
-- OP1 per-operator (id 49-64)
--@assign id=49 abbr="CRS" name="OP1 Coarse" l=0 h=63
--@assign id=50 abbr="Fine" name="OP1 Fine Freq" l=0 h=15
--@assign id=51 abbr="FRng" name="OP1 Freq Range" l=0 h=7
--@assign id=52 abbr="DET" name="OP1 Detune" l=0 h=6
--@assign id=53 abbr="AR" name="OP1 Attack" l=0 h=31
--@assign id=54 abbr="D1R" name="OP1 Decay 1" l=0 h=31
--@assign id=55 abbr="D2R" name="OP1 Decay 2" l=0 h=31
--@assign id=56 abbr="RR" name="OP1 Release" l=1 h=15
--@assign id=57 abbr="D1L" name="OP1 Decay Lvl" l=0 h=15
--@assign id=58 abbr="LS" name="OP1 Level Scale" l=0 h=99
--@assign id=59 abbr="RS" name="OP1 Rate Scale" l=0 h=3
--@assign id=60 abbr="EBS" name="OP1 EG Bias Sens" l=0 h=7
--@assign id=61 abbr="KVS" name="OP1 Key Vel Sens" l=0 h=7
--@assign id=62 abbr="OUT" name="OP1 Output Level" l=0 h=99
--@assign id=63 abbr="SHFT" name="OP1 EG Shift" l=0 h=3
--@assign id=64 abbr="OSW" name="OP1 Osc Wave" l=0 h=7
-- Voice common (id 65-81)
--@assign id=65 abbr="ALG" name="Algorithm" l=0 h=7
--@assign id=66 abbr="FB" name="Feedback" l=0 h=7
--@assign id=67 abbr="LSPD" name="LFO Speed" l=0 h=99
--@assign id=68 abbr="LDLY" name="LFO Delay" l=0 h=99
--@assign id=69 abbr="PMD" name="PM Depth" l=0 h=99
--@assign id=70 abbr="AMD" name="AM Depth" l=0 h=99
--@assign id=71 abbr="LSYN" name="LFO Key Sync" l=0 h=1
--@assign id=72 abbr="LW" name="LFO Wave" l=0 h=3
--@assign id=73 abbr="PMS" name="LFO PM Sens" l=0 h=7
--@assign id=74 abbr="AMS" name="LFO AM Sens" l=0 h=3
--@assign id=75 abbr="MID" name="Middle C" l=0 h=48
--@assign id=76 abbr="PLAY" name="Play Mode" l=0 h=1
--@assign id=77 abbr="PB" name="Pitch Bend Range" l=0 h=12
--@assign id=78 abbr="PMOD" name="Portamento Mode" l=0 h=1
--@assign id=79 abbr="PTIM" name="Portamento Time" l=0 h=99
--@assign id=80 abbr="MWP" name="MW Pitch Range" l=0 h=99
--@assign id=81 abbr="MWA" name="MW Amp Range" l=0 h=99

-- Per-operator ratio/fixed toggle (id 82-85)
--@assign id=82 abbr="R/F" name="OP4 Ratio/Fixed" l=0 h=1
--@assign id=83 abbr="R/F" name="OP3 Ratio/Fixed" l=0 h=1
--@assign id=84 abbr="R/F" name="OP2 Ratio/Fixed" l=0 h=1
--@assign id=85 abbr="R/F" name="OP1 Ratio/Fixed" l=0 h=1
-- Reverb (id 86)
--@assign id=86 abbr="REV" name="Reverb Rate" l=0 h=7
-- Operator enable push toggles (id 87-90)
--@assign id=87 abbr="OP1" name="OP1 Enable" p=true
--@assign id=88 abbr="OP2" name="OP2 Enable" p=true
--@assign id=89 abbr="OP3" name="OP3 Enable" p=true
--@assign id=90 abbr="OP4" name="OP4 Enable" p=true

local out = 0
local channel = 0
local vced = {0xF0, 0x43, 0x10 + channel, 0x12, 0, 0, 0xF7}
local aced = {0xF0, 0x43, 0x10 + channel, 0x13, 0, 0, 0xF7}
-- 0 = VCED, 1 = ACED per script_id (1-86)
local param_type = {
    -- OP4 (1-16)
    0,1,1,0, 0,0,0,0,0,0,0,0,0,0,1,1,
    -- OP3 (17-32)
    0,1,1,0, 0,0,0,0,0,0,0,0,0,0,1,1,
    -- OP2 (33-48)
    0,1,1,0, 0,0,0,0,0,0,0,0,0,0,1,1,
    -- OP1 (49-64)
    0,1,1,0, 0,0,0,0,0,0,0,0,0,0,1,1,
    -- Voice common (65-81): all VCED
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    -- Ratio/Fixed (82-85): all ACED
    1,1,1,1,
    -- Reverb (86): ACED
    1,
}

-- Sysex address byte per script_id (1-86)
local param_num = {
    -- OP4 (1-16)
    11, 2, 1,12, 0, 1, 2, 3, 4, 5, 6, 7, 9,10, 4, 3,
    -- OP3 (17-32)
    24, 7, 6,25, 13,14,15,16,17,18,19,20,22,23, 9, 8,
    -- OP2 (33-48)
    37,12,11,38, 26,27,28,29,30,31,32,33,35,36,14,13,
    -- OP1 (49-64)
    50,17,16,51, 39,40,41,42,43,44,45,46,48,49,19,18,
    -- Voice common (65-81): VCED addresses
    0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,
    0x3C,0x3D,0x3E,0x3F,0x40,0x41,0x42,0x47,0x48,
    -- Ratio/Fixed (82-85): ACED addresses Op4,Op3,Op2,Op1
    0x00,0x05,0x0A,0x0F,
    -- Reverb (86): ACED address
    0x14,
}
-- Operator enable state: Op1, Op2, Op3, Op4 (1=on, 0=off)
local op_en = {1, 1, 1, 1}

local function sendOpEnable()
    local packed = (op_en[1] * 8) + (op_en[2] * 4) + (op_en[3] * 2) + op_en[4]
    vced[5] = 0x5D
    vced[6] = packed
    midi.sendSysex(out, vced)
end

function page.onInit()
    page.setTitle("TX81Z")
end

function controller.onEncoderTurn(enc)
    if enc.id >= 1 and enc.id <= 86 then
        local msg = param_type[enc.id] == 1 and aced or vced
        msg[5] = param_num[enc.id]
        msg[6] = enc.scaled
        midi.sendSysex(out, msg)
    end
end

function controller.onEncoderPress(enc)
    -- Op enable toggles (id 87=OP1, 88=OP2, 89=OP3, 90=OP4)
    if enc.id >= 87 and enc.id <= 90 then
        local op = enc.id - 86 -- 1-4
        op_en[op] = 1 - op_en[op]
        sendOpEnable()
        slots.update(enc.index, op_en[op] == 1 and "ON" or "OFF")
    end
end
```
