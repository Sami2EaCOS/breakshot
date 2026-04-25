# Asset Ownership

Use these folders by runtime purpose:

- `game/`: sprites used by game objects through `samibrick_texture_atlas_v1.png`.
- `ui/`: UI atlas and button art.
- `backgrounds/`: full-screen arena backgrounds, normally `720x1280`.
- `effects/`: standalone visual effects loaded by `scripts/Main.gd`.
- `legacy/`: old placeholders or references; do not reference these from runtime code.

When replacing a runtime asset, preserve its expected dimensions unless the drawing code is changed in the same patch.
