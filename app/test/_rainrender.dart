// Throwaway: render the rain frame to out/rain.png for inspection.
// Set RAIN_RENDER=<name> to write out/rain_<name>.png instead.
// Run: flutter test test/_rainrender.dart --plain-name "rain render"
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower_app/camera.dart';
import 'package:water_tower_app/render/grid_painter.dart';
import 'package:water_tower_app/sim_state.dart';

void main() {
  test('rain render', () async {
    final suffix = Platform.environment['RAIN_RENDER'];
    final outName = suffix == null ? 'rain' : 'rain_$suffix';
    final state = SimState('seed-1');
    state.setRain(17);
    if (Platform.environment['RAIN_DAMAGE'] == '1') {
      state.tools.tool = Tool.bomb;
      for (final p in const [(100, 101), (110, 101), (120, 101), (105, 100),
          (115, 100), (125, 101), (95, 101), (100, 150), (118, 130),
          (110, 170), (105, 120), (125, 160), (95, 140), (115, 190),
          (108, 200), (120, 210)]) {
        state.tools.apply(state.world, p.$1, p.$2);
      }
    }
    for (var t = 0; t < 600; t++) {
      state.sim.tick(state.world);
    }
    state.paused = true; // freeze the drops mid-fall

    const w = 1200.0, h = 1000.0;
    final cam = Camera()..fit(w, h);
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    GridPainter.draw(c, Size(w, h), state, cam, null, false, (-1, -1));
    final pic = recorder.endRecording();
    final img = await pic.toImage(w.round(), h.round());
    final data = await img.toByteData(); // PNG by default
    File('../out/$outName.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}
