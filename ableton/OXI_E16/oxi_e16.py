"""OXI E16 <-> Ableton Live: parameters of the selected device on the sixteen encoders.

Live watches whichever device is selected, abbreviates each parameter name to the four
characters the E16 screen allows, and pushes name + value to the controller over SysEx.
Turning an encoder sets the parameter back in Live.

SysEx in both directions is deliberate. `controller.onSysex` is the only inbound callback
the E16 firmware offers a script -- incoming CC and notes never reach Lua -- so parameter
data can only arrive that way. It also keeps this side simple: Live forwards SysEx to a
control surface unconditionally, whereas each CC would have to be registered with
`forward_midi_cc` in `build_midi_map` before `receive_midi` ever saw it.

Pairs with `scripts/live-device.lua`. Protocol reference:
https://tsln-lab.github.io/oxi-e16-lua-api/ableton-live/
"""

import logging
import re

try:
    # Live 10 and later.
    from ableton.v2.control_surface import ControlSurface
except ImportError:  # pragma: no cover - Live 9 and earlier
    from _Framework.ControlSurface import ControlSurface

# Flip to True and restart Live to trace the inbound path in Live's Log.txt. Every message
# the script receives is logged raw, and every parameter write reports what it did. That
# separates the three ways this direction can fail: nothing reaches Live at all, something
# reaches it but is not our message, or ours arrives and the write is refused.
DEBUG = False

SYSEX_ID = 0x7D  # reserved for non-commercial use

# Live -> E16
CMD_DEVICE = 0x01  # device name, for the header
CMD_PARAM = 0x02   # slot, value, name -- a full slot refresh
CMD_VALUE = 0x03   # slot, value -- parameter moved in Live
CMD_CLEAR = 0x04   # this script is going away

# E16 -> Live
CMD_SET = 0x10     # slot, value -- encoder turned on the controller
CMD_HELLO = 0x11   # send me the current device

# Live puts the device on/off switch at parameters[0] on every device. It is not worth one
# of sixteen encoders, so the slots start after it. Set to 0 to include it again.
SKIP_PARAMS = 1

SLOTS = 16         # encoders on an E16
MAX_14 = 16383     # the E16's internal value range is 14-bit
TITLE_CHARS = 15   # page.setTitle limit
LABEL_CHARS = 4    # encoder label limit
BLANK_LABEL = "-"  # shown on a slot the device has no parameter for
NO_DEVICE_TITLE = "No Device"

# Names whose automatic abbreviation is poor. Values must be <= 4 characters.
NAME_OVERRIDES = {
    "Device On": "On",
    "Dry/Wet": "D/W",
    "Chorus On": "Chor",
    "Filter Freq": "Freq",
    "Filter Res": "Res",
    "Filter Type": "Type",
}


def _ascii(text, limit):
    """SysEx data bytes are 7-bit, so anything outside printable ASCII has to go."""
    clean = "".join(c if 32 <= ord(c) < 127 else " " for c in (text or ""))
    return clean.strip()[:limit]


def abbreviate(name):
    """Squeeze a Live parameter name into the four characters the E16 can show.

    Live's names are mostly one or two words, so the rules are shaped around those:
    a single word keeps its first four characters ("Frequency" -> "Freq", "Feedback"
    -> "Feed"), two words give two characters each ("Filter Freq" -> "FiFr"), a
    trailing number is always kept ("Macro 1" -> "Mac1"), and anything longer falls
    back to initials padded from the last word ("Osc 1 Coarse" -> "O1Co"). Add
    entries to NAME_OVERRIDES where that reads badly.
    """
    name = _ascii(name, 64)
    if name in NAME_OVERRIDES:
        return NAME_OVERRIDES[name][:LABEL_CHARS]
    words = [w for w in re.split(r"[^A-Za-z0-9]+", name) if w]
    if not words:
        return BLANK_LABEL
    if len(words) == 1:
        return words[0][:LABEL_CHARS]
    if words[-1].isdigit():
        num = words[-1][:LABEL_CHARS]
        return (words[0][: LABEL_CHARS - len(num)] + num)[:LABEL_CHARS]
    if len(words) == 2:
        return (words[0][:2] + words[1][:2])[:LABEL_CHARS]
    initials = "".join(w[0] for w in words)[:LABEL_CHARS]
    # Pad a short set of initials from the tail of the last word: "Osc 1 Coarse"
    # reads better as "O1Co" than "O1C".
    return (initials + words[-1][1:])[:LABEL_CHARS]


class OxiE16(ControlSurface):

    def __init__(self, c_instance, *a, **k):
        ControlSurface.__init__(self, c_instance, *a, **k)
        self._c = c_instance
        self._track = None
        self._device = None
        self._params = []
        self._param_listeners = []
        self._sent = [None] * SLOTS  # last 14-bit value pushed, per slot
        self._dirty = set()
        self._pending_full = False
        self._song_listener_added = False
        self._connect_song()
        # Live is still wiring up ports during __init__; give it a few ticks before the
        # first push so the opening burst is not sent into a port that is not open yet.
        self.schedule_message(5, self._request_full)

    # -- Live plumbing ----------------------------------------------------------

    def _song(self):
        song = getattr(self, "song", None)
        if callable(song):  # _Framework exposes song() as a method
            return song()
        if song is not None:  # ableton.v2 exposes it as a property
            return song
        return self._c.song()

    def disconnect(self):
        self._unbind_device()
        self._disconnect_track()
        if self._song_listener_added:
            try:
                self._song().view.remove_selected_track_listener(self._on_track_changed)
            except (RuntimeError, AttributeError):
                pass
            self._song_listener_added = False
        # Tell the E16 the link is down, so it shows "No Live" rather than a stale
        # device's parameters that no longer control anything.
        self._send(CMD_CLEAR, [])
        ControlSurface.disconnect(self)

    def refresh_state(self):
        inherited = getattr(ControlSurface, "refresh_state", None)
        if inherited is not None:
            inherited(self)
        self._request_full()

    def update_display(self):
        """Live's ~100ms tick, and the only place outgoing value updates are sent.

        Parameter listeners just mark a slot dirty. Sending straight from the listener
        would put a SysEx message on the wire for every automation frame of every
        visible parameter; coalescing here caps it at sixteen messages per tick.
        """
        ControlSurface.update_display(self)
        try:
            if self._pending_full:
                self._pending_full = False
                self._send_full_state()
            elif self._dirty:
                dirty, self._dirty = sorted(self._dirty), set()
                for slot in dirty:
                    self._send_value(slot)
        except Exception as err:  # never let the tick die
            self._log("update_display failed: %s" % (err,))

    def _log(self, message):
        """Write to Live's Log.txt, and never raise.

        `ControlSurface.log_message` exists in `_Framework` but not in `ableton.v2`, where
        logging moved to the standard `logging` module. This is called from `except`
        blocks, so it has to survive both — a logger that raises substitutes its own error
        for the one being reported, and the original is lost.
        """
        text = "OXI E16: " + message
        try:
            self._c.log_message(text)
            return
        except Exception:
            pass
        try:
            logging.getLogger(__name__).info(text)
        except Exception:
            pass

    def _debug(self, message):
        if DEBUG:
            self._log(message)

    def receive_midi(self, midi_bytes):
        if DEBUG:
            self._debug("rx %s" % " ".join("%02X" % b for b in midi_bytes))
        if (
            len(midi_bytes) >= 4
            and midi_bytes[0] == 0xF0
            and midi_bytes[1] == SYSEX_ID
        ):
            try:
                self._handle_sysex(midi_bytes)
            except Exception as err:
                self._log("bad sysex %r: %s" % (midi_bytes, err))
        # Anything else is ignored on purpose: this script defines no control elements,
        # so there is nothing for the base class to dispatch a CC or note to.

    def receive_midi_chunk(self, midi_chunk):
        """Dispatch inbound MIDI ourselves. Deferring to the base class loses it.

        Live delivers batched MIDI here, and `ableton.v2`'s implementation routes SysEx
        only to registered control elements — anything else is dropped with a
        "Got unknown sysex message" warning in Log.txt. It does **not** fall through to
        `receive_midi`. This script registers no elements, by design, so calling the base
        class discards every message this integration depends on.

        Nothing is lost by not calling it: with no elements there is nothing for it to
        dispatch to. Queued outbound MIDI is flushed by `update_display` on Live's tick.
        """
        self._debug("rx chunk of %d" % len(midi_chunk))
        for midi_bytes in midi_chunk:
            self.receive_midi(midi_bytes)

    # -- selection tracking -----------------------------------------------------

    def _connect_song(self):
        try:
            self._song().view.add_selected_track_listener(self._on_track_changed)
            self._song_listener_added = True
        except (RuntimeError, AttributeError) as err:
            self._log("cannot follow track selection: %s" % (err,))
        self._on_track_changed()

    def _disconnect_track(self):
        if self._track is not None:
            try:
                self._track.view.remove_selected_device_listener(self._on_device_changed)
            except (RuntimeError, AttributeError):
                pass
        self._track = None

    def _on_track_changed(self):
        self._disconnect_track()
        try:
            track = self._song().view.selected_track
        except (RuntimeError, AttributeError):
            track = None
        self._track = track
        if track is not None:
            try:
                track.view.add_selected_device_listener(self._on_device_changed)
            except (RuntimeError, AttributeError):
                pass
        self._on_device_changed()

    def _on_device_changed(self):
        device = None
        if self._track is not None:
            try:
                device = self._track.view.selected_device
            except (RuntimeError, AttributeError):
                device = None
        self._bind_device(device)
        self._request_full()

    def _on_name_changed(self):
        self._request_full()

    def _unbind_device(self):
        for param, listener in self._param_listeners:
            try:
                param.remove_value_listener(listener)
            except (RuntimeError, AttributeError):
                pass
        self._param_listeners = []
        if self._device is not None:
            try:
                self._device.remove_name_listener(self._on_name_changed)
            except (RuntimeError, AttributeError):
                pass
        self._device = None
        self._params = []

    def _bind_device(self, device):
        self._unbind_device()
        self._device = device
        if device is None:
            return
        try:
            device.add_name_listener(self._on_name_changed)
        except (RuntimeError, AttributeError):
            pass
        try:
            params = list(device.parameters)[SKIP_PARAMS:]
            self._params = params[:SLOTS]
        except (RuntimeError, AttributeError):
            self._params = []
        for slot, param in enumerate(self._params):
            listener = self._make_listener(slot)
            try:
                param.add_value_listener(listener)
                self._param_listeners.append((param, listener))
            except (RuntimeError, AttributeError):
                pass

    def _make_listener(self, slot):
        def _mark_dirty():
            self._dirty.add(slot)

        return _mark_dirty

    def _param_at(self, slot):
        if 0 <= slot < len(self._params):
            return self._params[slot]
        return None

    # -- protocol ---------------------------------------------------------------

    def _handle_sysex(self, midi_bytes):
        command = midi_bytes[2]
        if command == CMD_HELLO:
            self._request_full()
        elif command == CMD_SET and len(midi_bytes) >= 7:
            slot = midi_bytes[3]
            self._apply(slot, (midi_bytes[4] << 7) | midi_bytes[5])
        else:
            self._debug("unhandled command %02X, %d bytes" % (command, len(midi_bytes)))

    def _send(self, command, payload):
        try:
            self._send_midi(tuple([0xF0, SYSEX_ID, command] + list(payload) + [0xF7]))
        except Exception as err:
            self._log("send failed: %s" % (err,))

    def _request_full(self):
        self._pending_full = True

    def _send_full_state(self):
        name = NO_DEVICE_TITLE
        if self._device is not None:
            try:
                name = _ascii(self._device.name, TITLE_CHARS) or NO_DEVICE_TITLE
            except (RuntimeError, AttributeError):
                name = NO_DEVICE_TITLE
        self._send(CMD_DEVICE, [ord(c) for c in name])

        self._dirty = set()
        for slot in range(SLOTS):
            param = self._param_at(slot)
            value = self._encode(param)
            label = BLANK_LABEL
            if param is not None:
                try:
                    label = abbreviate(param.name) or BLANK_LABEL
                except (RuntimeError, AttributeError):
                    label = BLANK_LABEL
            self._sent[slot] = value if param is not None else None
            self._send(
                CMD_PARAM,
                [slot, value >> 7, value & 0x7F] + [ord(c) for c in label],
            )

    def _send_value(self, slot):
        param = self._param_at(slot)
        if param is None:
            return
        value = self._encode(param)
        if value == self._sent[slot]:
            return  # unchanged at the E16's resolution, including our own echo
        self._sent[slot] = value
        self._send(CMD_VALUE, [slot, value >> 7, value & 0x7F])

    def _encode(self, param):
        """Parameter value -> 0..16383, the E16's internal range."""
        if param is None:
            return 0
        try:
            low, high = param.min, param.max
            if high <= low:
                return 0
            fraction = (param.value - low) / float(high - low)
        except (RuntimeError, AttributeError, TypeError):
            return 0
        return max(0, min(MAX_14, int(round(fraction * MAX_14))))

    def _apply(self, slot, value14):
        param = self._param_at(slot)
        if param is None:
            self._debug("slot %d holds no parameter (device has %d)"
                        % (slot, len(self._params)))
            return
        try:
            if not getattr(param, "is_enabled", True):
                # e.g. a macro-mapped parameter, which Live will not let us set
                self._debug("%r is not enabled, ignoring" % (param.name,))
                return
            low, high = param.min, param.max
            if high <= low:
                return
            value = low + (high - low) * (max(0, min(MAX_14, value14)) / float(MAX_14))
            if getattr(param, "is_quantized", False):
                value = round(value)
            param.value = max(low, min(high, value))
            self._debug("set %r to %s (from 14-bit %d, range %s..%s)"
                        % (param.name, param.value, value14, low, high))
        except (RuntimeError, AttributeError, TypeError) as err:
            self._log("cannot set slot %d: %s" % (slot, err))
            return
        # Record what the controller asked for so the resulting value listener does not
        # echo it straight back. If Live snapped the value (quantized parameters do),
        # the encoded result differs and _send_value pushes the correction -- which is
        # what makes the LED ring show where the parameter actually landed.
        self._sent[slot] = max(0, min(MAX_14, value14))
