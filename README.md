# Breakshot

Prototype Godot Web 1v1 : duel vertical entre Pong, casse-briques et tirs de projectiles.

## Contenu

- `project.godot` : projet Godot 4.6.x.
- `scenes/Main.tscn` : scene principale.
- `scripts/Main.gd` : client Godot, rendu, inputs tactile/clavier, WebSocket.
- `server/index.js` : serveur Node.js autoritaire + serveur statique pour l'export Web.
- `web_export/` : build Web generee par Godot.
- `Dockerfile` : image de production qui sert `web_export/` via le serveur Node.
- `.github/workflows/deploy.yml` : CI/CD GitHub Actions.

## Lancer en local

```bash
cd server
npm ci
PORT=8792 STATIC_ROOT=../web_export npm start
```

Puis ouvrir :

```text
http://127.0.0.1:8792
```

Le client Web construit automatiquement son URL WebSocket depuis l'origine de la page.

## Export Web

```bash
godot --headless --path . --export-release Web web_export/index.html
```

## Docker

Build :

```bash
docker build -t breakshot:local .
```

Run local :

```bash
docker run --rm -p 127.0.0.1:8792:8787 breakshot:local
```

Le serveur ecoute dans le conteneur sur `PORT=8787` et sert les fichiers statiques depuis `/app/web_export`.

## Deploiement GitHub Actions

La CI se declenche a chaque push :

- push sur `main` : deploiement production sur le port `8787`, conteneur `breakshot-prod`;
- push sur une autre branche : deploiement dev sur le port `8788`, conteneur `breakshot-dev`.

Secrets GitHub requis :

| Secret | Exemple | Role |
|---|---|---|
| `SSH_HOST` | `example.com` | hote SSH du serveur |
| `SSH_USER` | `sami` | utilisateur SSH |
| `SSH_PRIVATE_KEY` | cle privee OpenSSH | cle de deploiement |

Secrets optionnels :

| Secret | Defaut | Role |
|---|---:|---|
| `SSH_PORT` | `22` | port SSH |
| `DEPLOY_BASE_DIR` | `$HOME/godot` | dossier parent distant |
| `PROD_PORT` | `8787` | port local prod pour le reverse proxy |
| `DEV_PORT` | `8788` | port local dev pour le reverse proxy |

Le deploiement copie un tarball sur le serveur, build l'image Docker sur la machine distante, puis remplace le conteneur cible. Les ports sont exposes directement sur l'hote : prod sur `8787`, dev sur `8788`.

## Gameplay actuel

- Sniper comme tir principal.
- Munitions rechargees balle par balle.
- Maintien du bouton tir avec cadence, clics repetes instantanes si une balle est disponible.
- Power-ups caches dans les briques puis reveles a la destruction.
- Actions stockables : `rapid`, `shield`, `split`.
- `rapid` accelere temporairement la recharge.
- `shield` protege temporairement les briques.
- `split` transforme temporairement les tirs sniper en triple tir.

## Production

Le serveur est autoritaire sur les rooms, collisions, balles, projectiles, briques, power-ups et victoire. Pour HTTPS/WSS, placer le conteneur derriere un reverse proxy.
