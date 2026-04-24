# Brick Duel One-Shot — MVP Godot Web 1v1

Prototype jouable du concept : duel 1v1 type Pong / casse-briques / tirs de projectiles.

## Contenu du zip

- `project.godot` : projet Godot 4.x.
- `scenes/Main.tscn` : scène principale.
- `scripts/Main.gd` : client Godot, rendu, inputs clavier/tactile, WebSocket.
- `assets/placeholders/` : placeholders PNG remplaçables.
- `server/index.js` : serveur Node.js WebSocket autoritaire + serveur statique pour l'export web.
- `export_presets.cfg` : preset Web pointant vers `web_export/index.html`.

## Gameplay implémenté

- 1v1 temps réel via WebSocket.
- Chaque joueur se voit toujours en bas ; l'adversaire est affiché en haut.
- Arène verticale mobile-first en 720 × 1280.
- Balle commune synchronisée par le serveur.
- Canons/paddles contrôlables horizontalement.
- Tirs qui modifient la trajectoire de la balle.
- Collisions balle/briques + destruction.
- Mini balle capable de casser les briques adverses.
- Protection des briques pendant 1 seconde.
- Cooldowns, munitions et perte des munitions restantes quand on quitte un actif.
- Power-ups générés lors de la destruction d'une brique, destinés au propriétaire du mur cassé.
- Victoire : un joueur perd quand toutes ses briques sont détruites.

## Lancer en local depuis Godot

Prérequis : Node.js + Godot 4.x.

```bash
cd server
npm install
npm start
```

Puis ouvrez le projet dans Godot et lancez deux instances du jeu, ou lancez une instance Godot + un export web.

Par défaut, le client se connecte à :

```text
ws://localhost:8787
```

## Export web

1. Ouvrir le projet dans Godot.
2. Installer les templates d'export Web si nécessaire.
3. Aller dans **Project > Export**.
4. Sélectionner le preset **Web**.
5. Exporter vers :

```text
web_export/index.html
```

6. Lancer le serveur :

```bash
cd server
npm start
```

7. Ouvrir :

```text
http://localhost:8787
```

Le client web construit automatiquement son URL WebSocket à partir de l'origine de la page : `ws://host:port` ou `wss://host` si la page est servie en HTTPS.

## Contrôles

### Mobile / tactile

- Glisser dans l'arène : déplacer le canon horizontalement.
- Bouton **TIR** : tirer avec l'actif équipé.
- Boutons d'actifs en bas : changer d'actif.

### Clavier

- `A/D` ou `←/→` : déplacement.
- `Espace` ou `Entrée` : tir.
- `1` : Sniper.
- `2` : Mini balle.
- `3` : Mini gun.
- `4` : Protection.
- `R` : demander une revanche / reset de manche.

## Actifs

| Actif | Rôle | Munitions | Cooldown serveur |
|---|---|---:|---:|
| Sniper | Tir précis, impact fort sur la balle | 6 | 0,72 s |
| Mini balle | Projectile qui impacte la balle et casse les briques adverses | 5 | 0,86 s |
| Mini gun | Rafale rapide, impacts faibles mais fréquents | 24 | 0,13 s |
| Protection | Rend les briques du joueur invincibles pendant 1 seconde | 2 | 6 s |

Règle appliquée : quand un joueur change d'actif, les munitions restantes de l'actif quitté sont perdues. Les autres actifs gardent leur réserve jusqu'à ce qu'ils soient équipés ou abandonnés.

## Power-ups

Les power-ups apparaissent avec une chance de 36 % quand une brique est détruite. Ils se déplacent vers le joueur propriétaire du mur cassé.

Types actuellement implémentés :

- `ammo` : recharge l'actif actuellement équipé.
- `shield` : ajoute 1 seconde de protection.
- `rapid` : réduit temporairement les cooldowns de tir pendant 5 secondes.

## Remplacer les assets

Les placeholders sont dans :

```text
assets/placeholders/
```

Pour remplacer vite : gardez les mêmes noms de fichiers PNG et rouvrez le projet dans Godot. Le code redimensionne les textures dans les rectangles de gameplay.

## Notes de production

Ce MVP est volontairement simple : le serveur est autoritaire sur les collisions, la balle, les projectiles, les briques, les power-ups et la victoire. Il n'inclut pas encore de système d'authentification, de lobby avancé, de matchmaking classé, de rollback/prediction réseau, ni d'anti-triche avancé.

Pour une mise en ligne HTTPS, placez le serveur derrière un reverse proxy et utilisez `wss://`. Le client bascule automatiquement vers `wss://` si la page Godot est servie en HTTPS.
