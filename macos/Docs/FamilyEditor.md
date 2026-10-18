# Family Editor: capability assessment (ARCUS-088)

Arcus families are Arcus's own parametric content, stored as `FamilyDefinition` values and saved as `.arcusfamily` packages ([FileFormat.md](FileFormat.md)). They are not RFA files and make no claim of RFA compatibility. RFA content arrives only through the Arcus Bridge export ([RevitInterop.md](RevitInterop.md)).

## How to open it

| Entry point | What happens |
|---|---|
| Manage ▸ New Family… (menu bar) | `NewFamilyDialog`: pick a category template and a name. `FamilyTemplates.make` seeds the family from a starter (door, window, casework, plumbing fixture, tag, title block, annotation, profile, detail component; every other 3D category gets the Generic Box), keeps its first type and opens an editor window with no project family attached. |
| Edit Family (Manage ▸ Manage Project, Modify contextual tab, or the command palette) | Enabled when exactly one instance or type of a loadable family is selected. Opens the family element's definition (`FamilyEditorWindowController.open(familyID:)`). |
| Load Family / Reload Family / Type Catalog (Manage menu) | Loads `.arcusfamily` files or a CSV type catalog into the project. These don't open the editor. |

The editor is a document-style window (W4-FAMED): a **browser** sidebar (views, family types, reference planes, dimensions, forms, lines, labels, loaded families, parameters), a central **family canvas** with a ribbon above it, and a **Properties** inspector on the right. Each pane scrolls on its own; the window enforces a 1000 × 640 pt minimum, and the frame and split positions persist (`ArcusFamilyEditor`, `ArcusFamilyEditor.split`). The sidebar and inspector collapse from the toolbar. Each change goes through `FamilyEditorModel.edit`, which re-evaluates the family and registers undo; Edit ▸ Undo/Redo and ⌘Z use the window's own undo stack (`windowWillReturnUndoManager`).

### Structure

| Part | What it holds |
|---|---|
| Toolbar | Sidebar toggle, Zoom to Fit, Family Types, Flex Test, Save As, Load into Project, inspector toggle. The subtitle shows the category and whether the family is loaded in the project. |
| Ribbon ▸ Create | Datum (Reference Plane ▾ vertical/horizontal in this view or X/Y/Z, Dimension, EQ, Aligned), Forms (Extrusion, Blend, Revolve, Sweep, Void Extrusion), Detail (Symbolic Line, Annotation Line, Arc, Label, Text), Insert (Load Family ▾ from file or the project), Properties (Family Types, Category and Parameters), Family Editor (Load into Project, Flex Test, Save As…). Scrolls horizontally in a narrow window instead of clipping. |
| Ribbon ▸ Modify | Modify (leave the tool), Delete, Duplicate, Deselect; View (Plan/Front/Right/3D, Zoom to Fit, Preview Visibility); Family Types (New/Rename/Delete Type). |
| Browser | `Floor Plan: Ref. Level`, `Elevation: Front`, `Elevation: Right`, `3D View: {3D}`; the types (the current one is marked; context menu: make current, new, duplicate, rename, delete); every reference plane (axis, origin marker), dimension (label or lock, conflict marker), form, line, label, loaded family (place, shared, remove) and nested instance, and every parameter with its value in the current type. Selecting a row selects it on the canvas and in Properties. |
| Canvas | `FamilyCanvasView` (AppKit, CoreGraphics). Grid in a 1-2-5 metre series with the origin cross, reference planes as dashed green lines with their names (strong references heavier, origin planes marked ⌖), dimension strings stacked outside the content (labelled dimensions bold, conflicts red), forms filled with their outlines, symbolic lines, labels, voids dashed orange, and hidden-by-visibility content dotted when Preview Visibility is off. Navigation as in the project's 2D views: wheel zooms about the cursor (`NavigationZoom`), trackpad scroll and middle-drag or ⌥-drag pan, pinch zooms, double-click or F fits. Click selects (hover pre-highlights), a selected reference plane can be dragged: a plane driven by a labelled dimension changes that parameter in the current type, a plane with a numeric offset gets a new offset, and origin, EQ-held, locked and formula-placed planes refuse with a message. Delete removes the selection, Esc cancels the tool or clears the selection; right-click gives Delete/Duplicate/Zoom to Fit. Sketch tools: Reference Plane (click; snaps to planes and the millimetre), Dimension (click two parallel planes), Symbolic/Annotation Line (two clicks, plan view), Extrusion and Void Extrusion (drag a rectangle in plan for a footprint, or in an elevation for width × height), Label (click, plan view). |
| View bar | Plan/Front/Right/3D, detail level, Preview Visibility, cursor readout in project units, Zoom to Fit. |
| Status strip | Messages, flex-test results, evaluation errors (red) and warnings (orange). |
| Properties | The family (name, category, shared, description, manufacturer, current type with New/Duplicate/Rename/Delete and its values, Family Types…) when nothing is selected; otherwise the selected type (rename, values), parameter (rename, kind, group, formula, value), reference plane (rename, offset, position, Is Reference, constrained-by links), dimension (planes, label with Add Parameter…, lock, value), form (name, void, shape editor, material, subcategory, visibility), line (points or arc, subcategory, weight, visibility), label (parameter or text, position, height, bold, alignment) or nested instance (type, insertion point, rotation, mirror, visibility, associated parameters). Rows are label-over-control so nothing truncates at 300 pt. |
| Family Types dialog | Sheet: type picker with New/Duplicate/Rename/Delete, a resizable table (Parameter, Value, Formula, Type, Kind, Group) with rename/delete in the context menu, Add Parameter, undo/redo buttons, Flex Test. |
| Category and Parameters dialog | Sheet: change the category among templates of the same kind (2D/3D), Shared, tagged categories, description, manufacturer, the parameter list with Edit links into Properties. |

## What exists

| Area | Status | Where |
|---|---|---|
| Editor environment | Present. Document-style window (browser · canvas · Properties), per-window undo wired to the Edit menu, family rename, Shared toggle, category change, persisted frame and splits. | `UI/FamilyEditor/FamilyEditor.swift`, `FamilyEditorShell.swift`, `FamilyRibbon.swift`, `FamilyBrowserView.swift`, `FamilyInspectorView.swift` |
| Canvas | Present. Plan, Front, Right and 3D views with zoom/pan, grid, named reference planes, labelled dimensions, selection and hover, plane dragging and the Create sketch tools. Evaluation errors are shown in red and warnings in orange in the status strip. | `FamilyCanvas.swift`, `FamilyPreview.swift` |
| Reference planes | Present. Sketch a plane on the canvas or add X/Y/Z planes; the offset is a number or a formula; Is Reference; origin planes are locked; rename updates dimensions and locked faces; delete bakes locked faces to the plane's position; drag on the canvas. | `FamilyInspectorView.swift`, `Domain/Model/FamilyEditing.swift` |
| Dimensions and constraints | Present. Click two parallel planes on the canvas or use Aligned/EQ; a label parameter (or Add Parameter… with each type's current distance), EQ across three planes, lock, conflict marker. Solved by least squares from the sketch in `FamilyConstraintSolver`. | `FamilyInspectorView.swift`, `FamilyFormGeometry.swift` |
| Parameters | Present. Every user-creatable type (length, area, Yes/No, material, text…); type or instance; group; rename (formulas, labels, visibility, material and nested bindings follow); delete (built-ins are protected). No shared parameters inside families, no reporting parameters. | `FamilyTypesPane.swift`, `FamilyEditing.swift` |
| Formulas | Present. Units (`600 mm`), arithmetic, `if`/`and`/`not`, trig in degrees, `sqrt`; unit checking; cycle detection in Flex Test. A parameter driven by a formula is read-only per type and in project Properties. | `FamilyEvaluator.parameterValues`, `ArcusCalc` |
| Types | Present. New, Duplicate, Rename, Delete (the last type stays), a per-type value column, all undoable; from the dialog, the browser, the ribbon and Properties. | `FamilyTypesPane.swift`, `FamilyEditing.swift` |
| Forms | Present. Extrusion (sketched as a rectangle on the canvas, or rectangle/polygon/circle typed), blend, revolve, and sweep (sketched profile or embedded profile family). Void extrusions cut solid extrusions; void sweeps, blends and revolves don't cut. Each face or point is a plane name (locks to the plane) or a formula. Material parameter, subcategory, and visibility (3D, plan, front/back, left/right, detail levels, Yes/No parameter). Click a form on the canvas to edit it in Properties. | `FamilyFormsPane.swift`, `FamilyEvaluator.swift` |
| Symbolic lines and labels | Present for plan lines (sketched with two clicks), arcs, annotation lines and labels/text (parameter, static text, height, bold, alignment). Fills are evaluated and previewed but only edited in files. | `FamilyInspectorView.swift` |
| Nested families | Present. Insert ▸ Load Family from the project or a file; place from the browser's Loaded Families; x/y/z (plane or formula), rotation and mirror, associate nested parameters with host formulas, visibility, in Properties. Cycle and depth guards. A shared nested family loads into the project as its own family. | `FamilyNestedPane.swift` |
| Flex Test | Present. Evaluates every type, plus each non-formula length parameter at 50% and 150%. It gates Load into Project (errors block the load) and warns on Save As…. | `FamilyEvaluator.flexTest` |
| Save As… | Present. Writes a `.arcusfamily` package (keeps the document ID on overwrite; no thumbnail). | `FamilyPackage.write` |
| Load into Project / reload | Present. A family with no project family attached is loaded as new, or reloads a project family with the same name. Reload asks Keep Project Values or Use Family Values. | `FamilyProjectLoader.load` |
| Placed instances follow edits | Present. Instances re-evaluate from the project type's values plus instance overrides (`Parameters.effectiveFamily`); caches are keyed by family and type revisions. | `InstanceGeometry.swift` |
| Model In-Place | **Missing.** There is no project-only family and no in-place editing mode. | RevitParity C10 |

## Defects fixed (marked `// BL-SITE`)

1. **A new labeled dimension moved the whole family off its insertion point** (`FamilyDefinition.swift`, `FamilyEditor.swift`). Generic Box-based templates (furniture, generic model, column and the others) had no origin plane on X or Y, and their Top plane was positioned only by its "Height" offset. The solver keeps planes as close to the sketch as it can, so labeling a newly added plane spread the correction over every unanchored plane: Left, Right and Top moved. New Family now calls `FamilyDefinition.addTemplateOriginConstraints()`. On X and Y it adds a fixed centre plane, held midway by EQ, when an axis has no origin plane; on Z it adds a Bottom–Top dimension labeled Height. The starters' geometry is unchanged. Because of the EQ rows, new families need family reader 2, which every current build has.
2. **A labeled dimension could flip sides while flexing** (`FamilyDefinition.swift`, `FamilyFormGeometry.swift`, `FamilyEditor.swift`, `FamilyConstraintsPane.swift`). The side of A that B stays on was read again from the sketched offsets on every evaluation. After Top moved below Underside's numeric offset (Height at 50%), the top form collapsed, or a leg plane jumped outside the table without any error. `FamilyDimension.direction` is now recorded when a label is applied or the measured planes change (`fixLabelDirection`), and the solver uses it. This is an additive, optional JSON key and it doesn't raise `minimumReaderVersion`. Older readers ignore it and fall back to the sketch-derived side. Families without it behave as before.
3. **After a family was renamed and reloaded, its project types still showed the old name** in the type selector, Project Browser, schedules and IFC names (`FamilyLoading.swift`).
4. **After a reload with Keep Project Values, a newly added parameter read 0 in Properties and tags while the geometry used the family value** (`FamilyLoading.swift`). Existing types now take the family value for parameters they don't have yet. Values that already exist are still kept.
5. **The formula values in type Properties used the values stored in the family instead of the project type's values** (`Parameters.typeEntries`). They now read the same values that instances and geometry use.
6. **`Parameters.value` returned the default for a family type parameter read on a type element** (`Parameters.swift`).

## Defects fixed in wave 4 (marked `// W4-FAMED`)

1. **The left column clipped** (owner screenshots 12/13): the tab picker was cut off on the left, rows drew off-screen and captions were truncated at the pane edge, because the panes used fixed column widths inside an `HSplitView` whose SwiftUI minimums (560 + 420) exceeded what the window gave them. The window is now an `NSSplitViewController` with hosting controllers whose `sizingOptions` are empty, so panes never demand more than their split minimums (210 / 440 / 300); every pane scrolls, Properties rows stack label-over-control, the ribbon scrolls horizontally, and the toolbar carries the commands that were truncated ("Load int…", "F…").
2. **Reference planes and parameters couldn't be renamed** (gap P1). `FamilyEditing.renamePlane` and `renameParameter` update dimensions, locked bounds, type values, formulas (whole-name token replacement that leaves "Frame Width" alone when "Width" is renamed), dimension labels, visibility/material parameters, labels and nested bindings.
3. **Deleting a plane left forms locked to a missing plane**, reported only by the flex test. `FamilyEditing.deletePlane` bakes each locked bound to the plane's solved position.
4. **Edit ▸ Undo did nothing in the editor** (only ⌘Z over the pane worked): the window now returns the family's `UndoManager`.
5. **Edit Family opened a second window for a family already being edited**: the existing window comes to the front.
6. **After the first Load into Project a New Family window stayed unattached**, so a rename followed by another load created a second family: the model now attaches to the project family it created.
7. **Labels and annotation lines could not be authored** (Detail ▸ Label/Text/Annotation Line and the label inspector).

## What the tests cover

`Arcus/Tests/DomainTests/FamilyEditingTests.swift` (16 tests, W4-FAMED) covers the editor-model logic in `FamilyEditing`: number and name formatting, formula token replacement, parameter rename across values/formulas/labels/visibility/material/nested bindings, parameter delete, plane rename and delete (baked bounds, origin protection), new plane naming and dimension pairing, plane-drag resolution (parameter / offset / refusals for origin, EQ, lock and formula planes), type add/rename/delete rules, sketched extrusions, lines, labels and duplicates, delete-by-item, camera round trip, zoom about the cursor, fit and clamping, plane and outline hit-testing, and the evaluator's source identities.

`Arcus/Tests/DomainTests/FamilyEditorFlowTests.swift` (9 tests; run with the 17 in `FamilyEditorTests.swift`, 26 in total) drives the same Domain calls the panes make:

- New Family seeding and anchoring. Anchoring leaves the door, window, cabinet, basin and box starters unchanged and flex-clean, and a labeled leg plane no longer moves Left, Right or Top.
- Authoring a side table: an added plane with Label ▸ Add Parameter…, a second plane labeled with an existing parameter, length and area formulas with units, instance Length and Yes/No parameters, four locked or formula forms, three types. Each type is evaluated and its bounds, planes, formula values and form sizes are checked; Flex Test passes; instance overrides move and hide the shelf.
- The label direction survives flexing. The legacy fallback, JSON round trip and omission of the key when unset are also checked.
- Flex Test gating: circular formulas, unit mismatch, a deleted parameter or plane, and a flex-only collapse.
- Load into Project: the family and its types (category, family name, values) are created, a placed instance has the expected world bounds (and swapped extents when rotated), Properties entries show instance and type parameters, instance and type edits change the mesh, and formula parameters can't be set.
- Reload with Keep and Use Family Values: the rename propagates, new types and forms arrive, new parameters are seeded, project-tuned values are kept or replaced, and reloading an identical family changes nothing.

`Arcus/Tests/PersistenceTests/FamilyEditorPersistenceTests.swift` (2 tests):

- Save As… round trip, including the dimension direction.
- Load from disk, save and reopen the project with identical instance bounds.
- Re-save over the same file (the document ID is kept), then Reload Family ▸ Use Family Values updates the reopened project.

The window, NSAlert prompts and pane code themselves (`FamilyEditorModel`, `FamilyTemplates.make`, the canvas view) live in the app target and are not unit-tested. The tests mirror their edit closures, and the app target builds. The QA screenshot scenario (`QAHarness+FamilyEditor.swift`) captures the editor at 1000 pt and 1440 pt in light and dark with a form selected, the front elevation and the Family Types sheet (`family-editor-*`, `family-types-dialog-*`).

## Gaps against a reference Family Editor (prioritized)

| Pri | Gap | Notes |
|---|---|---|
| P0 | Model In-Place (project-only families, edited in the project context) | Not present. Needs a family element flagged project-only, an in-context editing mode over the project views, and no separate file. |
| P1 | Shape handles on forms, sketching polygons/arcs/blends/sweeps/revolves on the canvas | Planes, dimensions, rectangular extrusions, lines and labels are sketched; other shapes are typed in Properties. RevitParity C9. |
| P1 | Open a `.arcusfamily` file straight into the editor, and edit a family selected in the Project Browser | Today you must load the family and select an instance or type. |
| P1 | Editing wall openings (doors, windows), fills, profile loops and tag categories in the editor | These are evaluated and previewed, but can only be authored in code or JSON. Annotation lines and labels are editable now. |
| P2 | Void sweeps, blends and revolves; solid Boolean cuts of non-extrusions; swept blends | Voids cut extrusions only. |
| P2 | Host-based templates (wall-, face-, ceiling-based) and work-plane-based placement | The category can be changed among templates of the same kind (Category and Parameters); hosting is not. |
| P2 | Family and shared parameters inside families, reporting parameters, lookup tables, array parameters | Not present. |
| P2 | Arc-length and angular dimensions, radius labels | Only linear distances between parallel planes. |
| P2 | Thumbnails on Save As… | `FamilyPackage.write` accepts one; the editor passes nil. |

## Retest checklist

1. `cd .agents/lead && swift test --filter FamilyEdit` reports 42 tests passing (16 editing + 26 editor).
2. `swift test --scratch-path <scratch>-full --filter FamilyEditorPersistence` reports 2 tests passing.
3. Manage ▸ New Family… ▸ Furniture ▸ Create. The window opens at its saved size (never below 1000 × 640): browser left, canvas with the ribbon, Properties right; nothing is clipped at 1000 pt, and the ribbon scrolls. In the browser, "Center (Left/Right)" and "Center (Front/Back)" carry the origin marker and Dimensions lists an EQ for each.
4. Create ▸ Reference Plane ▸ Vertical, click on the canvas: a "Plane N" appears where clicked and is selected in Properties. Create ▸ Dimension, click Left then the new plane, then Label ▸ Add Parameter… in Properties. Left and Right must not move (Position in Properties). Drag the new plane on the canvas: the parameter value changes; drag Center: the refusal message appears.
5. In Elevation: Front, Reference Plane ▸ Horizontal at about 0.9, dimension it to Top, and label it. Set Height to 0.5 and run Flex Test: it passes, and the top stays above the new plane. Rename the plane in Properties: the dimension and any locked face follow (flex still passes). Delete a plane a face is locked to: the face keeps its position.
6. Family Types: New…, change Width, Done; switch types in the browser: the canvas flexes. Edit ▸ Undo reverts the value. Load into Project, place two types, and check their sizes in plan and 3D. Rename the family in Properties and Load into Project again: it reloads instead of adding a second family.
7. Edit Family on a placed instance, rename the family, add a parameter and a form, then Load into Project ▸ Keep Project Values. The type selector and Project Browser show the new name, the new form appears, and the new parameter shows its family value in type Properties.
8. Change a type parameter used by a formula in the project's type Properties: the formula parameter's value updates there.
9. Save As…, close the editor, Load Family from that file into a new project, save it, reopen it, and check that the instance is unchanged.
