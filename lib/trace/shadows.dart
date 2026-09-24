import 'dart:math' as math;

/// Angular-sweep visibility for a point light in the 2-D grid (the 2-D form
/// of a shadow map). Every light-blocking cell is an occluder disc of the
/// cell's circumradius (sqrt(2)/2) around its centre. The disc contains the
/// cell square, so no ray that crosses a blocking cell can be visible —
/// one-cell partitions seal exactly — while the diagonal corner slivers
/// over-shadow by at most a hair (a safe direction).
///
/// Build computes the true lower envelope: the disc that a ray at each
/// angle hits first. It sweeps the discs' angular intervals (each disc
/// covers [a - asin(r/d), a + asin(r/d)] as seen from the light) with a
/// min-heap of the active discs, emitting the active minimum per angle
/// band. Build is O(B log B); a query is one atan2 plus a binary search,
/// O(log B).
class ShadowSweep {
  static const double discR = 0.7071067811865476;
  static const double _twoPi = 6.283185307179586;

  double lx = 0, ly = 0;
  final List<double> _start = [];
  final List<double> _end = [];
  final List<double> _dist = [];
  final List<int> _cell = [];

  /// True when the straight line from the light to (px, py) crosses no
  /// blocking cell. [excludeCell] (packed bx * 256 + by) is ignored: a
  /// point inside a blocking cell of its own does not shadow itself,
  /// matching the old march, which never checked the start cell.
  bool isVisible(double px, double py, {int excludeCell = -1}) {
    final dx = px - lx;
    final dy = py - ly;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-9) return true;
    var phi = math.atan2(dy, dx);
    if (phi < 0) phi += _twoPi;
    var lo = 0;
    var hi = _start.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (_start[mid] <= phi) lo = mid + 1;
      else hi = mid;
    }
    var k = lo - 1;
    while (k >= 0 && _start[k] <= phi) {
      if (_end[k] > phi && _dist[k] < d && _cell[k] != excludeCell) {
        return false;
      }
      k--;
    }
    return true;
  }

  void build(double lightX, double lightY, Iterable<(int, int)> blockers) {
    lx = lightX;
    ly = lightY;
    _start.clear();
    _end.clear();
    _dist.clear();
    _cell.clear();
    // (angle, 0 = remove | 1 = add, d, packed)
    final events = <(double, int, double, int)>[];
    final heap = _MinHeap();
    for (final (bx, by) in blockers) {
      final cx = bx + 0.5 - lightX;
      final cy = by + 0.5 - lightY;
      final d = math.sqrt(cx * cx + cy * cy);
      final packed = bx * 256 + by;
      final a = math.atan2(cy, cx);
      final alpha = math.asin(discR / d > 1 ? 1 : discR / d);
      final s = a - alpha;
      final e = a + alpha;
      if (e - s >= _twoPi) {
        // The light sits inside the disc: it shadows every direction.
        heap.push(d, packed);
        continue;
      }
      if (s < 0) {
        events.add((s + _twoPi, 1, d, packed));
        events.add((_twoPi, 0, d, packed));
        events.add((0.0, 1, d, packed));
        events.add((e, 0, d, packed));
      } else if (e > _twoPi) {
        events.add((s, 1, d, packed));
        events.add((_twoPi, 0, d, packed));
        events.add((0.0, 1, d, packed));
        events.add((e - _twoPi, 0, d, packed));
      } else {
        events.add((s, 1, d, packed));
        events.add((e, 0, d, packed));
      }
    }
    events.sort((p, q) {
      final c = p.$1.compareTo(q.$1);
      if (c != 0) return c;
      return p.$2.compareTo(q.$2); // removes before adds at one angle
    });
    final removed = <int>{};
    var prevA = 0.0;
    (double, int) top() {
      while (heap.isNotEmpty) {
        final t = heap.peek();
        if (!removed.contains(t.$2)) return t;
        heap.pop();
      }
      return (double.infinity, -1);
    }
    var curMin = top();
    for (final (ang, type, d, packed) in events) {
      if (type == 1) {
        heap.push(d, packed);
      } else {
        removed.add(packed);
      }
      final newMin = top();
      if ((newMin.$1 != curMin.$1 || newMin.$2 != curMin.$2) &&
          curMin.$1 < double.infinity) {
        _insert(prevA, ang, curMin.$1, curMin.$2);
        prevA = ang;
      }
      curMin = newMin;
    }
    if (curMin.$1 < double.infinity) {
      _insert(prevA, _twoPi, curMin.$1, curMin.$2);
    }
  }

  void _insert(double s, double e, double d, int packed) {
    if (e <= s) return;
    _start.add(s);
    _end.add(e);
    _dist.add(d);
    _cell.add(packed);
    var j = _start.length - 1;
    while (j > 0 && _start[j - 1] > _start[j]) {
      final ts = _start[j - 1];
      _start[j - 1] = _start[j];
      _start[j] = ts;
      final te = _end[j - 1];
      _end[j - 1] = _end[j];
      _end[j] = te;
      final td = _dist[j - 1];
      _dist[j - 1] = _dist[j];
      _dist[j] = td;
      final tc = _cell[j - 1];
      _cell[j - 1] = _cell[j];
      _cell[j] = tc;
      j--;
    }
  }
}

/// A min-heap of (distance, packed cell) with a deterministic tie-break on
/// the packed cell, so a rebuild always yields the same envelope.
class _MinHeap {
  final List<(double, int)> _a = [];

  bool get isEmpty => _a.isEmpty;
  bool get isNotEmpty => _a.isNotEmpty;

  (double, int) peek() => _a[0];

  void push(double d, int packed) {
    _a.add((d, packed));
    var i = _a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_less(i, p)) {
        _swap(i, p);
        i = p;
      } else {
        break;
      }
    }
  }

  void pop() {
    final n = _a.length;
    if (n <= 1) {
      _a.clear();
      return;
    }
    _a[0] = _a.removeLast();
    var i = 0;
    for (;;) {
      final l = 2 * i + 1;
      final r = l + 1;
      var m = i;
      if (l < _a.length && _less(l, m)) m = l;
      if (r < _a.length && _less(r, m)) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
  }

  bool _less(int i, int j) {
    final a = _a[i];
    final b = _a[j];
    if (a.$1 != b.$1) return a.$1 < b.$1;
    return a.$2 < b.$2;
  }

  void _swap(int i, int j) {
    final t = _a[i];
    _a[i] = _a[j];
    _a[j] = t;
  }
}
