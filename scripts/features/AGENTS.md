# Feature Scripts

Keep feature scripts narrow and reusable. `Main.gd` owns scene orchestration and gameplay input, while files here should contain isolated responsibilities:

- `audio/`: local sound generation and playback helpers.
- `room/`: room code parsing and URL/clipboard helpers.
- `state/`: snapshot interpolation and state presentation helpers.
- `ui/`: editor-owned UI controls and HUD glue.

Avoid moving behavior here if it requires broad access to `Main.gd` internals; extract pure helpers first.
