# UI audit (wave 4)

How the shell, dialogs and workflows were inspected screen by screen, what was wrong, and what was done. The captures
come from `script/qa_capture.sh screenshots <out>`; the audit extension in `Arcus/UI/Shell/QAHarness+Audit.swift`
(W4-AUDIT) adds to the base scenario:

- every `DialogKind` (`Arcus/UI/Shell/DocumentState.swift`) with representative data from the Courtyard House sample;
  fixture files (DXF, PDF, IFC, CSV, PNG, point CSV) are written under `<out>/fixtures`, and `Sample.rvt` is deliberately
  absent so the Revit-file dialog shows its unavailable path;
- Settings (top, middle, bottom of the scroll so every section appears), the hub's New tab (Recent was already captured),
  onboarding;
- the main window in both workspaces (BIM Familiar, Mac Spacious) at 980, 1280 and 1920 pt: plain plan, a wall selected
  (Properties filled), the Wall tool active (Options Bar and contextual tab);
- the Family Editor for the first door family and a tag family.

Everything is captured in light and dark. The run used for this audit produced 236 captures (`build/qa-audit1`); the
screenshots scenario passed 6/6 steps. The interaction scenario gained four steps (`QAInteraction+Audit.swift`) that
open every dialog, check it fits inside the window and closes with Escape, and drive the Revit-feel behaviours below.

## Review checklist

Legend: **Fixed** (this wave, W4-AUDIT), **Reported** (belongs to another engineer: SHELL = DialogFrame,
DocumentWindowController, Ribbon.swift, sidebar; FAMED = Family Editor; HATCH = fill patterns), **Deferred** (logged in
Docs/RevitParity.md open items), **OK** (reviewed, nothing wrong).

| # | Capture(s) | Defect | Resolution |
|---|---|---|---|
| 1 | materials-dialog-light/dark (owner screenshot 11) | Material name field clipped at the top: the 20 pt semibold plain text field inherited a body-height frame | Fixed: `MaterialsUI.swift` `MaterialDetail` name field gets `.frame(height: 30)` |
| 2 | onboarding-light/dark | The four feature captions sit on different baselines because the SF Symbols differ in height | Fixed: `HubAndOnboarding.swift` `feature()` puts the icon in a fixed 30 pt box |
| 3 | new-view-*-dialog | When every level already has a view, the explanation is followed by an empty 160 pt list | Fixed: `ViewDialogs.swift` `NewViewDialog` shows the text alone |
| 4 | override-graphics-dialog | The grouped form grew to the full window height; Reset / OK were pushed to the window's edge | Fixed: form height capped at 560 pt (scrolls) |
| 5 | audit-*-980-* | Status bar: "No warnings" wrapped to "N / o" at 980 pt; the prompt should truncate instead | Fixed: `ContentArea.swift` `StatusBarView` warnings label `.lineLimit(1).fixedSize()` |
| 6 | import-dxf-dialog (during read) | Progress placeholder (160 pt) is much shorter than the loaded layout, so the sheet jumps in size after reading | Fixed: placeholder min height 280 pt (`ExchangeDialogs.swift`) |
| 7 | import-revit-dialog | Subtitle stayed "Reading the file…" after the inspection failed | Fixed: `RevitImportDialog.swift` subtitle switches to "The file could not be inspected." |
| 8 | phases, revisions, design-options, manage-links, materials, model-health, report, keyboard-shortcuts, warnings, snaps, dwg-unavailable | Dialogs with only a Done button did not close with Escape (no `.cancelAction` button) | Fixed: `DialogHost.swift` `.onExitCommand { state.presented = nil }`; the interaction step verifies every dialog closes with Escape |
| 9 | project-parameters-dialog | Empty parameter list is an unexplained blank area with no border | Fixed: empty-state text, background and border (`ManageDialogs.swift`) |
| 10 | manage-links-dialog | Empty table shows only striped blank rows | Fixed: empty-state overlay (`ExchangeDialogs.swift`) |
| 11 | design-options-dialog | Empty list is a 220 pt blank area | Fixed: empty-state overlay (`ManageDialogs.swift`) |
| 12 | audit-familiar-walltool-980, audit-spacious-walltool-980 | Options Bar at 980 pt: "Offset" and "Join Status" labels wrap letter by letter ("Of/fs/et"), and the bar overflows the canvas to the right | Reported → SHELL (`Ribbon.swift` `OptionControl` label needs `.lineLimit(1).fixedSize()`; the bar needs to collapse or scroll under ~1100 pt) |
| 13 | audit-*-980-* | At 980 pt the ribbon tabs are hidden behind the toolbar's » overflow; only panels show, so the user cannot switch tabs | Reported → SHELL (DocumentWindowController toolbar) |
| 14 | audit-spacious-wall-980-dark | Mac Spacious inspector at 980 pt: pickers truncate ("Wall Cent…", "Ground Fl…", "New Cons…") while the label column keeps 60 % of the width | Reported → SHELL (sidebar/inspector column split); Properties itself is BL-PROPS |
| 15 | audit-spacious-walltool-1920-dark | Properties pickers truncate ("Wall Cent…") even at 1920 pt because the inspector width is fixed | Reported → SHELL |
| 16 | family-editor-door-*, family-editor-tag-* | "Instance" toggle label wraps to "In-/stanc/e"; header "Door - Sin…" and "Load int…" truncate; preview label "Center (Left/Right)" clipped at the right edge ("Ce") | Reported → FAMED |
| 17 | additional-settings-fill-patterns-dialog | Reviewed: no clipping; the pattern preview column is narrow but readable | OK (HATCH owns further changes) |
| 18 | schedule-properties-tab1..4 | Sorting/Grouping and Appearance tabs leave 60 % of the sheet empty (fixed 540 pt height for the Fields tab) | Deferred: size per tab (small visual cost) |
| 19 | color-schemes-dialog | OK; the legend variant identical | OK |
| 20 | type-properties-dialog, type-properties-family-dialog | OK; Width field focused with a ring on open (matches first-field focus) | OK |
| 21 | settings-top/middle/bottom | Every section visible; nothing clipped | OK |
| 22 | hub-light/dark, hub-new-* | OK | OK |
| 23 | plan/wall/sketch/schedule/sheet/section/elevation/3d, command-search, error-toast | OK in both appearances | OK |
| 24 | keyboard-shortcuts, snaps, purge, paste-to-levels, filter-selection, select-by-category, select-by-id, warnings, object-styles, filters, view-templates-*, view-range, place-view, sheet-title, rename, new-sheet, new-schedule-*, csv-import, tag-all, find-replace, check-spelling, site-*, link-pdf/image, import-ifc/dxf/dwg, location, project-info/units, phases, revisions, new-family, new-area-plan, user-interface, additional-settings-* | Reviewed; layout, paddings, default buttons and content sizing are consistent | OK |

Tally: 236 captures reviewed (118 states × light/dark); 18 defects found; 11 fixed; 5 reported to other engineers
(4 SHELL, 1 FAMED); 1 deferred; 1 noted OK for HATCH.

## Revit-feel sweep

Driven through `QAInteraction+Audit.swift` and the existing interaction steps (all of which still pass), compared with
the reference tool's public help for each workflow:

| Workflow | Verified on screen | Deviation → action |
|---|---|---|
| Walls: chain, Options Bar (Height/Depth, Location Line, Chain, Offset, Radius, Join Status), Space flips side, typed length | Yes: WA, clicks, Space toggles `flipSide` with a message, a typed `3000` opens the listening field and Return creates a 3 m wall | None found (prompts already name Space and Esc) |
| Doors/windows: hosting, Space (facing) and Shift+Space (hand), temp dims | Yes (interaction step) | None found |
| Floors: sketch mode, halftone, Finish | Existing BL-CANVAS step holds | — |
| Rooms + tags, dimensions (aligned, grips, EQ), text | Existing steps hold (D43–D49 work verified) | — |
| Select: window (fully enclosed) vs crossing (touched, dashed), Tab cycle, two-stage Esc, filter | Yes: window over the wall middle selects 0, crossing selects it; Tab changes the pre-selection; Esc clears | None found |
| Move/copy/rotate/mirror/array/align/trim/split/offset, grips, pinned | Existing steps hold | Prompts match the reference's "Click … or type" phrasing |
| Views (section/elevation/callout), sheets/viewports, schedules, undo/redo | Existing steps hold | — |
| Dialogs: default button, Escape | All 87 dialog states close with Escape; every one fits inside a 1500×940 window | Fixed (#8) |

Larger gaps are logged under "Open items (wave 4 audit)" in Docs/RevitParity.md.
