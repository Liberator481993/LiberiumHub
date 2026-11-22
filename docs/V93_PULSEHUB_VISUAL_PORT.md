# LiberiumHub v93 — PulseHub visual-only port

Status: Stage 1 visual port rebased onto current `main`; static/runtime acceptance still pending.
Working branch: `v93/pulsehub-visual-only`
Base: `main`
Entry point: root `Keyless`

## Scope lock

This branch is for the menu's visual system only. It must not introduce, remove, or rewrite gameplay features. The current main branch remains untouched. The older `v92/pulsehub-port` branch is 53 commits behind current main and is not used as the base for this visual-only continuation.

The visual implementation is based on the user's supplied PulseHub source as a behavioral and layout reference. It is independently implemented in Liberium's existing Luau UI; it does not load PulseHub at runtime or copy its hidden offline harness, network hooks, proprietary assets, or script-key persistence logic.

## Stage 1 — PulseHub visual parity

Reference measurements:
- Main window: 812 × 584
- Initial scale: 0.86
- Sidebar: 208 px
- Minimum desktop size: 660 × 420
- Default compact palette: Midnight / Crimson
- Reference surfaces: Background #0C0D10, Sidebar #0F1014, Surface #14161B, Surface2 #1B1E25
- Accent: Crimson #D64458; logo glow: Orange #FF7A1A

Required visual areas:
1. Floating rounded window, brand header, title/subtitle, version/status footer.
2. Persistent grouped sidebar, search, selected-tab state, collapsible groups and subtabs.
3. Main content header and consistent cards/sections.
4. Shared Toggle, Slider, Dropdown, Button and Keybind visual language.
5. Consistent hover/pressed/selection animations and notifications.
6. Responsive mobile scaling, touch-sized controls, safe dragging and independent scrolling.
7. Theme/appearance options and persistent preferences, only where they can be implemented without changing gameplay behavior.

### Stage 1 acceptance gates

- [ ] 812 × 584 / 0.86 desktop proportions and 208 px sidebar verified.
- [ ] Navigation groups, search, selection and subtabs verified.
- [ ] Toggle, slider, dropdown, button and keybind visuals/interactions verified.
- [ ] Dropdowns open in the correct direction and remain inside the viewport.
- [ ] Portrait and landscape Android layouts verified; no clipped controls or overlapping scroll areas.
- [ ] Dragging does not block touch controls; window can hide/show and clean up without duplicates.
- [ ] Visual comparison against PulseHub screenshots completed.
- [ ] Static source validation completed.
- [ ] Live Arceus X and Delta device tests completed.

No stage is considered visually complete until its applicable acceptance gates pass. Static source inspection is not a substitute for executor testing.

## Historical v92 roadmap (not active in this visual-only branch)

The previous full port plan had eight stages:
1. UI Foundation.
2. Movement extensions.
3. ESP and Visuals.
4. Farm.
5. Combat.
6. Skins, Animations and Effects.
7. Teleport, Server, Trade, Audio and Social systems.
8. Release integration and final verification.

For this continuation, stages 2–8 are explicitly out of scope. The user requested visual menu work only. Do not start feature migration until the user changes that scope.
