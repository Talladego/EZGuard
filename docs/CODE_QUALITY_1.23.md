# EZGuard CODE_QUALITY 1.23

**Date:** 2026-09-14 (Europe/Stockholm)  
**HEAD:** `e9d5701ce834817c656b156d0e2845a81b93fd95`  
**Version:** 1.23 (`EZGuard.mod` / `VERSION`)  
**Prior:** 1.21 quality pass 2026-09-13 (issues #2–#9, closed after fix commits)

Summary issue: https://github.com/Talladego/EZGuard/issues/14

---

## Verdict

1.23 fixes the 1.21 critical/high set (#3–#9). Remaining: **1 critical** + **3 high** (filed #10–#13). Usable as a personal tank tool after those; not fully clean for “ship as-is.”

---

## Claimed fixes verified

| Prior | Fix in 1.23 |
|-------|-------------|
| C1 ActionButton / Settings nil | Hooks only when `isTank`; `Settings` nil-checked before `.enabled` |
| C2 `hasGuard` at login | `RefreshGuardHotbarSlot` scans hotbar slots 1–60 |
| H3 Warband target index | Self → `TARGET_SELF`; other slots → `PartyTargetEvent[index]` |
| H4 `GetBuffs` nil | `type(buffs) ~= "table"` → false |
| H5 AutoTarget spam | `lastBroadcastName` — broadcast once per suggested ally |
| H6 Enable chat-spam | Early-return when already enabled (see new C1) |
| H7 DefaultSettings alias | `mergeSettings` / `initializeSettings` |
| Missing `GROUP_STATUS_UPDATED` | Handler → `markPlayersDirty()` |
| Stale player name | `LOCAL_PLAYER_NAME` refreshed in `Initialize` / `LOADING_END` |

---

## New findings

### Critical

**C1 — Settings GUI Enable/Disable skipped** — #10  
LibConfig writes `Settings.enabled` before `SettingsChanged`. `Enable`/`Disable` early-return when the flag already matches, so UI toggle does not call `RegisterEventHandlers`. Worst path: Ctrl-click disable, then re-enable only from `/ezguard` UI → overlay on, events off.

### High

**H1 — Scenario careerLine wrong type** — #11  
Scenario branch passes `ArcheType[CareerIDsToLines[id]]` into `getArchetypeWeight` → all weights 999999; Hitpoints Factors ignored in scenarios/sieges.

**H2 — Stale NewGuardTarget on leave group** — #12  
`SelectHurtPlayer` gated on `GetNumGroupmates() > 0`; leaving party leaves glow/auto-target on a stale target event.

**H3 — No normalize on SettingsChanged** — #13  
Numeric textboxes not clamped after UI edit → possible tick errors / broken range/priority.

---

## Labels

Repo has `bug`, `quality`, `grokbot`, `severity:high`. **`severity:critical` is still absent** (could not create via available MCP/`gh`). Critical filed with `severity:high` + `[critical]` title (same pattern as 1.21).

---

## Issue index

| Issue | Title |
|-------|-------|
| #14 | `[quality] CODE_QUALITY 1.23 summary` |
| #10 | `[critical] C1: Settings GUI Enable/Disable skipped by early-return` |
| #11 | `[high] H1: Scenario snapshot passes archetype string as careerLine` |
| #12 | `[high] H2: Stale NewGuardTarget when leaving group` |
| #13 | `[high] H3: SettingsChanged never normalizes numeric fields` |
