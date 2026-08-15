# Player Intercept Course Detection

A Stand Lua script for GTA V that predicts whether another player's current movement is likely to cross dangerously close to the local player.

## Version

**2.0.0**

## What changed in 2.0

The original detector projected every remote player toward the local player using a fixed speed. Version 2.0 instead measures actual player movement over time and predicts the closest point of approach using relative velocity.

This substantially reduces false positives from players who are nearby but moving away, travelling parallel to you, or passing at a different elevation.

### New features

- Measured local and remote player velocity instead of a fixed assumed speed
- Relative-motion closest-approach prediction
- Configurable intercept radius
- Configurable prediction horizon
- Minimum closing-speed threshold
- Vertical-separation filtering for bridges, aircraft, stacked roads, etc.
- Velocity smoothing to reduce network-position jitter
- Join grace period for newly discovered players
- Per-player alert cooldowns
- Optional friend filtering
- Live status menu
- DirectX debug overlay
- Player tracking cleanup when players leave
- Session-aware reset behaviour
- Persistent Stand command states for supported menu controls

## Stand API requirement

`Interception.lua` is implemented using the documented Stand Lua API surface only. It does not require native hashes or external Lua libraries.

Main API namespaces used:

- `players`
- `menu`
- `util`
- `directx`

Standard Lua `math`, `string`, and table functionality is also used.

## Installation

1. Download `Interception.lua`.
2. Place it in your Stand Lua Scripts directory.
3. Load it through Stand's Lua Scripts menu.
4. Open **Intercept Detection v2.0.0**.
5. Enable **Intercept Detection**.

## Recommended defaults

The built-in defaults are intended as a balanced starting point:

| Setting | Default |
| --- | ---: |
| Intercept Radius | 25 m |
| Prediction Horizon | 8 s |
| Minimum Closing Speed | 3 m/s |
| Vertical Tolerance | 20 m |
| Sample Interval | 250 ms |
| Velocity Smoothing | 35% |
| Join Grace Period | 5 s |
| Alert Cooldown | 10 s |

Fast aircraft or very high-speed vehicle sessions may benefit from a longer prediction horizon and larger intercept radius.

## Detection model

For each tracked player, the script samples the local player's and remote player's positions. It estimates their velocities and forms a relative-position vector and a relative-velocity vector.

It then computes the time at which horizontal separation will be smallest within the configured prediction horizon. A warning is raised only when all configured conditions are satisfied, including closest horizontal distance, closing speed, vertical separation, and join grace.

The calculation predicts movement from current observations. It cannot know future steering, braking, teleportation, network corrections, or other sudden changes, because apparently predicting human drivers was not already ambitious enough.

## Legacy Pluto file

`Intercept.pluto` remains in the repository for historical compatibility. The actively maintained implementation is `Interception.lua`.

## Author

**whistledev**
