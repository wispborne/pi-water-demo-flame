import 'package:test/test.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

/// Phase 4 contract (PHASES.md): the sun is a deterministic function of sim
/// time and freezes when paused; the hammer and bomb reduce a cell's
/// strength toward destruction; rain at N spawns ~N water cells/s on the
/// top row; 2x advances the sim twice as fast as 1x per wall second.
void main() {
  /// An empty (ungenerated) world: exact geometry, independent of the
  /// seeded tower.
  World bare() => World(
    const Settings(floors: 1, width: 1, material: 'concrete'),
    'phase4',
  );

  /// The same generated world (a real tower + pool) from [seed].
  World generated(String seed) =>
      WorldBuilder(seed, const Settings()).build();

  group('sun', () {
    test('position is a deterministic function of sim time', () {
      // Same time, same position — a pure function.
      expect(Sun.position(123.45), Sun.position(123.45));
      // The arc: rise at the left, set at the right, peak at mid-day.
      final rise = Sun.position(0);
      final noon = Sun.position(Constants.sunCycleSec / 2);
      final set = Sun.position(Constants.sunCycleSec - 0.01);
      expect(rise.$1, closeTo(0, 1));
      expect(noon.$1, closeTo((Constants.gridW - 1) / 2, 1));
      expect(set.$1, closeTo(Constants.gridW - 1, 1));
      expect(noon.$2, lessThan(rise.$2)); // the peak is higher in the sky
      // The cycle loops: one cycle later the sun is exactly where it
      // started.
      expect(Sun.position(Constants.sunCycleSec), Sun.position(0));
    });

    test('the sun freezes when the world is paused', () {
      final w = generated('freeze');
      final sim = Sim();
      sim.advance(w, 1.0); // 30 ticks at 1x
      final t0 = sim.sun.timeSec;
      final pos0 = Sun.position(t0);
      final snap0 = w.snapshot();
      sim.speedScale = 0; // pause
      sim.advance(w, 5.0); // 5 wall-seconds of nothing
      expect(sim.sun.timeSec, t0);
      expect(Sun.position(sim.sun.timeSec), pos0);
      expect(w.snapshot(), snap0); // the whole world is frozen too
    });
  });

  group('tools', () {
    test('a hammer reduces a cell\'s strength toward destruction', () {
      final w = bare();
      w.set(100, 100, Material.concrete); // hp 8
      w.set(98, 100, Material.wood); // hp 3, inside the brush
      w.set(100, 101, Material.ground); // inside the brush, never damaged
      final tools = Tools()..tool = Tool.hammer;
      for (var i = 1; i <= 7; i++) {
        tools.apply(w, 100, 100);
        expect(w.at(100, 100), Material.concrete);
        expect(w.strength[w.idx(100, 100)], 8 - i);
      }
      // The wood (hp 3) is destroyed into debris on its 3rd hit, and
      // ground under the brush is untouched.
      expect(w.at(98, 100), Material.debris);
      expect(w.at(100, 101), Material.ground);
      tools.apply(w, 100, 100); // the 8th hit destroys the concrete
      expect(w.at(100, 100), Material.rubble); // structure breaks to rubble
      expect(w.strength[w.idx(100, 100)], 0);
      expect(w.destroyedCount, 2);
    });

    test('a bomb damages with a decaying falloff and destroys the core', () {
      final w = bare();
      w.fillRect(90, 90, 110, 110, Material.rebar); // hp 12
      final tools = Tools()..tool = Tool.bomb; // brush 5 -> radius 5
      tools.apply(w, 100, 100);
      // The centre takes the most damage; the blast edge the least.
      final center = w.strength[w.idx(100, 100)];
      final edge = w.strength[w.idx(105, 100)];
      final outside = w.strength[w.idx(107, 100)];
      expect(center, lessThan(edge));
      expect(edge, 12 - 1); // one strength off at the radius edge
      expect(outside, 12); // the blast does not reach this far
      // A second blast destroys the weakened core into rubble.
      tools.apply(w, 100, 100);
      expect(w.at(100, 100), Material.rubble);
      expect(w.destroyedCount, 1);
    });

    test('the build tools place their material and erase clears it', () {
      final w = bare();
      final tools = Tools();
      tools.tool = Tool.buildGlass;
      tools.apply(w, 100, 100);
      expect(w.at(100, 100), Material.glass);
      tools.tool = Tool.erase;
      tools.apply(w, 100, 100);
      expect(w.at(100, 100), Material.air);
    });
  });

  group('rain', () {
    test('rain spawns water on the top row, uniform left to right', () {
      final w = bare();
      final tools = Tools()..rain = 30;
      for (var i = 0; i < 10; i++) {
        tools.rainTick(w, 0.1); // 10 x 0.1 s = 1 sim-second = 30 drops
      }
      var top = 0;
      for (var x = 0; x < Constants.gridW; x++) {
        if (w.at(x, 0) == Material.water) top++;
      }
      expect(top, 30); // every drop is on the top row...
      for (var x = 0; x < 30; x++) {
        expect(w.at(x, 0), Material.water); // ...left to right
      }
      expect(w.at(30, 0), Material.air);
      expect(w.at(100, 0), Material.air); // not scattered mid-row
    });

    test('rain at N spawns N water cells per sim-second (1x, 2x, 0.5x)', () {
      for (final (rate, scale, wallSec) in [
        (10, 1.0, 6.0),
        (10, 2.0, 3.0),
        (10, 0.5, 12.0),
      ]) {
        final w = bare();
        final sim = Sim()..speedScale = scale;
        sim.tools.rain = rate;
        sim.advance(w, wallSec);
        // Exactly rate * (wallSec * scale) sim-seconds of rain.
        final expectTotal = rate * (wallSec * scale).round();
        expect(
          w.countWater(),
          inInclusiveRange(expectTotal - 1, expectTotal + 1),
          reason: 'rate $rate at ${scale}x for $wallSec wall-seconds',
        );
      }
    });
  });

  group('sim driver', () {
    test('2x advances the sim state twice as fast as 1x per wall second', () {
      final a = generated('fast');
      final b = generated('fast');
      final sa = Sim();
      final sb = Sim()..speedScale = 2;
      sa.advance(a, 2.0); // 2 wall-seconds at 1x = 60 ticks
      sb.advance(b, 1.0); // 1 wall-second at 2x = 60 ticks
      expect(a.snapshot(), b.snapshot());
      expect(sa.sun.timeSec, closeTo(sb.sun.timeSec, 1e-9));
    });

    test('0.5x advances half as fast as 1x per wall second', () {
      final a = generated('slow');
      final b = generated('slow');
      final sa = Sim()..tools.rain = 30;
      final sb = Sim()
        ..speedScale = 0.5
        ..tools.rain = 30;
      sa.advance(a, 1.0); // 30 ticks (1 sim-second of rain: 30 drops)
      sb.advance(b, 1.0); // 15 ticks (0.5 sim-seconds of rain: 15 drops)
      expect(sa.sun.timeSec, closeTo(sb.sun.timeSec * 2, 1e-9));
      expect(a.countWater(), greaterThan(b.countWater()));
    });

    test('the speed cycles 0.5 -> 1 -> 2 and reports its label', () {
      final sim = Sim()..speedScale = 0.5;
      expect(sim.speedLabel, '0.5');
      sim.cycleSpeed();
      expect(sim.speedScale, 1);
      expect(sim.speedLabel, '1');
      sim.cycleSpeed();
      expect(sim.speedScale, 2);
      expect(sim.speedLabel, '2');
      sim.cycleSpeed();
      expect(sim.speedScale, 0.5);
      sim.speedScale = 0;
      expect(sim.speedLabel, '0');
    });
  });
}
