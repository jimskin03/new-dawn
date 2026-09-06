# Agent play guide — New Dawn

The agent must play the **visible Godot GUI**. A local file-based RPC bridge provides the equivalent semantic controls and live JSON observations; it does not run a second simulation. Human clicks and agent commands affect the same game instance.

## Quick start

Run from the project directory in PowerShell 5.1 or later:

```powershell
.\tools\agent.ps1 launch
.\tools\agent.ps1 status -Full
.\tools\agent.ps1 actions
```

`launch` opens `build/Windows/NewDawn.exe` visibly and pauses the new instance. If an instance already owns the selected bridge directory, it attaches without changing that instance's speed or state. Normal double-click launches also expose the bridge. The green **AGENT CONNECTED** label means the bridge is available, including when no client is currently issuing commands.

The default bridge is `build/Windows/.agent/`. Its `state.json` is refreshed about four times per second, even while paused or displaying a modal. Reads require a heartbeat no older than five seconds. There is no network listener, HTTP dependency, Python dependency, or external AI service.

For an independent experiment, use a unique directory on **every** command:

```powershell
$bridge = Join-Path $PWD 'build\my-agent-run'
.\tools\agent.ps1 launch -BridgeDir $bridge -Isolated
.\tools\agent.ps1 status -BridgeDir $bridge -Full
```

`-Isolated` puts this instance's save in that directory instead of the normal player save. It only affects launching a new instance, not attaching. Do not run two clients with competing plans against the same session. A second game process refuses a bridge with a fresh owner heartbeat. If an old process crashes, its stale bridge can be reclaimed after five seconds; use a different directory if the old GUI is still open.

Do not use `--headless` for actual play. Tests may use it for protocol validation; `ui.visible` will explicitly be false and the screenshot command will be rejected.

## Read the state before acting

`status` prints compact JSON. `status -Full` includes:

| Field | Meaning |
|---|---|
| `protocol`, `session_id`, `pid` | Protocol version and identity of the running game |
| `sequence`, `updated_at_ms`, `running` | Snapshot counter, UTC Unix milliseconds, and process lifecycle |
| `simulation` | Resources, ten rooms, survivors, integrity, morale, game seconds, raid timer, expedition, research, unlocks, journal, outcome |
| `rates` | Net resource change per game second, after consumption |
| `idle_workers`, `capacity`, `scientists`, `defense` | Current derived staffing and shelter values |
| `objective` | The next step toward the rescue ending |
| `next_raid` | Time remaining, threat, and damage projected with current defenses |
| `depletion_seconds` | Estimated time until each stock reaches zero at the current rate; null when not declining |
| `available_actions` | Currently legal gameplay actions with their exact arguments and costs |
| `ui` | Renderer visibility, selected room, tab, floor depth, modal, speed, whether time is advancing, and pause reasons |
| `last_action` | Most recently processed request and its result |

`sequence` advances when a snapshot is published, even if paused. It is a freshness counter, not a simulation revision. Resources and timers can change while the agent reasons at 1×, 2×, or 4×. Pause when exact planning matters. `available_actions` evaluates the same simulation methods as the GUI on disposable copies, without mutating the live state; legality is checked again at execution time.

Room IDs are **zero-based**, 0–9. Each also exposes a one-based `chamber` and `floor`. At a fresh start:

| ID | GUI chamber | Room |
|---|---|---|
| 0 | 01 | Command Center |
| 1 | 02 | Power Generator |
| 2 | 03 | Water Treatment |
| 3 | 04 | Hydroponics |
| 4 | 05 | Sleeping Quarters |
| 5 | 06 | First empty chamber |
| 6–9 | 07–10 | Deeper empty chambers |

## Control the live game

Every action returns JSON with `ok`, `code`, `error`, `request`, and the resulting `state`. Check `ok` rather than assuming success. The CLI returns a nonzero exit code for rejection or connection errors. Use `-AsObject` when composing calls in PowerShell.

```powershell
.\tools\agent.ps1 pause
.\tools\agent.ps1 dismiss                  # close help/menu/end overlay
.\tools\agent.ps1 build -Room 5 -Kind lab
.\tools\agent.ps1 step -Seconds 15         # game remains paused afterward
.\tools\agent.ps1 assign -Room 5 -Delta 1
.\tools\agent.ps1 research -Key efficiency
.\tools\agent.ps1 step -Seconds 28
.\tools\agent.ps1 status -Full
.\tools\agent.ps1 screenshot               # returns an absolute PNG path
```

Gameplay commands:

| Command | Arguments |
|---|---|
| `build` | `-Room 0..9 -Kind power/water/food/dorm/lab/workshop/security/medbay` |
| `assign` | `-Room 0..9 -Delta 1` or `-Delta -1` |
| `upgrade` | `-Room 0..9` |
| `expedition` | `-Route depot/reservoir/outpost` |
| `research` | `-Key efficiency/defense/relay` |
| `fortify` | none; 30 energy for +45 defense on the next raid |
| `repair` | none; 35 scrap for +25 integrity, capped at 100 |

Control and observation commands:

| Command | Behavior |
|---|---|
| `status [-Full]` | Read the latest live snapshot |
| `actions` | Read currently legal gameplay actions |
| `watch -Count 10` | Bounded series of observations at one-second intervals |
| `state` | Request an immediate authoritative state response through RPC |
| `pause` / `resume` | Stop time / dismiss modal and run at 1× |
| `speed -Rate 0/1/2/4` | Set speed; an open modal still pauses time |
| `step -Seconds n` | Advance normal rules by `0 < n <= 30` game seconds; requires speed 0, no modal, and an unfinished run |
| `select -Room n` | Select a room and reveal its floor |
| `tab -Name Shelter/Build/People/Research/Map` | Select a GUI tab |
| `depth -Depth 0/1/2` | Change the first of three visible underground floors |
| `dismiss` | Close the current overlay |
| `screenshot` | Capture the actual rendered Godot viewport into `.agent/screenshots/<id>.png` |
| `save` / `load` | Save / load the current instance; loading pauses it |
| `new_game -ConfirmReset` | Replace this instance's run and save with a fresh paused shelter |
| `shutdown` | Save successfully, then close the game |

Semantic commands do not require pixel coordinates or opening the right tab. Successful build/staff/upgrade commands select the affected room; research and expedition commands select their corresponding tabs. They obey the ordinary resource costs, workers, prerequisites, upgrade caps, and ending rules. There are no commands for setting stocks, unlocking research, granting survivors, or overriding outcomes.

`step` is an explicit deterministic control in addition to the real-time GUI speed buttons. It advances the same simulation, including consumption, raids, construction, and endings. It cannot exceed 30 seconds in one request. Do not blindly step past an approaching raid.

## A workable survival plan

Win by restoring the long-range relay and reaching **day 7** with integrity and morale above zero. Each day lasts 90 game seconds; day 7 begins at 540 seconds.

1. Observe the run. If it is already in progress, adapt to its resources and staffing instead of resetting it.
2. On a fresh run, dispatch the two idle survivors to the depot, then build the lab in room 5. Keep the initial workers in command, power, water, and food.
3. Step 30 seconds, inspect, then step 3. The expedition and lab should both be ready. Assign one survivor to the lab.
4. Research `efficiency` (90 scrap, 28 scientist-seconds). When complete, research `relay` (160 scrap, 45 scientist-seconds). Recheck funds and power first.
5. During the remaining days, keep net food/water/energy sustainable. Compare `next_raid.projected_damage` with integrity. Fortify before a raid and repair when integrity falls below about 75.
6. While waiting, take steps of 10–20 seconds, shortening them near raids. Inspect every result. The next raid is at 115 seconds, then every 110 seconds; threats escalate.
7. Stop when `simulation.outcome` is `victory` or `defeat`. Do not infer victory only from a completed relay. Capture a screenshot and save.

The initial six survivors need food and water. Missing either reduces morale and integrity. A lab needs at least one scientist and positive energy to progress. Beds add capacity but need no workers. Medical bays heal while staffed and powered. Security workers increase defense. An outpost expedition recruits a survivor only when a bed is available.

## File RPC for any agent or language

Clients may implement the protocol directly without PowerShell:

1. Read `<bridge>/state.json`. Verify `protocol == "new-dawn-agent/1"`, `running == true`, and a recent heartbeat. Record `session_id`.
2. Generate a unique id consisting of 1–80 ASCII letters, digits, `_`, or `-`.
3. Write a complete UTF-8 JSON file to a temporary name, then atomically rename it to `<bridge>/requests/<id>.json`:

```json
{
  "id": "agent_build_001",
  "session_id": "COPY_FROM_THE_CURRENT_LIVE_STATE",
  "action": "build",
  "args": {"room": 5, "kind": "lab"}
}
```

4. Wait for `<bridge>/responses/<id>.json`. The server polls at roughly 10 Hz. It processes commands serially on Godot's main thread, with no arbitrary code execution or filesystem path arguments.
5. Read the response's `ok` and resulting `state`. Reobserve before the next decision. The optional `expected_sequence` field rejects a command if the snapshot counter has already changed; this strict check is usually unnecessary with pause-and-act play.

Responses retain the original request and session. The live process remembers request IDs and never executes the same ID twice. If a client times out, **retry the identical action and arguments with the same ID**. The CLI supports `-RequestId`. Reusing that ID for another action is a client error, not a new command. Responses from another process session must not be reused.

There is no exactly-once guarantee across a process crash between applying an action and writing its result/save. After a crash, reconnect to the new session, inspect the loaded state, and decide what still needs doing; do not replay an old-session command blindly. A session accepts at most 10,000 remembered command IDs to bound memory. Response files remain available for inspection. Archive or clean an old isolated bridge directory only after its game is closed; do not edit an active inbox/outbox or live state to affect gameplay.

The bridge is a local trusted-client interface. Any process that can write that directory can send game commands. Use a writable local directory, not a shared or cloud-synced folder. Launch with `-- --no-agent` to disable it. `-- --agent-dir ABSOLUTE_PATH --agent-paused` chooses the bridge explicitly. `--save-path ABSOLUTE_FILE` chooses a separate save for an isolated run.

## Verification

`tests/test_agent_bridge.gd` checks command validation, JSON number handling, legal-action reporting and simulation parity. `tests/test_agent_cli.ps1` talks to a real running GUI through the CLI, tests retries/rejections and screenshots, and can complete the full rescue campaign with ordinary actions. Tests use an isolated save. See `README.md` for commands.
