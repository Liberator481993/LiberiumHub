# LiberiumHub v92 — PulseHub Migration Audit

Status: Stage 1 UI shell, navigation, shared controls, and responsive source pass committed; runtime visual sign-off pending. Feature migration not started.
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


### Stage 1 implementation update — 2026-11-12

The working branch now includes the full source-side UI pass: reference desktop sizing/scale, compact touch layouts, brand and page headers, grouped sidebar navigation, tab/subtab search filtering, subtab auto-reveal, section cards, toggle/slider/button/dropdown styling, popup viewport clamping, hover/selection/expand animations, floating UI toggle, notification stack, and cleanup wiring. Startup keybind and blur defaults were aligned with the reference notes. Existing feature callbacks and the public `Lib` / `Win` / `Tab` / `Sub` / `Sec` control API remain in place.

This is implementation completion at source level only. Stage 1 is not signed off until the file is parsed/compiled and the UI is launched in Roblox on target Delta/Arceus devices, then compared against PulseHub screenshots at matching viewports. Do not begin feature migration until that visual/runtime gate is passed.


## 7. Stage 2 — source inventory and dependency audit (2026-11-12)

Status: **completed as a static source audit**. This stage inventories both exact checked-in inputs and establishes a safe migration order. It does not authorize feature rollout before the Stage 1 runtime/visual gate.

### 7.1 Exact source snapshots inspected

| Input | Verified snapshot | Notes |
|---|---|---|
| PulseHub reference | 12,469,988 bytes; 53,100 lines | Retrieved from the user's Library artifact `PulseHub.luau.txt`; the file is readable Luau source, not a binary payload. |
| Liberium integration target | `Keyless`, 255,401 characters; 3,206 lines; blob SHA `47f8344e1e2d6ae1981cce6bb2e07435cf26100f` | Fetched from `v92/pulsehub-ui-parity`. |
| Migration audit before this section | blob SHA `2c090b1fb4c66c683aa0ef81e8df67ca9ce91795` | This update is appended to the same branch; `main` is not changed. |

A static scan of the PulseHub artifact found **109 top-level module/table declarations**. The source has a clear composition root at `PulseApplication.create` (around line 52641) and feature installation begins around line 52694. The exact module inventory is grouped below; line numbers refer to the 53,100-line reference artifact.

### 7.2 PulseHub module inventory and destination map

| Source modules (reference line ranges) | Responsibility | Destination in Liberium | Risk |
|---|---|---|---|
| `PulseWindow`, `PulseTab`, `NovaFoundation`, `NovaUtility`, `NovaMotion`, `NovaRefresh`, `NovaTheme`, `NovaFont`, `NovaIcons`, `NovaStore`, `NovaSound`, `NovaTexture`, `NovaWidgets`, `NovaSection` (411–18,492) | Window framework, controls, themes, persistence, motion and shared UI helpers | Existing Liberium UI API only; selectively reproduce missing interaction patterns | High if transplanted wholesale; low/medium for isolated visual behavior |
| `InputBindings`, `Movement`, `FovSettings`, `FovLifecycle`, `FovTarget`, `FovController`, `FovFeature`, `AimCalibration`, `AimGeometry`, `AimMotion`, `AimPlan`, `AimTarget`, `AimTiming`, `AimEngine` (1–107; 1,468–1,502; 4,056–4,342; 18,551–21,982) | Input mapping, movement, target geometry, prediction and FOV lifecycle | Combat / Player modules, only after independent target validation and teardown design | High |
| `RoleData`, `RoleCache`, `SheriffRuntime`, `SheriffSection`, `MurderFeature`, `KnifeAim`, `CombatTracer`, `AntiAim`, `MuzzleGuard`, `FlingFeature`, `GunFeature` (3,090–4,055; 7,423–7,697; 21,983–22,303; 24,473–25,169; 27,803–30,008) | Role resolution, sheriff/murderer combat, gun hooks and fling | Combat; retain Liberium role resolver as source of truth until a parity test proves otherwise | High |
| `FarmState`, `FarmMotion`, `FarmRuntime`, `RoleFarm`, `BoxFarm` (22,304–24,472) | Round/bag state, movement/contact, coin farm and alternate farm modes | Farm, as separately managed state machines; do not merge their loops into the current coin tracker | High |
| `EspSettings`, `EspText`, `EspColor`, `EspBox`, `EspRole`, `EspProjection`, `EspLabel`, `EspLine`, `EspTracer`, `EspSkeleton`, `EspHead`, `EspChams`, `EspChamModel`, `EspRadar`, `EspGhost`, `EspFeature` (25,170–27,802) | Render primitives and player/role ESP | Visuals / ESP; build atop Liberium role and player lifecycle | Medium–high; render-step and instance cleanup |
| `TradeValues` (6,389–7,037) | Read-only trade/inventory UI parsing and value labels | Inventory / Trade, behind an explicit read-only feature boundary | Medium; GUI hierarchy and external data-source assumptions |
| `Music`, `Boombox`, `CustomSounds`, `GameSounds` (6,352–6,388; 7,038–7,422; 30,009–30,431) | Audio controls, game sound replacement and previews | Optional Audio tab | Medium; asset permissions, sound instances and stop lifecycle |
| `TeleportFeature`, `ServerIdentity`, `ServerIdentity.MapVote` (7,697–8,794) | Place/server navigation and map voting | System / Server | High; asynchronous teleport and cancellation/rejoin lifecycle |
| `Configuration`, `Translation`, `Appearance`, `OfflineFiles`, `ResourceData`, `OfflineRequests`, `OfflineServices`, `OfflineEnvironment`, `LocalResponseClient` (3,509–4,055; 4,649–6,351; 17,047–18,550) | Settings, localization, appearance, and offline compatibility wrappers | Keep Liberium config schema; selectively port safe local helpers only | High for wrappers or persistence; medium for isolated config/UI behavior |
| `SkinModel`, `SkinCatalog`, `PulseSkin`, `WeaponSkins`, `RemoteSkins`, `ThrownSkins`, `InventoryChanger` (30,432–32,877) | Cosmetic models, local skin rendering and inventory UI changes | Optional Cosmetics; strictly client-only and visibly labeled | High; never imply server ownership/tradability |
| `GameEffects`, `AuraEngine`, `AuraHat`, `AuraTint`, `AuraFeature`, `SelfChams`, `WalkTrail` (32,878–41,576) | Character effects, aura and trails | Visuals / Effects | Medium; character respawn and object restoration |
| `Optimizer`, `CustomCursor`, `VisualWorld`, `VisualSky`, `TexturePack`, `Weather`, `SkyFx` (41,577–45,134) | Performance, cursor, lighting/world and environment effects | Visuals / Environment | Medium–high; save/restore every changed property and avoid permanent world mutation |
| `AvatarSkins`, `RemoteAvatarSkins`, `AnimationFeature` (45,135–47,058) | Avatar appearance and animation assets/tracks | Player / Appearance and Animations | High; asset loading, humanoid replacement, animation track cleanup |
| `PulseApplication.Mobile`, `PulseApplication.Trolly`, `PulseApplication.installAppearance`, `installMenu`, `installGeneral`, `PulseApplication.create` (47,059–53,100) | Mobile controls, special game-specific interaction, application composition and startup | No direct transplant; use as a dependency map for later isolated modules | High; composition root and game-specific assumptions |

### 7.3 Current Liberium integration surface (verified)

The current branch's `Keyless` is a 3,206-line monolithic script with these shared Roblox services acquired at the top: Players, TweenService, UserInputService, RunService, Workspace, ReplicatedStorage, HttpService, Lighting, TextService, TeleportService, Stats and Debris.

The checked-in UI/API surface is:
- `Lib.new`
- `Win:AddTab`, `Win:ApplySearch`, `Win:Destroy`
- `Tab:AddSubTab`, `Sub:AddSection`
- `Sec:AddToggle`, `Sec:AddSlider`, `Sec:AddButton`, `Sec:AddDropdown`
- `LiberiumAPI` registry/event/hook/unload wrapper, with section controls routed through that same UI API.

The current visible feature tabs are **Home, Farm, Visuals, Player, Combat and Settings**. The current `CFG` table is the shared configuration state. Role/session state is held in `roles`, `currentSession` and `canFarmNow`; feature managers are retained in top-level tracker/manager references so the global cleanup can stop them. The cleanup closure disconnects session and character connections and destroys/stops the UI, HUD, notification, ESP, farm, movement, FOV, tracer, skeleton, weapon, optimizer, session and aesthetics managers.

Existing Liberium behavior to preserve during any later migration:
- Farm: coin AutoFarm and bounded GunDrop AutoPickup are separate trackers with mutually aware start/stop callbacks.
- Visuals: role Outline/Fill, name/distance overheads, Skeleton ESP, candy-only Loot ESP, optimization, stats, shader preset and local aura.
- Player: walk speed, jump power and noclip.
- Combat: auto/manual fling, anti-fling, prediction display, crosshair, FOV circle and bullet tracer hooks.
- Settings: config save/load, Anti-AFK, rejoin and server hop.

No new feature should create its own untracked permanent RenderStepped/Heartbeat loop, global input listener, CharacterAdded listener, or persistent Instance. Each component must expose one idempotent `stop/destroy` path and register all connections/instances with the existing cleanup owner.

### 7.4 Dependency matrix

| Dependency class | PulseHub evidence | Liberium integration rule |
|---|---|---|
| Roblox services | Players, RunService, Workspace, ReplicatedStorage, Lighting, HttpService, TeleportService, Stats, input and GUI services are used across the source | Resolve once through a passed context; avoid hidden service lookups in feature internals |
| Shared configuration | PulseHub passes a common `configuration` and `defaults` table to feature installers | Add namespaced defaults and migration logic; never overwrite unrelated `CFG` keys |
| Role/player state | RoleData/RoleCache feed combat, ESP, farm and target modules | Use one normalized role/session provider; handle unknown role and respawn explicitly |
| Render/input loops | The reference uses many event connections and render-step bindings; static scan found 178 direct `:Connect(` sites and 110 render/step references | Every listener must be tracked, disconnected on disable, character removal and unload |
| UI integration | Features are installed with a section/context and build controls during installation | Register controls through Liberium's public API; feature modules must not create a second window |
| HTTP/assets | Offline wrapper provides request/HttpGet proxies and local response behavior; TradeValues and catalog/asset modules expect external data | Do not copy wrapper or endpoints blindly; validate source, timeout, cache, failure state and user consent before any external request |
| Executor/runtime | The reference uses executor environment/global adapters and compatibility shims | Isolate optional capabilities behind guarded adapters; feature must fail closed when unsupported |
| Remotes/game authority | Static scan found no literal direct `.FireServer(` or `.InvokeServer(` calls in this artifact | This is not proof that no indirect/dynamic remote path exists. Do not infer server-side authority or copy dynamic remote access without a separate focused audit |

### 7.5 Security, privacy and behavior boundaries

- The offline wrapper in this artifact deliberately replaces or constrains outbound request, WebSocket, dynamic loading and teleport-queue behavior. Those stubs are part of the test copy, not production functionality.
- The farm webhook is optional and user-configured in the source; it must remain opt-in, display its destination/behavior clearly, and never inherit a hard-coded destination.
- The reference includes script-key persistence/re-execution logic around rejoin. It is excluded from the migration plan; preserve only ordinary place/server rejoin behavior without key storage or credential handling.
- Cosmetic inventory changes are client-side presentation. Locally created cosmetic entries are scrubbed from trade inventory rendering in the reference; never represent these as server-owned, tradeable inventory.
- TradeValues is a read-only display candidate. It must not automate trade acceptance, modify offers, or send inventory mutations.
- No direct remote invocation was found by the simple static pattern scan. This is a limited negative finding, not a security certification.

### 7.6 Migration order and acceptance gates

| Order | Candidate | Why this order | Required acceptance |
|---|---|---|---|
| 0 | Stage 1 runtime/visual sign-off | The current UI source is not compiled or device-tested | Luau parse/compile; launch on Delta and Arceus; screenshots at desktop, portrait and landscape; test search, dropdowns, touch and cleanup |
| 1 | TradeValues read-only UI | Bounded surface area; no need to alter movement/combat state | Parse current TradeGUI and inventory UI safely; duplicate item counts; values/totals; no writes to offers or remotes; cache/source failure handled |
| 2 | ESP additions (radar, chams, richer labels/box modes) | Builds on current role/ESP foundation | One render owner; role colors remain correct; no stale drawings/instances after player respawn/leave or disable |
| 3 | Additional farm modes (RoleFarm, BoxFarm) | Reuse current map/session state but isolate from coin AutoFarm | Independent toggles/state machines; no under-map movement; stop on round end, death, bag full and unload |
| 4 | Sheriff/Murderer modules | Highest gameplay coupling and target/role lifecycle | Role gate; target validity; no action before role resolution; all hooks/loops reversible |
| 5 | Visual environment/effects | Mostly reversible local state | Snapshot/restore Lighting, world and character properties; no residue after disable/unload |
| 6 | Cosmetics, animation, audio and optional mobile tools | Asset/runtime-specific and lower priority | Client-only labeling; asset failure fallback; character respawn cleanup; no false inventory/trade claims |
| 7 | Optional social and convenience features | Non-core; external behavior increases maintenance | Explicit opt-in; no hidden requests, messages, webhook or persistence |

**Stage 2 exit criteria met:** both source snapshots were re-fetched/inspected; PulseHub's module groups and composition root were enumerated; current Liberium API/state/cleanup surfaces were mapped; dependencies and risk tiers were documented; migration order and acceptance tests were written.

**Stage 3 remains gated:** no feature code is being inserted into `Keyless` until the user/runtime process supplies a successful Luau parse/launch and matching screenshots for Stage 1. This is deliberate: the audit is complete, but the UI has not yet passed its runtime acceptance gate.
