# Particle Disintegrator

A hand tool mod for Farming Simulator 25 that removes unwanted fill heaps from the terrain. Point, shoot, and watch grass, chaff, straw, and any other pile cluttering your farm disappear.

## Features

- Removes **all heap types** from the terrain - grass, chaff, straw, manure, woodchips, and anything else that can be tipped to the ground, including materials added by other mods
- Visual laser beam shows exactly where material is being removed
- Sound effect provides audio feedback while active
- Works in **singleplayer and multiplayer** (including dedicated servers)
- Configurable settings (radius, range, cost) via XML

## How to Use

1. Purchase the **Particle Disintegrator** from the shop (found in Hand Tools / Misc category)
2. Equip it from your inventory
3. Aim at the unwanted heap
4. **Hold your platform's "Activate" button** to fire
5. The laser beam appears and material is removed for as long as you hold the button
6. Release to stop

## Configuration

The following settings can be adjusted in 'ParticleDisintegrator.xml' under the '<particleDisintegrator>' element:

| Setting | Default | Description |
|---------|---------|-------------|
| 'raycastDistance' | 5 | How far the tool can reach, in meters |
| 'radius' | 0.5 | Size of the removal area around the aim point, in meters |
| 'pricePerMinute' | 0 | Operating cose per minute (0 = free to use) |

## Installation

1. Download the latest release zip from the [Releases](../../releases) page
2. Place the zip file (do not extract) in your mods folder
3. Activate the mod in the mod selection screen when starting or loading a save

## Multiplayer

Fully supported. The tool works on dedicated servers and in peer-to-peer multiplayer. All players can purchase and use their own particle Disintegrator independently.

## Known Limitations

- The tool removes **all** fill materials in its radius - it does not distinguish between fill types. Be careful when valuable and unwanted heaps are very close together.
- There is no undo. Once material is removed, it's gone.

## Roadmap

These features are planned for future updates but are not yet in development:

- **Expanded disintegration targets** - support for removing tree, bushes, and other objects beyond fill heaps
- **Target type cycling** - an in-game hotkey to switch between different disintegration modes (e.g., heaps, trees, bushes) as new target types are added
- **In-game settings** - on-screen controls to adjust radius, range, and cost per minute without editing XML files

## Version History

### v1.0.0.0
- Initial release
- Core disintegration functionality using terrain density map clearing
- Laser beam visual indicator
- Sound effect on activation
- Multiplayer / dedicated server support

## Author
**ephesius**
