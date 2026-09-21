/// Seeded PRNG for ADR 0001: seed + settings -> the exact same world.
///
/// FNV-1a 64-bit hash of (seed string + settings) -> PCG32 state. Pure Dart,
/// integer-only (no doubles), stable across platforms and Dart versions.
/// Never use dart:math's Random here.
class Rng {
  int _state; // 64-bit state
  int _inc; // 64-bit increment (must be odd)

  Rng._(this._state, this._inc);

  /// Derive an rng from a seed string and a settings fingerprint string.
  factory Rng.fromString(String seed, [String settings = '']) {
    final h = fnv1a64('$seed\0settings=$settings');
    final rng = Rng._(h & 0xFFFFFFFFFFFFFFFF, ((h >>> 32) & 0xFFFFFFFF) * 2 + 1);
    rng._next(); // discard the first draw (state not yet mixed)
    return rng;
  }

  /// FNV-1a 64-bit of a string; surrogate pairs are decoded to code points so
  /// the hash does not depend on the seed's UTF-16 encoding.
  static int fnv1a64(String s) {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    final code = _decodeCodeUnits(s);
    for (var i = 0; i < code.length; i++) {
      h = _mul64(h ^ code[i], prime);
    }
    return h;
  }

  /// 32-bit PCG32 draw (canonical O'Neill PCG-XSH-RR).
  int nextU32() {
    _state = _mul64(_state, 6364136223846793005) + _inc;
    _state &= 0xFFFFFFFFFFFFFFFF;
    final xorShifted = (((_state >>> 18) ^ _state) >>> 27) & 0x3FFFFFFF;
    final rot = (_state >>> 27) & 31;
    return ((xorShifted >>> rot) | (xorShifted << (31 - rot))) & 0xFFFFFFFF;
  }

  /// 64-bit draw from two 32-bit draws.
  int nextU64() => (nextU32() << 32) | nextU32();

  /// Uniform int in [min, max] inclusive (both bounds).
  int range(int min, int max) {
    if (max < min) throw ArgumentError('max < min');
    return min + nextU32() % (max - min + 1);
  }

  /// True with probability p (0.0 <= p <= 1.0).
  bool chance(double p) => nextU32() / 0xFFFFFFFF < p;

  /// Skip ahead by a fixed number of draws (deterministic stream fork).
  void skip(int n) {
    for (var i = 0; i < n; i++) _next();
  }

  void _next() => nextU32();

  static int _mul64(int a, int b) => (a * b) & 0xFFFFFFFFFFFFFFFF;

  /// Decode UTF-16 code units to a list of code points.
  static List<int> _decodeCodeUnits(String s) {
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      var u = s.codeUnitAt(i);
      if (0xD800 <= u && u <= 0xDBFF && i + 1 < s.length) {
        final lo = s.codeUnitAt(i + 1);
        if (0xDC00 <= lo && lo <= 0xDFFF) {
          out.add(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00));
          i++;
          continue;
        }
      }
      out.add(u);
    }
    return out;
  }
}
