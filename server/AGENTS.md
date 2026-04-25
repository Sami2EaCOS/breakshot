# Server Layout

- `index.js`: application entry point, WebSocket protocol, room lifecycle, simulation, snapshots, static HTTP serving.
- `src/rules.js`: gameplay constants, default rules, and sanitized accessors shared by the simulation.

When adding server logic, prefer new modules in `src/` for features that can be isolated. Keep protocol message handling in `index.js` unless the whole protocol surface is moved.
