# 30 Floors & a Pool

The product context for a 2D side-view interactive web page: a seeded tower built beside a pool of water, where the structure fails cell by cell under water, pressure, and user attack, and where light is physically traced.

## Language

### World

**Cell**:
A single square in the world grid; holds one material or air.
_Avoid_: tile, block, pixel

**Material**:
What fills a cell: air, water, a structure material, ground, glass, wood, rubble, debris, or a piece of furniture.
_Avoid_: substance

**Structure material**:
The material of a generated tower's walls and slabs, in four tiers of increasing strength — concrete, reinforced concrete, steel, titanium; default reinforced concrete.
_Avoid_: building material

**Ground**:
The very hard earth below the world; the foundation a tower stands on. Not a structure material and not buildable.
_Avoid_: bedrock, rock

**Pool**:
The water body the tower sits beside; present in every world.

**Water body**:
A connected mass of water; every cell of a body shares one pressure.
_Avoid_: lake, puddle

**Pressure (head)**:
The force a water body exerts, measured from the body's own surface and carried sideways through the connected body; erodes an adjacent material only once the head exceeds that material's tolerance.
_Avoid_: depth, force

### Tower

**Seed**:
The text or number that deterministically determines the whole world — stage layout and tower; shareable by name and passable in the URL.
_Avoid_: world id, random

**Floor**:
One level of a generated tower, divided into 1–3 rooms.

**Room**:
A portion of a floor; has 2–5 furniture items and 1–3 lamps.

**Bay**:
One unit of tower width (1–5).

**Furniture**:
A loose indoor object, one of ten types: sofa, bed, desk, chair, table, counter, fridge, tub, plant, TV. Transparent to water and to light; each type has a fixed footprint and a buoyancy.
_Avoid_: item, prop, decoration

**Lamp**:
An object that emits light, in three kinds: floor lamp, ceiling lamp (fixed to the ceiling until the slab above it breaks, then falls as a loose lamp that stays lit until it itself breaks), table lamp (sits on a table, or on the room floor if the room has no table).
_Avoid_: light (light is the phenomenon, not the object)

### Physics

**Wall**:
A material that blocks water and light: the four structure materials, ground, and wood. Glass blocks water but is transparent to light.
_Avoid_: solid, barrier

**Pass-through**:
Material water moves through unimpeded: all furniture, rubble, and debris.
_Avoid_: permeable

**Rubble**:
Broken heavy building material; water passes through it unimpeded; sinks.

**Debris**:
Broken light things (furniture, wood); water passes through it unimpeded; floats.
### Light

**Light**:
The traced phenomenon of the traced view; travels through air, water, and glass only; bends and tints in water and glass; never crosses solid walls.

**Sun**:
The day-sky light source; drifts on a ~7-minute arc and loops; freezes when the world is paused.
_Avoid_: daylight

**Glow**:
A decorative bright band along the water surface, with slow brightness waves and bright crests; toggleable; never affects physics.
_Avoid_: lighting

**Traced view**:
The default lighting mode, in which light is genuinely transported through air, water, and glass with no ambient; falls back to the plain view on machines without the required graphics support.
_Avoid_: ray-traced view, physically-traced view (both refer to this same mode; the control is labelled "Path Trace")

### Checks

**Standing check**:
A named scenario asserting the physical correctness of the world: lamp light blocked by solid walls (including one-cell partitions), lamp light passing through furniture, a roofed pool's surface static across the sun's arc, an open pool glinting brightest under the sun.
_Avoid_: test (too general)
