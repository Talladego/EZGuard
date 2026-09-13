# EZGuard Code Quality Report

**Addon:** EZGuard (Warhammer Online / Return of Reckoning UI mod)  
**Current version:** **1.21** (`EZGuard.mod` `UiMod version="1.21"`; `EZGuard.lua` `VERSION = 1.21`; `.mod` date `29/01/2022`; `gameVersion="1.4.8"`)  
**Scope:** Application code plus bundled `libs/` (LibStub / LibGUI / LibConfig). No tests, no README.

---

## Overall verdict

The idea is sound: a tank-only helper that picks a nearby injured ally and retargets before Guard is pressed. The implementation is a single 540-line script with large vendored UI libraries, leftover commented code, and several **runtime-crash and "addon never activates" bugs**.

It is **not production-quality**. It can throw on action-bar clicks for non-tanks, may never detect Guard at login, can target the wrong warband slot, and does expensive work on a 0.5s tick plus every group-status event. Usable as a personal tank tool after fixes; not safe to ship as-is.

---

## Findings

### Critical

**1. Global `ActionButton` hooks dereference `EZGuard.Settings` with no nil/tank guard**  
Files: `EZGuard.lua` (hooks ~507–538), `EZGuard.Initialize` (~148–156)

Hooks are installed at **file load**, not in `Initialize`. Non-tanks (and any character whose career ID is missing from `CareerIDsToLines`) hit:

```lua
isTank = false
return
```

That skip means **no settings init, no slash commands, no events**. Saved variables may also be absent on a new character.

`ActionButton.OnLButtonDown` / `UpdateInventory` then evaluate `EZGuard.Settings.enabled` on **every bar click / inventory update**. A nil `Settings` is a Lua error on the default action bar.

`OnShutdown` still unregisters events that were never registered (client error spam).

---

**2. `CheckGuard()` at login cannot set `hasGuard`**  
File: `EZGuard.lua` ~158, 221–225

```lua
EZGuard.CheckGuard()  -- no args
...
function EZGuard.CheckGuard(slot, actionType, actionId)
    if actionId == GuardAbilityID[GameData.Player.career.line] then
        hasGuard = true
    end
end
```

`actionId` is nil on the init call. `hasGuard` is **never set false** if Guard is removed. The working 1–60 hotbar scan is commented out (~227–236).

Until `PLAYER_HOT_BAR_UPDATED` fires with Guard’s ID, `OnUpdate` will not call `Enable()`, glow/auto-target stay inert. Many logins never fire that event for an unchanged bar → **addon silently does nothing**.

---

### High

**3. Warband member index ≠ `TARGET_GROUP_MEMBER_n`**  
File: `EZGuard.lua` ~359–372, 289–296, 507–516

Comments correctly note warband `players` **includes self**, group data does **not**. The same `index = i` is passed to `PartyTargetEvent[index]` (`TARGET_GROUP_MEMBER_1`–`6`).

Group path: index 1 = first other member → usually correct.  
Warband path: index includes the tank’s slot, so the event can hit the **wrong person** (or an invalid member 6). Guard then lands on the wrong ally.

`PartyUtils.GetWarbandParty(partyIndex)` is used with no nil check. If `IsPlayerInWarband` fails (name/`^` suffix mismatch), `.players` errors.

---

**4. `GetBuffs` used without a nil check**  
File: `EZGuard.lua` ~322–332

```lua
local buffs = GetBuffs(targetType)
for _, v in pairs(buffs) do
```

`GetBuffs` is nil when there is no friendly target / no buff table. `UpdateGuardTarget` is registered for `PLAYER_TARGET_EFFECTS_UPDATED`, so this is a **combat-time crash**.

---

**5. `AutoTarget` broadcasts a target event every 0.5s**  
Files: `EZGuard.lua` `OnUpdate` ~190–213, `AutoTarget` ~289–296

While enabled + auto-target + a suggested target ≠ current guard, `BroadcastEvent(TARGET_GROUP_MEMBER_n)` runs on the `TIME_DELAY` tick. That steals the friendly target continuously (blocks heals, assists, ground targeting) and spam-fires targeting.

---

**6. `Enable()` can chat-spam if the Guard button is not found**  
Files: `EZGuard.lua` ~200–205, 265–268, 482–501

Every 0.5s:

```lua
if EZGuard.Settings.enabled and hasGuard and not buttonActive then
    EZGuard.Enable()  -- PrintSettings() every time
end
```

If `hasGuard` is true but `ActionBars:BarAndButtonIdFromSlot` / `m_Buttons` fails, `buttonActive` stays false → **“EZGuard enabled.” every 0.5s**.

---

**7. Version mismatch replaces settings with the *DefaultSettings table itself***  
File: `EZGuard.lua` ~160–164

```lua
EZGuard.Settings = EZGuard.DefaultSettings
```

No copy, no field migration. User options are wiped on any version change, and in-session writes mutate defaults. LibConfig has already captured the old table if the window was opened.

---

### Medium

**8. “Self / no target” health is raw HP, not percent**  
File: `EZGuard.lua` ~343–346

```lua
return fixString(LOCAL_PLAYER_NAME), GameData.Player.hitPoints.current
```

Everywhere else health is 0–100. This can store thousands in `CurrentFriendlyTarget.healthPercent`. Combined with (9), dead-guard logic is unreliable.

---

**9. `CurrentGuardTarget` health/index stay stale**  
Files: `EZGuard.lua` `UpdateGuardTarget` ~303–319, `UpdateGroup` ~386–388, `SelectHurtPlayer` ~452–455

Guard name/HP are copied only while **you are targeting** the guardee. `UpdateGroup` refreshes `index` by name but **not** `healthPercent`.  
`SelectHurtPlayer` treats `CurrentGuardTarget.healthPercent == 0` as “guardee dead” — usually false unless you still have them targeted.

---

**10. Player name frozen at file load**  
File: `EZGuard.lua` ~16

```lua
local LOCAL_PLAYER_NAME = GameData.Player.name
```

At parse time this can be empty or still have `^M`/`^F`. Later code `fixString`s it, but warband lookup and self-filters can fail for the whole session.

---

**11. Tank detection uses `career.id` → `CareerIDsToLines`; everything else uses `career.line`**  
File: `EZGuard.lua` ~71–96, 148–156 vs 222, 326, 465, 512

If `career.id` is missing/unexpected, `isTank` is false and the addon bails even for a real tank. `GuardAbilityID[GameData.Player.career.line]` is the consistent key.

---

**12. Magic `m_Windows[6]` / `[7]` with no nil checks**  
File: `EZGuard.lua` ~460–501

Custom bars or a different client layout → errors inside `SetButtonGlow` / `SetButtonActive`. Glow also **Stop/StartAnimation every 0.5s** (`buttonGlowLevel` is written, never compared) → flicker and extra work.

---

**13. `UpdateGroup` on `GROUP_STATUS_UPDATED` scans 511 map points**  
Files: `EZGuard.lua` ~175–176, 409–418, 426–457

Every party HP/distance tick:

- rebuilds the party table  
- `GetMapPointData(..., i)` for `i = 1..511`  
- sorts (sort does **not** use archetype weights; selection does)

Then `OnUpdate` walks the party again twice a second. `isDistant` is stored and ignored. Unknown careers get weight `999999` (effectively never chosen).

---

**14. Target-then-cast race**  
File: `EZGuard.lua` ~507–522

`BroadcastEvent` runs in `OnLButtonDown` **before** `orgActionButtonOnLButtonDown`. If the client applies Guard before the target event is processed, Guard hits the **previous** friendly target.

---

**15. Config: no validation; docs describe missing features**  
File: `EZGuard_Config.lua`

- Hitpoint-factor help text refers to a **“HURT” guard mode** that does not exist.  
- `guardDistance` / weights have no min/max (`LibConfig.MinMax` exists, unused). Negative distance → nobody in range.  
- Typo: “withing guard range”.  
- Slash `/ezguard` only opens the GUI. Distance toggle in `EZGuard.Slash` (~238–247) is **dead** (init registers `EZGuard_Config.Slash`).  
- Chat string: “disbled” (`EZGuard.lua` ~253).

---

**16. Hooks never removed; `UpdateBurning` swallows the original for Guard**  
File: `EZGuard.lua` ~525–530

Disable/shutdown leave `ActionButton.OnLButtonDown`, `UpdateBurning`, and `UpdateInventory` patched. Guard’s default burn FX never runs. `/reloadui` stacking is a WAR hazard if the file is evaluated twice.

---

### Low

**17. Dead / leftover state**  
`EZGuard.lua`: unused `EZGuard.NewGuardTargetIndex`; unused sort-for-selection; large commented `CheckGuard` variants; commented `level >= 10` (Guard is level 10).  
`EZGuard.Slash` unused. Level-10 tanks without the ability still run the full path.

**18. `fixString` shadows its argument** (`local str = str`, ~107–113). Harmless.

**19. LibSlash is a `.mod` dependency but not shipped.** Missing LibSlash aborts `Initialize` after the early tank path (settings may exist; events may not).

**20. Vendored libraries dominate the tree** (`LibGUI.lua` ~1390 lines, `LibConfig.lua` ~620). Notable library issues (lower priority): `LibGUI.elementCount` increments even when `New` fails; `Destroy` leaves `{destroyed=true}` in the element map; `LibConfig.OnUpdate` is registered globally for a color picker this addon never uses; colorizer `Hide()` assumes `LibConfig.colorizer` exists.

**21. No tests, no README, XML uses backslashes in file names** (normal for WAR). `.gitignore` only ignores editor junk.

---

## Top fixes (priority order)

1. **Gate all hooks and `OnUpdate` UI** on `isTank` **and** a non-nil `EZGuard.Settings`. Initialize settings (copy of defaults) for every character; return from *logic*, not from “don’t even create Settings.” Make `OnShutdown` unregister only what `Initialize` registered.

2. **Restore a hotbar scan in `CheckGuard` / `Initialize`** (the commented 1–60 loop). Set `hasGuard = false` when Guard is not on any slot. Cache bar/button instead of scanning 60 slots on every glow tick.

3. **Normalize party indices** to `TARGET_GROUP_MEMBER_*` (exclude self; remap warband slots). Nil-check `GetWarbandParty` and `GetBuffs`.

4. **Do not `BroadcastEvent` on a timer** unless the target actually changed; debounce auto-target. Don’t call `Enable()`/`PrintSettings()` unless state changed.

5. **Deep-copy + migrate settings** on version change; don’t alias `DefaultSettings`. Read `GameData.Player.name` in `Initialize`. Prefer `GameData.Player.career.line` for tank detection.

6. **Performance:** scan map points incrementally or on a slower cadence; skip `SetButtonGlow` if glow level unchanged; don’t rebuild/sort the full party on every `GROUP_STATUS_UPDATED` if you only need one member’s HP.

7. **Correct self HP** (`current / maximum * 100`). Sync `CurrentGuardTarget.healthPercent` from party data. Add nil checks on `button.m_Windows[6/7]`.

8. **Cleanup:** delete dead `EZGuard.Slash` or wire it; fix strings; remove “HURT mode” copy; clamp numeric config; unhook on shutdown.

---

## Structure (short)

| Piece | Role |
|--------|------|
| `EZGuard.mod` | WAR module: version **1.21**, files, saved `EZGuard.Settings`, `OnInitialize` / `OnUpdate` / `OnShutdown` |
| `EZGuard.lua` | All combat/targeting/hotbar logic + global `ActionButton` monkey-patches |
| `EZGuard_Config.lua` | Slash → LibConfig window |
| `libs/` | LibStub + full LibGUI + LibConfig (not EZGuard-specific) |

There is no module split (targeting vs UI vs settings), no cached hotbar slot, and no defensive API wrappers. The interesting logic is ~200 lines inside a file that also hosts hooks, glow, and commented experiments.

---

*Report only — no application code was changed and no fix PR was opened.*