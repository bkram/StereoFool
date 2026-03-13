# StereoFool macOS HIG plan

## Goals

- Make the app feel like a real native macOS utility.
- Keep all current DSP, routing, monitoring, and RDS functionality.
- Remove UI patterns that feel custom, iPad-like, or non-HIG.

## Priority 1: Window and app behavior

- Keep title bars clean: no buttons or custom controls in the title bar or toolbar.
- Make close, reopen, minimize, and dock-click behavior match standard macOS app behavior.
- Stop using toggle-style window menu actions that close a window when it is already frontmost.
- Ensure auxiliary windows (`Scopes`, `Spectrum`, `Levels`, `Help`) behave like normal utility/document windows.
- Review main-window lifecycle to avoid AppKit/SwiftUI teardown crashes.

## Priority 2: Standard macOS menu bar

- Add a proper `Edit` menu with standard text editing commands so text fields behave correctly.
- Rework the current custom menus so command placement feels native.
- Keep app-specific actions, but rename and group them like a normal macOS utility.
- Make menu item labels and enabled states reflect current app state (`Start` vs `Stop`, bypass state, pending apply state).
- Use standard About, Settings, Window, and Help behaviors where possible.

## Priority 3: Main window layout

- Keep the fixed sidebar with `HSplitView`, but make it feel less custom and more native.
- Reduce decorative chrome and rely more on standard macOS spacing, alignment, and materials.
- Simplify the large detail header so sections feel like native panes instead of a custom dashboard shell.
- Review sidebar width, resizing, and persistence.
- Remove redundant icons or overly literal audio symbolism where it does not add value.

## Priority 4: Monitoring screen

- Keep Monitoring as the most dashboard-like area, but make it calmer and more Mac-like.
- Merge or simplify cards where useful to reduce visual fragmentation.
- Use clearer hierarchy for status, transport, interfaces, DSP, RDS, levels, and scopes.
- Make action placement consistent with macOS utility apps.
- Check whether meters, scopes, and analyzer visuals can use subtler native-adjacent styling.

## Priority 5: Configuration screens

- Convert configuration-heavy sections (`System`, `Interfaces`, `Processing`, `RDS`) toward grouped forms.
- Use `Form`, `LabeledContent`, standard control widths, and more aligned labels.
- Reserve cards for summary/monitoring views rather than dense editing surfaces.
- Reduce full-width segmented controls when the number of segments gets large.
- Consider Mac-style subsection navigation for `Processing` and `RDS` instead of wide segmented pickers.

## Priority 6: Standard app surfaces

- Replace custom About handling with the standard macOS About panel if possible.
- Move Settings toward a more standard app settings window pattern.
- Make Help feel like a standard macOS help/documentation surface.
- Review alerts, sheets, and file dialogs for native wording and placement.

## Priority 7: Visual refinement

- Use standard macOS control sizing and spacing throughout.
- Keep card radius and spacing consistent with project guidance.
- Tone down visual elements that feel too branded, too literal, or too heavy.
- Prefer clarity and restraint over dashboard-style emphasis.
- Make sure all screens still feel coherent with the app's technical purpose.

## Implementation notes

- Primary file: `macOS/Sources/StereoFool/SwiftUIControlApp.swift`
- Preserve all audio, DSP, monitoring, and RDS features while changing presentation.
- Follow `AGENTS.md` rules:
  - no buttons in the title bar
  - use native macOS window chrome
  - prefer `HSplitView` when sidebar collapse is not needed
  - use standard macOS form/button/picker styles

## Suggested order of work

1. Fix window lifecycle and native close/reopen behavior.
2. Normalize menus and standard app commands.
3. Refine main window shell and sidebar/detail structure.
4. Convert editing-heavy screens to more native forms.
5. Refine Monitoring visuals and hierarchy.
6. Standardize About/Settings/Help surfaces.
7. Do final polish pass for spacing, labels, and macOS consistency.
