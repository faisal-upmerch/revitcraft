# Dialogs

Every modal in Arcus uses one dialog design system (`Arcus/UI/Shell/Dialogs/DesignSystem/`) so sheets look and behave
like a first-party Mac app (System Settings, Xcode sheets). This page is the guideline for new dialogs, followed by the
inventory of every dialog and its status.

## Dialog guidelines

**Container.** Build a modal with `ArcusDialog` (or `DialogFrame` / `DialogFrameWithActions` for a document sheet:
Cancel and Escape set `state.presented = nil`). It draws, top to bottom:

- **Header**: an SF Symbol on a tinted rounded tile (`icon`, `tint`), the title in `.title3` semibold, and one line of
  subtitle in secondary. For imports and links pass `file:` and the header shows the file's Finder icon; put the file
  name (and size, `DialogFileInfo.sizeSuffix`) in the subtitle. Keep Revit's dialog titles.
- **Content**: 20 pt from the edges, sections 16 pt apart (8 pt grid).
- **Footer**: a full-width separator; secondary actions on the left (`leading:` — Copy Report, Check All / None,
  Import…, Help); on the right extra buttons (`trailing:` — Apply), Cancel (Esc) and the default button (Return,
  accent-coloured). When the default button is disabled pass `disabledReason`: it shows inline when the footer has no
  secondary actions and always as the button's help tag. Editors whose fields take Return use
  `.okKeyboardShortcut(⌘Return)` or `.returnKeyEnabled(false)` while a field is focused.

**Size.** Pick a class, never a fixed frame: `.small` 420, `.medium` 560 (default), `.large` 720, `.wide` 900,
`.extraWide` 1120 (tables with many columns). The dialog is as tall as its content; long forms pass `scrolls: true`
(the content grows up to the class's maximum, then scrolls). Window-like editors (Materials, V/G, Type Properties)
pass `height:` and let their panes fill it. Tabbed dialogs let each tab size itself, as Settings panes do.

**Sections and rows.** Group controls in `DialogSection("Title", footnote:)` boxes. Inside, use
`DialogRow("Label") { control }`: labels sit in one column whose width the dialog sets (`labelWidth`), so every control
starts on the same line. Hide control labels (`.labelsHidden()`), size pop-ups to their content (`.fixedSize()`), put
units after fields in secondary, use `PillSegmented` for two to four choices (see Pills and selection). Read-only facts are
`DialogValueRow`. Explanations go in a section's footnote, not in loose caption text. `boxed: false` gives a list its
title and accessory (Check All / None, Include views) without a second box around it.

**Lists.** `DialogCheckList` for checkboxes (counts on the right, "N of M checked" under it), `DialogListBox` around a
`List`/`Table`, `DialogPane` for the panes of a master-detail dialog (+ / − bar at the bottom), `DialogListRow` for
rows with an icon, title and secondary line. Lists hug their rows (no blank area under two items) up to a maximum,
then scroll.

**Empty states.** Every list has one, inside its box: `DialogEmptyState(icon:title:message:)`, at most one action;
`illustrated: true` for a master list that is the whole dialog (Design Options).

**Notices.** Explanations, warnings and errors are `DialogNotice(.info | .success | .warning | .error, title:, message,
detail:)` — never raw coloured paragraphs. Long help goes in `detail:` behind "Learn more". Show errors with
`DialogErrorText.describe(error)`, never `"\(error)"` (no `Error Domain=…` dumps).

**Reports.** Results use `DialogSummaryTiles` (counts by severity, click to filter), `DialogIssueList` (grouped by
severity with Show / Select per row) and `DialogReportText` (headings, paragraphs and bullet rows in the system font).
Copy Report goes in the footer.

**Opaque.** Sheets never show the canvas through them: `DialogHost` applies `.opaqueDialogBackground()` (window
background plus `presentationBackground`), and so must any other `.sheet` content and NSPanel sheet.

**Colours and radii.** Use `DialogColors` (section fill, stroke, row dividers) and `Tokens.radiusSection`,
`radiusTile`, `radiusCard`; all are dynamic, light and dark.

**Render check.** Add the dialog to `QAHarness.dialogCatalog` (the test `DialogDesignTests` fails when a `DialogKind`
is missing). `swift test --filter DialogRenderTests` renders every dialog at its sheet size, light and dark, to
`/tmp/arcus-dialogs/` with 2 × 2 review sheets (`_sheet-light-NN.png`); `ARCUS_DIALOG=name,name` renders only those.
Read the PNGs before you finish: no clipping, truncation, misalignment or empty areas. (Offscreen the test process is
not the active app, so default buttons draw grey; in a sheet they are accent-coloured.)

## Pills and selection

One spec for every selected or hovered capsule in Arcus: tabs, segmented controls, chips, toggles and selected rows
(`PillSpec` in `UI/Shell/DesignTokens.swift`; the parts in `UI/Shell/PillControls.swift`).

| Rule | Value |
| --- | --- |
| Inset of a selected capsule inside its glass pill or container, all round | `PillSpec.inset` = 4 pt (segmented tracks: `trackInset` = 3 pt) |
| Side padding between a capsule's edge and its text or icon | `PillSpec.padding` = 12 pt each side; before a close button `closePadding` = 8 pt (its 16 pt circle brings the ✕ to 12 pt) |
| Selected list rows | `rowPadding` = 12 pt each side, rounded, inset from the list's edge |
| Heights | 36 pt shell pills → 28 pt capsules (ribbon tabs, controls, bottom bar); 30 pt view-tab pill → 22 pt; segmented 24 / 26 / 30 pt tracks |
| Corners | Capsule inside capsule; a rounded selection's radius = container radius − inset (`PillSpec.radius(inside:)`); cards concentric with the thumbnail they hold |
| Gap between neighbouring capsules | `PillSpec.gap` = 2 pt (ribbon tabs touch: their padding spaces the titles) |
| Fills | Hover `primary` 7 %; selected neutral `primary` 11 %; tinted 20 % with a 50 % edge (active view tab, contextual tab, "on" toggle); segments raised (white with a soft shadow; 17 % white in dark) |

- Use `.pillHighlight(selected, style)` on the padded content, then `.padding(PillSpec.inset)` inside the pill: hover
  and selection share the shape, so nothing jumps.
- Use `PillSegmented(selection:, [(value, "Title")])` instead of `Picker(...).pickerStyle(.segmented)`, in dialogs and in
  the shell alike (`size: .small` in the Options Bar and panels, `.large` on Home, `fill: true` across a pane).
- Bottom pill items are 28 pt capsules (`barMenuItem()` for menus); icon buttons in the controls pill are 32 × 28 pt.
- Content that a state change swaps (the ribbon's panels, the status prompt, the Options Bar) never cross-fades:
  `instantContent(_:key:)` switches it in one frame while the pills around it may slide. The contextual tab switches
  in the same update as the tool (`DocumentState.setTool`), never from an `onChange` a frame later.
- Render-check: `swift test --filter PILLSUITests` writes every pill to `/tmp/arcus-pills/` (light on glass, dark on
  the opaque surface); zoom into the selected state and check the inset and padding by eye.

## Inventory

Every dialog presented by `DialogHost` (and its sub-hosts), plus the nested sheets. All are on the design system and
render-checked light and dark. System panels (open/save panels, `NSAlert` prompts, the print panel) are AppKit's own and
already first-party; the Settings window and Home are windows, not modals.

| Dialog | File (`Arcus/UI/`) | Size | Status |
|---|---|---|---|
| AdditionalSettingsDialog | `Shell/Dialogs/ManageSettingsDialogs.swift` | wide | Done |
| AddToSetDialog | `Shell/Dialogs/F11ManageDialogs.swift` | medium | Done |
| AssociateFamilyParameterDialog | `Shell/Dialogs/FMG4AssociateDialog.swift` | medium | Done |
| CategoryPickDialog | `Shell/Dialogs/ViewDialogs.swift` | medium | Done |
| CheckPartsDialog | `Shell/Dialogs/FurnitureFabricationDialogs.swift` | large | Done |
| CheckSpellingDialog | `Shell/Dialogs/AnnotationDialogs.swift` | medium | Done |
| ClaudeSetupView | `Claude/ClaudeSetupView.swift` | own layout | Opaque sheet background added; its layout is the MCP batch's design |
| CNCExportDialog | `Shell/Dialogs/FurnitureFabricationDialogs.swift` | wide | Done |
| ColorSchemesDialog | `Shell/Dialogs/RoomAnnotationDialogs.swift` | wide | Done |
| CombineParametersDialog | `Shell/Dialogs/F12ScheduleDialogs.swift` | wide | Done |
| ComponentActionDialog | `Library/Components/ComponentDialogs.swift` | medium | Done |
| ComponentAssemblyDialog | `Library/Components/ComponentDialogs.swift` | large | Done |
| ComponentLibraryView | `Library/ComponentLibraryView.swift` | browser 1120 | Done (own browser layout; header tile, footer and opaque sheet aligned) |
| ConnectLevelsDialog | `Shell/Dialogs/F2Dialogs.swift` | small | Done |
| CSVImportDialog | `Shell/Dialogs/ScheduleDialogs.swift` | large | Done |
| DecalTypesDialog | `Shell/Dialogs/F67InsertDialogs.swift` | large | Done |
| DesignOptionsDialog | `Shell/Dialogs/ManageDialogs.swift` | large | Done |
| DWFMarkupDialog | `Shell/Dialogs/F67InsertDialogs.swift` | medium | Done |
| DWGUnavailableDialog | `Shell/Dialogs/ManageDialogs.swift` | large | Done |
| ExportDWFxDialog | `Shell/Dialogs/F13ExportDialogs.swift` | medium | Done |
| ExportDWGDialog | `Shell/Dialogs/DWGExportDialog.swift` | medium | Done |
| ExportIFCDialog | `Shell/Dialogs/ExchangeDialogs.swift` | medium | Done |
| ExportPDFDialog | `Shell/Dialogs/ExchangeDialogs.swift` | wide | Done |
| FamilyCategoryDialog | `FamilyEditor/FamilyTypesPane.swift` | medium | Done |
| FamilyTypesDialog | `FamilyEditor/FamilyTypesPane.swift` | extraWide | Done |
| FamilyWorkPlaneDialog | `FamilyEditor/FamilyEditorShell+F1415.swift` | medium | Done |
| FillPatternEditor | `Shell/Dialogs/FillPatternsUI.swift` | large | Done |
| FiltersDialog | `Shell/Dialogs/FiltersDialog.swift` | wide | Done |
| FindReplaceDialog | `Shell/Dialogs/AnnotationDialogs.swift` | large | Done |
| FurnitureCategoryDialog | `Shell/Dialogs/FurnitureDialogs.swift` | medium | Done |
| FurnitureFlexDialog | `Shell/Dialogs/FurnitureDialogs.swift` | medium | Done |
| FurnitureJointRulesDialog | `Shell/Dialogs/FurnitureJointRulesDialog.swift` | extraWide | Done |
| FurnitureLibraryBrowser | `Library/FurnitureLibraryBrowser.swift` | browser 1120 | Done (own browser layout; header tile, footer and opaque sheet aligned) |
| FurnitureLoadDialog | `Shell/Dialogs/FurnitureDialogs.swift` | medium | Done |
| FurnitureTypesDialog | `Shell/Dialogs/FurnitureDialogs.swift` | wide | Done |
| GlobalParametersDialog | `Shell/Dialogs/F11ManageDialogs.swift` | large | Done |
| GuideGridDialog | `Shell/Dialogs/PresentationDialogs.swift` | small | Done |
| HardwareCatalogDialog | `Shell/Dialogs/FurnitureFabricationDialogs.swift` | wide | Done |
| HardwareRulesDialog | `Library/Components/ComponentDialogs.swift` | wide | Done |
| ImportCADDialog | `Shell/Dialogs/ExchangeDialogs.swift` | large | Done |
| ImportIFCDialog | `Shell/Dialogs/ExchangeDialogs.swift` | medium | Done |
| ImportPDFDialog | `Shell/Dialogs/F67InsertDialogs.swift` | medium | Done |
| InsertFromFileDialog | `Shell/Dialogs/F67InsertDialogs.swift` | medium | Done |
| KeyboardShortcutsDialog | `Shell/Dialogs/KeyboardShortcutsDialog.swift` | large | Done |
| KeynotingSettingsDialog | `Shell/Dialogs/F11ManageDialogs.swift` | medium | Done |
| LineStylesDialog | `Shell/Dialogs/LineStylesDialog.swift` | large | Done |
| LocationDialog | `Shell/Dialogs/ManageDialogs.swift` | wide | Done |
| ManageLinksDialog | `Shell/Dialogs/ExchangeDialogs.swift` | large | Done |
| MaterialLibraryPicker | `Shell/Dialogs/MaterialLibraryPicker.swift` | large | Done |
| MaterialsDialog | `Shell/Dialogs/MaterialsUI.swift` | wide | Done |
| ModelHealthDialog | `Shell/Dialogs/ManageDialogs.swift` | large | Done |
| ModelInPlaceDialog | `Shell/Dialogs/F5MassingDialogs.swift` | small | Done |
| NewAreaPlanDialog | `Shell/Dialogs/RoomAnnotationDialogs.swift` | medium | Done |
| NewFamilyDialog | `Shell/Dialogs/ManageDialogs.swift` | small | Done |
| NewScheduleDialog | `Shell/Dialogs/ScheduleDialogs.swift` | small | Done |
| NewSheetDialog | `Shell/Dialogs/ViewDialogs.swift` | medium | Done |
| NewViewDialog | `Shell/Dialogs/ViewDialogs.swift` | medium | Done |
| ObjectStylesDialog | `Shell/Dialogs/ManageSettingsDialogs.swift` | extraWide | Done |
| OverrideGraphicsDialog | `Shell/Dialogs/ViewDialogs.swift` | large | Done |
| PasteToLevelsDialog | `Shell/Dialogs/ViewDialogs.swift` | medium | Done |
| PhasesDialog | `Shell/Dialogs/ManageDialogs.swift` | medium | Done |
| PlaceViewDialog | `Shell/Dialogs/ProjectBrowserDialogs.swift` | medium | Done |
| PointFileDialog | `Shell/Dialogs/SiteDialogs.swift` | medium | Done |
| PointLinkDialog | `Shell/Dialogs/F67InsertDialogs.swift` | medium | Done |
| PrintPreviewDialog | `Shell/Dialogs/F13ExportDialogs.swift` | wide | Done |
| PrintSetupDialog | `Shell/Dialogs/F13ExportDialogs.swift` | medium | Done |
| ProjectInfoDialog | `Shell/Dialogs/ManageDialogs.swift` | medium | Done |
| ProjectParametersDialog | `Shell/Dialogs/ManageDialogs.swift` | large | Done |
| ProjectTurnDialog | `Shell/Dialogs/F11ManageDialogs.swift` | small | Done |
| ProjectUnitsDialog | `Shell/Dialogs/ManageDialogs.swift` | medium | Done |
| PurgeDialog | `Shell/Dialogs/ManageDialogs.swift` | medium | Done |
| RebarCoverDialog | `Shell/Dialogs/StructuralDialogs.swift` | small | Done |
| RenameDialog | `Shell/Dialogs/ViewDialogs.swift` | small | Done |
| RenderGalleryDialog | `Shell/Dialogs/PresentationDialogs.swift` | medium | Done |
| RenderingDialog | `Shell/Dialogs/PresentationDialogs.swift` | wide | Done |
| ReportDialog | `Shell/Dialogs/ManageDialogs.swift` | medium | Done |
| RevisionsDialog | `Shell/Dialogs/ManageDialogs.swift` | large | Done |
| RevitImportDialog | `Shell/Dialogs/RevitImportDialog.swift` | medium | Done |
| SaveComponentPresetDialog | `Library/Components/ComponentDialogs.swift` | small | Done |
| SaveFurnitureTemplateDialog | `Shell/Dialogs/FM8Dialogs.swift` | medium | Done |
| SaveSelectionComponentDialog | `Library/Components/ComponentDialogs.swift` | medium | Done |
| ScheduleBordersDialog | `Shell/Dialogs/F12ScheduleDialogs.swift` | medium | Done |
| ScheduleFontDialog | `Shell/Dialogs/F12ScheduleDialogs.swift` | small | Done |
| SchedulePropertiesDialog | `Shell/Dialogs/ScheduleDialogs.swift` | wide | Done |
| ScheduleShadingDialog | `Shell/Dialogs/F12ScheduleDialogs.swift` | small | Done |
| SelectByIDDialog | `Shell/Dialogs/ManageSettingsDialogs.swift` | small | Done |
| SelectionSetsDialog | `Shell/Dialogs/F11ManageDialogs.swift` | medium | Done |
| SelectTitleBlockDialog | `Shell/Dialogs/PresentationDialogs.swift` | medium | Done |
| SheetTitleDialog | `Shell/Dialogs/ProjectBrowserDialogs.swift` | small | Done |
| SimplifySurfaceDialog | `Shell/Dialogs/SiteDialogs.swift` | medium | Done |
| SiteSettingsDialog | `Shell/Dialogs/SiteDialogs.swift` | medium | Done |
| SnapsDialog | `Shell/Dialogs/SnapsDialog.swift` | medium | Done |
| SpecifyCoordinatesDialog | `Shell/Dialogs/F11ManageDialogs.swift` | medium | Done |
| SplitAndPlaceDialog | `Shell/Dialogs/F12ScheduleDialogs.swift` | medium | Done |
| StairRailingDialogView | `Shell/Dialogs/StairDialogs.swift` | small | Done |
| StartingViewDialog | `Shell/Dialogs/F11ManageDialogs.swift` | small | Done |
| StockSheetsDialog | `Shell/Dialogs/FurnitureFabricationDialogs.swift` | wide | Done |
| StructuralSettingsDialog | `Shell/Dialogs/StructuralDialogs.swift` | large | Done |
| TagAllDialog | `Shell/Dialogs/RoomAnnotationDialogs.swift` | medium | Done |
| TopoFromImportDialog | `Shell/Dialogs/SiteDialogs.swift` | medium | Done (not in the render catalog: needs a CAD link) |
| TransferStandardsDialog | `Shell/Dialogs/F67InsertDialogs.swift` | medium | Done |
| TypePropertiesDialog | `Shell/Dialogs/TypePropertiesDialog.swift` | wide | Done |
| UnderlayDialog | `Shell/Dialogs/ExchangeDialogs.swift` | medium | Done |
| UpdateComponentsDialog | `Library/Components/ComponentDialogs.swift` | medium | Done |
| UserInterfaceDialog | `Shell/Dialogs/ManageSettingsDialogs.swift` | small | Done |
| ViewRangeDialog | `Shell/Dialogs/ProjectBrowserDialogs.swift` | large | Done |
| ViewTemplatesDialog | `Shell/Dialogs/ViewTemplatesDialog.swift` | wide | Done |
| VisibilityGraphicsDialog | `Shell/Dialogs/VisibilityGraphicsDialog.swift` | extraWide | Done |
| WarningsDialog | `Shell/Dialogs/ManageSettingsDialogs.swift` | large | Done |
| WorkPlaneDialog | `Shell/Dialogs/F2Dialogs.swift` | small | Done |
