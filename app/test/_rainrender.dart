// Throwaway: render the rain frame to out/rain.png for inspection.
// Set RAIN_RENDER=<name> to write out/rain_<name>.png instead.
// Run: flutter test test/_rainrender.dart --plain-name "rain render"
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_tower_app/camera.dart';
import 'package:water_tower_app/render/grid_painter.dart';
import 'package:water_tower_app/sim_state.dart';

void main() {
  test('rain render', () async {
    final suffix = Platform.environment['RAIN_RENDER'];
    final outName = suffix == null ? 'rain' : 'rain_$suffix';
    final state = SimState('seed-1');
    state.setRain(17);
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
