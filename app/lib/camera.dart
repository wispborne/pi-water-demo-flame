import 'dart:math' as math;

import 'package:water_tower/core/constants.dart';

/// The camera: pixels-per-cell zoom plus the world's top-left screen offset.
/// Pure Dart (testable headless).
class Camera {
  double cellPx = 3;
  double offX = 0;
  double offY = 0;

  /// Fit the whole world, centred (SPEC 9: at load and after Reset /
  /// New seed).
  void fit(double w, double h) {
    cellPx = math.min(w / Constants.gridW, h / Constants.gridH);
    offX = (w - cellPx * Constants.gridW) / 2;
    offY = (h - cellPx * Constants.gridH) / 2;
  }

  void pan(double dx, double dy) {
    offX += dx;
    offY += dy;
  }

  /// Zoom centred on the screen point (px, py); the world point under
  /// the cursor stays fixed.
  void zoomAt(double px, double py, double factor) {
    final wx = (px - offX) / cellPx;
    final wy = (py - offY) / cellPx;
    cellPx = (cellPx * factor).clamp(1.0, 64.0);
    offX = px - wx * cellPx;
    offY = py - wy * cellPx;
  }

  /// The world coordinates (in cell units; a cell (x, y) occupies
  /// [x, x+1)) of a screen point.
  (double, double) screenToWorld(double px, double py) =>
      (((px - offX) / cellPx, (py - offY) / cellPx));

  /// The visible cell range, clamped (x1/y1 exclusive).
  (int, int, int, int) visible(double w, double h) {
    final x0 = (-offX / cellPx).floor().clamp(0, Constants.gridW);
    final y0 = (-offY / cellPx).floor().clamp(0, Constants.gridH);
    final x1 = ((w - offX) / cellPx).ceil().clamp(0, Constants.gridW);
    final y1 = ((h - offY) / cellPx).ceil().clamp(0, Constants.gridH);
    return (x0, y0, x1, y1);
  }
  /// The cell containing a screen point (a cell (x, y) occupies
  /// [x, x+1)).
  (int, int) screenToCell(double px, double py) {
    final (wx, wy) = screenToWorld(px, py);
    return (wx.floor(), wy.floor());
  }
}
