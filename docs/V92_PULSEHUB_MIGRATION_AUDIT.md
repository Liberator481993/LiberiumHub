# LiberiumHub v92 — PulseHub Migration Audit

Status: Initial UI shell committed; feature migration not started.
Working branch: `v92/pulsehub-ui-parity`
Baseline: `main/Keyless` (v91.70)
Reference artifact: user-provided `PulseHub.luau.txt` (12,469,988 bytes; approximately 53.1k lines).

## 1. Scope and source constraints

The supplied PulseHub file is an offline-adapted reference artifact. Its wrapper blocks outbound HTTP, disables WebSocket, makes `queue_on_teleport` a no-op, and restricts dynamic source loading. Therefore, this file is not proof of the current official/live PulseHub loader or of the behavior of every upstream build.

The audit did not identify an item-transfer endpoint, credential/cookie harvesting, or a hidden third-party logger in the reviewed artifact. It did identify an optional user-configured farming-stat webhook. Its requests are blocked by the offline wrapper in this copy. Rejoin code also includes a script-key persistence/re-execution path; do not transplant that fragment unchanged.

WeaponSkins/InventoryChanger behavior in this copy is local profile/UI manipulation. Locally spawned cosmetic entries are specifically scrubbed from the trade inventory view. Do not present these as server-owned inventory or real tradable items.

Implementation rule: reproduce compatible behavior in Liberium's own code and API. Do not copy the 53k-line reference wholesale or bring across offline stubs, hidden runtime dependencies, webhook destinations, or key-persistence logic.

## 2. Liberium baseline already present

The v91.70 `Keyless` already contains a substantial implementation and must remain the integration base:

- Startup readiness checks for LocalPlayer and PlayerGui, plus a global cleanup lifecycle.
- Existing Nova-like window primitives: `Lib.new`, `Win:AddTab`, `Tab:AddSubTab`, `Sub:AddSection`, and section controls for toggles, sliders, buttons, and dropdowns.
- MM2 role resolution and role-coloured player highlighting, including separate Hero handling.
- Name/distance overhead labels, Skeleton ESP, bullet tracers, FOV circle, target HUD, and candy-only Loot ESP.
- Coin AutoFarm with active-map/coin-container checks, movement/contact handling, and a mobile farm status HUD.
- GunDrop-only AutoPickup with bounded touch attempts and status reporting.
- Movement controls, noclip, anti-fling, aim prediction, FPS optimisation, stats, shaders, local aura, config save/load, Anti-AFK, rejoin, and server-hop controls.

These systems are not being replaced by PulseHub code. The first UI commit leaves their existing feature logic in place.

## 3. Reference feature map and migration order

### A — Core MM2 systems

| PulseHub area | Liberium destination | Migration approach |
|---|---|---|
| EspBox, EspRole, EspLabel, EspLine, EspTracer, EspSkeleton, EspChams, EspRadar, EspGhost | Visuals / ESP | Keep current role and loot resolution; add missing render modes as independent opt-in components. |
| FarmRuntime, FarmState, FarmMotion | Farm | Compare behavior against current coin/gun routines; preserve active-map validation and cleanup. |
| RoleFarm, BoxFarm | Farm | New independent modes; do not overload the existing AutoFarm state machine. |
| Sheriff aim/target/FOV/tracer modules | Combat / Sheriff | Build as separate components with explicit target validation, settings, and stop/cleanup paths. |
| MurderFeature, KnifeAim | Combat / Murderer | Separate role-gated feature group; never start before role state is known. |
| TeleportFeature, ServerIdentity, MapVote | Server / Teleport | Reuse existing session lifecycle where possible; validate destinations and async cancellation. |

### B — Visuals and customization

| PulseHub area | Liberium destination | Migration approach |
|---|---|---|
| WeaponSkins, RemoteSkins, ThrownSkins, InventoryChanger | Visuals / Inventory | Audit local-only effects and game UI dependencies; clearly label cosmetic/client-only behavior. |
| AnimationFeature, AvatarSkins, RemoteAvatarSkins | Player / Animations | Migrate only supported animation/catalog operations; isolate asset loading and cleanup. |
| AuraEngine, SelfChams, WalkTrail, GameEffects | Visuals / Effects | Reuse the existing aura manager where safe; add independently disposable effects. |
| Optimizer, VisualWorld, VisualSky, TexturePack, Weather, SkyFx, CustomCursor | Visuals / Environment | Separate reversible property changes from asset/network loading; restore original state on unload. |

### C — Optional and social features

| PulseHub area | Liberium destination | Migration approach |
|---|---|---|
| TradeValues | Inventory / Trade | Read-only UI integration only; do not imply ownership or execute trades. |
| Music, Boombox, GameSounds, CustomSounds | Audio | Optional; validate asset permissions and provide explicit stop/cleanup. |
| Chat, Pulse Users, server/social panels | Social | Optional and lower priority; no hidden messaging or background network calls. |
| Configuration, NovaStore, NovaTheme, NovaMotion, NovaSound, NovaTexture | Settings / UI | Recreate only the needed local settings/theme patterns; retain Liberium's config schema and cleanup. |

## 4. v92 UI shell — implemented in this branch

Commit: `2df7ea0f18005eb535120bbbf1a12a8e61e20219`

Changes in `Keyless`:
- Added grouped sidebar navigation with Overview, Combat, Player, Economy, and System group labels.
- Added a sidebar search field; matching tab and subtab names remain visible and empty group headings are hidden.
- Moved the desktop layout baseline to 812 × 584 with a 208 px sidebar, keeping a compact portrait-touch layout.
- Applied the dark neutral/crimson visual tokens and orange highlight used by the v92 reference spec.
- Updated the footer/status labels to v92 and Delta/Arceus Android.
- Preserved the existing feature-control API, Farm HUD, cleanup path, and current tab feature callbacks.

Static verification after the GitHub write:
- Fetched `Keyless` from the working branch again and confirmed the new blob SHA.
- Confirmed the search TextBox and `Win:ApplySearch` exist.
- Confirmed all six current tabs have explicit group assignments.
- Confirmed reference desktop dimensions are present.
- Confirmed the existing Farm HUD update function and global cleanup entry point remain present.

Not yet verified:
- Luau parser/compiler result.
- Roblox runtime behavior.
- Delta Android or Arceus X device behavior.
- Pixel-level parity against screenshots at matching viewport sizes.
- Touch behavior and clipping on real device sizes.

## 5. Next implementation stages

1. Finish and statically review the shared UI controls against the PulseHub reference: section/card hierarchy, toggle/slider/dropdown states, notifications, keybind capture, and search behavior.
2. Add explicit collapsible navigation groups and a stable search/selection lifecycle without changing the existing public UI API.
3. Extract a migration map for each missing A-priority component, including its dependencies, state, connections, and cleanup.
4. Migrate ESP additions and farm modes one component at a time; preserve current baseline behavior.
5. Add the distinct Sheriff and Murderer feature groups after role/target lifecycle checks.
6. Continue with reversible visual modules, then optional customization/social features.
7. Run static checks and available Luau validation; only claim executor/runtime success after actual Delta/Arceus execution.

## 6. Acceptance policy

A feature is not marked complete merely because its UI control exists. Completion requires implementation, a static review of state transitions and cleanup, and runtime verification where the executor/game behavior matters. Until runtime verification is available, mark it as static-only and do not ask the user to test a half-finished stage.
