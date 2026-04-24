# Checklist CDC → MVP

| Exigence | Implémentation |
|---|---|
| Godot | Projet Godot 4.x avec scène `Main.tscn` |
| Navigateur web | Preset export Web + serveur statique Node |
| 1v1 temps réel | Serveur WebSocket autoritaire, rooms de 2 joueurs |
| Lecture locale en bas | Transformation client : le joueur rôle 1 voit le monde inversé verticalement |
| Balle commune | Simulée côté serveur et synchronisée par snapshots |
| Tirs | Inputs client → projectiles serveur |
| Tirs modifient la balle | Collision projectile/balle avec impulsion selon actif |
| Briques destructibles | Collision balle/briques + mini balle/briques adverses |
| Actifs | Sniper, Mini balle, Mini gun, Protection |
| Cooldowns | `nextShotAt` serveur + HUD client |
| Munitions | Réserves par actif, compteur HUD |
| Perte au changement | Réserve de l'actif quitté forcée à 0 |
| Power-ups comeback | Apparition sur brique cassée, propriétaire du mur comme bénéficiaire |
| Victoire | Toutes les briques d'un joueur détruites |
| Téléphone/tactile | Arène portrait + drag + bouton TIR + boutons actifs |
| Placeholders | PNG dans `assets/placeholders/` |
