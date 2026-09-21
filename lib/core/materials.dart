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
  rubble, // broken heavy building material; pass-through; sinks
  debris, // broken light things (furniture, wood); pass-through; floats
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

  static MaterialProps of(Material m) => props[m]!;

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

  /// Wall class (SPEC section 3): blocks water and light.
  static bool blocksWater(Material m) =>
      structure.contains(m) ||
      m == Material.ground ||
      m == Material.wood ||
      m == Material.glass;

  /// Wall class: blocks light. Glass blocks water but is transparent to light.
  static bool blocksLight(Material m) =>
      structure.contains(m) || m == Material.ground || m == Material.wood;

  /// Pass-through to water: all furniture, rubble, debris, water, lamp.
  static bool passThroughWater(Material m) =>
      furnitureTypes.contains(m) ||
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

  static bool isFurniture(Material m) => furnitureTypes.contains(m);

  static bool floats(Material m) => of(m).floats;

  /// The broken form of a material (SPEC 5 / CONTEXT.md): heavy structure
  /// becomes sinking rubble; everything else that can break (furniture,
  /// wood, glass, lamps) becomes floating debris.
  static Material breaksInto(Material m) =>
      structure.contains(m) ? Material.rubble : Material.debris;

  static int clampPoolFill(int poolDepth) => min(Constants.poolFill, poolDepth);
}
