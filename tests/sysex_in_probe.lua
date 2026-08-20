-- Inbound-SysEx probe for the OXI E16.
--
-- Answers open question 7 in docs/src/content/docs/open-questions.md: `controller.onSysex`
-- is documented as firing "when the E16 receives a SysEx message", but the manual never
-- says which input it listens on. Everything that talks to the E16 from a computer --
-- the Ableton Live integration in `scripts/live-device.lua` among them -- depends on
-- SysEx arriving over USB actually reaching the script, and nothing else in the API can
-- carry data inbound: there is no CC or note callback.
--
-- METHOD
-- The header counts messages and identifies the last one, so any SysEx reaching the
-- script is visible without a debug session:
--
--     "0 waiting"        -> nothing has arrived
--     "7 7D 02 11"       -> 7 messages so far; the last was ID 0x7D, command 0x02,
--                           17 bytes long
--
-- Send it something. With the Live Remote Script installed, selecting a device emits a
-- burst of 17 messages, so the count should jump from 0 to 17 in one go. Any SysEx
-- utility works too -- the probe does not care what the bytes mean.
--
-- Turning encoder 1 sends `F0 7D 7F <value> F7` back out, which checks the other
-- direction: watch for it in your DAW's MIDI monitor.
--
-- RESULT, 2026-08-20: inbound SysEx over USB works.
--
-- Sending `F0 7D 01 48 69 F7` from a host utility showed "1 7D 01 6" and then "2 7D 01 6"
-- on a second send: the message arrives, the count accumulates, `#b` of 6 confirms the
-- framing bytes are included, and 0x7D reaches the script unaltered. Recorded on
-- docs/src/content/docs/callbacks.md.
--
-- With SendMIDI, note that it reads numbers as DECIMAL unless told otherwise -- `hex` has
-- to come before `syx`, or "7D" is parsed as 7 and the ID byte arrives wrong:
--
--     sendmidi dev "OXI E16" hex syx 7D 01 48 69
--
-- STILL OPEN
--   1. Do the other transports deliver inbound SysEx too, or only USB? (TRS, BLE)
--   2. Does a DAW control surface's output reach the script the same way a standalone
--      utility does?
--   3. Does the outbound ping show up in the DAW, and on which port?

--@assign id=1 abbr="PING" name="Send Ping" desc="Turn to emit a SysEx ping" l=0 h=127 dis=0

local count = 0

function page.onInit()
    page.setTitle("0 waiting")
end

function controller.onSysex(b)
    count = count + 1
    page.setTitle(string.format("%d %02X %02X %d", count, b[2] or 0, b[3] or 0, #b))
end

function controller.onEncoderTurn(enc)
    midi.sendSysex(0, { 0xF0, 0x7D, 0x7F, enc.scaled, 0xF7 })
end
