import 'constants.dart';

/// The three generation settings (SPEC section 2).
class Settings {
  final int floors; // 1..50, default 30
  final int width; // bays 1..5, default 3
  final String material; // concrete | rebar | steel | titanium, default rebar

  const Settings({
    this.floors = 30,
    this.width = 3,
    this.material = 'rebar',
  });

  factory Settings.validate({int? floors, int? width, String? material}) {
    final f = floors ?? 30;
    final w = width ?? 3;
    final m = material ?? 'rebar';
    if (f < Constants.floorsMin || f > Constants.floorsMax) {
      throw ArgumentError('floors $f out of range');
    }
    if (w < Constants.widthMin || w > Constants.widthMax) {
      throw ArgumentError('width $w out of range');
    }
    if (m != 'concrete' && m != 'rebar' && m != 'steel' && m != 'titanium') {
      throw ArgumentError('bad material $m');
    }
    return Settings(floors: f, width: w, material: m);
  }

  /// Stable fingerprint used by Rng.fromString and the world fingerprint.
  String get fingerprint => 'f=$floors,w=$width,m=$material';

  @override
  String toString() => 'Settings($fingerprint)';
}
