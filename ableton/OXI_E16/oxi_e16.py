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

# The E16's sixteen encoders are a 4x4 grid numbered left to right, top row first, so a
# column is {1, 5, 9, 13} and so on. Mixer mode uses each column as one channel strip.
STRIPS = 4         # channel strips across the grid = tracks visible per bank
ROWS = 4           # volume, pan, send A, send B -- top to bottom
SENDS = ROWS - 2

SLOTS = STRIPS * ROWS  # encoders on an E16

# E16 page 1 shows the selected device; pages 2 and up are mixer banks of STRIPS tracks.
# Pages are the device's own mode mechanism, and onPageChange already fires a resync.
DEVICE_PAGE = 1
FIRST_MIXER_PAGE = 2
MAX_14 = 16383     # the E16's internal value range is 14-bit
TITLE_CHARS = 15   # page.setTitle limit
LABEL_CHARS = 4    # encoder label limit
BLANK_LABEL = "-"  # shown on a slot the device has no parameter for
NO_DEVICE_TITLE = "No Device"
NO_TRACKS_TITLE = "No Tracks"

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


def send_label(name, index):
    """Label a send from its return track, dropping Live's leading letter designator.

    Live names return tracks "A Reverb", "B Delay". That first letter is the send letter,
    already implied by which row the encoder is in, and it would eat two of the four
    characters available.
    """
    words = [w for w in re.split(r"[^A-Za-z0-9]+", _ascii(name, 64)) if w]
    if len(words) > 1 and len(words[0]) == 1 and words[0].isalpha():
        return abbreviate(" ".join(words[1:]))
    if words:
        return abbreviate(name)
    return "Snd" + chr(ord("A") + index)


class OxiE16(ControlSurface):

    def __init__(self, c_instance, *a, **k):
        ControlSurface.__init__(self, c_instance, *a, **k)
        self._c = c_instance
        self._page = DEVICE_PAGE
        # One entry per encoder: (parameter, label), or None where the page has nothing.
        # Mixer controls are DeviceParameters too, so everything downstream -- reading,
        # writing, listening, echo suppression -- is identical for both modes.
        self._slots = [None] * SLOTS
        self._title = NO_DEVICE_TITLE
        self._bound = []       # listeners belonging to the current page
        self._song_bound = []  # listeners that outlive a page change
        self._sent = [None] * SLOTS  # last 14-bit value pushed, per slot
        self._dirty = set()
        self._pending_full = False
        self._connect_song()
        self._rebind()
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
        self._release(self._bound)
        self._release(self._song_bound)
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

    # -- listeners --------------------------------------------------------------

    def _listen(self, subject, event, callback, permanent=False):
        """Attach a listener and remember how to detach it.

        Live raises if the underlying object has gone away, and every subject here can:
        tracks are deleted, devices replaced, return tracks removed. Failing to attach is
        not fatal -- that slot simply will not update -- so it is logged, not raised.
        """
        try:
            getattr(subject, "add_%s_listener" % event)(callback)
        except (RuntimeError, AttributeError) as err:
            self._debug("cannot listen for %s: %s" % (event, err))
            return
        (self._song_bound if permanent else self._bound).append(
            (subject, event, callback))

    def _release(self, store):
        for subject, event, callback in store:
            try:
                getattr(subject, "remove_%s_listener" % event)(callback)
            except (RuntimeError, AttributeError):
                pass
        del store[:]

    def _connect_song(self):
        song = self._song()
        try:
            view = song.view
        except (RuntimeError, AttributeError) as err:
            self._log("cannot reach the song view: %s" % (err,))
            return
        # Selection only matters on the device page, but the listeners are cheap and
        # keeping them attached means switching back to it is already up to date.
        self._listen(view, "selected_track", self._on_selection_changed, permanent=True)
        # Adding or removing a track shifts every strip after it, so the mixer has to
        # rebind rather than just refresh values.
        self._listen(song, "tracks", self._on_tracks_changed, permanent=True)

    def _on_selection_changed(self):
        if self._page == DEVICE_PAGE:
            self._rebind()

    def _on_tracks_changed(self):
        if self._page != DEVICE_PAGE:
            self._rebind()

    def _on_names_changed(self):
        # Labels travel with a full refresh, so there is nothing finer to send.
        self._request_full()

    def _make_listener(self, slot):
        def _mark_dirty():
            self._dirty.add(slot)

        return _mark_dirty

    # -- what each page shows ---------------------------------------------------

    def _set_page(self, page):
        if page < DEVICE_PAGE:
            page = DEVICE_PAGE
        if page != self._page:
            self._page = page
            self._rebind()

    def _rebind(self):
        """Rebuild the slot table for the current page and listen to what is in it."""
        self._release(self._bound)
        if self._page == DEVICE_PAGE:
            slots, title = self._device_slots()
        else:
            slots, title = self._mixer_slots(self._page - FIRST_MIXER_PAGE)
        self._slots = slots
        self._title = title
        for slot, entry in enumerate(slots):
            if entry is not None:
                self._listen(entry[0], "value", self._make_listener(slot))
        self._request_full()

    def _device_slots(self):
        slots = [None] * SLOTS
        try:
            track = self._song().view.selected_track
        except (RuntimeError, AttributeError):
            track = None
        if track is None:
            return slots, NO_DEVICE_TITLE
        self._listen(track.view, "selected_device", self._on_selection_changed)
        try:
            device = track.view.selected_device
        except (RuntimeError, AttributeError):
            device = None
        if device is None:
            return slots, NO_DEVICE_TITLE
        self._listen(device, "name", self._on_names_changed)
        try:
            params = list(device.parameters)[SKIP_PARAMS:][:SLOTS]
        except (RuntimeError, AttributeError):
            params = []
        for slot, param in enumerate(params):
            slots[slot] = (param, abbreviate(param.name))
        try:
            title = _ascii(device.name, TITLE_CHARS) or NO_DEVICE_TITLE
        except (RuntimeError, AttributeError):
            title = NO_DEVICE_TITLE
        return slots, title

    def _mixer_slots(self, bank):
        """One channel strip per column: volume, pan, send A, send B, top to bottom."""
        slots = [None] * SLOTS
        try:
            tracks = list(self._song().tracks)
        except (RuntimeError, AttributeError):
            tracks = []
        first = max(0, bank) * STRIPS
        visible = tracks[first:first + STRIPS]
        if not visible:
            return slots, NO_TRACKS_TITLE

        labels = self._send_labels()
        for column, track in enumerate(visible):
            try:
                mixer = track.mixer_device
                sends = list(mixer.sends)
            except (RuntimeError, AttributeError):
                continue
            self._listen(track, "name", self._on_names_changed)

            # Top-down: the sends in A-to-B order, then pan, then the fader at the
            # bottom. Reorder these lines to move a control; nothing else depends on it.
            strip = []
            for send in range(SENDS):
                strip.append((sends[send], labels[send])
                             if send < len(sends) else None)
            strip.append((mixer.panning, "Pan"))
            strip.append((mixer.volume, abbreviate(track.name)))

            for row, entry in enumerate(strip[:ROWS]):
                slots[row * STRIPS + column] = entry

        return slots, "Mix %d-%d" % (first + 1, first + len(visible))

    def _send_labels(self):
        try:
            returns = list(self._song().return_tracks)
        except (RuntimeError, AttributeError):
            returns = []
        labels = []
        for send in range(SENDS):
            if send < len(returns):
                self._listen(returns[send], "name", self._on_names_changed)
                labels.append(send_label(returns[send].name, send))
            else:
                labels.append("Snd" + chr(ord("A") + send))
        return labels

    def _param_at(self, slot):
        if 0 <= slot < SLOTS:
            entry = self._slots[slot]
            if entry is not None:
                return entry[0]
        return None

    def _label_at(self, slot):
        if 0 <= slot < SLOTS:
            entry = self._slots[slot]
            if entry is not None:
                return entry[1] or BLANK_LABEL
        return BLANK_LABEL

    # -- protocol ---------------------------------------------------------------

    def _handle_sysex(self, midi_bytes):
        command = midi_bytes[2]
        if command == CMD_HELLO and len(midi_bytes) >= 5:
            self._set_page(midi_bytes[3])
            self._request_full()
        elif command == CMD_SET and len(midi_bytes) >= 8:
            page, slot = midi_bytes[3], midi_bytes[4]
            if page != self._page:
                # The E16 changed page and this turn beat the hello. Catch up and drop
                # it: the slot means something different on each page, so applying it
                # would move whatever the previous page had bound there.
                self._debug("turn from page %d, expected %d" % (page, self._page))
                self._set_page(page)
                return
            self._apply(slot, (midi_bytes[5] << 7) | midi_bytes[6])
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
        self._send(CMD_DEVICE, [ord(c) for c in _ascii(self._title, TITLE_CHARS)])

        self._dirty = set()
        for slot in range(SLOTS):
            param = self._param_at(slot)
            value = self._encode(param)
            label = _ascii(self._label_at(slot), LABEL_CHARS) or BLANK_LABEL
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
            self._debug("nothing bound to slot %d on page %d" % (slot, self._page))
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
