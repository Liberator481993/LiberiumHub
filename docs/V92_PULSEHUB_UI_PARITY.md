# LiberiumHub v92 — PulseHub UI Parity Specification

Status: Stage 1 / initial UI shell implemented in working branch; static verification only  
Target branch: `v92/pulsehub-ui-parity`  
Reference artifact: user-provided `PulseHub.luau.txt`  
Current integration baseline: `Keyless` on `main` (v91.70)

## Goal

Make the LiberiumHub interface visually as close as practicable to the supplied PulseHub reference. UI parity is the first milestone; feature modules must not dictate or distort the layout.

This is an independent implementation specification. Rebuild the visual system and interaction patterns in LiberiumHub's own code. Do not transplant third-party closed modules, proprietary assets, or large source sections without confirming permission and license compatibility.

## Reference measurements and settings found in the supplied source

- Window title: Pulse Hub
- Subtitle: Murder Mystery 2
- Footer version text: v1.1
- Initial window size: 812 × 584
- Initial UI scale: 0.86
- Sidebar width: 208 px
- Density: Compact
- Search placeholder: Search
- Blur: disabled in the initial window options
- Initial keybind: LeftControl
- Minimum window size in the Nova window implementation: 660 × 420
- Saved appearance defaults also include: sidebar width 199 px, scale 0.74, opacity 0.66, radius 0.45, text scale 1.12, auto-fit enabled, motion enabled, tooltips enabled, font Roboto, density Comfortable, and saved size 676 × 585.

Note: the source has both initial constructor values and persisted appearance defaults. The implementation must preserve this distinction rather than silently treating them as one set of values.

## Visual identity

### Main structure

1. Floating rounded main window.
2. Persistent left sidebar with brand/logo area, search, grouped navigation, and selected-tab state.
3. Main content region to the right with tab title/description and vertically arranged sections/cards.
4. Compact controls with consistent alignment and spacing.
5. Responsive scaling and scrolling for narrow mobile screens.

### Reference palette

The reference includes multiple selectable base palettes. Its default theme tokens are:

| Token | Hex |
|---|---|
| Background | #0C0D10 |
| Sidebar | #0F1014 |
| Surface | #14161B |
| Surface2 | #1B1E25 |
| Elevated | #22252D |
| Line | #1F2229 |
| Text | #ECEEF3 |
| Muted | #8A8F9E |
| Faint | #575C69 |
| Accent / Crimson | #D64458 |
| Success | #3DDC97 |
| Warning | #F5B94A |
| Danger | #F0506E |

The window constructor also uses an orange logo glow (#FF7A1A). The saved appearance defaults specify the Halloween base and orange accent (#FF7A1A), while the theme module's raw initial tokens start at Midnight/Crimson. Preserve these as separate defaults/configuration layers.

### Supported appearance settings to reproduce

- Base theme and accent presets
- Panel color and opacity
- Card style (including Frosted)
- Density (Compact / Comfortable)
- Sidebar width and collapsed state
- UI scale and text scale
- Corner radius
- Font family
- Motion and hover transitions
- Tooltips and sounds
- Search and grouped navigation
- Persisted tab order and collapsed sections

## Controls and interaction language

Implement one shared component system for:
- Toggle rows with clear ON/OFF states
- Sliders with current numeric value
- Dropdowns with selected-item marker and scrollable options
- Searchable selectors where appropriate
- Buttons with hover/pressed feedback
- Section headers, descriptions, badges, and compact cards
- Notifications/toasts
- Keybind capture
- Expandable/collapsible groups and subtabs

All controls must use consistent heights, padding, corner radii, typography, focus/selection states, and touch behavior. Avoid tiny mobile tap targets.

## Mobile requirements

- Keep the same visual hierarchy as desktop.
- Scale the window to the available viewport without clipping.
- Ensure the sidebar can collapse or switch to a compact navigation mode.
- Make all controls touch-friendly.
- Prevent dropdowns and search results from rendering off-screen.
- Ensure scroll areas have independent, predictable scrolling.
- Support safe repositioning and dragging without blocking gameplay controls.

## Architecture requirements

- Separate the UI shell from MM2 feature modules.
- Keep a single source of truth for theme tokens and component styles.
- Feature modules register controls through the shared component API.
- UI initialization must be safe if the player GUI is not ready immediately.
- Cleanup must remove prior UI instances, connections, and temporary effects.
- Avoid loading a third-party UI framework at runtime as a hidden dependency.
- Keep executor-specific compatibility checks isolated from the visual layer.

## Stage 1 acceptance checklist

- [ ] Main window proportions match the reference (812 × 584 baseline, scale 0.86).
- [ ] Sidebar width, grouping, search placement, and selected state match.
- [ ] Brand header, logo treatment, title/subtitle/footer hierarchy match.
- [ ] Background/surface/line/text/accent palette matches the selected reference preset.
- [ ] Cards, section headers, toggles, sliders, dropdowns, and buttons share the same visual language.
- [ ] Animations and hover/pressed states are consistent.
- [ ] Sidebar collapse, search, tab selection, and subtabs work.
- [ ] Mobile scaling and touch interactions work on Android.
- [ ] No clipping, overlap, or inaccessible dropdowns at narrow viewport sizes.
- [ ] UI can be closed/reopened and cleaned up without duplicate instances.
- [ ] Visual comparison screenshots have been checked at matching viewport sizes.

## Required next inputs for visual sign-off

A screenshot of the actual PulseHub menu in its normal state and one screenshot showing a tab with several different control types are the strongest visual acceptance references. The source file provides dimensions, theme values, and component behavior, but screenshots are still needed to verify pixel-level spacing and appearance.

## Implementation order

1. Build the UI shell and layout.
2. Recreate navigation, search, groups, and subtabs.
3. Recreate shared control components.
4. Add responsive/mobile behavior.
5. Compare screenshots and tune dimensions/colors/spacing.
6. Only after UI sign-off, migrate feature modules into the shared component system.


## Current implementation checkpoint (v92.0)

The UI shell now includes collapsible sidebar groups and collapsible feature sections. Searching tab, subtab, or group names temporarily reveals matching tabs even when their group is collapsed. Section controls (toggles, sliders, buttons, and dropdowns) are parented to a dedicated section body so the heading can collapse them together. Responsive sizing now uses separate design canvases for touch portrait (420 × 620), touch landscape (760 × 420), and desktop (812 × 584), with corresponding sidebar widths of 116, 176, and 208 px. This is intended to reduce unnecessary downscaling on phones while retaining the same navigation hierarchy. Existing gameplay feature logic and the public UI control API were preserved. The latest changes were fetched back from GitHub and statically inspected for the new hierarchy, control parenting, and viewport sizing branches. They have not been compiled or executed in Roblox, Delta, or Arceus X, so runtime behavior, actual touch target sizes, and visual parity remain unverified. The acceptance checklist below remains open.

See `docs/V92_PULSEHUB_MIGRATION_AUDIT.md` for the full feature map and migration order.
