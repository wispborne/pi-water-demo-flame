import 'dart:async';

import 'package:flutter/material.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower_app/game/water_game.dart';
import 'package:water_tower_app/sim_state.dart';

/// The HUD (SPEC 10): the counters, the hover readout, the controls, and
/// the sliders. A Flutter overlay over the game canvas; it reads [SimState]
/// at 10 Hz (a [Timer]) so it never blocks the render loop.
class HudOverlay extends StatefulWidget {
  const HudOverlay({super.key, required this.state, required this.game});

  final SimState state;
  final WaterGame game;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  late final TextEditingController _seedCtrl;
  final _seedFocus = FocusNode();
  Timer? _debounce;
  Timer? _ticker;
  (int, int, String) _pending = (0, 0, '');

  @override
  void initState() {
    super.initState();
    _seedCtrl = TextEditingController(text: widget.state.seed);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _seedCtrl.dispose();
    _seedFocus.dispose();
    _debounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _applySettings(int? floors, int? width, String? material) {
    final s = widget.state.settings;
    _pending = (floors ?? s.floors, width ?? s.width, material ?? s.material);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      final (f, w, m) = _pending;
      widget.state.applySettings(f, w, m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          Positioned(top: 8, left: 8, child: _hoverPanel(s)),
          Positioned(left: 8, right: 8, bottom: 8, child: _bottomBar(s)),
        ],
      ),
    );
  }

  Widget _hoverPanel(SimState s) {
    final (hx, hy) = widget.game.hover;
    if (hx < 0) return const SizedBox.shrink();
    final i = s.world.idx(hx, hy);
    final m = s.world.at(hx, hy);
    final hp = s.world.strength[i];
    final maxHp = Materials.of(m).hp;
    final head = s.sim.water.bodyHead[i];
    final traced = s.pathTrace;
    final (r, g, b) = s.tracer.field.rgb8(i);
    final lum = (s.tracer.field.luminance(i) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC101828),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            m.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Text(
            'HP $hp/$maxHp  head $head'
            '${traced ? '  light $lum%' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          if (traced) ...[
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              color: Color.fromARGB(255, r, g, b),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(SimState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC101828),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'water ${s.waterCount}   damage ${s.damagePercent.toStringAsFixed(1)}%   '
                    'destroyed ${s.world.destroyedCount}   FPS ${widget.game.fps}   '
                    'seed ${s.seed}   tool ${s.tool.name}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  _btn(s.paused ? 'Resume' : 'Pause', s.togglePause),
                  const SizedBox(width: 4),
                  _btn('${s.speedLabel}x', s.cycleSpeed),
                  const SizedBox(width: 4),
                  _btn('Reset', () {
                    s.reset();
                    widget.game.requestFit();
                  }),
                  const SizedBox(width: 4),
                  _btn('New seed', () {
                    s.newSeed();
                    _seedCtrl.text = s.seed;
                    widget.game.requestFit();
                  }),
                  const SizedBox(width: 4),
                  _btn(s.glow ? 'Glow on' : 'Glow off', s.toggleGlow),
                  const SizedBox(width: 4),
                  _btn(
                    s.pathTrace ? 'Path trace on' : 'Path trace off',
                    s.togglePathTrace,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _seedCtrl,
                      focusNode: _seedFocus,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'seed name',
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          s.newSeed(v);
                          widget.game.requestFit();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  _slider('brush', 1, 15, s.tools.brushSize.toDouble(),
                      (v) => s.setBrush(v.round())),
                  const SizedBox(width: 12),
                  _slider('rain', 0, 40, s.tools.rain.toDouble(),
                      (v) => s.setRain(v.round())),
                  const SizedBox(width: 12),
                  _slider('floors', 1, 50, s.settings.floors.toDouble(),
                      (v) => _applySettings(v.round(), null, null)),
                  const SizedBox(width: 12),
                  _slider('width', 1, 5, s.settings.width.toDouble(),
                      (v) => _applySettings(null, v.round(), null)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'structure',
                            style: TextStyle(
                                fontSize: 11, color: Colors.white70)),
                        DropdownButton<String>(
                          value: s.settings.material,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: const Color(0xFF101828),
                          items: const [
                            DropdownMenuItem(value: 'concrete', child: Text('concrete')),
                            DropdownMenuItem(value: 'rebar', child: Text('rebar')),
                            DropdownMenuItem(value: 'steel', child: Text('steel')),
                            DropdownMenuItem(value: 'titanium', child: Text('titanium')),
                          ],
                          onChanged: (m) =>
                              m == null ? null : _applySettings(null, null, m),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'keys 1-8 tools · LMB apply · RMB pan · wheel zoom',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        minimumSize: const Size(0, 28),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }

  Widget _slider(String label, double min, double max, double value,
      ValueChanged<double> onChanged) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${value.round()}',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Maps a key (1-8) to a tool via the core (SPEC 8); null outside range.
Tool? toolForKey(int key) => key >= 1 && key <= 8
    ? Tool.values[key - 1]
    : null;

