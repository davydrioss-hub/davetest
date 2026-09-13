# Validation — City Expansion 0.3

The project targets official Godot 4.4.1 and its matching Windows x64 template.

- **150 core checks:** all previous cargo, economy, movement, seat, shift,
  persistence and migration checks, plus reachability of every new destination
  and activity, water/pier collision, collectible conservation, timed service
  reservations, single payment, cancellation, fleet purchases, independent
  driving/cargo, campaign reward validation, employee hiring, persistent
  exploration, expanded save/load, additive 0.2 migration, and a walkable
  reconnect after saving while seated in a vehicle.
- **103 real networking checks:** ENet listen host plus seven clients, capacity,
  password and identity handling, authority and ownership races, load/unload,
  payout and upgrade conservation, host-only shift changes, seats/reconnect,
  host persistence, empty passwords, invalid movement and host termination.
  Expansion checks exercise collection, six-second roadside repair, rejected
  premature completion, exact company income, campaign reward, vehicle
  purchase, second-car movement and a late-join snapshot retaining all domains.
- **Rendered scenes:** menus and settings, contracts, city map, business,
  fleet, city activities, loading/cargo, streets, rain, harbor, park, workshop,
  dealership and residential area are inspected using software OpenGL.
  Texture mipmaps and VRAM compression reduce distance shimmer; material and
  lighting balance are checked against the actual game, not concept art.
- **Packaging:** the builder rejects script/import/export errors, validates
  the Windows PE header and requires the accompanying PCK. GitHub Actions
  independently exports and launches that EXE on `windows-latest` headlessly,
  checks its engine log, and validates the saved city, company, fleet, jobs,
  activities and player. A green workflow is required before delivery.

A physical Windows GPU playtest and connectivity across separate homes and
routers remain outside this automated validation. There is no measured
consumer-GPU performance guarantee and no claim of photorealistic art.

## Authority and update rates

The host owns all game mutations. Clients send sequenced, bounded-rate intents.
Local identities sign one-use challenges; no store or account service is used.
A joining player receives the current snapshot, including fleet, employees,
activities and campaign. Revisioned reliable deltas use channel 0; vehicle and
player movement uses 20 Hz channel 1; NPC presentation uses 5 Hz channel 2.
Distant pedestrians use less frequent simulation. Cargo and inventories use
state changes instead of distributed rigid-body physics.

Protocol and world format are 3. Formats 1 and 2 migrate additively; old cargo,
orders, identity and company money are retained. Save envelopes 1/2/3 are
accepted. Backups and checksums prevent silently replacing a damaged world.

## Reproducing the asset build

`tools/assets-manifest.json` pins all 13 used material files by URL, exact byte
count and SHA-256. `tools/material-imports/` pins mipmaps, normal-map processing
and compression. `tools/prepare_assets.py` prepares missing files; the release
contains their imported resources, and never downloads content at runtime.
Kenney models, animations and four original Ogg compositions are in source.
The developer generator for music is optional and not part of a normal build.

Godot 4.4.1 emits `Parameter "t" is null` while generating GLTF/FBX thumbnails
with the headless dummy renderer. The builder recognizes only the exact dummy
texture diagnostic described in https://github.com/godotengine/godot/issues/108994.
Other engine errors fail the build. Actual model rendering is checked in OpenGL.
