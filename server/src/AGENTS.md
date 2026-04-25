# Server Feature Modules

Use this folder for isolated server features.

- `rules.js`: arena constants, weapon/power-up defaults, rule sanitation and rule lookups.

Keep mutable room state and WebSocket protocol orchestration in `../index.js` unless a whole feature can be moved without circular dependencies.
