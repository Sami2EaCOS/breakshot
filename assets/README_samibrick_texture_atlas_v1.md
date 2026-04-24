# Sami / Brick Duel — Texture Atlas v1

Pack généré pour un jeu 1v1 Pong / casse-briques / projectiles.

- `samibrick_texture_atlas_v1.png` : atlas PNG transparent 1024×1024.
- `samibrick_texture_atlas_v1.json` : coordonnées au format JSON.
- `SamiBrickAtlas.gd` : helper Godot 4.
- `samibrick_texture_atlas_v1_preview.png` : preview avec grille et labels, à ne pas utiliser en jeu.

## Utilisation Godot rapide

Place le PNG et `SamiBrickAtlas.gd` dans `res://assets/`, puis :

```gdscript
const SamiBrickAtlas = preload("res://assets/SamiBrickAtlas.gd")
$Sprite2D.texture = SamiBrickAtlas.make_atlas_texture("ball_main_32")
```

Conseil : désactive le filtrage de texture pour un rendu plus net, ou laisse le filtrage linéaire pour conserver le glow néon.
