import 'dart:math' show min;

import 'constants.dart';

/// Everything that can fill a cell (CONTEXT.md: Material).
enum Material {
  air,
  ground,
  concrete,
  rebar, // reinforced concrete (default structure material)
  steel,
  titanium,
  glass,
  wood,
  rubble, // broken heavy building material; washed by flowing water; sinks
  debris, // broken light things; washed by flowing water; floats
  water,
  chair,
  plant,
  tv,
  fridge,
  desk,
  table,
  counter,
  bed,
  tub,
  sofa,
  lamp, // lamp object (floor/ceiling/table); kind tracked separately
}

/// One property row of the material table (PLAN decision 6).
class MaterialProps {
  /// Water head in cells that erodes this material; -1 means never (infinity).
  final int tolerance;

  /// Tool damage required to destroy a cell.
  final int hp;

  /// Floats (a little) when it becomes a loose object.
  final bool floats;

  const MaterialProps(this.tolerance, this.hp, this.floats);
}

class Materials {
  static const Map<Material, MaterialProps> props = {
    Material.air: MaterialProps(-1, 1, false),
    Material.ground: const MaterialProps(-1, 999, false), // very hard
    Material.concrete: const MaterialProps(12, 8, false),
    Material.rebar: const MaterialProps(20, 12, false),
    Material.steel: const MaterialProps(30, 20, false),
    Material.titanium: const MaterialProps(40, 30, false),
    Material.glass: const MaterialProps(
      2,
      2,
      true,
    ), // very weak, floats a little
    Material.wood: const MaterialProps(6, 3, true),
    Material.rubble: const MaterialProps(-1, 999, false),
    Material.debris: const MaterialProps(-1, 999, true),
    Material.water: const MaterialProps(-1, 1, true),
    Material.chair: const MaterialProps(-1, 3, true),
    Material.plant: const MaterialProps(-1, 3, true),
    Material.tv: const MaterialProps(-1, 3, false),
    Material.fridge: const MaterialProps(-1, 3, false),
    Material.desk: const MaterialProps(-1, 3, true),
    Material.table: const MaterialProps(-1, 3, true),
    Material.counter: const MaterialProps(-1, 3, true),
    Material.bed: const MaterialProps(-1, 3, false),
    Material.tub: const MaterialProps(-1, 3, false),
    Material.sofa: const MaterialProps(-1, 3, true),
    Material.lamp: const MaterialProps(-1, 3, true),
  };

  /// Structure materials: the tower's walls, slabs, partitions, roof.
  static const Set<Material> structure = {
    Material.concrete,
    Material.rebar,
    Material.steel,
    Material.titanium,
  };

  static const Set<Material> furnitureTypes = {
    Material.chair,
    Material.plant,
    Material.tv,
    Material.fridge,
    Material.desk,
    Material.table,
    Material.counter,
    Material.bed,
    Material.tub,
    Material.sofa,
  };

  // Material-indexed fast tables for the hot per-cell loops (a List lookup
  // instead of a Set/Map hash): built once from the sets above.
  static final List<bool> structureByIndex =
      [for (final m in Material.values) structure.contains(m)];
  static final List<bool> furnitureByIndex =
      [for (final m in Material.values) furnitureTypes.contains(m)];
  static final List<bool> blocksWaterByIndex = [
    for (final m in Material.values)
      structure.contains(m) ||
          m == Material.ground ||
          m == Material.wood ||
          m == Material.glass
  ];
  static final List<bool> blocksLightByIndex = [
    for (final m in Material.values)
      structure.contains(m) || m == Material.ground || m == Material.wood
  ];

  /// Per-channel reflectance for the light-blocking materials: the traced
  /// view multiplies the light arriving at a solid cell by this, so walls
  /// read darker than the lit air around them. Values follow the plain
  /// view's palette (non-blocking materials are white: unaffected).
  static final List<(double, double, double)> albedoByIndex = [
    for (final m in Material.values) _albedo(m),
  ];

  static (double, double, double) _albedo(Material m) {
    switch (m) {
      case Material.ground:
        return (0.23, 0.20, 0.16);
      case Material.concrete:
        return (0.66, 0.66, 0.66);
      case Material.rebar:
        return (0.71, 0.67, 0.61);
      case Material.steel:
        return (0.56, 0.65, 0.70);
      case Material.titanium:
        return (0.78, 0.79, 0.81);
      case Material.wood:
        return (0.54, 0.42, 0.30);
      default:
        return (1.0, 1.0, 1.0);
    }
  }
  static final List<int> toleranceByIndex =
      [for (final m in Material.values) props[m]!.tolerance];
  static final List<int> hpByIndex =
      [for (final m in Material.values) props[m]!.hp];

  /// The material's water-erosion tolerance (-1 = never erodes).
  static int tolerance(Material m) => toleranceByIndex[m.index];

  /// The material's tool-damage hp.
  static int hp(Material m) => hpByIndex[m.index];

  /// True when [m] is a structure material.
  static bool isStructure(Material m) => structureByIndex[m.index];

  static MaterialProps of(Material m) => props[m]!;

  /// Wall class (SPEC section 3): blocks water and light.
  static bool blocksWater(Material m) => blocksWaterByIndex[m.index];

  /// Wall class: blocks light. Glass blocks water but is transparent to light.
  static bool blocksLight(Material m) => blocksLightByIndex[m.index];

  /// Pass-through to water: all furniture, rubble, debris, water, lamp.
  static bool passThroughWater(Material m) =>
      furnitureByIndex[m.index] ||
      m == Material.rubble ||
      m == Material.debris ||
      m == Material.water ||
      m == Material.lamp;

  /// Fixed footprint in cells (width x height, SPEC section 2 table).
  static const Map<Material, (int, int)> furnitureSize = {
    Material.chair: (1, 1),
    Material.plant: (1, 1),
    Material.tv: (1, 1),
    Material.fridge: (2, 2),
    Material.desk: (2, 1),
    Material.table: (2, 1),
    Material.counter: (2, 1),
    Material.bed: (2, 1),
    Material.tub: (2, 1),
    Material.sofa: (3, 1),
  };

  static bool isFurniture(Material m) => furnitureByIndex[m.index];

  static bool floats(Material m) => of(m).floats;

  /// The broken form of a material (SPEC 5 / CONTEXT.md): heavy structure
  /// becomes sinking rubble; everything else that can break (furniture,
  /// wood, glass, lamps) becomes floating debris.
  static Material breaksInto(Material m) =>
      structureByIndex[m.index] ? Material.rubble : Material.debris;

  static int clampPoolFill(int poolDepth) => min(Constants.poolFill, poolDepth);
}
