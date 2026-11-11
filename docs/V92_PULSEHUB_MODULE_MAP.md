# Liberium Hub v92 — PulseHub port map

Status: Stage 1 UI foundation integrated; static validation pending  
Working branch: `v92/pulsehub-port`  
Base: `v92/pulsehub-ui-parity`  
Production entry point remains: `Keyless`  
Runtime targets: Delta Android and Arceus X Android

## Reference inspected

The user-provided `PulseHub.luau.txt` is approximately 12.47 MB and 53,100 lines. The reference is treated as a behavioral and visual specification. Liberium implementations will be written as original modules and will not depend on PulseHub's runtime, hidden offline harness, remote services, or proprietary assets.

## UI architecture identified

The reference has a separate Nova UI system rather than feature-specific menus:

- `NovaUtility`, `NovaMotion`, `NovaRefresh`
- `NovaTheme`, `NovaFont`, `NovaIcons`
- `NovaStore`, `NovaSound`, `NovaTexture`
- `NovaWidgets`, `NovaSection`, `NovaTab`, `NovaWindow`
- `Translation` and `NovaFoundation`

Its navigation hierarchy includes grouped tabs, per-tab descriptions, subtabs, searchable sections, persistent appearance settings, floating/dockable cards, and separate UI/feature state. The v92 UI specification records the 812×584 reference window, 208 px sidebar, 660×420 minimum size, 0.86 initial scale, default Midnight/Crimson tokens, and mobile scaling requirements.

The Liberium UI adapter must preserve the existing feature-facing API where practical:

- `Lib.new(title)`
- `Win:AddTab(name, icon)`
- `Tab:AddSubTab(name)`
- `Sub:AddSection(name)`
- `Section:AddToggle(name, default, callback)`
- `Section:AddSlider(name, min, max, default, callback, increment)`
- `Section:AddDropdown(name, options, default, callback)`
- `Section:AddButton(name, callback)`

Additional controls such as keybinds, color pickers, notes, and notifications will be added behind the same component system as migration requires.

## Reference feature inventory

The source is organized into the following functional systems. Line ranges are from the inspected reference file and are inventory pointers, not copy targets.

| Area | Reference modules | Planned Liberium destination |
|---|---|---|
| UI and navigation | Nova foundation, window, tabs, sections, widgets, theme, motion, fonts, icons, store, sound | `src/ui/` |
| Movement | Noclip, camera noclip, anti-coin, bomb jump, invisibility, spin/bhop, fly, speed, glitch, wall hop, gravity | `src/features/Movement/` |
| Sheriff / aim | Aim calibration, geometry, motion, plans, target selection, timing, aim engine, sheriff runtime, FOV | `src/features/Combat/Sheriff/` |
| Farm | Farm state, movement, runtime, role farm, box farm | `src/features/Farm/` |
| ESP | Settings, text, colors, box, role, projection, labels, lines, tracers, skeleton, head, chams, radar, ghost, feature controller | `src/features/ESP/` |
| Murderer / combat | Murderer actions, knife aim, combat tracers, anti-aim, muzzle guard, fling | `src/features/Combat/Murderer/` and `src/features/Combat/Shared/` |
| Skins / inventory | Skin model/catalog, weapon skins, remote/thrown skins, inventory changer | `src/features/Customization/Skins/` |
| Visual effects | Game effects, aura engine/hat/tint, self chams, walk trails, world, sky, weather, texture packs, sky FX, optimizer, cursor | `src/features/Visuals/` |
| Avatar / animation | Avatar skins, remote avatar skins, animation catalog/runtime | `src/features/Customization/Avatar/` |
| Economy / utility | Trade value counter, teleport, server identity, music/boombox, sound libraries, webhook hooks | `src/features/Economy/`, `src/features/Server/`, `src/features/Audio/` |
| Mobile | Floating touch actions, saved positions, per-button sizing/lock state | `src/ui/mobile/` |
| Social / config | Chat, Pulse-user server listing, configuration browser/sharing | `src/features/Social/` and `src/core/Config/` |

The reference also contains offline filesystem/request/service simulation modules. Those belong to its local diagnostic harness and are not production MM2 features; they will not be carried into Liberium.

## Existing Liberium baseline

The current `Keyless` source on the v92 base is still a single-file v91.70 build. It already contains useful implementations that must be preserved and adapted rather than discarded:

- Core role detection and role-colored player ESP.
- Independent ESP Outline and Fill toggles, name/distance overlays, Skeleton ESP, and candy-only Loot ESP.
- Separate AutoFarm coin collection and gun-only AutoPickup, with AutoFarm priority.
- Farm HUD and active-map/coin/gun readiness states.
- Movement controls, combat prediction/FOV-related helpers, Anti-Fling, session tools, notifications, and local configuration.
- Cleanup on re-execution and bounded startup waits for the local player and PlayerGui.

The older branch named `liberium-v91-89-pulsehub-ui-rebuild` contains a v91.72 Keyless file and archived UI experiments. It diverges substantially from the current `main` and will not be merged wholesale.

## Migration order and acceptance gates

1. **UI foundation — active.** Theme tokens, lifetime cleanup, window shell, grouped navigation, search, subtabs, shared cards/controls, notifications, and mobile layout. Keep the old `Keyless` API stable while replacing its renderer.
2. **Player and Movement.** Port the supported movement controls through feature registration; preserve safe state restoration and executor guards.
3. **ESP and Visuals.** Add box/chams/skeleton/tracers/radar and role/color controls, with shared rendering and cleanup.
4. **Farm.** Add coin, role, and box modes plus session statistics and webhook configuration. Keep coin AutoFarm and weapon AutoPickup as separate behaviors.
5. **Combat.** Add Sheriff aim/FOV tools and Murderer/knife systems as independently switchable modules.
6. **Customization.** Add weapon skins, inventory/animation catalogs, kill effects, auras, cursor and world effects.
7. **Systems.** Add teleport/server browser, trade value counter, audio, config sharing and community features where dependencies and permissions allow.
8. **Integration and verification.** Generate the single-file `Keyless` release, run static syntax/consistency checks, and record what still needs live Delta/Arceus X verification.

A stage is not marked complete until its source, integration path, cleanup behavior, and available static checks are reviewed. No live Roblox runtime success is claimed from static inspection alone.
