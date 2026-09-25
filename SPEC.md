# 30 Floors & a Pool — Product Specification

A 2D side-view (cutaway) interactive desktop program: a multi-storey tower built from a grid of square cells, sitting beside a pool of water. Water floods the structure; the structure fails cell by cell under water, pressure, and user attack; loose items float or sink. The scene is lit by two modes: a plain day-sky view (the default), and the traced view, where light is genuinely transported through air, water, and glass.

Terminology follows `CONTEXT.md`; decisions of record live in `docs/adr/`.

## 1. World

- A grid of square cells; each cell holds one material or air.
- Water and loose material fall cell by cell (falling-sand style).
- **Grid dimensions are fixed constants**, independent of seed, floors, and width.
- **The whole world is seeded** (ADR 0001): seed + settings deterministically determine stage layout (tower geometry, room splits, furniture and lamp draws, pool size and position, ground surface level) and the tower. Same seed + settings → the same world, exactly, at t=0.
- **Ground**: the very hard earth below the world; the foundation a tower stands on. Not a structure material, not buildable.
- **Pool**: the water body the tower sits beside; present in every world. Seed varies the pool's size and its position relative to the tower. **Initial pool fill is a fixed 8 cells deep**, clamped to the pool's height.
- **Camera**: fits the whole world (tower + pool + margin) at load and after Reset / New seed. Left-drag with the selected tool; right-drag or space+drag pans; mouse wheel zooms around the cursor.

## 2. Tower generation

- Generated from a **seed** (any text or number) plus three settings: **floors** (1–50, default 30), **width in bays** (1–10, default 6), **structure material** (four tiers of increasing strength — concrete, reinforced concrete, steel, titanium; default reinforced concrete).
- **Rooms**: every floor is divided into 1–3 rooms (count seeded per floor). Rooms are contiguous segments of the floor's bays; the partition among valid splits is seeded. Partition walls are 1 cell thick, in the structure material.
- Each room gets a random **non-overlapping mix** of **2–5 furniture items** and **1–3 lamps**. Non-overlapping means: at most one of each type per room, and no two items share a cell.
- **Furniture** (ten types, each with a fixed footprint in cells and a fixed buoyancy):

  | Type | Footprint | Buoyancy |
  |---|---|---|
  | chair | 1×1 | floats |
  | plant | 1×1 | floats |
  | TV | 1×1 | sinks |
  | fridge | 1×2 | sinks |
  | desk | 2×1 | floats |
  | table | 2×1 | floats |
  | counter | 2×1 | floats |
  | bed | 2×1 | sinks |
  | tub | 2×1 | sinks |
  | sofa | 3×1 | floats |

  Placement never exceeds room bounds; if an item does not fit, that draw is redrawn once, then skipped.
- **Lamps** (three kinds): a floor lamp on the room floor; a ceiling lamp fixed to the ceiling until the slab above it breaks — it then falls as a loose lamp that stays lit until it itself breaks; a table lamp sitting on a table if the room drew one, otherwise on the room floor (fallback to a floor lamp).
- A **"New seed"** button (new seed, new world) and a **"Reset"** button (rebuilds the *current* seed). Reset and New seed clear all user modifications and restore the exact t=0 state: pool at its initial fill, rain at default (0), sun at cycle start, speed 1×, camera refit.
- The seed is **shareable by name** and **passable as a startup argument**.

## 3. Materials

| Class | Materials | Water | Light |
|---|---|---|---|
| Wall | concrete, reinforced concrete, steel, titanium, ground, wood | blocked | blocked |
| Glass | glass | blocked | transparent |
| Pass-through | all ten furniture types, rubble, debris | unimpeded | transparent (furniture) |

- **Structure materials** have four tiers of increasing strength: concrete < reinforced concrete < steel < titanium. Ground is very hard.
- **Glass** is very weak and floats a little.
- **Furniture is transparent to light** (a lamp lights the wall beyond a sofa) and to water (water passes through all furniture as if it were not there). There is no seep mechanism: no material is permeable; water either blocks, or passes unimpeded.
- **Rubble**: broken heavy building material; sinks.
- **Debris**: broken light things (furniture, wood); floats.
- The default structure material (reinforced concrete) is **not among the Build tools**.

## 4. Water behaviour

- **Rain** (slider 0–40, default 0): water cells spawned per second on the top row, distributed uniformly across the full world width (40 ≈ heavy). Spawned water then falls and flows normally.
- Water falls and flows.
- **Pressure**: connected water shares one pressure per water body — the head from the body's own surface, carried sideways (a thin sheet running off a wall pushes with the deep pool's full depth). Pressure erodes adjacent wall material only once the head exceeds that material's tolerance (tanked concrete shrugs a shallow pool; deep water crushes slabs and washes rubble away).
- **Jets**: deep water under a roof or in a body whose head is ≥ 8 cells jets upward out of any open crack; spurt height scales with the head.
- Deep water under a roof can pour off and **cascade floor by floor**.
- **Surface motion**: a calm pool's surface is a flat line. Water that lands — a pour, a falling column, rain, a jet, a broken wall dumping in — stirs a visible dip where it touches down, and the ripples spread sideways and decay back to flat in a couple of seconds. The surface is flat exactly where the water is at rest; there is no ambient swell.

## 5. Structural failure and buoyancy

- A section that loses its load path to the foundation (severed by a support gap of **≥ 3 cells**; gaps of ≤ 2 cells still bridge) **slumps into rubble over ~2 s**, rather than vanishing.
- Heavy material that breaks becomes **sinking rubble**; light things (furniture, wood) become **floating debris**.
- **Furniture outlasts the building** around it: a flooded sofa pops to the surface, a fridge drops, a TV sinks (per the table in §2).

## 6. Sun and glow

- **Sun**: a warm disc in the day sky; a **full cycle of ~7 minutes** — rise, arc up and down across the sky (passing behind the tower), set, then immediately loops. Pausing the world freezes the sun. The scene never goes dark.
- **Glow** (decorative, separate from lighting, toggleable, on by default): a soft brighter band along the water surface with a slow wave of brightness and occasional bright crests. Purely visual — it never affects physics.

## 7. Traced view (default off, toggleable)

- The scene is lit **only by traced light** — no ambient, no overlay. The sun and every lamp are real light sources.
- Light bounces off surfaces; **water and glass bend and tint it** the deeper it goes (red dies before green); walls cast soft shadows.
- A lamp in a sealed room lights its room and **only its room** (never crosses solid walls, including one-cell partitions); **light passes through furniture**.
- A lamp under water glows warm amber and warms the water around it.
- Light beams are visible inside water as **forward-scattering shafts**, brightest near the light's own angle.
- The water surface **glitters only where the sun actually reaches** (a roofed pool's surface stays calm as the sun crosses the sky), with the glint gathered in a band toward the sun; an open pool glitters brightest under the sun.
- Sunlight concentrates into a **caustic drifting across the pool floor**.
- The water surface renders as a line that is flat where the water is at rest and dips and ripples where water is landing; water darkens quickly with depth, so a deep pool reads dark blue-green under a bright shimmering waterline.
- The image **settles to a clean, steady picture in about a second** instead of flickering; it follows slow changes (the drifting sun) with a short lag; when the world changes (water moves, a wall breaks) the light re-converges **only in the places that changed**.
- **Fallback contract**: on a machine without the required graphics support, the scene quietly falls back to the plain 2D view and the toggle cannot switch on; if the graphics device gives up mid-run, it falls back and the toggle can switch back on. (Which graphics API is "required" is an implementation decision, not a spec one.)

## 8. Tools (mouse, or keys 1–8)

| Key | Tool |
|---|---|
| 1 | Hammer — damages material under a brush |
| 2 | Bomb — a radius blast with a decaying damage falloff, orange spark burst, screen flash |
| 3 | Water — paints water |
| 4 | Erase |
| 5 | Build concrete |
| 6 | Build steel |
| 7 | Build glass |
| 8 | Build wood |

- **Brush size** adjustable (1–15 cells, default 5). **Initial tool: Water** (key 3).
- There is **no flood tool**: the old "Flood" button and the single-key tower-blast were removed and do not return; there is no user-facing way to flood the world (see Standing checks — the flood scenario is *not* part of the contract).

## 9. Controls

- **Pause** (freezes the world and the sun).
- **Speed cycle**: 0.5× → 1× → 2×; scales physics, sun, and glow together (pause = scale 0).
- **Reset** (rebuilds current seed, exact t=0 state) · **New seed** · **Glow** · **Path Trace** (traced view on/off).
- **Sliders**: brush, rain, floors, width, structure.

## 10. Readouts

- **HUD**: water cell count, building damage % (damaged structural cells ÷ total original structural cells), **destroyed cells** (cells destroyed by any cause), FPS.
- **Hover readout** on any cell under the cursor: its material, remaining strength (with a colour-coded bar), water pressure, and, in traced mode, a swatch of the settled light's colour and brightness as a percentage.
- (There is no minimap.)

## 11. Standing checks

Named scenarios asserting the world's physical correctness:

1. **Lamp light must not cross a solid wall** — including one-cell partitions.
2. **Lamp light must pass through furniture.**
3. **A roofed pool's surface must not move** as the sun crosses the sky.
4. **An open pool must glitter brightest under the sun.**

(The former flood-scenario check was removed with the flood tool and is not part of the contract.)
