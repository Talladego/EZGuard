# EZGuard

Tank helper for Return of Reckoning. Picks a hurt party member in guard range and targets them when you use your guard ability.

## Commands

- `/ezguard` or `/ezg` - open settings
- Ctrl-click guard ability - toggle enabled/disabled

## Settings

| Setting | Description |
| --- | --- |
| Enabled | Master toggle |
| Auto Target | Automatically target the selected ally (you still press guard) |
| Burn Effect | Glow guard button when a new guard candidate is available |
| Range Check | Use overhead map distance lookup (disable to skip map scan) |
| Guard Distance | Max range in feet (default 50) |
| Hitpoint factors | Lower weight = higher priority when HP is equal |

## Version 1.23

- Nil-safe `GetBuffs` in guard-buff detection
- Auto-target broadcasts once per suggested ally (no tick spam)
- Warband self maps to `TARGET_SELF`; slot events match WarTriage
- `GROUP_STATUS_UPDATED` handler (was registered but missing)

## Version 1.22

- Map distance scan early-out (WarTriage 3.01 pattern)
- Group events mark dirty only; roster/distance work runs on 0.5s gate
- Cached guard hotbar slot (no 1-60 scan every tick)
- ActionButton hooks install on tank login only
- Settings migration preserves existing config (no wipe on upgrade)
- Warband/scenario roster parity with WarTriage snapshot paths
- Auto-target throttle (0.25s)

## Tank careers

Ironbreaker, Knight, Swordmaster, Blackguard, Chosen, Black Orc (Save Da Runts)
