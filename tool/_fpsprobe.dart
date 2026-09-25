/// Headless probe: per-frame trace() cost and occluder-change count for the
/// default 30-floor/6-bay scene left to run at 1x.
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

void main() {
  const settings = Settings();
  final world = WorldBuilder('probe', settings).build();
  final sim = Sim();
  final t = Tracer();

  int occluderCount() {
    var n = 0;
    for (var y = 0; y < 240; y++) {
      for (var x = 0; x < 220; x++) {
        if (Materials.blocksLight(world.at(x, y))) n++;
      }
    }
    return n;
  }

  // Converge.
  for (var i = 0; i < 450; i++) {
    sim.advance(world, 1 / 60);
    t.trace(world, sim.water, sim.sun);
  }
  print('occluders: ${occluderCount()}');

  var changedFrames = 0;
  final sw = Stopwatch()..start();
  const frames = 180;
  for (var i = 0; i < frames; i++) {
    sim.advance(world, 1 / 60);
    t.trace(world, sim.water, sim.sun);
  }
  sw.stop();
  print('trace: ${sw.elapsedMicroseconds / frames / 1000} ms/frame over $frames frames');

  // How often do light-blocking cells change, tick by tick?
  var prev = -1;
  for (var i = 0; i < 300; i++) {
    sim.advance(world, 1 / 60);
    final now = occluderCount();
    if (prev >= 0 && now != prev) changedFrames++;
    prev = now;
  }
  print('occluder count changed in $changedFrames/300 ticks');
}
