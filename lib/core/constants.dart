/// Fixed world constants (PLAN decisions, decision 1/4/8).
/// Grid is 220 (W) x 240 (H) cells; cell (0,0) is top-left, y grows downward.
class Constants {
  static const int gridW = 220;
  static const int gridH = 240;

  /// One floor = 1 slab row + 3 interior rows.
  static const int floorHeight = 4;

  /// One bay = 8 cells wide (interior span only; outer walls add 1 per side).
  static const int bayWidth = 8;

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

  /// Settling substeps per tick (the water falling/flow pass and the
  /// granular rubble/debris pass): a pile sheds one cell per substep, so a
  /// poured column collapses [settleSubsteps]x faster than a single pass
  /// would; a settled field makes no moves and exits after the first pass.
  static const int settleSubsteps = 6;

  /// Tools: brush size 1..15 cells (default 5); rain 0..40 cells/s (SPEC 8/9).
  static const int brushMin = 1;
  static const int brushMax = 15;
  static const int brushDefault = 5;
  static const int rainMax = 40;
  static const int slumpTicks = 60;

  /// Sun arc (SPEC 6): the disc rises at the left edge, peaks at row
  /// [sunTopY], sets at the right edge; [sunArcDepth] is the arc's sag
  /// below its top at the horizon.
  static const int sunTopY = 6;
  static const int sunArcDepth = 34;

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
  static const int widthMax = 10;
}
