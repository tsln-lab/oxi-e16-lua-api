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
from collections import namedtuple

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

# What one encoder is bound to. `quantized` is resolved once at bind time because it needs
# the owning device, which the slot table does not otherwise keep.
Slot = namedtuple("Slot", "parameter label color quantized")

# E16 page 1 shows the selected device; pages 2 and up are mixer banks of STRIPS tracks.
# Pages are the device's own mode mechanism, and onPageChange already fires a resync.
DEVICE_PAGE = 1
FIRST_MIXER_PAGE = 2

# Colour each mixer column with its track's colour. Set False to leave every ring drawn by
# the firmware, which is the safer default if the mapping below turns out to be wrong.
TRACK_COLORS = True

# Sent in place of a colour to mean "firmware draws this ring". 0-100 are real colours, so
# the sentinel has to sit outside that range but stay inside a 7-bit SysEx data byte.
NO_COLOR = 127

# Below this, a colour is too close to grey for its hue to mean anything. Chosen against
# Live's own track palette, where 13 of 70 entries fall below it.
MIN_SATURATION = 0.25
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


# Some devices have parameters that step like quantized ones but do not declare it, so
# `parameter.is_quantized` alone is wrong for them. Verbatim from the decompiled Live 12
# scripts, ableton/v3/live/util.py — Live's own control surfaces carry the same table.
UNDECLARED_QUANTIZED_PARAMETERS = {
    "AutoFilter": ("LFO Sync Rate",),
    "AutoPan": ("Sync Rate",),
    "BeatRepeat": ("Gate", "Grid", "Interval", "Offset", "Variation"),
    "Corpus": ("LFO Sync Rate",),
    "Flanger": ("Sync Rate",),
    "FrequencyShifter": ("Sync Rate",),
    "GlueCompressor": ("Ratio", "Attack", "Release"),
    "MidiArpeggiator": ("Offset", "Synced Rate", "Repeats", "Ret. Interval",
                        "Transp. Steps"),
    "MidiNoteLength": ("Synced Length",),
    "MidiScale": ("Base",),
    "MultiSampler": ("L 1 Sync Rate", "L 2 Sync Rate", "L 3 Sync Rate"),
    "Operator": ("LFO Sync",),
    "OriginalSimpler": ("L Sync Rate",),
    "Phaser": ("LFO Sync Rate",),
}


def is_quantized(parameter, device):
    """Whether a parameter steps, including the ones Live does not declare."""
    try:
        if parameter.is_quantized:
            return True
        undeclared = UNDECLARED_QUANTIZED_PARAMETERS.get(
            getattr(device, "class_name", None), ())
        return parameter.name in undeclared
    except (RuntimeError, AttributeError):
        return False


def e16_color(rgb):
    """Map a Live track colour to the E16's 0-100 ring colour.

    **Unverified.** API 1.2.0 redefines `leds.update`'s `color` as a "0-100 rotation",
    replacing the 0-15 palette index of 1.0.0 — and the sixteen-entry palette measured on
    hardware predates that change, so it no longer describes what the argument does. The
    word "rotation" suggests a hue wheel, which is what this assumes: hue in degrees,
    scaled to 0-100.

    Returns NO_COLOR for anything too desaturated to have a hue, leaving that ring to the
    firmware.

    If the probe shows otherwise, this function is the only thing that has to change.
    See open question 1, and `tests/led_color_probe.lua`, which sweeps the full range.
    """
    red = ((rgb >> 16) & 0xFF) / 255.0
    green = ((rgb >> 8) & 0xFF) / 255.0
    blue = (rgb & 0xFF) / 255.0
    high, low = max(red, green, blue), min(red, green, blue)
    if high <= 0 or (high - low) / high < MIN_SATURATION:
        # No meaningful hue to rotate to, so leave the ring to the firmware rather than
        # inventing one. This is not a defensive edge case: of the 70 colours in Live's
        # track palette, 13 fall below this threshold and 5 are pure grey, and every grey
        # has a hue of exactly 0 — so without this a grey track would show a red ring.
        return NO_COLOR
    span = high - low
    if high == red:
        hue = ((green - blue) / span) % 6
    elif high == green:
        hue = (blue - red) / span + 2
    else:
        hue = (red - green) / span + 4
    return int(round(hue * 60.0 / 360.0 * 100)) % 100


def track_color(track):
    if not TRACK_COLORS:
        return NO_COLOR
    try:
        return e16_color(int(track.color))
    except (RuntimeError, AttributeError, TypeError, ValueError):
        return NO_COLOR


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
        # One entry per encoder: (parameter, label, colour), or None where the page has
        # nothing.
        # Mixer controls are DeviceParameters too, so everything downstream -- reading,
        # writing, listening, echo suppression -- is identical for both modes.
        self._slots = [None] * SLOTS
        self._title = NO_DEVICE_TITLE
        self._bound = []       # listeners belonging to the current page
        self._song_bound = []  # listeners that outlive a page change
        self._sent = [None] * SLOTS  # last 14-bit value pushed, per slot
        self._dirty = set()
        self._pending_full = False
        self._rebind_pending = False
        self._own_midi_dispatch = True
        self._connect_midi()
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
        if not self._own_midi_dispatch:
            try:
                self.remove_received_midi_listener(self._on_received_midi)
            except (RuntimeError, AttributeError):
                pass
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

    def _connect_midi(self):
        """Subscribe to raw inbound MIDI through the event the base class provides.

        `ableton.v2` routes SysEx only to registered control elements; anything else is
        dropped with a "Got unknown sysex message" warning, and `receive_midi_chunk` does
        **not** fall through to `receive_midi`. This script registers no elements by
        design, so it has to get the bytes some other way.

        `SimpleControlSurface` declares `__events__ = ('received_midi', ...)`, and both
        `_do_receive_midi` and `_do_receive_midi_chunk` fire it before dispatching. That
        is the supported hook, and it is better than overriding the entry points:

        - both the single-message and chunked paths reach it, with no duplication;
        - the base class's `component_guard()` still wraps the handling, so parameter
          writes are batched and MIDI-map rebuilds suppressed, which an override skips;
        - registering a listener makes `received_midi_listener_count()` non-zero, which
          is exactly the condition that suppresses the warning — so Log.txt stays quiet.

        Older frameworks have no such event, hence the fallback.
        """
        if callable(getattr(self, "add_received_midi_listener", None)):
            try:
                self.add_received_midi_listener(self._on_received_midi)
                self._own_midi_dispatch = False
                return
            except Exception as err:
                self._log("cannot subscribe to received_midi: %s" % (err,))
        self._own_midi_dispatch = True
        self._debug("no received_midi event; dispatching inbound MIDI directly")

    def _on_received_midi(self, *midi_bytes):
        # The event passes the bytes as separate arguments, not as one sequence.
        self._handle_midi(midi_bytes)

    def _handle_midi(self, midi_bytes):
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

    def receive_midi(self, midi_bytes):
        if self._own_midi_dispatch:
            self._handle_midi(midi_bytes)
        else:
            ControlSurface.receive_midi(self, midi_bytes)

    def receive_midi_chunk(self, midi_chunk):
        self._debug("rx chunk of %d" % len(midi_chunk))
        if self._own_midi_dispatch:
            for midi_bytes in midi_chunk:
                self._handle_midi(midi_bytes)
            return
        inherited = getattr(ControlSurface, "receive_midi_chunk", None)
        if inherited is not None:
            inherited(self, midi_chunk)
        else:
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

    def _schedule_rebind(self):
        """Rebuild the slot table on the next tick.

        Deferred rather than immediate because these callbacks are Live listeners, and a
        rebind detaches listeners — including, sometimes, the one currently running.
        Collapsing repeats also matters: renaming a track fires per keystroke.
        """
        if not self._rebind_pending:
            self._rebind_pending = True
            self.schedule_message(1, self._deferred_rebind)

    def _deferred_rebind(self):
        self._rebind_pending = False
        self._rebind()

    def _on_selection_changed(self):
        if self._page == DEVICE_PAGE:
            self._schedule_rebind()

    def _on_tracks_changed(self):
        if self._page != DEVICE_PAGE:
            self._schedule_rebind()

    def _on_appearance_changed(self):
        # Labels and colours are read when the slot table is built, so a refresh would
        # re-send exactly what was sent before. The table itself has to be rebuilt.
        self._schedule_rebind()

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
        self._listen(device, "name", self._on_appearance_changed)
        try:
            params = list(device.parameters)[SKIP_PARAMS:][:SLOTS]
        except (RuntimeError, AttributeError):
            params = []
        for slot, param in enumerate(params):
            # Device pages leave the rings to the firmware: there is no track colour that
            # belongs to an individual parameter, and not owning them means nothing to
            # reset on the way out.
            slots[slot] = Slot(param, abbreviate(param.name), NO_COLOR,
                               is_quantized(param, device))
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
            self._listen(track, "name", self._on_appearance_changed)
            self._listen(track, "color", self._on_appearance_changed)
            color = track_color(track)

            # Top-down: the sends in A-to-B order, then pan, then the fader at the
            # bottom. Reorder these lines to move a control; nothing else depends on it.
            strip = []
            for send in range(SENDS):
                strip.append((sends[send], labels[send])
                             if send < len(sends) else None)
            strip.append((mixer.panning, "Pan"))
            strip.append((mixer.volume, abbreviate(track.name)))

            # The whole column carries the track's colour, so a strip reads as one track.
            for row, entry in enumerate(strip[:ROWS]):
                if entry is not None:
                    param, label = entry
                    entry = Slot(param, label, color, is_quantized(param, None))
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
                self._listen(returns[send], "name", self._on_appearance_changed)
                labels.append(send_label(returns[send].name, send))
            else:
                labels.append("Snd" + chr(ord("A") + send))
        return labels

    def _slot_at(self, slot):
        if 0 <= slot < SLOTS:
            return self._slots[slot]
        return None

    def _param_at(self, slot):
        entry = self._slot_at(slot)
        return entry.parameter if entry is not None else None

    def _label_at(self, slot):
        entry = self._slot_at(slot)
        return (entry.label or BLANK_LABEL) if entry is not None else BLANK_LABEL

    def _color_at(self, slot):
        entry = self._slot_at(slot)
        return entry.color if entry is not None else NO_COLOR

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
                [slot, value >> 7, value & 0x7F, self._color_at(slot)]
                + [ord(c) for c in label],
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
        entry = self._slot_at(slot)
        param = entry.parameter if entry is not None else None
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
            if entry.quantized:
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
