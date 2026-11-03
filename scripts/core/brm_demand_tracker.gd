extends RefCounted

# Per-target demand smoothing for Auto mode. Demand rises quickly (a machine
# that needs more gets it within a few ticks) and falls slowly (a transient
# dip does not hand its share to someone else and back again). Small changes
# inside the deadband are ignored, which removes most allocation jitter.

const RISE := 0.6
const FALL := 0.25
const DEADBAND := 0.02
# A demand that went to zero is dropped once it decayed below this share of
# its last peak (about 14 ticks at FALL = 0.25).
const SNAP_TO_ZERO := 0.02

var _values: Dictionary = {}
var _peaks: Dictionary = {}


func smooth(key: String, raw: float) -> float:
    if not is_finite(raw) or raw < 0.0:
        raw = 0.0

    if not _values.has(key):
        _values[key] = raw
        _peaks[key] = raw
        return raw

    var previous := float(_values[key])
    var reference := maxf(previous, raw)
    if reference <= 0.0:
        _values[key] = 0.0
        _peaks[key] = 0.0
        return 0.0

    if absf(raw - previous) <= reference * DEADBAND:
        return previous

    var alpha := RISE if raw > previous else FALL
    var value := previous + (raw - previous) * alpha
    var peak := maxf(float(_peaks.get(key, 0.0)), value)
    if raw <= 0.0 and value <= peak * SNAP_TO_ZERO:
        value = 0.0
        peak = 0.0
    _values[key] = value
    _peaks[key] = peak
    return value


func retain(keys: Array) -> void:
    for key in _values.keys():
        if not keys.has(key):
            _values.erase(key)
            _peaks.erase(key)


func clear() -> void:
    _values.clear()
    _peaks.clear()


func size() -> int:
    return _values.size()
