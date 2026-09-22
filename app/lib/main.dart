import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:water_tower_app/game/water_game.dart';
import 'package:water_tower_app/sim_state.dart';
import 'package:water_tower_app/ui/hud.dart';

void main(List<String> args) {
  var seed = 'seed-1';
  for (final a in args) {
    if (a.startsWith('--seed=')) seed = a.substring(7);
  }
  final state = SimState(seed);
  final game = WaterGame(state);
  runApp(WaterApp(state: state, game: game));
}

class WaterApp extends StatefulWidget {
  const WaterApp({super.key, required this.state, required this.game});

  final SimState state;
  final WaterGame game;

  @override
  State<WaterApp> createState() => _WaterAppState();
}

class _WaterAppState extends State<WaterApp> {
  final _gameFocus = FocusNode();

  @override
  void dispose() {
    _gameFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Ignore keys while the seed text field has focus.
    if (!_gameFocus.hasFocus) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyP:
        widget.state.togglePause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        widget.state.cycleSpeed();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        widget.state.toggleGlow();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        widget.state.togglePathTrace();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        widget.state.reset();
        widget.game.requestFit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        widget.state.newSeed();
        widget.game.requestFit();
        return KeyEventResult.handled;
      default:
        final n = _digit(event.logicalKey);
        if (n == null) return KeyEventResult.ignored;
        final t = toolForKey(n);
        if (t == null) return KeyEventResult.ignored;
        widget.state.tools.tool = t;
        return KeyEventResult.handled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '30 Floors & a Pool',
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Focus(
              focusNode: _gameFocus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Listener(
                onPointerDown: (e) =>
                    widget.game.pointerDown(e.position.dx, e.position.dy, e.buttons),
                onPointerMove: (e) =>
                    widget.game.pointerMove(e.position.dx, e.position.dy, e.buttons),
                onPointerUp: (e) => widget.game.pointerUp(e.buttons),
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    widget.game.scroll(e.position.dx, e.position.dy, e.delta.dy);
                  }
                },
                child: GameWidget(game: widget.game),
              ),
            ),
            HudOverlay(state: widget.state, game: widget.game),
          ],
        ),
      ),
    );
  }
}

int? _digit(LogicalKeyboardKey k) {
  switch (k) {
    case LogicalKeyboardKey.digit1:
    case LogicalKeyboardKey.numpad1:
      return 1;
    case LogicalKeyboardKey.digit2:
    case LogicalKeyboardKey.numpad2:
      return 2;
    case LogicalKeyboardKey.digit3:
    case LogicalKeyboardKey.numpad3:
      return 3;
    case LogicalKeyboardKey.digit4:
    case LogicalKeyboardKey.numpad4:
      return 4;
    case LogicalKeyboardKey.digit5:
    case LogicalKeyboardKey.numpad5:
      return 5;
    case LogicalKeyboardKey.digit6:
    case LogicalKeyboardKey.numpad6:
      return 6;
    case LogicalKeyboardKey.digit7:
    case LogicalKeyboardKey.numpad7:
      return 7;
    case LogicalKeyboardKey.digit8:
    case LogicalKeyboardKey.numpad8:
      return 8;
    default:
      return null;
  }
}
