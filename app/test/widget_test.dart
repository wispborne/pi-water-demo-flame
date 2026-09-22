// Phase 6 testable contract (PHASES.md):
// - the camera fits the whole world at load and after Reset / New seed;
// - speed / pause / scale propagate to the sim driver;
// - the traced view falls back to the plain view on sustained overrun
//   and the toggle re-enables on recovery.
import 'package:water_tower/core/materials.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower/trace/tracer.dart';
import 'package:water_tower_app/camera.dart';
import 'package:water_tower_app/game/water_game.dart';
import 'package:water_tower_app/main.dart';
import 'package:water_tower_app/sim_state.dart';

void main() {
  test('camera fits the whole world, centred', () {
    final cam = Camera();
    cam.fit(1280, 720);
    // Everything visible: the world's bounds map inside the screen.
    expect(cam.cellPx * Constants.gridW, lessThanOrEqualTo(1280));
    expect(cam.cellPx * Constants.gridH, lessThanOrEqualTo(720));
    // Centred: symmetric margins.
    expect(cam.offX, closeTo((1280 - cam.cellPx * Constants.gridW) / 2, 0.001));
    expect(cam.offY, closeTo((720 - cam.cellPx * Constants.gridH) / 2, 0.001));
    // The visible range is the full grid.
    final (x0, y0, x1, y1) = cam.visible(1280, 720);
    expect(x0, 0);
    expect(y0, 0);
    expect(x1, Constants.gridW);
    expect(y1, Constants.gridH);
  });

  test('screenToCell inverts the camera transform', () {
    final cam = Camera();
    cam.fit(1280, 720);
    for (final (x, y) in [
      (0, 0),
      (10, 5),
      (Constants.gridW ~/ 2, Constants.gridH ~/ 2),
      (Constants.gridW - 1, Constants.gridH - 1),
    ]) {
      final px = cam.offX + (x + 0.5) * cam.cellPx;
      final py = cam.offY + (y + 0.5) * cam.cellPx;
      final (cx, cy) = cam.screenToCell(px, py);
      expect(cx, x, reason: 'cell x for ($x, $y)');
      expect(cy, y, reason: 'cell y for ($x, $y)');
    }
  });

  test('zoom keeps the world point under the cursor fixed', () {
    final cam = Camera();
    cam.fit(1280, 720);
    final px = 640.0;
    final py = 360.0;
    final (wx0, wy0) = cam.screenToWorld(px, py);
    cam.zoomAt(px, py, 2.5);
    final (wx1, wy1) = cam.screenToWorld(px, py);
    expect(wx1, closeTo(wx0, 1e-9));
    expect(wy1, closeTo(wy0, 1e-9));
    cam.zoomAt(px, py, 1e6);
    expect(cam.cellPx, 64.0, reason: 'zoom clamped to max');
  });

  test('reset rebuilds the identical t=0 world', () {
    final s = SimState('seed-42');
    final before = List<core.Material>.of(s.world.cells);
    for (var i = 0; i < 30; i++) {
      s.sim.advance(s.world, 1 / 30);
    }
    s.reset();
    expect(s.world.cells, before);
    expect(s.sim.sun.timeSec, 0);
  });

  test('new seed with the same name rebuilds the identical world', () {
    final s = SimState('seed-42');
    final before = List<core.Material>.of(s.world.cells);
    s.newSeed('seed-42');
    expect(s.world.cells, before);
  });

  test('new seed with a different name changes the world', () {
    final s = SimState('seed-42');
    final before = List<core.Material>.of(s.world.cells);
    s.newSeed('seed-99');
    expect(s.world.cells, isNot(before));
  });

  test('pause freezes the sim clock; speed scales it', () {
    final s = SimState('seed-42');
    s.paused = true;
    expect(s.speedScale, 0.0);
    final t0 = s.sim.sun.timeSec;
    s.sim.advance(s.world, 5.0);
    expect(s.sim.sun.timeSec, t0, reason: 'paused world does not advance');
    s.paused = false;
    s.speedIndex = 2; // 2x
    expect(s.speedScale, 2.0);
    s.sim.advance(s.world, 1.0);
    // 1.0 wall-sec at 2x = 2 sim-sec = 60 ticks of 1/30 s each.
    expect(s.sim.sun.timeSec, closeTo(2.0, 0.1));
  });

  test('speed label cycles 0.5 -> 1 -> 2', () {
    final s = SimState('seed-42');
    expect(s.speedLabel, '1');
    s.cycleSpeed();
    expect(s.speedLabel, '2');
    s.cycleSpeed();
    expect(s.speedLabel, '0.5');
    s.cycleSpeed();
    expect(s.speedLabel, '1');
  });

  test('traced view falls back on budget overrun and re-enables on recovery', () {
    final s = SimState('seed-42');
    final game = WaterGame(s);
    expect(s.pathTrace, isTrue);
    expect(game.tracedActive, isTrue);

    // Simulate a sustained overrun: the budget falls back.
    for (var i = 0; i < TraceBudget.windowFrames + 1; i++) {
      s.tracer.budget.record(TraceBudget.cap + 1000);
    }
    expect(s.tracer.budget.fellBack, isTrue);
    expect(game.tracedActive, isFalse);

    // A full window under the cap recovers the toggle.
    for (var i = 0; i < TraceBudget.windowFrames + 1; i++) {
      s.tracer.budget.record(100);
    }
    expect(s.tracer.budget.fellBack, isFalse);
    expect(game.tracedActive, isTrue);
  });

  test('tool selection keys 1-8 map to the tool enum', () {
    final s = SimState('seed-42');
    for (var k = 1; k <= 8; k++) {
      s.tools.tool = Tool.values[k - 1];
      expect(s.tool, Tool.values[k - 1]);
    }
  });

  testWidgets('app builds: the HUD shows the counters and controls',
      (tester) async {
    final state = SimState('seed-42');
    final game = WaterGame(state);
    await tester.pumpWidget(WaterApp(state: state, game: game));
    await tester.pump();
    // The counter line (water count) and the controls are present.
    expect(find.textContaining('water'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('New seed'), findsOneWidget);
    expect(find.textContaining('Path trace'), findsOneWidget);
    game.dispose();
  });
}
