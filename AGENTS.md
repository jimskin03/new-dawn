# Playing New Dawn

When asked to play or evaluate this game, read `docs/AGENT_PLAY.md` first.

- Run the visible Godot GUI. Use `tools/agent.ps1 launch` to start it or attach to its existing live bridge. Do not substitute a headless simulation for actual agent play.
- Observe `tools/agent.ps1 status -Full` and use its `available_actions`. The CLI and GUI share the same live simulation. `state.json` is a live observation, not a save file.
- Use CLI gameplay commands, or GUI controls, to play. Do not edit saves, game resources, simulation code, or live-state files to obtain a win.
- Pause before planning or taking deterministic `step` actions. A step is limited to 30 game seconds and uses the normal simulation rules. Reobserve after actions and before approaching raids.
- On a command timeout, its outcome is unknown. Retry the identical command with the reported `-RequestId`; do not send a fresh id that could spend resources twice.
- Treat `running: false`, a stale heartbeat, or a changed session id as a lost connection. Reconnect before acting.
- `new_game -ConfirmReset` replaces the current save. Preserve an existing player run unless the user asks for a reset. For testing, use a unique `-BridgeDir` with `launch -Isolated`.
- End actual play by pausing and saving unless the user asks to close the window. Report outcome, day, survivors, integrity, and relevant limitations from fresh live state.

For code changes, run the existing simulation/UI/save tests and the relevant bridge tests. Headless mode is suitable for software tests, while the end-to-end agent play test must use the GUI. No external service or model credentials are needed.
