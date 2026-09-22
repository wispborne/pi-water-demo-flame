 import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:image/image.dart' as img;
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/trace/field.dart';
import 'package:water_tower_app/camera.dart';
import 'package:water_tower_app/render/grid_painter.dart';
import 'package:water_tower_app/sim_state.dart';

/// The Flame layer: game loop, camera, and rendering. All simulation state
/// lives in [SimState]; this class only renders (PLAN decision 4). Raw
/// pointer events are routed from the `Listener` wrapper in main.dart via
/// [pointerDown]/[pointerMove]/[pointerUp]/[scroll].
class WaterGame extends FlameGame {
  WaterGame(this.state);

  final SimState state;
  final Camera cam = Camera();
  final FieldBlitter blitter = FieldBlitter();

  /// Set on load / Reset / New seed: the camera re-fits the whole world
  /// (SPEC 9).
  bool refit = true;

  int fps = 0;
  int _frames = 0;
  double _fpsClock = 0;

  (double, double)? _lastMouse;
  bool _leftDown = false;
  bool _rightDown = false;
  bool _midDown = false;

  /// The cell under the cursor (for the hover readout); (-1, -1) when
  /// outside the world.
  (int, int) hover = (-1, -1);

  /// The traced view is active when the user enabled it and the ray
  /// budget has not fallen back (PLAN decision 2: a sustained overrun
  /// drops to the plain view; a full window back under the cap
  /// re-enables the toggle).
  bool get tracedActive => state.pathTrace && !state.tracer.budget.fellBack;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (refit) {
      cam.fit(size.x, size.y);
      refit = false;
    }
  }

  void requestFit() => refit = true;

  @override
  void update(double dt) {
    super.update(dt);
    state.sim.advance(state.world, dt);
    if (tracedActive) {
      state.tracer.trace(state.world, state.sim.water, state.sim.sun);
      blitter.update(state.tracer.field);
    }
    _frames++;
    _fpsClock += dt;
    if (_fpsClock >= 0.5) {
      fps = (_frames / _fpsClock).round();
      state.fps = fps.toDouble();
      _frames = 0;
      _fpsClock = 0;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    GridPainter.draw(
      canvas,
      ui.Size(size.x, size.y),
      state,
      cam,
      blitter.image,
      tracedActive,
      hover,
    );
  }

  // ---- Raw pointer routing (from the Listener wrapper) ----

  void pointerDown(double x, double y, int buttons) {
    _lastMouse = (x, y);
    if (buttons & 1 != 0) {
      _leftDown = true;
      _applyTool(x, y);
    }
    if (buttons & 2 != 0) _rightDown = true;
    if (buttons & 4 != 0) _midDown = true;
  }

  void pointerMove(double x, double y, int buttons) {
    _setHover(x, y);
    final last = _lastMouse;
    if (last != null) {
      if (_rightDown || _midDown) cam.pan(x - last.$1, y - last.$2);
      if (_leftDown) _applyTool(x, y);
    }
    _lastMouse = (x, y);
  }

  void pointerUp(int buttons) {
    if (buttons & 1 == 0) _leftDown = false;
    if (buttons & 2 == 0) _rightDown = false;
    if (buttons & 4 == 0) _midDown = false;
  }

  void scroll(double x, double y, double dx, double dy) {
    // While the middle button is held, Windows delivers the drag as
    // WM_MOUSEWHEEL (the OS auto-scroll feature), not as mouse moves —
    // so the drag arrives here: pan by both axes.
    if (_midDown) {
      cam.pan(dx, dy);
      return;
    }
    // ~120 logical px per mouse wheel notch: one notch = x1.1;
    // trackpads send small continuous deltas and zoom smoothly.
    final factor = math.pow(1.1, -dy / 120).toDouble();
    cam.zoomAt(x, y, factor);
  }

  void _setHover(double x, double y) {
    final (cx, cy) = cam.screenToCell(x, y);
    hover = cx >= 0 && cy >= 0 && cx < Constants.gridW && cy < Constants.gridH
        ? (cx, cy)
        : (-1, -1);
  }

  void _applyTool(double x, double y) {
    final (cx, cy) = cam.screenToCell(x, y);
    if (cx >= 0 && cy >= 0 && cx < Constants.gridW && cy < Constants.gridH) {
      state.sim.tools.apply(state.world, cx, cy);
    }
  }
}

/// Blits the light field (220x240 RGBA) to a [ui.Image] for the traced
/// view. The raw buffer is PNG-encoded (pure-Dart `image` package; the
/// SDK here exposes no PNG encoder) and decoded on a codec thread; the
/// last completed image is drawn, so the field lags by at most a frame or
/// two — invisible on a field that settles in ~1 s.
class FieldBlitter {
  ui.Image? image;
  bool _pending = false;

  void update(LightField field) {
    if (_pending) return;
    _pending = true;
    final w = Constants.gridW;
    final h = Constants.gridH;
    final raw = field.rgbaPixels();
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: raw.buffer,
      format: img.Format.uint8,
      numChannels: 4,
    );
    final png = img.encodePng(im);
    ui
        .instantiateImageCodec(png)
        .then((codec) => codec.getNextFrame())
        .then((f) {
          image = f.image;
          _pending = false;
        })
        .catchError((Object _) {
          _pending = false;
        });
  }
}
