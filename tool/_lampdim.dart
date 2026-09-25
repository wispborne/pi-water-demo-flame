/// Headless probe: the exact settled lamp-light values for the phase5 test
/// scene (one lamp, a glass two-cell gap in the partition), so the test
/// thresholds sit on the real numbers.
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/ray.dart';
import 'package:water_tower/trace/shadows.dart';
import 'package:water_tower/trace/tracer.dart';
import 'package:water_tower/trace/transport.dart';

const _settings = Settings(floors: 30, width: 3, material: 'rebar');

void main() {
  final w = World(_settings, 'phase5');
  w.fillRect(0, 238, 219, 239, Material.ground);
  w.fillRect(180, 0, 180, 237, Material.concrete);
  w.fillRect(210, 0, 210, 237, Material.concrete);
  w.fillRect(180, 0, 210, 0, Material.concrete);
  w.fillRect(195, 0, 195, 237, Material.concrete);
  w.set(195, 229, Material.glass);
  w.set(195, 230, Material.glass);
  w.lamps.add(Lamp(LampKind.floor, 188, 228));

  final sim = Sim();
  sim.sun.timeSec = 841.0;
  final t = Tracer();
  for (var i = 0; i < 90; i++) t.trace(w, sim.water, sim.sun);

  // Exact one-sample values (no running mean): build the transport by hand.
  final (sx, sy) = Sun.position(841.0);
  final spans = SceneSpans()..rebuildAll(w, sim.water);
  final blockers = <(int, int)>[];
  for (var y = 0; y < 240; y++) {
    for (var x = 0; x < 220; x++) {
      if (Materials.blocksLight(w.at(x, y))) blockers.add((x, y));
    }
  }
  final sunSweep = ShadowSweep()..build(sx, sy, blockers);
  final lampSweep = ShadowSweep()..build(188.5, 228.5, blockers);
  final transport = Transport(
    spans, sunSweep, [lampSweep], [188], [228], w, sim.water, sx, sy, 841.0);
  for (final (x, y) in [
    (190, 228),
    (202, 230),
    (195, 230),
    (195, 229),
  ]) {
    final (r, g, b) = transport.sample(x, y);
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    print('exact  ($x,$y): r=$r g=$g b=$b lum=$lum');
  }
  print('field  (202,230): ${t.field.luminance(w.idx(202, 230))} after 90 frames');
  print('field  (195,230): ${t.field.luminance(w.idx(195, 230))}');
  print('field  (190,228): ${t.field.luminance(w.idx(190, 228))}');
}
