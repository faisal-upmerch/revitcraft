# Accessibility

Arcus uses standard AppKit and SwiftUI controls wherever it can, so VoiceOver, Full Keyboard Access, Voice Control and the system display settings work without special handling. This document covers what Arcus adds for its custom surfaces (the 2D canvas and the 3D viewport) and how it follows the system accessibility settings. It also lists what is still limited.

## VoiceOver

| Surface | What VoiceOver gets |
|---|---|
| Command Deck | A "Command Deck" group. Tabs are buttons with a selected trait. Each command button has its title as the label, its help text as the hint, and the reason it is unavailable when it is disabled (for example, "Select a wall first"). The active tool is marked selected. |
| Properties inspector | A "Properties" group. Parameter groups announce whether they are collapsed or expanded. Every field is labelled with the parameter name. Read-only values say "Read only" and why (for example, "Calculated from the model" or "Driven by a formula"). The type selector is labelled "Type: <name>". Edit Type has a hint. |
| Project Browser | Rows read as "<name>, <detail>" (for example, "Ground Floor, on A101") and have an **Open** action. The filter field is labelled. |
| View tabs and view control bar | Tabs are buttons with a selected trait and a labelled close button. View scale, detail level and visual style controls read their current value. |
| 2D canvas (plans, sections, elevations, sheets) | A group labelled with the view kind and name ("Floor Plan: Ground Floor"). Its value is the selection summary plus the active tool and its prompt ("Tool: Wall. Click the start point…"). Selected elements are exposed as children with descriptions and on-screen frames. Custom actions: **Select next element**, **Select previous element**, **Zoom to fit**, plus **Zoom to selection** and **Delete selection** when something is selected. |
| 3D viewport | Its value describes the projection, viewing direction ("viewed from the south-east, above"), element count, selection and visual style. Custom actions: **Orient to Top/Bottom/Front/Back/Left/Right/Isometric** and **Zoom to fit**. The orientation widget is an accessible child. |
| Schedules | A standard `NSTableView`: rows, columns and headers are navigable, and editable cells are text fields. |
| Dialogs | SwiftUI forms with labelled controls. Default and cancel buttons respond to Return and Esc. |

Announcements: results and errors that appear as toasts (for example, "Couldn't place the door: the wall is too short") are also posted as VoiceOver announcements, with high priority for errors. Stepping through elements with `]` and `[` announces each element and its position ("Wall, Basic Wall: Exterior - Brick on CMU, 12 of 431").

## Keyboard-only use

- Every command is in the menu bar, and Command Search (`⌘K`) finds any command by name, alias or keyword.
- Typed aliases (`WA`, `DR`, `DI`…) start tools from the canvas. Coordinates and lengths can be typed: start typing a number while a tool is waiting for a length.
- In the canvas, `]` and `[` select the next or previous element in reading order, `Tab` cycles overlapping candidates, arrow keys nudge (hold `Shift` for larger steps), `Delete` deletes, `Return` finishes and `Esc` cancels.
- The Properties inspector, Project Browser, schedules and dialogs are ordinary focusable controls, so Full Keyboard Access (System Settings → Keyboard → Keyboard navigation) reaches everything.
- See [KeyboardShortcuts.md](KeyboardShortcuts.md) for the full list.

## System settings Arcus follows

| Setting | Effect in Arcus |
|---|---|
| **Reduce Motion** | Panel collapse and expand, onboarding page transitions, toast messages and 3D camera moves (zoom to fit, orient to a view) happen instantly instead of animating. |
| **Reduce Transparency** | Liquid Glass capsules (view control strip, floating controls) become opaque, with a separator outline. |
| **Increase Contrast** | Glass capsules become opaque with outlines. In the 2D canvas, halftoned graphics (underlays, links, other phases) blend much less toward the background, and the minimum stroke is one device pixel. The canvas redraws immediately when the setting changes. |
| **Appearance (light/dark)** | The whole UI follows the system. In dark mode, 2D views draw light ink on a dark canvas. Sheets always stay paper-white, because they represent printed output. Selection and preselection colours have light and dark variants, including high-contrast variants. |
| **Text size** | Panels use system text styles. Drawing text is fixed paper size by design, as in any CAD tool: zoom the canvas to enlarge it. |

## Colour

Selection and preselection use both colour and line weight. Warnings in Model Health use an icon shape (octagon, triangle or circle) that VoiceOver speaks as "error", "warning" or "info", as well as a colour. Plan graphics use line weight and pattern, not colour alone, to show cut versus projection and phases.

## Verification

- The scripted QA workflow (`script/qa_capture.sh`) exercises keyboard element stepping and checks that the canvas exposes the VoiceOver actions. It also captures light and dark screenshots at minimum (980 × 640) and spacious sizes.
- Accessibility labels were reviewed in code for every custom control listed above.

## Known limitations

- The contents of the 2D drawing are not an element-by-element accessibility tree. That would mean thousands of nodes in a typical plan. VoiceOver users instead step through elements with `]` / `[` or the custom actions and read and edit them in the Properties inspector.
- Drawing geometry (for example, sketching a floor boundary) needs pointer input or typed lengths along the current direction. There is no fully keyboard-driven way to enter absolute coordinates yet.
- The Family Editor canvas has the same model as the 2D canvas, but without element stepping.
- A full manual VoiceOver pass by a screen-reader user has not been done. The work so far is code review plus the automated checks above.
