# Validation — 2026-09-12

Engine pinned to Godot 4.4.1 stable, official commit `49a5bc7b6`.

## Executed

- 35 core assertions passed: distance/ownership checks; single-winner pickup; atomic delivery reward and item consumption; repeated order rejection; inventory conservation; property purchase and employee income; vehicle occupancy/release; death and delayed respawn; door collision; delta reconstruction; checksummed atomic save, backup recovery and path validation; address parsing.
- 34 network checks passed using independent Godot processes and real ENet/UDP sockets, with one host and seven clients. Covered full snapshots, late joining, player capacity, incorrect and empty passwords, movement replication, competing pickups, authoritative order validation, duplicate rewards, invented money commands, oversized movement, reconnect with persistent identity, inventory/money/stats recovery, duplicate identity rejection, host-only saves, save/reload, graceful shutdown and abrupt host termination.
- Exported pack was launched with the matching Linux runtime in headless single-player mode.
- Main menu, first-run identity, play, host, join, settings and gameplay were rendered with the Godot OpenGL Compatibility renderer. Host/join forms and gameplay HUD were visually inspected; HUD contrast was corrected.
- Windows x64 `.exe` and `.pck` were generated from the official Windows release template. No Steam SDK or third-party networking plugin is present. Test scenes/scripts are excluded from the exported pack.

## Boundaries

The networking checks run on local loopback. They do not establish performance on separate physical PCs, real Wi-Fi, an ISP router, public internet/NAT or a virtual LAN. Native Windows execution and Windows firewall behavior have **not** been tested in this Linux workspace. The Windows executable is an actual exported PE binary, not a script or placeholder.

The 3D yard is a networking prototype. Patrol/NPC behavior is basic; there is no complete police/combat system, large open world, advanced vehicle physics, host migration, internet relay or client prediction. Private play does not require any player account.

## Reproduce

```sh
godot --headless --path . res://tests/core_tests.tscn
python tests/network_tests.py /path/to/godot
python tools/build_windows.py
```

See `tests/last_network_result.json` after a local test run for its ordered checks. Test identities and world saves are generated outside the project and are not distributed.
