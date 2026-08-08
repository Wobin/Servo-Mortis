# Servo Mortis

A Darktide mod. When you die, spectating becomes a mouse controlled third person orbit of whoever you
are watching, and a servo skull marks who each dead teammate is watching.

## Features

- Third person camera while spectating, with free mouse look
- Bots are valid spectate targets, and you can cycle either way
- Right click (or B / Circle on a controller) steps back to the previous target
- A servo skull orbits the player each dead teammate is watching, nameplated in their slot colour
- The skull follows behind a moving target, avoids walls, and rides higher on an ogryn
- Optional test mode that simulates two watchers so the skulls can be seen solo

Watcher skulls are shared over [Vox Manifold](https://www.nexusmods.com/warhammer40kdarktide/mods/1085)
presence. Without it the mod still works, you just will not see other players' skulls.

## Requirements

- Darktide Mod Framework
- Vox Manifold (optional, needed only for skulls shared between players)

## Development

The mod has an offline test suite that runs without the game:

```
luajit spec/run_all.lua
```

## Author

Wobin
