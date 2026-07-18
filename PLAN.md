# Goal
Resume the interrupted Kong Island build: restore the content-complete world (world.json + quests.json + 34 already-generated Meshy GLBs from the prior deploy — NO regeneration), re-apply the QA fixes the prior session engineered but lost, re-export the Godot 4.6.3 nothreads web build, deploy the preview, and ship the full project on feat/kong-island-game.

# Files to touch
- `world.json`, `quests.json` — replace with the content-complete versions from the prior deploy; bridge-cell prop colliders off + explicit span; campfire prop swap (`Hilly_Prop_Camp_Campfire.glb` + positional `campfire` sound).
- `models/meshy/*.glb` (+ `.gdignore`) — the 34 downloaded Meshy assets, committed for persistence, excluded from the .pck (they stream from R2 at runtime).
- `enemy.gd` — P0-1: skeleton-aware height measurement (main.gd `_char_height` idiom) so a Meshy rig's 0.01-scale Armature can't under-measure and over-scale Kong/lava_creature ~550x.
- `chunk_manager.gd` — P0-2: walkable pitched deck collider + rail colliders in `_place_bridge`; ladder USE anchor clamps to the water surface when the foot is submerged.
- `interaction.gd` — one-way gate lock (keyless open from the inland side so trapped players can escape); chest weapons force-equip.
- `quest.gd` — `current_objective()` prefers the ACTIVE quest over the first (often COMPLETE) one.
- `rpg_systems.gd` — equip gate compares DPS (damage x rate), not raw damage; add `cycle_weapon()`.
- `main.gd` — HUD WEAPON cycle button; auto-draw on equip change; touch input hit-tests HUD button rects before claiming joystick/look; right button column never crosses the joystick half-line in portrait.

# Verification approach
Targeted headless spot-checks only (no full adversarial QA — memory discipline, one Godot process at a time): static pre-import grep gates; per-fix in-engine asserts (kong height ~11m at eye level, bridge deck walkable end-to-end, gate opens keyless from inland side, ladder anchor at water level, active-quest objective label, weapon cycle force-equips + draws, touch on HUD button doesn't rotate camera); smoke-verify the exported web build boots with frames.

# Out of scope
Regenerating any Meshy asset; fresh full QA/game-feel passes; new gameplay features; multiplayer.
