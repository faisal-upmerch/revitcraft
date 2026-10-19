# Keyboard shortcuts

Arcus has three ways to run a command from the keyboard:

1. **Menu shortcuts** (⌘-based). These follow macOS conventions.
2. **Typed aliases.** With the canvas (2D or 3D) focused, type two or three letters, such as `WA` for Wall, `DI` for Aligned Dimension or `ZE` for Zoom to Fit. There is no Return to press; the command starts as soon as the letters are a complete alias. The status bar shows what you have typed ("Shortcut: Z…"); the buffer clears when a command runs, when the letters can't match any alias, when you press `Esc`, and 1.5 seconds after the last key. When a complete alias is also the start of a longer one, it runs on the next key that doesn't continue the longer one, or after the pause. Zoom and snap-override aliases work while a tool is active without ending it. You can view and change aliases in the **Keyboard Shortcuts** dialog (Manage and Help menus, alias `KS`); the changes are stored locally in user defaults.
   **Text input always wins:** while a text field, search field, inline editor (such as a Project Browser rename) or a dialog's text control has the keyboard, letters, `Return`, `Space` and `⌘A` go to that control: no alias, tool shortcut, Finish or element Select All runs.
3. **Command Search** (`⌘K`). Find any command by name, alias or keyword.

The tables below are generated from the command catalog (`Arcus/Application/Commands.swift`) with
`swift run -c release arcus-bench --commands-markdown`, so they match the code.

## Canvas keys (2D views and sheets)

| Key | Action |
|---|---|
| `Esc` | Two-stage cancel: the first `Esc` cancels the current step (ends a wall chain, drops a pending point, cancels a Move/Copy preview, closes the typed-value box) and the tool stays active; the second returns to Modify, keeping the selection; in Modify it clears the selection (Select Previous restores it). In sketch mode `Esc` never leaves the sketch: use Finish or Cancel Edit Mode. A partly typed alias or a Modify command waiting for its selection is cancelled first. Context-menu **Cancel** does the same |
| `Return` / `Enter` | Finish the current tool (for example, end a wall chain or finish a sketch). In Modify: repeat the last creation or modify command (as **Repeat** in the context menu, alias `RC`). While Move, Copy, Rotate, Mirror, Array, Scale, Pin, Unpin or Delete waits for its selection: continue with the selected elements |
| `Tab` | In Modify: cycle through overlapping elements under the cursor, then the chain of joined walls. While drawing: cycle through the snap candidates under the pointer |
| `⇧` while drawing | Constrain to horizontal or vertical |
| `SE` `SM` `SI` `SN` `SC` `SP` `ST` `SQ` | While drawing: use only the endpoint / midpoint / intersection / nearest / centre / perpendicular / tangent / quadrant snap for the next pick |
| `SW` `SX` `SR` `SZ` | While drawing, for the next pick: grid intersections (Arcus's stand-in for a work plane grid) / points (end and centre points) / remote objects (a four times larger capture radius) / close (endpoints only, to close a chain on its start) |
| `SS` / `SO` | While drawing: turn a snap override off / snaps off for the next pick. All of these are also in the drawing context menu under **Snap Overrides** |
| Click / `⌘`-click / `⇧`-click | Select / add to the selection / remove from the selection (BIM style, the default). With the Mac style in Settings: `⇧`-click adds and `⌘`-click toggles |
| `⌥⌘←` (`⌃←` when macOS does not use it for Spaces) | Select Previous |
| `⌘A` | Select All: the model elements visible in the view (in drafting views, legends and sheets: their detail and annotation elements). View markers, datums, scope boxes, cameras and links are never included. An Arcus extension; `SA` is Select All Instances in the entire project |
| `]` / `[` | Select the next or previous element shown in the view, in reading order. VoiceOver announces each one |
| Arrow keys | Nudge the selection (4 pt on screen; hold `Shift` for 20 pt) |
| `Delete` / `⌦` | Delete the selection |
| `Space` | While placing: flip a door or window's facing (the flip stays as the pointer moves), rotate a component by 90°, flip a wall's exterior side, or flip a section's look direction. `⇧Space` flips a door or window's hand. In Modify: flip the selected doors and windows (facing) and walls |
| `0`–`9`, `-`, `.`, `=`, `(` | While a tool expects a length or angle, or while dragging the selection or a grip, start numeric entry. It accepts units and formulas, such as `3600`, `12' 6"` or `=2400*1.5` |
| Click a temporary dimension value | Type a new value; the element moves by exactly the difference. The small button beside it makes the dimension permanent |
| Two-finger scroll | Pan |
| Pinch, `⌘`/`⌥`+scroll, mouse wheel | Zoom about the pointer. One wheel notch scales the view by the same step (×1.18) in plans, elevations, sections and 3D views; a wheel rolled forward zooms in whatever the system scroll direction |
| Smart zoom (two-finger double-tap), middle-button double-click | Zoom to fit |
| Middle-drag | Pan |
| Right-click | Context menu for the element under the pointer |
| Double-click | Edit (open a view from its marker, edit a sketch or stair, edit a group, open a family, activate a viewport) |

## Window shortcuts (not in the command catalog)

| Key | Action |
|---|---|
| `⌥⌘S` | Show/Hide Sidebar: collapses the floating left panel (project header, Properties, Project Browser) or shows it again; the toolbar's sidebar button does the same. The inspector button shows or hides Properties (the right inspector in Mac Spacious). W4-SHELL |
| `⌃⌘F` | Enter/Exit Full Screen |

## Context menus

- **While drawing:** Cancel · Repeat [last command] · Recent Commands ▸ (the last five creation or modify commands) · Finish / Cancel Edit Mode (sketch mode) · Snap Overrides ▸ · Zoom In Region · Zoom Out (2x) · Zoom To Fit · Previous Pan/Zoom · Next Pan/Zoom · Browsers ▸ · Properties.
- **On an element:** Cancel · Repeat · Recent Commands ▸ · Hide in View ▸ (Elements, Category, By Filter) · Override Graphics in View ▸ (By Element, By Category, By Filter) · Create Similar · Edit Family (loadable families) · Select Previous · Select All Instances ▸ (Visible in View, In Entire Project) · Delete · Find Referring Views · the zoom items · Browsers ▸ · Properties; then Arcus's own commands below a separator (Edit Type, Edit Boundary, flips, Pick New Host, Move, Copy, Pin, Create Group, Selection Box, …). Temporary Hide/Isolate lives on the View Control Bar.
- **On empty canvas:** Cancel · Repeat · Recent Commands ▸ · Select Previous · the zoom items · Browsers ▸ · Properties; then Paste, Reset Temporary Hide/Isolate (when active) and Visibility/Graphics.

## Modify tools without a selection

Move, Copy, Rotate, Mirror, Array, Scale, Pin, Unpin and Delete run with nothing selected wait for a selection: select
elements (click, window, `⌘`-click), then press `Return` or click **Finish** on the contextual tab (`Esc` or **Cancel**
stops). While a Modify tool runs, the contextual tab keeps the selection's name (for example *Modify | Walls*); its
options (Constrain, Disjoin, Multiple, Copy, the Array settings, the Scale method) are on the contextual ribbon and are
remembered across launches. Tag on Placement, tag orientation and leader, dimension Prefer/Pick and a level's Make Plan
Views are on the contextual ribbon too; placement values (wall height, location line, chain, offset, join status, sill
height) stay on the floating Options Bar.

## Keyboard Shortcuts dialog and shortcut files

Pick a command, type the new keys in **Press new keys** and choose **Assign**. If the keys belong to another command the
dialog says so and the button becomes **Reassign** (the keys move). Keys that start a longer alias, or extend a shorter
one, are pointed out: both still work (the shorter one waits for the next key or the pause). Remove keys with the ×
beside them. **Restore Defaults** brings back the defaults. Nothing changes until **OK**.

**Export…** writes, and **Import…** reads, *Arcus Keyboard Shortcuts.xml*: a simple XML file of Arcus's own design
whose shape follows the usual layout of BIM shortcut files — one item per command with its identifier, name, keys
and group. It is not another application's format.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Shortcuts application="Arcus" formatVersion="1">
  <ShortcutItem CommandId="wall" CommandName="Wall" Shortcuts="WA" Paths="Architecture"/>
  <ShortcutItem CommandId="zoomExtents" CommandName="Zoom to Fit" Shortcuts="ZE#ZF#ZX" Paths="View"/>
</Shortcuts>
```

`Shortcuts` lists the keys separated by `#` (spaces and commas are accepted on import); an empty value removes a
command's keys. Commands listed in an imported file get exactly the file's keys, other commands keep theirs; unknown
command ids are skipped and reported, and keys given to two commands go to the last one (the dialog lists them).
Menu shortcuts (`⌘`-keys) are fixed and not in the file.

## Differences from the reference defaults

The typed aliases follow the published defaults of mainstream BIM tools (for example `ZA` Zoom All to Fit, `ZE` `ZF`
`ZX` Zoom to Fit, `ZR` `ZZ` Zoom in Region, `ZO` `ZV` Zoom Out (2x), `ZS` Zoom Sheet Size, `ZP` `ZC` Previous
Pan/Zoom, the `S…` snap overrides, `SA` Select All Instances, `CS` Create Similar, `RE` Scale, `RC` Repeat Last
Command, `EOD` Override Graphics by Element, `KS` Keyboard Shortcuts, `VP` View Properties, `PP` Properties).
Deliberate differences:

- Arcus extras kept: `FL` Floor, `RF` Roof, `EV` Elevation, `3D` Default 3D View, `MD` Modify, `BX` Selection Box,
  `LB` Component Library, `VH` Hide Category in View and the others in the tables below without a reference default.
- Section and Stair have no alias (`SX` and `SR` are snap overrides).
- Properties is `⌥⌘2` (the Project Browser is `⌥⌘1`); `⌘1` is not used.
- `LW` Linework, `GD` Graphic Display Options (a View Control Bar menu in Arcus), `SU` Sun Settings (same menu) and
  `SF` Split Face have no command in Arcus yet, so they have no alias.
- `⌘A` selects model elements (see above); the reference tools have no Select All.

## 3D view keys

| Key | Action |
|---|---|
| Arrow keys | Orbit 15° about the view centre |
| `+` / `-` | Zoom in or out |
| `F` | Zoom to fit |
| `Esc` | Clear preselection |
| `⌥`-drag | Orbit (`⌥⇧` pans, `⌥⌃` dollies) |
| Middle-drag | Pan (`Shift` orbits, `Control` dollies); see *3D navigation* below |
| Two-finger scroll | Pan (`Shift` orbits, `⌥`/`⌘` zooms); see *3D navigation* below |
| Mouse wheel / pinch | Zoom toward the point under the pointer |
| Orientation cube (top right) | Click a face, edge, corner or compass letter to orient the view; drag to orbit; the house returns to Home |

VoiceOver users can also use the 3D view's custom actions: *Orient to Top/Front/…* and *Zoom to fit*.

## 3D navigation

Every 3D view, including camera views, uses BIM-style navigation by default; the Blender-style scheme is one click
away in **Settings ▸ 3D Navigation** (also *View ▸ 3D Navigation ▸ Middle Button*), which describes both. The bindings
avoid the typed aliases: plain letters and the main-row digits are never used for navigation (the numeric keypad, `⇧F`
and `⌃⌥` menu shortcuts are). All of these are also in **View ▸ 3D Navigation** and in the 3D menu of the floating
navigation bar.

| Input | BIM-style (default) | Blender-style |
|---|---|---|
| Middle-drag | Pan | Orbit about the point under the pointer (or the selection, with *Orbit Around Selection*) |
| `⇧` middle-drag | Orbit about the selection's centre, or the model's centre when nothing is selected | Pan |
| `⌃` middle-drag | Dolly toward the point where the drag started (drag up to move closer) | Same |
| `⌥`-drag, `⌥⇧`-drag, `⌥⌃`-drag | Orbit, pan, dolly with the left button (for trackpads and one-button mice) | Same |
| Two-finger swipe (trackpad) | Pan; `⇧` orbits; `⌥` or `⌘` zooms | Orbit; `⇧` pans; `⌥` or `⌘` zooms |
| Two-finger rotate (trackpad) | Turn the model about the orbit point | Same |
| Pinch, mouse wheel | Zoom toward the point under the pointer (×1.18 per wheel notch, as in 2D views) | Same |
| Smart zoom (two-finger double-tap), middle-button double-click | Frame all | Same |
| Orientation cube | Click a face, edge, corner or compass letter to look from there (Top shows the plan with north up); drag to orbit; the house button goes Home | Same |

Swipes follow the system scroll direction; there is no gliding with Reduce Motion.

| Key | Action |
|---|---|
| Keypad `1` / `3` / `7` | Front / right / top view (`⌃` for back / left / bottom). Menu: `⌃⌥1` `⌃⌥3` `⌃⌥7` (`⌃⌥⌘` for the opposite side) |
| Keypad `5` | Perspective ↔ orthographic (`⌃⌥5`) |
| Keypad `2` `4` `6` `8` | Orbit down / left / right / up in 15° steps |
| Keypad `9` | View from the opposite side |
| Keypad `.` | Frame selected (`⌃⌥.`) |
| `Home` | Frame all (also `⌘0`) |
| Keypad `+` / `-` | Zoom in / out |
| Keypad `0` | View through the active camera; again to return (`⌃⌥0`) |
| `⌃⌥` keypad `0` | Align the active camera (or this camera view's camera) to the view (`⌃⌥⌘0`) |
| `⇧F` | Fly mode (also `⌃⌥F`) |
| `⌃⌥L` | Lock Camera to View on or off |

**Fly mode.** Move the mouse to look around. `W` `A` `S` `D` (or the arrow keys) move forward, left, back and right
along the view; `Q` / `E` move down / up. Scroll to change the speed (shown at the bottom of the view); hold `⇧` to go
four times faster or `⌥` for a quarter speed. `Return` or a click keeps the new view; `Esc` or a right-click restores
the view from before. Movement eases in and out over about 80 ms (immediately with Reduce Motion).

**Middle button style.** *Settings ▸ 3D Navigation* (or *View ▸ 3D Navigation ▸ Middle Button*) switches between the
BIM-style scheme (the default: middle-drag pans, `⇧` middle-drag orbits, a two-finger swipe pans) and the Blender-style
scheme (middle-drag orbits, `⇧` middle-drag pans, a two-finger swipe orbits). Animated view changes (presets, framing,
keypad steps, orientation cube clicks) are instant when Reduce Motion is on.

**Cameras.** A camera view has *Lock Camera to View* on by default: navigating it moves the camera, and each navigation
(a drag, a gesture, a key step or a fly) is one undoable change once it ends. With the lock off, navigating a camera
view doesn't change the saved camera. In other 3D views the lock is off by default: *View Through Camera* looks through
the active camera, and navigating then leaves the camera (or moves it, with the lock on). Cameras are listed under
**3D Views** in the Project Browser; right-click one for *Show Camera*, *Set as Active Camera*, *Look Through* and
*Align to Current View*.

**Project Browser and view tabs.** In the Project Browser, `Return` or a double-click opens the selected view, `F2`, a
slow second click or *Rename…* edits the name in place (`Return` commits, `Esc` cancels, clicking elsewhere commits;
sheets open the Sheet Title dialog for number and name), and `⇧`/`⌘`-click selects several items. Drag views onto a
sheet (on the canvas or on the sheet's row) to place them: the viewport follows the pointer and a click places it.
`⌃⇥` and `⌃⇧⇥` (Window menu) show the next and previous view tab.

**Snapping in 3D views.** While a tool is active in a 3D view, `Tab` steps through the snaps under the pointer (3D
corners, edge midpoints, centres, crossings, nearest, and the work plane's own snaps), as in plan views.

**Family Editor.** In the plan and elevation views, snapping works as in project views. While a tool is active,
`Tab` cycles the snaps under the pointer, and the typed snap overrides `SE` `SM` `SI` `SN` `SC` `SP` `ST` `SQ` `SX`
`SR` `SZ` `SO` `SS` apply to the next pick. `Return` finishes a sketch, `Delete` removes its last point, and `Esc` ends
the rubber band or chain.

## Commands

### Modify

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Modify | `⎋⎋` | `MD` | Return to selection mode. |
| Select All | `⌘A` |  | Select the model elements visible in the view (in drafting views and sheets: their detail elements). View markers and datums are left out. An Arcus extension. |
| Select All Instances: Visible in View |  | `SA` | Select every instance of the selected type visible in the view. |
| Select All Instances: In Entire Project |  |  | Select every instance of the selected type in the project. |
| Select by Category… |  |  | Select all visible elements of chosen categories. |
| Filter Selection… |  |  | Keep only chosen categories in the selection. |
| Move |  | `MV` | Move selected elements by picking two points or typing a distance. |
| Copy |  | `CO` `CC` | Copy selected elements by picking two points. |
| Rotate |  | `RO` | Rotate selected elements about a center. |
| Mirror - Pick Axis |  | `MM` | Mirror selected elements about a picked line. |
| Mirror - Draw Axis |  | `DM` | Mirror selected elements about a drawn line. |
| Array |  | `AR` | Create a linear array of the selection. |
| Align |  | `AL` | Align elements to a reference; optionally lock the alignment. |
| Offset |  | `OF` | Offset walls or lines by a distance. |
| Trim/Extend to Corner |  | `TR` | Trim or extend two elements to form a corner. |
| Trim/Extend Single Element |  |  | Trim or extend one element to a boundary. |
| Trim/Extend Multiple Elements |  |  | Trim or extend several elements to one boundary. |
| Split Element |  | `SL` | Split a wall or line at a picked point. |
| Pin |  | `PN` | Prevent selected elements from moving. |
| Unpin |  | `UP` | Allow selected elements to move. |
| Delete | `⌫` | `DE` | Delete the selection and dependent elements. |
| Match Type Properties |  | `MA` | Apply the type of a source element to other elements. |
| Paint |  | `PT` | Apply a material to an element's surfaces (stored as an element material override). |
| Remove Paint |  |  | Remove painted material overrides. |
| Allow Join |  |  | Allow the selected walls to join at their ends. |
| Disallow Join |  |  | Stop the selected walls joining at their ends. |
| Create Group |  | `GP` | Group the selected elements. |
| Ungroup |  | `UG` | Dissolve the selected group. |
| Edit Group |  | `EG` | Edit the members of a group; changes apply to every instance of the group type. |
| Finish Group |  |  | Finish editing the group. |
| Flip Facing |  |  | Flip the facing of doors and windows. |
| Flip Hand |  |  | Flip the hand (hinge side) of doors and windows. |
| Flip Wall |  |  | Swap the exterior and interior sides of walls. |
| Attach Top/Base |  |  | Attach wall tops to a roof or floor. |
| Detach Top/Base |  |  | Detach wall tops from roofs and floors. |
| Edit Profile |  |  | Edit the elevation profile of a wall. |
| Reset Profile |  |  | Restore a wall's rectangular profile. |
| Edit Boundary |  |  | Edit the sketch of a floor, ceiling, roof or region. |
| Finish Edit Mode | `↩` |  | Validate and commit the sketch. |
| Cancel Edit Mode |  |  | Discard the sketch and restore the previous state. |
| Pick New Host |  |  | Move a door or window to another wall. |
| Type Properties |  |  | Edit the type of the selection or of the element being placed (shared by every instance). |
| Snaps Off (Next Pick) |  | `SO` | Turn snapping off for the next pick of the current tool. |
| Snap to Endpoint (Next Pick) |  | `SE` | Snap only to endpoints for the next pick. |
| Snap to Midpoint (Next Pick) |  | `SM` | Snap only to midpoints for the next pick. |
| Snap to Intersection (Next Pick) |  | `SI` | Snap only to intersections for the next pick. |
| Snap to Nearest (Next Pick) |  | `SN` | Snap only to the nearest point on a line for the next pick. |
| Snap to Center (Next Pick) |  | `SC` | Snap only to arc and circle centres for the next pick. |
| Snap to Perpendicular (Next Pick) |  | `SP` | Snap only perpendicular to a line for the next pick. |
| Snap to Tangent (Next Pick) |  | `ST` | Snap only tangent to an arc for the next pick. |
| Snap to Quadrant (Next Pick) |  | `SQ` | Snap only to arc quadrant points for the next pick. |
| Select Previous | `⌥⌘←` |  | Select again the elements that were selected last. |
| Edit Witness Lines |  |  | Add or remove references of the selected dimension by clicking them. |
| Edit Stair |  |  | Edit a placed stair: drag its start, direction, run width or landing, or change its shape and riser counts. |
| Modify Sub Elements |  |  | Select points and vertices of a floor or flat roof and type their elevation offsets. |
| Add Point |  |  | Add shape-editing points to a floor or flat roof at an elevation offset. |
| Reset Shape |  |  | Remove shape editing from the selected floors and roofs. |
| Attach Walls |  |  | Attach the walls below the selected roof or floor to its underside. |
| Join Geometry |  | `JG` | Join overlapping walls, floors, roofs and ceilings so the overlap is cut from one of them and counted once. Walls cut floors, roofs and ceilings; roofs cut floors; floors cut ceilings. |
| Unjoin Geometry |  |  | Remove geometry joins between the selected elements. |
| Cut Geometry |  |  | Cut one floor, ceiling or roof with another element: pick the element to cut first, then the cutting element. |
| Uncut Geometry |  |  | Remove cuts between the selected elements. |
| Switch Join Order |  |  | Make the element that was cut by a join cut the other one instead. |
| Create Similar |  | `CS` | Start placing a new element of the selected element's type. |
| Measure Between Two References |  | `ME` | Measure the distance between picked points; nothing is added to the model. |
| Measure Along an Element |  |  | Measure the length of a wall or line, or the perimeter of a floor, roof or region. |
| Demolish |  |  | Mark picked elements (and their doors and windows) as demolished in the view's phase. |
| Array Number… |  |  | Change the number of members of the selected array group; the copies are regenerated. |
| Scale |  | `RE` | Resize lines, walls, regions and images about a base point, graphically or by a factor. |
| Edit Surface |  |  | Add, delete or re-level the points of the selected toposurface. |
| Simplify Surface… |  |  | Remove survey points that barely change the selected toposolid or toposurface. |
| Excavate |  |  | Lower or raise the selected toposolid to the underside of the selected floors and building pads, and record the cut and fill. |
| Snap to Work Plane Grid (Next Pick) |  | `SW` | Snap only to grid intersections for the next pick (Arcus has no separate work plane grid in 2D views). |
| Snap to Points (Next Pick) |  | `SX` | Snap only to points (element end and centre points) for the next pick. |
| Snap to Remote Objects (Next Pick) |  | `SR` | Snap to objects farther from the pointer than usual for the next pick. |
| Snap Close (Next Pick) |  | `SZ` | Snap only to endpoints for the next pick, to close a chain on its start point. |
| Turn Override Off |  | `SS` | Cancel a snap override typed for the next pick; the normal snaps apply again. |
| Repeat Last Command |  | `RC` | Run the last creation or modify command again. Return in Modify does the same. |
| Select Joined Elements |  |  | Adds the elements joined to the selection. |

### Architecture

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Wall |  | `WA` | Draw walls with lines; chain by default. |
| Wall – Arc |  |  | Draw a curved wall through three points. |
| Wall – Rectangle |  |  | Draw four walls from two corners. |
| Wall – Pick Lines |  |  | Create walls on picked lines, grids or CAD geometry. |
| Door |  | `DR` | Place a door in a wall. |
| Window |  | `WN` | Place a window in a wall. |
| Component |  | `CM` | Place furniture, casework, fixtures and generic models. |
| Column: Architectural |  |  | Place architectural columns. |
| Floor |  | `FL` | Sketch a floor boundary. |
| Floor – Pick Walls |  |  | Create a floor from the walls enclosing a picked area. |
| Ceiling |  |  | Sketch a ceiling or pick a room to fill. |
| Roof by Footprint |  | `RF` | Sketch a roof footprint with slope-defining edges. |
| Roof – Pick Walls |  |  | Create a hip roof over the walls enclosing a picked area. |
| Stair – Straight |  |  | Place a straight stair by picking start and direction. |
| Stair – L-Shaped |  |  | Place an L-shaped stair with a landing. |
| Stair – U-Shaped |  |  | Place a U-shaped stair with a landing. |
| Railing |  | `RA` | Sketch a railing path. |
| Room |  | `RM` | Place rooms in enclosed regions. |
| Room Separator |  | `RS` | Draw lines that divide rooms without walls. |
| Area |  |  | Place areas in an area plan. |
| Area Boundary |  |  | Draw area boundary lines. |
| Model Line |  | `LI` | Draw 3D model lines on the level. |
| Grid |  | `GR` | Draw grid lines; names increment automatically. |
| Level |  | `LL` | Add a level (in an elevation or section) with plan views. |
| Reference Plane |  | `RP` | Draw a reference plane. |
| Property Line |  |  | Sketch site property lines. |
| Toposurface |  |  | Create terrain from picked points and elevations. |
| Building Pad |  |  | Sketch a building pad. |
| Wall – Curtain Wall |  |  | Draw curtain walls: glazed panels on a grid with mullions. |
| Curtain Grid |  | `CG` | Add grid lines to a curtain wall, or remove grid lines you added. |
| Mullion |  | `MU` | Add mullions to curtain grid lines, or remove them. |
| Curtain Panel |  |  | Swap curtain wall panels to the panel type chosen in the type selector. |
| Wall Opening |  |  | Cut a rectangular opening in a wall from an elevation or section. |
| Shaft |  |  | Sketch a shaft that cuts every floor, ceiling and roof between its base and top. |
| Ramp |  |  | Draw a ramp run from its bottom to its top; clicks between turn at landings. Railings are added on both sides. |
| Roof by Extrusion |  |  | Sketch an open roof profile in an elevation or section and extrude it perpendicular to the work plane. |
| Grid – Pick Lines |  |  | Create grid lines on picked lines, walls or CAD lines. |
| Place Rooms Automatically |  |  | Place a tagged room in every enclosed region of the level that has none. |
| Place Areas Automatically |  |  | Place a tagged area in every region enclosed by area boundaries that has none. |
| Color Schemes… |  |  | Colour rooms or areas by a parameter value or range, and choose the view's scheme. |
| Toposurface from Point File… |  |  | Create a toposurface from a CSV, TXT or XYZ file of x, y, z survey points. |
| Toposurface from Import… |  |  | Create a toposurface from the contour lines and points on chosen layers of a linked or imported DXF/DWG. |
| Sub-Region |  |  | Sketch an area of a toposurface with its own material (paving, lawn, planting beds). |
| Split Surface |  |  | Split a toposurface in two along a sketched line. |
| Merge Surfaces |  |  | Join the selected toposurfaces into one. |
| Graded Region |  |  | Copy a toposurface as the proposed (graded) ground: the existing surface is demolished in the view's phase and the copy opens for editing. |
| Site Component |  |  | Place trees, planting, entourage and site furniture. |
| Parking Component |  |  | Place parking stalls, signs and other parking components. |
| Parking Layout |  |  | Fill a sketched or picked area with painted parking stalls at 90°, 60° or 45°, with optional wheel stops, and report the stall count. |
| Wall: Sweep |  |  | Add a horizontal sweep (base course, string course, cornice) to the selected walls; set its height, size and side in Properties. |
| Floor: Slab Edge |  |  | Add a thickened slab edge under the selected floors; set its width and depth in Properties. |
| Roof: Soffit |  |  | Add a flat soffit under the eaves of the selected roofs; set its depth in Properties. |
| Toposolid |  |  | Sketch the boundary of a layered site solid; shape it afterwards with Edit Surface. |
| Toposolid from Point File… |  |  | Create a toposolid from a CSV, TXT or XYZ file of x, y, z survey points. |
| Toposolid from Import… |  |  | Create a toposolid from the contour lines and points on chosen layers of a linked or imported DXF/DWG. |
| Generate Toposolid |  |  | Replace the selected legacy toposurface with a toposolid; its sub-regions become sub-divisions. |
| Sub-Divide |  |  | Sketch an area of a toposolid as a thin layered solid (paving, lawn, planting beds) that follows its surface. |
| Model Text |  |  | Places three-dimensional text in the model. |
| Wall: Reveal |  |  | Cuts a reveal into a wall face: click the face in a 3D, elevation or section view. |
| By Face |  |  | Cuts an opening perpendicular to the selected face of a roof, floor or ceiling. |
| Vertical Opening |  |  | Cuts a vertical opening through a roof, floor or ceiling. |
| Dormer Opening |  |  | Cuts a roof where a dormer meets it: pick the roof, then the dormer's walls and edges. |
| Place Model Group |  |  | Places an instance of a model group. |
| Highlight Boundaries |  |  | Highlights the room-bounding elements of the level. |
| Wall: Stacked |  |  | Draws walls of a stacked wall type: basic wall types stacked by height. Edit the stack in Type Properties. |
| Grid: Multi-Segment |  |  | Sketches a grid of several connected segments. |
| Set Work Plane |  |  | Specifies the work plane of the current view: a level, a named reference plane, or a plane you pick. |
| Show Work Plane |  |  | Shows or hides the work plane grid in the current view. |
| Work Plane Viewer |  |  | Opens a viewer of the current work plane. |
| Connect Levels |  |  | Repeats the stair through the selected levels (multistory stair). |
| Boundary Line |  |  | Draws the boundary lines of the sketch. |
| Slope Arrow |  |  | Draws a slope arrow: the floor or roof rises from its tail to its head. |
| Align Eaves |  |  | Aligns the eaves of the roof being sketched: pick the eave to match, then the eaves to align. |
| Adjust Height |  |  | Aligns the picked eaves by adjusting the roof height. Available in Align Eaves mode. |
| Adjust Overhang |  |  | Aligns the picked eaves by adjusting the overhang. Available in Align Eaves mode. |
| Space |  |  | Places a space in a region bounded by walls or space separators. |
| Space Separator |  |  | Draws lines that bound spaces where there are no walls. |
| Show Mass |  |  | Shows or hides conceptual masses in every view. |
| In-Place Mass |  |  | Sketches the footprint of a conceptual mass and extrudes it to a height. |
| Curtain System by Face |  |  | Creates curtain walls on the vertical faces of the selected mass. |
| Roof by Face |  |  | Creates a roof on the top face of the selected mass. |
| Wall by Face |  |  | Creates walls on the vertical faces of the selected mass. |
| Floor by Face |  |  | Creates floors where levels cut the selected mass (mass floors). |
| Model In-place |  |  | Creates an in-place family: unique geometry modelled in the context of the project. |

### Structure

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Structural Column |  | `CL` | Place structural columns. |
| Beam |  | `BM` | Draw beams between points or supports. |
| Isolated Foundation |  |  | Add a pad footing under each selected structural column. |
| Wall Foundation |  | `FT` | Add a strip footing under each selected wall. |
| Foundation Slab |  |  | Sketch a structural foundation slab. |
| Structural Wall |  |  | Draw load-bearing walls (Structural is on). |
| Structural Floor |  | `SB` | Sketch a structural floor (Structural is on). |
| Vertical Column |  |  | Places vertical columns. |
| Slanted Column |  |  | Places slanted columns: click the base, then the top. |
| Columns at Grids |  |  | Places structural columns at the intersections of the grids you select; click Finish when done. |
| Columns at Columns |  |  | Places structural columns inside the architectural columns you select; click Finish when done. |
| Finish Placing Columns |  |  | Places the columns. |
| Cancel Placing Columns |  |  | Cancels placing multiple columns. |
| Truss |  |  | Places a flat truss of chords and diagonal members between two points. |
| Brace |  | `BR` | Adds diagonal braces from the current level up to the level above. |
| Beam System |  | `BS` | Sketches a bay and fills it with parallel beams at a fixed spacing. |
| Rebar |  | `RB` | Places a set of straight bars in a floor or slab at its bottom cover: click the bar's start and end. |
| Area |  |  | Reinforces a sketched area of a floor or slab with top and bottom bar layers both ways. |
| Path |  |  | Places bars along a sketched path in a floor or slab, each running into it at the path's spacing. |
| Fabric Area |  |  | Lays welded wire fabric sheets over a sketched area of a floor or slab, lapped at their edges. |
| Fabric Sheet |  |  | Places a single welded wire fabric sheet in a floor or slab. |
| Cover |  |  | Rebar Cover Settings: the concrete cover to the bars. |
| Rebar Coupler |  |  | Places couplers on the ends of a rebar set's bars, or between two sets that meet end to end. |
| Place on Bar End |  |  | Places couplers on the end of the bars you pick. |
| Place between Two Bars |  |  | Places couplers where two rebar sets meet end to end. |

### Insert

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Load Family… |  |  | Load .arcusfamily files into the project. |
| Reload Family |  |  | Reload a family from its file. |
| Load Type Catalog… |  |  | Load family types from a CSV type catalog. |
| Link DWG… |  |  | Link a DWG drawing (requires the licensed DWG SDK). |
| Import DWG… |  |  | Import a DWG drawing snapshot (requires the licensed DWG SDK). |
| Link DXF… |  |  | Link a DXF drawing. |
| Import DXF… |  |  | Import a DXF drawing snapshot. |
| Link CAD… |  |  | Link a CAD drawing (DXF, or DWG through the DWG converter or SDK); choose the format in the file dialog. |
| Import CAD… |  |  | Import a snapshot of a CAD drawing (DXF, or DWG through the DWG converter or SDK); choose the format in the file dialog. |
| Manage Links |  |  | Reload, relocate, unload or remove links. |
| Reload Link |  |  | Reload the selected link from its source. |
| Unload Link |  |  | Unload the selected link. |
| Explode… |  |  | Convert CAD geometry to detail or model lines. |
| Import IFC… |  |  | Import an IFC model; unsupported items stay as reference geometry. |
| Import Revit Model… |  |  | Import a .arcusx export from the Arcus Bridge add-in as native, editable elements and families, or inspect a .rvt/.rfa file. |
| Link PDF… |  |  | Place a PDF page as a scaled underlay. |
| Link Image… |  |  | Place a PNG, JPEG or TIFF image. |
| Component Library… |  | `LB` | Browse the built-in library of furniture, casework, fixtures, lighting, equipment, planting, entourage and parking, and place any item; a family is loaded when first placed. |
| Site & Parking Library… |  |  | Open the component library on planting, entourage, site furniture and parking content. |
| Link Model… |  |  | Links another Arcus project (.arcus) as a read-only model, internal origin to internal origin. It shows in plans at this view's cut plane, in sections, elevations and 3D, and is re-read when this project opens. |
| Link IFC… |  |  | Links an IFC model as a read-only model, internal origin to internal origin. It is re-read when this project opens. |
| Link Topography… |  |  | Links surveyed points (XYZ, PTS, CSV or TXT: x y z per line) as a toposolid through them. The toposolid follows the file when the project opens. |
| DWF Markup… |  |  | Links the markups of a DWFx file (lines, text and pictures) onto the matching sheets. |
| Place Decal |  |  | Places an image on a face of the model: a wall, floor, roof or other planar face. The image shows in the Realistic visual style. |
| Decal Types… |  |  | Creates and edits decal types: the image and how it renders. |
| Point Cloud… |  |  | Links a point cloud (XYZ, PTS, CSV, TXT or ASCII PLY: x y z [r g b] per line) into the project. Dense clouds are thinned evenly. |
| Coordination Model… |  |  | Links a coordination model (OBJ) for reference in 3D views. It is re-read when this project opens. |
| Import gbXML… |  |  | Imports the spaces of a gbXML file as rooms, each bounded by room separation lines along its outline. |
| Import PDF… |  |  | Imports a page of a PDF file into the current view or sheet; it is stored in the project. |
| Import Image… |  |  | Places a raster image (PNG, JPEG, TIFF or BMP) in the current view or sheet; it is stored in the project. |
| Load as Group… |  |  | Loads the model of another Arcus project as a model group, placed at the internal origin. |
| Insert Views from File… |  |  | Copies drafting views, legends and schedules (with their 2D content) from another project file. |
| Insert 2D Elements from File… |  |  | Copies the 2D elements of a drafting view or legend in another project into the current view. |

### Annotate

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Aligned Dimension |  | `DI` | Dimension between parallel references or points. |
| Linear Dimension |  |  | Horizontal or vertical dimension between points. |
| Angular Dimension |  |  | Measure the angle between two lines. |
| Radial Dimension |  |  | Measure the radius of an arc. |
| Diameter Dimension |  |  | Measure the diameter of an arc or circle. |
| Arc Length Dimension |  |  | Measure the length of an arc. |
| Spot Elevation |  | `EL` | Label the elevation of a point. |
| Spot Coordinate |  |  | Label the N/E coordinates of a point. |
| Spot Slope |  |  | Label the slope of a surface. |
| Detail Line |  | `DL` | Draw view-specific lines. |
| Filled Region |  |  | Sketch a hatched or filled region. |
| Masking Region |  |  | Sketch a region that hides elements behind it. |
| Detail Component |  |  | Place 2D detail components. |
| Insulation |  |  | Draw batt insulation. |
| Text |  | `TX` | Place a text note with optional leaders. |
| Tag by Category |  | `TG` | Tag elements by clicking them. |
| Tag All |  |  | Tag every untagged element of chosen categories in the view. |
| Tag Room |  | `RT` | Tag rooms. |
| Symbol |  |  | Place annotation symbols. |
| Revision Cloud |  |  | Sketch a revision cloud assigned to a revision. |
| North Arrow |  |  | Place a north arrow symbol. |
| Color Fill Legend |  |  | Place a legend listing the colour fill values used in the view. |
| Label Contours |  |  | Draw a line across contours to label their elevations. |
| Repeating Detail Component |  |  | Draw a path along which a detail component repeats (brick coursing, blocking). |
| Legend Component |  |  | Place the plan symbol of a door, window, furniture, wall or floor type in a legend view. |
| Place Detail Group |  |  | Place a copy of a detail group in this view. |
| Create Detail Group |  |  | Group the selected detail lines, regions, components and text of this view. |
| Check Spelling |  |  | Check the spelling of text notes in this view (or the selected notes) with the system dictionary, on this Mac. |
| Find/Replace |  |  | Find and replace text in text notes and in the values tags show, with a preview of every change. |
| Multi-Category Tag |  |  | Tag elements of any category with one tag showing their mark. |
| Material Tag |  |  | Tag the material of the element or wall layer under the pointer. |
| Tag Area |  |  | Tag areas with their name and area. |
| View Reference |  |  | Place a reference to another view: its detail and sheet number. Double-click it to open the view. |
| Element Keynote |  |  | Keynote an element with its type's Keynote. |
| Material Keynote |  |  | Keynote the material under the pointer with the material's Keynote. |
| User Keynote |  |  | Keynote an element with a key chosen from the keynote table. |
| Tread Number |  |  | Number the treads of a stair, on the side of the run you click. |
| Beam Annotations |  |  | Tag every untagged beam in the view at its midpoint. |
| Scale Bar |  |  | Place a graphic scale for this view's scale. |
| Span Direction |  |  | Show the span direction of a floor with a symbol. |
| Stair Path |  |  | Draw the walk line of a stair with its direction arrow and UP label. |
| Add Leader |  |  | Add a leader to the selected text notes, toward the nearest free side. |
| Remove Leader |  |  | Remove the last leader of the selected text notes. |
| Beam |  |  | Places a beam system symbol on a beam: a span arrow with its type. |
| Area |  |  | Places an area reinforcement symbol and tag on an area reinforcement. |
| Path |  |  | Places a path reinforcement symbol and tag on a path reinforcement. |
| Rebar |  |  | Places a rebar symbol across a rebar set with its quantity, size and spacing. |
| Fabric |  |  | Places a fabric reinforcement symbol on a fabric area or sheet. |
| Aligned Multi-Rebar Annotation |  |  | Dimensions the bars of a rebar set across the set, with its tag. |
| Linear Multi-Rebar Annotation |  |  | Dimensions the bars of a rebar set horizontally or vertically, with its tag. |
| Space Tag |  |  | Tags a space with its name and number. |
| Keynoting Settings |  |  | Chooses the keynote table and how keynote tags read. |

### View

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Floor Plan |  |  | Create floor plans for levels. |
| Reflected Ceiling Plan |  |  | Create reflected ceiling plans. |
| Structural Plan |  |  | Create structural plans. |
| Section |  |  | Draw a section line; a section view is created. |
| Elevation |  | `EV` | Place an elevation marker; an elevation view is created. |
| Callout |  |  | Sketch a callout; an enlarged plan view is created. |
| Drafting View |  |  | Create a view for 2D drafting. |
| Legend |  |  | Create a legend view. |
| Default 3D View |  | `3D` | Open the 3D coordination view. |
| Schedule/Quantities |  |  | Create a live schedule of a category. |
| Material Takeoff |  |  | Schedule material quantities. |
| Sheet List |  |  | Create a sheet list. |
| Revision Schedule |  |  | Create a revision schedule. |
| Sheet |  |  | Create a sheet from a title block. |
| Place View |  |  | Place a view or schedule on the active sheet. |
| Duplicate View |  |  | Duplicate the view without annotations. |
| Duplicate with Detailing |  |  | Duplicate the view with its annotations. |
| Duplicate as Dependent |  |  | Duplicate with a separate crop that follows the parent's settings. |
| Rename… | `F2` |  | Rename the selected view, sheet or schedule. |
| Apply View Template… |  |  | Apply a view template's settings. |
| Visibility/Graphics |  | `VG` `VV` | Category visibility, filters and overrides for the view. |
| View Range… |  |  | Set the cut plane and view depth. |
| Crop View |  |  | Toggle cropping. |
| Show Crop Region |  |  | Toggle crop region visibility. |
| Section Box |  |  | Toggle the 3D section box. |
| Thin Lines |  | `TL` | Show all lines at one pixel on screen (printing unaffected). |
| Hide Element |  | `HH` | Temporarily hide selected elements. |
| Isolate Element |  | `HI` | Temporarily show only the selection. |
| Hide Category |  | `HC` | Temporarily hide the selection's categories. |
| Isolate Category |  | `IC` | Temporarily show only the selection's categories. |
| Reset Temporary Hide/Isolate |  | `HR` | Restore the view after temporary hide/isolate. |
| Reveal Hidden Elements |  | `RH` | Show elements hidden in the view; unhide them from here. |
| Hide in View |  | `EH` | Permanently hide selected elements in this view. |
| Unhide in View |  | `EU` | Unhide selected elements in this view. |
| Zoom to Fit | `⌘0` | `ZE` `ZF` `ZX` | Zoom to show the whole view. |
| Zoom in Region |  | `ZR` `ZZ` | Drag a rectangle to zoom into. |
| Zoom In | `⌘+` |  | Zoom in. |
| Zoom Out | `⌘−` |  | Zoom out. |
| Zoom Out (2x) |  | `ZO` `ZV` | Halve the magnification around the centre of the view. |
| Zoom Sheet Size |  | `ZS` | Zoom so the drawing appears at its printed size. |
| Previous Pan/Zoom |  | `ZP` `ZC` | Step back to the previous pan and zoom of this view. |
| Next Pan/Zoom |  |  | Step forward again after Previous Pan/Zoom. |
| Previous View | `⌘[` |  | Return to the previously active view. |
| Close Inactive Views |  |  | Close every view tab except the active one. |
| Save 3D Orientation |  |  | Save the current 3D camera as a new 3D view. |
| Coarse |  |  | Coarse detail level. |
| Medium |  |  | Medium detail level. |
| Fine |  |  | Fine detail level. |
| Wireframe |  | `WF` | Wireframe visual style. |
| Hidden Line |  | `HL` | Hidden line visual style. |
| Shaded |  | `SD` | Shaded visual style. |
| Consistent Colors |  |  | Unlit material colors. |
| Transparent |  |  | Transparent visual style. |
| Schedule Properties |  |  | Fields, filter, sorting/grouping, formatting and appearance of the active schedule. |
| Insert Column |  |  | Add fields to the schedule (opens Schedule Properties, Fields). |
| Delete Column |  |  | Remove the fields of the selected columns from the schedule. |
| Hide Column |  |  | Hide the selected columns (they still filter and sort). |
| Unhide All |  |  | Show every hidden column. |
| Resize Column… |  |  | Set the width of the selected columns on paper. |
| Insert Data Row |  |  | Add a row where rows are records created here (sheet lists: a new sheet). |
| Delete Row |  |  | Delete the elements of the selected rows from the model. |
| Merge Unmerge |  |  | Merge the selected column headers under one heading, or unmerge them. |
| Group |  |  | Group the selected column headers under a new heading. |
| Ungroup |  |  | Remove the heading group of the selected columns. |
| Appearance |  |  | Grid lines, outline, text sizes and header shading of the schedule. |
| Format Unit |  |  | Heading, alignment, decimals and totals of the selected column. |
| Calculated |  |  | Add a calculated value (formula) field. |
| Highlight in Model |  |  | Select the elements of the selected schedule rows in a model view and zoom to them (also Option-double-click a row). |
| Filters… |  |  | Create and edit rule-based view filters: several categories, rules joined by AND or OR, and nested rule sets. |
| Manage View Templates… |  |  | Create, rename, duplicate and edit view templates and choose which settings each controls. |
| Create Template from Current View… |  |  | Save the current view's scale, detail level, visual style, view range, phase filter and V/G overrides as a view template. |
| Apply Template Properties to Current View… |  |  | Copy a view template's settings into the current view once, without assigning the template. |
| Temporary View Properties |  |  | Apply a view template to this view until you restore it; nothing is saved. |
| Reveal Constraints |  |  | Show locked dimensions, alignments and EQ constraints in this view. |
| User Interface… |  |  | Show or hide the Properties palette, Project Browser, status bar and navigation bar. |
| Selection Box |  | `BX` | Open a 3D view with its section box fitted around the selected elements. |
| Override Graphics in View… |  | `EOD` | Change line colour, weight and pattern, fills, halftone and transparency of the selected elements in this view only. |
| Activate View |  |  | Edit the selected viewport's view in place on the sheet; other viewports dim. |
| Deactivate View |  |  | Return to editing the sheet after working in a viewport. |
| Camera |  |  | Place a camera in a plan (eye, then target) to create a perspective 3D view. |
| Scope Box |  |  | Draw a scope box that limits where levels, grids and reference planes appear and can crop plan views. |
| Show Project Base Point |  |  | Show or hide the project base point in this view. |
| Show Survey Point |  |  | Show or hide the survey point in this view. |
| Area Plan |  |  | Create area plans for a gross or rentable area scheme, with boundary lines from exterior walls. |
| Front View | `⌃⌥1` |  | Look at the model from the front (south). Keypad 1 in a 3D view. |
| Back View | `⌃⌥⌘1` |  | Look at the model from the back (north). ⌃ keypad 1 in a 3D view. |
| Right View | `⌃⌥3` |  | Look at the model from the right (east). Keypad 3 in a 3D view. |
| Left View | `⌃⌥⌘3` |  | Look at the model from the left (west). ⌃ keypad 3 in a 3D view. |
| Top View | `⌃⌥7` |  | Look straight down at the model. Keypad 7 in a 3D view. |
| Bottom View | `⌃⌥⌘7` |  | Look straight up at the model. ⌃ keypad 7 in a 3D view. |
| Perspective/Orthographic | `⌃⌥5` |  | Switch the 3D view between perspective and orthographic projection. Keypad 5 in a 3D view. |
| Frame Selected | `⌃⌥.` |  | Zoom the 3D view to the selected elements. Keypad . in a 3D view. |
| Fly Navigation | `⌃⌥F` |  | Fly through the 3D view: move the mouse to look, W A S D to move, Q/E down/up, scroll for speed; Return keeps, Esc cancels. ⇧F in a 3D view. |
| View Through Camera | `⌃⌥0` |  | Look through the active camera in this 3D view (again to go back). Keypad 0 in a 3D view. |
| Align Camera to View | `⌃⌥⌘0` |  | Move the active camera (or this camera view's camera) to the current 3D view. ⌃⌥ keypad 0 in a 3D view. |
| Lock Camera to View | `⌃⌥L` |  | When on, navigating a camera view (or looking through a camera) moves the camera; when off, navigating leaves the saved camera alone. |
| Create Camera from View |  |  | Save the current 3D view as a new camera. |
| Zoom All to Fit |  | `ZA` | Zoom every open view to show its whole contents. |
| View Properties |  | `VP` | Clear the selection and show the active view's properties. |
| Find Referring Views… |  |  | List the views that show the selected element and open one. |
| Hide Category in View |  | `VH` | Hide every element of the selected elements' categories in this view (Visibility/Graphics). |
| Hide by Filter… |  |  | Open Visibility/Graphics on its Filters to hide elements by a filter in this view. |
| Override Graphics by Category… |  |  | Open Visibility/Graphics to override the graphics of a whole category in this view. |
| Override Graphics by Filter… |  |  | Open Visibility/Graphics on its Filters to override graphics by a filter in this view. |
| Show Hidden Lines |  |  | Shows the lines of an element hidden by another element as dashed lines. |
| Remove Hidden Lines |  |  | Stops showing the hidden lines of an element. |
| Cut Profile |  |  | Changes the shape of a cut wall in this view only: pick the wall, then sketch the region to add or cut away. |
| Render |  | `RR` | Renders the 3D view: quality, resolution, sun lighting and sky; save the image to the project or export it. |
| Render Gallery |  |  | Shows the renderings saved in the project, to export as PNG images or delete. |
| Export OBJ |  |  | Exports the model as OBJ with materials, for visualisation apps. |
| Framing Elevation |  |  | Places an elevation beside a grid, looking at it and cropped to it: click near the grid on the side to look from. |
| Sketch |  |  | Sketches the boundary of a callout of any shape. |
| Walkthrough |  |  | Places a walkthrough in a plan: click the camera's path, then Finish Walkthrough. |
| Finish Walkthrough |  |  | Creates the walkthrough from the clicked path. |
| Previous Frame |  |  | Shows the walkthrough's previous frame. |
| Next Frame |  |  | Shows the walkthrough's next frame. |
| Play |  |  | Plays the walkthrough from the current frame (again to stop). |
| Export |  |  | Exports the walkthrough's frames as PNG images, or as a QuickTime movie. |
| Title Block |  |  | Changes the title block of the sheet. |
| Guide Grid |  |  | Shows a guide grid on the sheet; viewports snap to it. |
| Matchline |  |  | Draws a matchline where a plan continues on another sheet. |
| Switch Windows |  |  | Switches to another open view. |
| Tab Views |  | `TW` | Arranges open views as tabs. |
| Tile Views |  | `WT` | Tiles open views side by side. |
| Canvas Theme |  |  | Switches the view canvas between the light, dark and black theme. |
| Navigation Wheel |  |  | The 2D Wheel (Zoom, Pan, Rewind) of plans, sections and sheets, or the Full Navigation Wheel of 3D views: press a wedge and drag. Esc closes it. |
| Combine Parameters |  |  | Combines several parameters into one column. |
| Insert Row |  |  | Inserts a row in the header. |
| Insert Row Above Selected |  |  | Inserts a header row above the selected row. |
| Insert Row Below Selected |  |  | Inserts a header row below the selected row. |
| Resize Row |  |  | Sets the height of the selected row. |
| Insert Image |  |  | Inserts an image in a header cell. |
| Clear Cell |  |  | Clears the text of a header cell. |
| Freeze Header |  |  | Keeps the title and headers in view while scrolling. |
| Shading |  |  | Sets the background colour of cells. |
| Borders |  |  | Sets the borders of cells. |
| Reset |  |  | Resets the appearance of cells. |
| Font |  |  | Sets the font of cells. |
| Align Left |  |  | Aligns the selected column: left. |
| Align Center |  |  | Aligns the selected column: center. |
| Align Right |  |  | Aligns the selected column: right. |
| Align Top |  |  | Aligns the selected cells' text to the top. |
| Align Middle |  |  | Aligns the selected cells' text to the middle. |
| Align Bottom |  |  | Aligns the selected cells' text to the bottom. |
| Split & Place |  |  | Splits the schedule and places the parts on a sheet. |
| Keynote Legend |  |  | Creates a legend listing the keynotes used in the project. |

### Manage

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Project Information |  |  | Edit project name, number, client and address. |
| Project Units |  | `UN` | Set length, area, volume, angle and slope units. |
| Project Parameters |  |  | Add parameters to categories. |
| Shared Parameters |  |  | Import/export shared parameter definitions. |
| Materials |  |  | Browse and edit materials. |
| Line Styles |  |  | Detail line styles. |
| Snaps… |  |  | Choose object snaps, the angle increment and whether snapping is on. |
| Phases |  |  | Project phases and phase filters. |
| Design Options |  |  | Option sets and options. |
| Sheet Issues/Revisions |  |  | Revision sequence, dates and issue status. |
| Location |  |  | Site location, true north, project base point and survey point. |
| Edit Family |  |  | Open the selected family in the Family Editor. |
| New Family… |  |  | Create a family from a category template. |
| Purge Unused |  |  | Remove unused types, families and materials. |
| Model Health |  |  | Warnings and model checks with navigation to elements. |
| Diagnostics |  |  | Version, performance timings and a redacted local log. |
| Object Styles… |  |  | Line weights, colours, patterns and materials of every category and subcategory, for all views. |
| Warnings… |  |  | Review warnings: expand to the elements, show or delete them, and export a report. |
| Select by ID… |  |  | Select elements by their ids. |
| IDs of Selection |  |  | Show the ids of the selected elements, ready to copy. |
| Additional Settings… |  |  | Line weights, line patterns, fill patterns, arrowheads and temporary dimensions. |
| Line Weights… |  |  | Pen widths of the line weights at each view scale. |
| Line Patterns… |  |  | The dash patterns lines can use. |
| Fill Patterns… |  |  | Drafting and model fill patterns used by materials, regions and overrides. |
| Arrowheads… |  |  | Dimension terminators and annotation arrowheads. |
| Temporary Dimensions… |  |  | Measure temporary dimensions of walls from their centerlines or faces. |
| Load Standard Types |  |  | Add the standard wall, floor, roof, ceiling, door, window and column types for the project's units that the project doesn't have yet. |
| Site Settings… |  |  | Contour interval, primary contours and contour display for toposurfaces. |
| Structural Settings |  |  | Symbolic cutbacks, brace symbols, load cases and load combinations. |
| Transfer Project Standards… |  |  | Copies types, materials, styles, view templates and parameters from another project file. |
| Global Parameters |  |  | Creates project-wide values that drive dimensions and element parameters. |
| Specify Coordinates at Point |  |  | Click a point and enter its shared coordinates (North/South, East/West, Elevation) and the angle to true north. |
| Report Shared Coordinates |  |  | Click points to read their shared coordinates. |
| Relocate Project |  |  | Moves the project against the shared coordinates: click a start and an end point. |
| Rotate True North |  |  | Sets the angle between project north and true north. |
| Rotate Project North |  |  | Turns the whole project (model and views) 90° or 180° about its origin; true north stays where it is. |
| Mirror Project |  |  | Mirrors the whole project about its north-south or east-west axis. |
| Add to Set |  |  | Moves the selected main model elements into design options of a set. |
| Pick to Edit |  |  | Click an element to edit the design option it belongs to. |
| Starting View |  |  | Specifies the view that opens when the project opens. |
| Save Selection |  |  | Saves the current selection so it can be loaded later. |
| Load Selection |  |  | Loads a saved selection. |
| Edit Selection |  |  | Renames or deletes saved selections. |
| Extrusion |  |  | Creates a solid by extruding a closed sketch perpendicular to the work plane. |
| Blend |  |  | Creates a solid that blends a base sketch into a top sketch. |
| Revolve |  |  | Creates a solid by revolving a sketch about an axis. |
| Sweep |  |  | Creates a solid by sweeping a profile along a path. |
| Swept Blend |  |  | Creates a solid swept along a path between two profiles. |
| Void Extrusion |  |  | Creates a void that cuts solids by extruding a closed sketch. |
| Void Blend |  |  | Creates a void blending a base sketch into a top sketch. |
| Void Revolve |  |  | Creates a void by revolving a sketch. |
| Void Sweep |  |  | Creates a void by sweeping a profile along a path. |
| Model Line |  |  | Draws lines that exist in 3D in the family. |
| Component |  |  | Places a nested family in the family. |
| Model Text |  |  | Places 3D text in the family. |
| Opening |  |  | Cuts an opening in the host of a hosted family. |
| Control |  |  | Adds flip arrows to the family. |
| Reference Line |  |  | Draws a reference line to drive angles and rigs. |
| Reference Plane |  |  | Draws reference planes that the family's geometry locks to. |
| Aligned |  |  | Dimensions between parallel reference planes; label it with a parameter to make it flex. |
| Symbolic Line |  |  | Draws lines shown in plan instead of the family's geometry. |
| Family Types |  |  | Creates types, adds parameters and sets their values and formulas. |
| Family Category and Parameters |  |  | Sets the family's category and its family parameters. |
| Load into Project |  |  | Loads the family into the project. |
| Load into Project and Close |  |  | Loads the family into the project and closes the family. |
| Finish Edit Mode |  |  | Finishes the sketch. |
| Cancel Edit Mode |  |  | Abandons the sketch. |
| Default 3D View |  |  | Opens the family's default 3D view, with orbit. |
| Single Vertical |  |  | Places a vertical flip control (flips the facing). |
| Double Vertical |  |  | Places a double vertical flip control (flips the facing). |
| Single Horizontal |  |  | Places a horizontal flip control (flips the hand). |
| Double Horizontal |  |  | Places a double horizontal flip control (flips the hand). |
| Filled Region |  |  | Sketches a filled region shown with the family in plan. |
| Masking Region |  |  | Sketches a masking region shown with the family in plan. |
| Text |  |  | Places static text in the family's plan (labels show a parameter instead). |
| Set Work Plane |  |  | Specifies the work plane of the current view: a named reference plane new forms, lines and text start from. |
| Show Work Plane |  |  | Shows or hides the work plane grid in the current view. |
| Load Family into Family… |  |  | Loads a family file into this family, to place as a nested component or use as a sweep profile. |
| Purge Unused Families |  |  | Removes families loaded into this family that no component or sweep uses. |
| Flex Test |  |  | Evaluates every type, and each length parameter at 50% and 150%, reporting geometry and constraint failures. |
| Save Family As… |  |  | Saves the family as a .arcusfamily file. |

### File

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Export IFC… |  |  | Export the architectural model to IFC2x3 or IFC4. |
| Export PDF… | `⌥⌘P` |  | Export sheets and views to vector PDF. |
| Export DXF… |  |  | Export the current view's 2D linework to DXF. |
| Export Schedule CSV… |  |  | Export the active schedule to CSV. |
| Import Schedule CSV… |  |  | Update writable schedule columns from a CSV file. |
| Export Image… |  |  | Save the active view or sheet as a PNG or JPEG image, rendered on this Mac. |
| New Title Block… |  |  | Open the Family Editor on a new title block family. |
| New Annotation Symbol… |  |  | Open the Family Editor on a new generic annotation family. |
| Print… | `⌘P` |  | Print sheets or views. |
| Home |  |  | Show the Home screen: start a project, open one, or pick a recent project. |
| New Project… | `⌘N` |  | Create a project from a template. |
| Open… | `⌘O` |  | Open an Arcus project. |
| Save | `⌘S` |  | Save the project. |
| Save As… | `⇧⌘S` |  | Save a copy under a new name. |
| Duplicate |  |  | Duplicate the project document. |
| Revert To Saved |  |  | Discard changes since the last save. |
| Close | `⌘W` |  | Close the project window. |
| Save Recovery Copy… |  |  | Write every readable element into a new project file. |
| Save as Template… |  |  | Save this project's types, families, views, sheets and settings, without model elements, as a template for new projects. |
| Export DWF/DWFx… |  |  | Exports views and sheets to a DWFx file (for markup and review). |
| Export STL… |  |  | Exports the model as an STL file (millimetres). |
| Export gbXML… |  |  | Saves the rooms and spaces as a gbXML file. |
| Export Room/Area Report… |  |  | Saves an HTML report of the rooms with their areas and shapes. |
| Export Family Types… |  |  | Exports the family's types to a type catalog (.txt). |
| Print Preview |  |  | Shows how the current view or sheet will print. |
| Print Setup… |  |  | Specifies the paper, zoom, colors and options used to print. |

### Arcus

| Command | Shortcut | Typed alias | What it does |
|---|---|---|---|
| Command Search | `⌘K` |  | Find any command by name, alias or keyword. |
| Settings… | `⌘,` |  | Arcus settings. |
| BIM Familiar Workspace |  |  | Properties above the Project Browser on the left. |
| Mac Spacious Workspace |  |  | Project Browser on the left, Properties inspector on the right. |
| Reset Workspace |  |  | Restore the default panel layout. |
| Project Browser | `⌥⌘1` |  | Show or hide the Project Browser. |
| Properties | `⌥⌘2` | `PP` | Show or hide the Properties inspector. |
| Keyboard Shortcuts… |  | `KS` | View, edit, import and export command aliases. |
| Welcome to Arcus |  |  | Show the welcome guide. |
| About Arcus |  |  | Version and build information. |
| Undo | `⌘Z` |  | Undo the last change. |
| Redo | `⇧⌘Z` |  | Redo. |
| Cut | `⌘X` |  | Cut to the clipboard. |
| Copy | `⌘C` |  | Copy to the clipboard. |
| Paste | `⌘V` |  | Paste and place with the cursor. |
| Paste Aligned to Same Place |  |  | Paste at the original location. |
| Paste Aligned to Selected Levels… |  |  | Paste to the same plan position on chosen levels. |
| Paste Aligned to Current View |  |  | Paste view-specific items into the current view at the same place. |
| Status Bar |  |  | Show or hide the status bar under the canvas. |
| Navigation Bar |  |  | Show or hide the navigation bar on views. |

