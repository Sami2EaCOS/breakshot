# Client Script Layout

`Main.gd` is still the main client controller, but keep edits within the existing section order:

1. constants and runtime state
2. setup, connection, room flow
3. input handling
4. audio and user feedback
5. weapon/action requests
6. snapshot interpolation
7. drawing
8. layout helpers

For new isolated behavior, add scripts under `scripts/features/<feature>/` and keep `Main.gd` as orchestration glue.
