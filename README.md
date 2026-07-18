# Kong Island

A cinematic open-world action-adventure inspired by King Kong, built with Godot 4.6 for the mobile web.

Pick **STORY** (a guided expedition in stages: sea -> beach -> the Great Wall -> the gorge bridge -> the insect pits -> jungle & swamp -> the volcano lair -> King Kong) or **FREE ROAM** (the whole island open: drive the expedition jeep, sail the steamship and rowboats, fly the seaplane, hunt or flee every creature).

- A large jungle island ringed by ocean: beaches, a half-sunk shipwreck, rivers, lakes, a misty swamp, deep pits, a tar pit, a gorge crossed by a rope-and-log bridge, ancient temple ruins, two native villages, jagged mountains and a smoking volcano with Kong's lair.
- A full day-night cycle and a living weather cycle (clear -> clouds -> tropical storm with lightning -> calm), fog, mist, ash and ember light near the crater.
- Meshy-generated cast: the hero, ship captain, film director, the actress Ann, sailors, two distinct tribes, King Kong and signature creatures; the library supplies rigged dinosaurs (T-rex, raptors, brontosaurus, triceratops, stegosaurus), bats, snakes, spiders and fish.
- Equippable arsenal: machete, tribal spear, bone club, revolver, hunting rifle, tommy gun, harpoon gun, gas grenades.

## Development
- `godot --headless --path . --import` then `--export-release "Web" out/index.html` (nothreads web template).
- World data is data-driven: `world.json` (chunk-streamed island) + `quests.json` (story chain).
