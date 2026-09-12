# Validation — Night Shift 0.2

Local verification uses the official Godot 4.4.1 Linux editor/exporter.

- **80 core checks:** contract creation and duplicate acceptance, exclusive and
  cooperative pickup, solo heavy trolley, cargo ownership conservation,
  distance validation, doors, loading, straps, unloading, payouts, multi-stop
  routing, fragile damage, deadlines, four seats, driver assignment, upgrades,
  knockdown/respawn, world collision, shift reports, reliable deletion replay,
  atomic saves, corruption recovery, malformed snapshot rejection, all four
  timed events, and migration of a 0.1 world with carried cargo.
- **62 network checks:** real ENet listen host plus seven client processes;
  capacity and password rejection, authoritative movement, cargo races,
  loading/straps/unloading, one-time company payment, a simultaneous upgrade
  purchase, host-only shift changes, four vehicle occupants, passenger input,
  reconnect with durable cargo/stats, duplicate identity rejection, host-only
  saves, reload retaining upgrades and world identity, next-night cleanup,
  optional empty password, oversized input rejection, abrupt host shutdown.
- **Rendered interface:** main, identity, play, host, join, settings, gameplay,
  contracts, map, company, cargo, loading, street destination and rain screens
  were rendered and inspected using software OpenGL. A garage beam occluding
  the camera was fixed after inspection. This is visual verification, not a
  representative consumer GPU performance benchmark.
- **Windows package:** exported using the matching official x86-64 release
  template; executable PE header and accompanying PCK checked by the builder.
  The CI workflow additionally runs the exported executable on `windows-latest`
  headlessly and verifies the resulting company, orders, player and host save.

Internet connectivity across two physical homes, arbitrary routers, and
interactive play on a physical Windows GPU require a friends' playtest. There
is no claim of measured minimum hardware requirements or photorealistic art.
The playable map, vehicle handling, NPC patrol and business simulation are a
small stylized first version.

All game mutations execute on the host. Clients send sequenced, rate-limited
intents; joins authenticate the local RSA identity using a one-use challenge.
Initial snapshots and reliable revisioned state deltas share channel 0;
movement is 20 Hz on channel 1, NPC presentation at 5 Hz on channel 2. NPCs far
from players update positions less frequently. Inventory is replicated as
changes, and cargo uses server ownership instead of distributed rigid bodies.

Known upstream import diagnostic: Godot 4.4.1 prints `Parameter "t" is null`
when creating GLTF/FBX scene thumbnails with the headless dummy renderer.
The build script recognizes only the exact dummy texture diagnostic from
https://github.com/godotengine/godot/issues/108994. Other engine errors still
fail the build. Rendered assets were checked with actual OpenGL.
