# Arcus Furniture mode, Home redesign and Family Editor shell

Owner's request, 2026-10-19. Decisions are listed in §1; everything else follows from them.

## 1. Decisions

| Topic | Decision |
|---|---|
| Home | Card-based Start a Project, fully redesigned. Cards: **Architectural**, **Furniture**, **Family**. No Residential. |
| Architectural units | Always Imperial (feet-inches, 1/16"). Project Units can still be changed later in Manage. |
| Furniture mode | A mix of the main app and the Family Editor. It works like Revit Architecture, so a Revit user learns nothing new. |
| Modelling | Revit-style furniture tools (Panels like walls, Shelves/Tops like floors, Legs like columns, Rails like beams, Doors/Drawers hosted like doors and windows) plus reference planes, parameters, types, and Forms for free shapes. |
| Furniture units | Always Imperial. |
| File format | `.arcusfurniture`. Loads into projects like a family (Furniture or Casework category). |
| Joints | Automatic joint rules: butt, miter, dado, rabbet, dowel, cam lock, pocket screw, mortise and tenon. Editable per joint, like wall joins. Cut sizes adjust and CNC gets the holes. |
| Hardware | Real parts: hinges, slides, handles, cam locks, shelf pins. Placed automatically, scheduled with cost, drilled. |
| Outputs | Dimensions, working drawings, construction details, shop drawing sheets, PDF and image export, cut list/panel schedule, sheet nesting (4'×8' or custom, grain, yield), DXF/DWG per part for CNC, material takeoff with cost (USD by default, editable). |
| Library | The owner's household list (~190 unique pieces). The Top 25 essentials at high detail, the rest simple. All are built with Furniture mode itself and saved as templates. |
| Family Editor | Rebuilt on the main-app shell: liquid glass, ribbon with tabs, Project Browser, Properties, Options Bar and status bar. Fixes the missing tab names and the clipped ribbon. |

## 2. How a Revit user makes custom furniture today, and how Arcus maps it

In Revit, custom furniture or millwork is either a loadable family (Furniture.rft / Casework.rft) or in-place casework:
- reference planes Left/Right/Front/Back/Top/Bottom, labelled dimensions Width/Depth/Height (EQ on centre planes);
- extrusions sketched and locked to the planes (padlocks), material parameters, visibility by detail level;
- nested door/drawer/handle families, family types, Flex;
- Load into Project, then schedules (Furniture Schedule, Material Takeoff) and sheets for shop drawings.

Shop work in Revit is slow because every board is a hand-made extrusion, and nothing knows about joints, hardware or cutting. Furniture mode keeps every Revit concept and command name, and replaces the hand-made extrusions with **system-family-like parts** that behave exactly like the Architecture tools.

| Revit concept | Furniture mode equivalent | Behaves like |
|---|---|---|
| Wall (WA) | **Panel** (PN): sides, dividers, backs, aprons. Drawn by line in plan or elevation; Location Line (Panel Centerline / Face Inside / Face Outside); Base/Top Constraint to reference planes with offsets; Edit Profile; Opening | Walls: chain drawing, flip (Space), joins, grips, Attach Top/Base |
| Floor (SB) | **Shelf / Top / Bottom** (SH): sketch boundary or Pick Panels; Height Offset from a plane; grain = span direction; Adjustable (shelf pins) or Fixed | Floors: sketch mode, Finish/Cancel, Pick Walls, span arrow |
| Column (CL) | **Leg** (LG): placed at points/plane intersections; types square, round, tapered, turned, hairpin, sled; Base/Top Constraint | Columns: At Grids → **At Corners** |
| Beam (BM) | **Rail** (RL): stretchers, aprons, cleats, slats; profile types; Z justification | Beams: chain, start/end offsets |
| Wall Sweep / Reveal | **Edge Profile / Groove**: mouldings, bullnose, chamfer, ogee, finger pulls along panel edges | Sweep / Reveal: pick edges |
| Room (RM) | **Bay** (BY): open space between panels detected in a front elevation; tag shows W×H | Rooms: click inside a bounded region; Bay Separator like Room Separator |
| Door / Window (DR/WN) | **Door / Drawer / Flap** (DF, DW): hosted in a bay; types full/half overlay or inset, single/pair; hinge side flips like a door swing; drawer box and slide type | Doors/windows: host, flip controls, type selector |
| Curtain Grid | **Bay Divide**: split a bay into equal drawers/doors (EQ) | Curtain grid lines |
| Component (CM) | **Hardware** and loadable families (handles, hinges, slides, cam locks, pins, glides, casters) | Components; nested in door/drawer types |
| Wall Joins | **Joint** (JT): butt (which part runs through), miter, dado, rabbet, dowel, cam lock, pocket screw, mortise and tenon | Modify ▸ Geometry ▸ Wall Joins |
| Object Styles / Line Styles | **Joint Rules** (Manage): default joint per pair (side–top, side–bottom, side–back, shelf–side, rail–leg, divider–shelf) | Settings dialogs |
| Family Types / Category and Parameters | Same dialogs, in the project shell: Width/Depth/Height and any parameter; types; Category Furniture or Casework | Family Editor |
| Reference Plane (RP) + Align (AL) + lock | Same. Parts snap to planes and lock (padlock), so changing Width moves the Right plane and everything locked to it | Revit constraints |
| Forms (Extrusion, Blend, Revolve, Sweep, Swept Blend, Void) | Same, for upholstery, turned legs and free shapes, plus **Cushion** (box with crown and radius) | Family Editor forms |
| Flex | Same: try every type and check nothing breaks | Family Editor Flex |
| Load into Project / Edit Family | Same. The project keeps the furniture source, so Edit Family reopens it in Furniture mode | Family Editor |
| Schedules, Material Takeoff | **Part List** (cut list), **Hardware Schedule**, **Material Takeoff** with cost, **Edge Banding** | Schedules |
| Sheets | **Shop drawing** sheets (ARCH D / Tabloid / Letter) with plan, elevations, sections, details, 3D, part list, nesting | Sheets |
| — (Arcus extras) | **Nesting** views: parts on stock sheets with grain and yield. **CNC Export**: DXF/DWG per part or per sheet with layered outlines, drills, grooves and pockets | Export ▸ CAD Formats |

## 3. Product shape

**A Furniture document is an Arcus project in a different mode**, not a new editor:
- It reuses the main shell: Metal canvas, 3D viewport, snapping, tools, undo, Properties, Project Browser, view tabs, sheets, schedules, dimensions and tags, and PDF/image/DWG export.
- It adds parametric family behaviour: reference planes with formula offsets, Family Types, Category, Flex, Load into Project.

### Document and file
- `ProjectInfoData.documentKind: DocumentKind?` (`.project` when nil, `.furniture`). The manifest gets `kind` (optional), and the format string is `arcus.furniture`.
- `.arcusfurniture` is a package like `.arcus` (same `ArcusPackage` reader/writer). It has its own exported UTType `com.local.arcus.furniture`, a document icon, and an `ArcusDocument` read type.
- The **template** (`FurnitureTemplates.blank(category:)`) creates:
  - level Ref. Level at 0;
  - views: Floor Plan Ref. Level, Front/Back/Left/Right elevations, {3D}, a sheet;
  - reference planes Center (Left/Right), Center (Front/Back), Left, Right, Front, Back, Bottom (Ref. Level), Top;
  - labelled Width/Depth/Height, with EQ about the centres;
  - default types, a materials set (plywood, MDF, particleboard, melamine, solid oak/walnut/maple/ash/pine, laminate, veneer, glass, steel, fabric, leather, foam), Joint Rules, the Part List / Hardware / Material Takeoff schedules, and a shop drawing sheet.
- **Parametric planes:** project reference planes gain an optional `offsetFormula` and an `axis`. `FurnitureParameters` evaluates formulas from the Family Types values with `FormulaSystem`, as families do.
- **Constraints:** a part's ends and faces store optional plane bindings (`FurnitureBound`: plane name + offset, or a fixed value), mirroring `FamilyBound`. When the Family Types values change, regeneration moves the planes and every bound part.

### Mode in the shell
`DocumentState.mode` comes from `documentKind`. The ribbon tabs, browser tree and menus read it:
- **Ribbon tabs (Furniture):**
  - Create: Select, Properties (Family Types, Category and Parameters), Parts (Panel, Shelf, Top, Back, Divider, Leg, Rail, Plinth, Edge Profile), Openings (Bay, Bay Divide, Door, Drawer, Flap), Forms (Extrusion, Blend, Revolve, Sweep, Swept Blend, Cushion, Void Forms), Model (Component, Hardware, Model Line, Model Text), Datum (Reference Plane), Work Plane.
  - Insert: Load Family, Load Furniture, Import CAD, Image.
  - Annotate: dimensions, tags, text, detail lines and components, symbols.
  - Fabricate: Joint, Joint Rules, Part List, Hardware Schedule, Material Takeoff, Nesting, CNC Export, Check Parts.
  - View: same as the main app.
  - Manage: Materials, Object Styles, Project Units (Imperial), Joint Rules, Stock Sheets, Hardware Catalog.
  - Modify: contextual, as in the main app.
  - Family Editor panel (on Create and Modify): Load into Project, Load into Project and Close, Flex.
- **Browser:** Views (Floor Plans, Elevations, Sections, 3D Views, Details), Sheets, Schedules, Nesting, Families (Hardware…), Parts (by type), Parameters and Types.
- The **Architectural** mode is unchanged.

### Furniture elements (new `ElementData` cases)
- `furniturePanel(PanelData)`: location line in plan or in an elevation work plane, thickness from type, height via base/top bounds, profile sketch optional, grain direction, edge banding per edge.
- `furnitureShelf(ShelfData)`: sketched or picked boundary loop, elevation bound, adjustable/fixed, pin pattern.
- `furnitureLeg(LegData)`, `furnitureRail(RailData)`, `furnitureEdgeProfile(EdgeProfileData)`.
- `furnitureBay(BayData)`: derived opening region in a front plane (stored with its seed point, recomputed like rooms).
- `furnitureFront(FrontData)`: door/drawer/flap in a bay, overlay type, hinge side, handle type and position, drawer box spec.
- `furnitureJoint(JointData)`: pair of part IDs, joint type, parameters (depth, dowel diameter/spacing, cam spacing), auto or user-set.
- Hardware is an ordinary loadable family in the new `Category.furnitureHardware`, placed as components owned by fronts and joints (ownerPartID). It is counted in schedules and its drill pattern is read from family parameters.

Types (`TypeData`) for each part kind: thickness, core material, face material, edge band material/thickness, grain, profile, overlay, etc. Material cost uses `MaterialData.cost` (per sheet, per ft², per board foot or each: new optional `costUnit`). The currency symbol comes from `UnitsSettings`, USD by default.

### Joints
- `JointSolver` runs at regeneration over every pair of touching or overlapping parts and applies the rule for the pair (Joint Rules), unless the user has set the joint.
- It decides which part runs through, trims the other, and adds machining: dado/rabbet grooves (voids), dowel/cam/pocket holes and mortises.
- The **cut size** of each part (length × width × thickness, with groove allowances and tenons) is the base of the Part List and CNC.
- Joint tool: click a joint marker to cycle types (like Wall Joins' Next/Previous), or pick from the Options Bar. Joint markers are drawn in plan and elevation while the tool is active.

### Fabrication outputs
- **Part List:** schedule kind `partList`. Fields: Mark, Part, Type, Material, Length, Width, Thickness, Grain, Edge Banding (L1 L2 W1 W2), Qty, Area, Cost. Grouped by material and thickness.
- **Hardware Schedule:** a category schedule on Furniture Hardware, with count and cost.
- **Material Takeoff:** adds Cost and Sheet Count fields (from nesting).
- **Nesting:** a guillotine/maxrects nesting engine on stock sheets (Manage ▸ Stock Sheets: 4'×8' default, thickness, material, kerf, edge trim, grain). Grain-locked parts don't rotate. Nesting views (new `ViewKind.nesting`) show each sheet, with yield %, and can be placed on sheets.
- **CNC Export:** DXF (and DWG via the bundled engine) per part or per nested sheet. Layers: `OUTLINE`, `INNER`, `DRILL_<dia>_<depth>`, `GROOVE_<depth>`, `POCKET_<depth>`, `GRAIN`, `LABEL`. Units in inches.
- **Shop drawings:** template sheet with plan, front/side elevations, a section, 3D, a part list and a title block. PDF via `PDFExporter`, images via `RasterExporter`.

### Load into Project and Edit Family
- `FurnitureCompiler.family(from:) -> FamilyDefinition`:
  - planes are copied with their formulas; parameters and types are copied;
  - each part becomes a `FamilySolid` bounded by the same planes, with its material parameter;
  - fronts and hardware are visible at Medium/Fine; a plan outline is drawn at Coarse;
  - joints and machining are visible at Fine only, so projects stay light.
- The compiled family stores the furniture source (`furnitureSource: Data?`, a zipped model), so **Edit Family** reopens it in Furniture mode, and Load into Project replaces the family as usual.
- Projects load `.arcusfurniture` files directly (Insert ▸ Load Family accepts both file types).

### Library
- `arcus-bench --furniture-library <dir>` builds every library piece with the Furniture mode API (the same operations the tools call) and saves `.arcusfurniture` files.
- The build bundles them in `Contents/Resources/Furniture Library/<Room>/<Name>.arcusfurniture`. They appear on Home ▸ Furniture as templates, in Insert ▸ Load Furniture, and in the Component Library.
- **Top 25 (high detail):** real construction, joints, hardware, 2–4 size types, materials, Coarse/Medium/Fine.
  - Sofa, Coffee Table, TV Stand, Armchair, Side Table, Bookshelf, Bed, Bedside Table, Wardrobe, Dresser, Dressing Table, Dining Table, Dining Chair, Sideboard
  - Kitchen Cabinet, Pantry Cabinet, Study Desk, Office Chair, Storage Cabinet, Shoe Rack, Entryway Bench, Bathroom Vanity, Shelving Unit, Ottoman, Console Table
- **The rest (simple):** correct overall form from panels, legs and fronts, parametric W/D/H and materials, one or two types.
- Repeats in the list (Kitchen Island, Bunk Bed, Corner Shelf, Rocking Chair, Lounge Chair, Nesting Tables, Storage Bed, Storage Cabinet, Storage Chest, Folding Chair, Plant Stand, Room Divider) are one file, listed under each room.

## 4. Home redesign

- One window (about 1040×660), liquid glass sidebar, card grid.
- **Left column:** app mark; **Start** with three large cards (illustration, title, one line):
  - Architectural Project: "Buildings, sheets and schedules. Imperial."
  - Furniture: "Custom pieces, cut lists and CNC."
  - Family: "Doors, windows and components."
- Below the cards: Open…, Open Sample Project.
- **Right side:**
  - A card is selected: its details. Architectural: name, template menu (Architectural, My Templates, Browse). Furniture: name, a category toggle (Furniture/Casework) and a gallery of Blank plus the library by room with search. Family: name and a grid of category templates. Then **Create**.
  - Nothing selected yet, or after Back: **Recent** as a thumbnail grid with kind badges (Project, Furniture, Family) and a filter (All / Projects / Furniture / Families).
- Removes `ProjectTemplateKind.residential` and the Units toggle (Architectural is Imperial). Empty stays only for tests and the stress model. Onboarding matches.

## 5. Family Editor on the main shell

- The window becomes full-size content with no NSToolbar, like `DocumentWindowController`.
- **Chrome:** glass ribbon tab pill, ribbon strip (`RibbonTabsPill` / `RibbonStrip` / `PanelCard`), floating left dock (family browser), right dock (Properties: family, types, element), view tab pills, options bar, bottom pill (Detail level, Preview Visibility, view scale), status bar, traffic lights in the dock.
- The toolbar's buttons (Fit, Family Types, Flex, Save As, Load) move into the ribbon (Family Editor panel) and keep their shortcuts.
- Fixes: the ribbon panel row gets a fixed height, and the tab row and view tabs are `fixedSize(vertical:)` (missing tab names, clipped panels).
- Canvas colours, grid, selection and snap markers match the main canvas.

## 6. Milestones

| ID | Milestone | Depends on |
|---|---|---|
| FM1 | Home redesign (cards, recents grid, Imperial Architectural, no Residential), onboarding to match | — |
| FM2 | Family Editor on the main shell + clipping fixes | — |
| FM3 | Furniture document: kind, `.arcusfurniture`, template, mode ribbon/browser/menus, parametric planes, Family Types/Category in the shell, Flex, basic compile + Load into Project | — |
| FM4 | Parts: Panel, Shelf/Top/Bottom, Back, Divider, Leg, Rail, Plinth, Edge Profile; types, constraints, grips, graphics, Properties | FM3 |
| FM5 | Bays, Bay Divide, Doors/Drawers/Flaps, hardware families and auto-placement | FM4 |
| FM6 | Joints: solver, Joint Rules, Joint tool, machining geometry, cut sizes | FM4 |
| FM7 | Fabrication: Part List, Hardware Schedule, Material Takeoff with cost, Stock Sheets, nesting engine and views, CNC Export, shop drawing sheet | FM5, FM6 |
| FM8 | Full compile, Edit Family round trip, projects load `.arcusfurniture` | FM5, FM6 |
| FM9 | Library: Top 25 high detail + the rest simple, bundled, on Home and in Load Furniture | FM8 |
| FM10 | Docs, keyboard shortcuts, QA checks (Home, Family Editor, Furniture mode), verification | all |
