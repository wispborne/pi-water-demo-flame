/// Lamp kinds (CONTEXT.md: Lamp) and their states.
enum LampKind { floor, ceiling, table }

enum LampState { fixed, free, broken }

/// One lamp object. A ceiling lamp is fixed to the ceiling slab until that
/// slab breaks, then falls as a loose lamp that stays lit until it itself
/// breaks (SPEC section 2).
class Lamp {
  final LampKind kind;
  int x;
  int y;
  LampState state;

  /// A lit lamp glows (traced view lights it; Phase 5 uses this).
  bool lit;

  Lamp(
    this.kind,
    this.x,
    this.y, {
    this.state = LampState.fixed,
    this.lit = true,
  });

  bool get isLit => lit && state != LampState.broken;

  @override
  String toString() =>
      'Lamp(${kind.name} @ $x,$y, ${state.name}, ${lit ? 'lit' : 'off'})';
}
