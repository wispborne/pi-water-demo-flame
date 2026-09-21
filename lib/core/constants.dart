/// Fixed world constants (PLAN decisions, decision 1/4/8).
/// Grid is 220 (W) x 240 (H) cells; cell (0,0) is top-left, y grows downward.
class Constants {
  static const int gridW = 220;
  static const int gridH = 240;

  /// One floor = 1 slab row + 3 interior rows.
  static const int floorHeight = 4;

  /// One bay = 4 cells wide (interior span only; outer walls add 1 per side).
  static const int bayWidth = 4;

  /// Ground surface is seeded 12..28 cells above the bottom row.
  static const int groundLevelMin = 12;
  static const int groundLevelMax = 28;

  /// Initial pool fill is fixed 8 cells deep, clamped to the pool's height.
  static const int poolFill = 8;

  /// Pool size ranges (seeded).
  static const int poolWMin = 8;
  static const int poolWMax = 24;
  static const int poolDepthMin = 6;
  static const int poolDepthMax = 12;
  static const int poolGapMin = 2;
  static const int poolGapMax = 6;

  /// Physics: 30 ticks/s at 1x; slump lasts 2 sim-seconds (decision 4).
  static const int physicsTicksPerSec = 30;

  /// Slump duration in ticks: 2 sim-seconds (decision 4).
  static const int slumpTicks = 60;

  /// Sun: full cycle is 420 sim-seconds (decision 3).
  static const double sunCycleSec = 420.0;

  /// Jets: head >= 8 cells spurts upward; height ~= head/2, capped (decision 8).
  static const int jetMinHead = 8;
  static const int jetMaxHeight = 12;

  /// A support gap >= 3 cells severs the load path; <= 2 still bridges.
  static const int severGap = 3;

  /// Settings ranges (SPEC section 2).
  static const int floorsMin = 1;
  static const int floorsMax = 50;
  static const int widthMin = 1;
  static const int widthMax = 5;
}
