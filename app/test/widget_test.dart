// Phase 6 testable contract (PHASES.md):
// - the camera fits the whole world at load and after Reset / New seed;
// - speed / pause / scale propagate to the sim driver;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart' as core;
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

  test('middle button drag pans the camera', () {
    final game = WaterGame(SimState('seed-42'));
    final before = (game.cam.offX, game.cam.offY);
    game.pointerDown(100, 100, 4);
    game.pointerMove(130, 80, 4);
    expect(game.cam.offX, closeTo(before.$1 + 30, 1e-9));
    expect(game.cam.offY, closeTo(before.$2 - 20, 1e-9));
    // No zoom side effect.
    game.pointerUp(0);
    expect(game.cam.cellPx, 3);
  });

  testWidgets('mouse wheel over the canvas zooms at the cursor',
      (tester) async {
    final state = SimState('seed-42');
    final game = WaterGame(state);
    await tester.pumpWidget(WaterApp(state: state, game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final before = (game.cam.cellPx, game.cam.offX, game.cam.offY);
    final center = Offset(400, 300);
    // A Windows wheel notch is ~120 logical px; the signal event carries
    // it in scrollDelta (PointerScrollEvent.delta stays Offset.zero).
    final signal = PointerScrollEvent(
      position: center,
      scrollDelta: const Offset(0, -120),
      kind: PointerDeviceKind.mouse,
    );
    final listener = tester.allRenderObjects
        .whereType<RenderPointerListener>()
        .firstWhere((l) => l.onPointerSignal != null);
    listener.onPointerSignal?.call(signal);
    await tester.pump();
    // One notch zooms in (x1.1) and the world point under the cursor
    // stays fixed.
    expect(game.cam.cellPx, closeTo(before.$1 * 1.1, 1e-9));
    final wx0 = (center.dx - before.$2) / before.$1;
    final wy0 = (center.dy - before.$3) / before.$1;
    final wx1 = (center.dx - game.cam.offX) / game.cam.cellPx;
    final wy1 = (center.dy - game.cam.offY) / game.cam.cellPx;
    expect(wx1, closeTo(wx0, 1e-9));
    expect(wy1, closeTo(wy0, 1e-9));
    game.dispose();
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

  testWidgets('hover readout shows the SPEC 10 strength bar', (tester) async {
    final state = SimState('seed-42');
    final game = WaterGame(state);
    state.paused = true; // freeze the sim so the hovered cell is stable
    await tester.pumpWidget(WaterApp(state: state, game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Find an undamaged structural cell.
    int cx = -1, cy = -1;
    outer:
    for (var y = 0; y < Constants.gridH; y++) {
      for (var x = 0; x < Constants.gridW; x++) {
        final m = state.world.at(x, y);
        if (core.Materials.structure.contains(m) &&
            state.world.strength[state.world.idx(x, y)] ==
                core.Materials.of(m).hp) {
          cx = x;
          cy = y;
          break outer;
        }
      }
    }
    expect(cx, greaterThanOrEqualTo(0));
    final maxHp = core.Materials.of(state.world.at(cx, cy)).hp;

    // Hover it: the bar appears, full width.
    final px = game.cam.offX + (cx + 0.5) * game.cam.cellPx;
    final py = game.cam.offY + (cy + 0.5) * game.cam.cellPx;
    game.pointerMove(px, py, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('strength-bar')), findsOneWidget);
    final full = tester.getSize(find.byKey(const ValueKey('strength-bar-fill')));
    expect(full.width, closeTo(60, 0.5));

    // Hammer the cell down to 1 hp: the bar shrinks in proportion.
    state.tools.tool = Tool.hammer;
    for (var i = 0; i < maxHp - 1; i++) {
      state.sim.tools.apply(state.world, cx, cy);
    }
    await tester.pump(const Duration(milliseconds: 150));
    final hp = state.world.strength[state.world.idx(cx, cy)];
    expect(hp, 1);
    final shrunken = tester.getSize(find.byKey(const ValueKey('strength-bar-fill')));
    expect(shrunken.width, closeTo(60 * hp / maxHp, 0.5));
    game.dispose();
  });
}
