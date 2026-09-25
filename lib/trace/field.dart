import 'dart:typed_data';

import '../core/constants.dart';

/// Per-cell accumulated light (PLAN decision 2: the field is 1:1 with the
/// grid, 220 x 240). Each cell holds a running mean of its exact
/// next-event-estimated light contribution; the rays are deterministic, so
/// one sample is the settled value and the running mean only adds a short
/// lag following slow changes (the drifting sun).
///
/// Dirty bookkeeping: a cell is re-converged when its [count] is reset to 0
/// (by [markDirty]); its last value is kept until the next sample, so a
/// change never flashes black, and converged undirty cells keep their value
/// untouched (SPEC 7: re-converge only in the places that changed).
class LightField {
  static const int convSamples = 32;

  final int w;
  final int h;
  final List<double> _r;
  final List<double> _g;
  final List<double> _b;
  final Uint16List _count;

  LightField({this.w = Constants.gridW, this.h = Constants.gridH})
    : _r = List<double>.filled(w * h, 0),
      _g = List<double>.filled(w * h, 0),
      _b = List<double>.filled(w * h, 0),
      _count = Uint16List(w * h);

  int idx(int x, int y) => y * w + x;

  double r(int i) => _r[i];
  double g(int i) => _g[i];
  double b(int i) => _b[i];

  /// The number of samples accumulated for the cell in its current epoch
  /// (0 = dirty/never sampled; >= [convSamples] = converged).
  int count(int i) => _count[i];

  bool converged(int i) => _count[i] >= convSamples;

  /// Absorb one exact sample into the cell's running mean. [weight] sets
  /// the follow rate of the mean (default: converging 1/(count+1)); the
  /// tracer's sun-drift stripe passes a fixed fast weight so a converged
  /// cell tracks the drifting sun with a sub-second lag.
  void sample(int i, double r, double g, double b, {double? weight}) {
    final c = _count[i];
    if (c == 0) {
      _r[i] = r;
      _g[i] = g;
      _b[i] = b;
      _count[i] = 1;
    } else {
      // Past the cap the value keeps tracking slowly (the "short lag" that
      // follows the drifting sun) without ever re-converging.
      final k = weight ?? 1.0 / (c + 1);
      _r[i] += (r - _r[i]) * k;
      _g[i] += (g - _g[i]) * k;
      _b[i] += (b - _b[i]) * k;
      if (c < convSamples) _count[i] = (c + 1).toInt();
    }
  }

  /// Mark the cell dirty: it re-converges on its next sample. The last value
  /// is kept until then (no black flash).
  void markDirty(int i) => _count[i] = 0;

  /// Reset the whole field (new world / Reset / New seed).
  void clear() {
    _r.fillRange(0, _r.length, 0);
    _g.fillRange(0, _g.length, 0);
    _b.fillRange(0, _b.length, 0);
    _count.fillRange(0, _count.length, 0);
  }

  /// Luminance in 0..1 (for the HUD's light percentage readout).
  double luminance(int i) =>
      0.2126 * _r[i] + 0.7152 * _g[i] + 0.0722 * _b[i];

  /// 8-bit colour for the cell (Reinhard tone map; for the GUI blit).
  (int, int, int) rgb8(int i) {
    final m = 255.0;
    return (
      (_r[i] / (1 + _r[i]) * m).round().clamp(0, 255),
      (_g[i] / (1 + _g[i]) * m).round().clamp(0, 255),
      (_b[i] / (1 + _b[i]) * m).round().clamp(0, 255),
    );
  }

  /// RGBA (premultiplied alpha not needed; fully opaque) for a [ui.Image]
  /// blit in the GUI.
  Uint8List rgbaPixels() {
    final out = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final (r, g, b) = rgb8(i);
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }
}
