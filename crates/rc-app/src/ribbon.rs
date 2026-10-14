//! The ribbon: Quick Access Toolbar, File menu, tabs, panels and the green contextual
//! "Modify | ..." tab that appears for the selection, the active tool or a sketch.

use crate::actions;
use crate::app::App;
use crate::canvas_tools;
use crate::commands::Cmd;
use crate::icons::{self};
use crate::style;
use crate::tools::{DrawMode, ToolKind};
use eframe::egui::{self, Color32, Rect, Sense, Stroke, pos2, vec2};
use rc_core::model::*;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tab {
    Architecture,
    Structure,
    Insert,
    Annotate,
    Analyze,
    MassingSite,
    View,
    Manage,
    Modify,
}

impl Tab {
    const ALL: [Tab; 9] = [Tab::Architecture, Tab::Structure, Tab::Insert, Tab::Annotate, Tab::Analyze, Tab::MassingSite, Tab::View, Tab::Manage, Tab::Modify];
    fn label(self) -> &'static str {
        match self {
            Tab::Architecture => "Architecture",
            Tab::Structure => "Structure",
            Tab::Insert => "Insert",
            Tab::Annotate => "Annotate",
            Tab::Analyze => "Analyze",
            Tab::MassingSite => "Massing & Site",
            Tab::View => "View",
            Tab::Manage => "Manage",
            Tab::Modify => "Modify",
        }
    }
}

enum Item {
    Big(Cmd),
    /// A big button whose arrow opens alternatives.
    Split(Cmd, Vec<Cmd>),
    /// Up to three small buttons stacked.
    Stack(Vec<Cmd>),
    /// A grid of icon-only buttons (two rows).
    Icons(Vec<Cmd>),
    /// Toggle with a state.
    Toggle(Cmd, bool),
    /// A big button with its own ribbon label ("\n" breaks the line) and optional
    /// alternatives under the arrow.
    Labeled(&'static str, Cmd, Vec<Cmd>),
}

struct Panel {
    title: &'static str,
    items: Vec<Item>,
}

fn panel(title: &'static str, items: Vec<Item>) -> Panel {
    Panel { title, items }
}

use Cmd as C;
use Item::*;

fn architecture() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel(
            "Build",
            vec![
                Labeled("Wall", C::Wall, vec![C::Wall, C::WallStructural]),
                Big(C::Door),
                Big(C::Window),
                Labeled("Component", C::Component, vec![C::Component, C::LoadFamily, C::NewFamily]),
                Labeled("Column", C::Column, vec![C::Column, C::StructColumn]),
                Labeled("Roof", C::RoofFootprint, vec![C::RoofFootprint, C::RoofExtrusion]),
                Big(C::Ceiling),
                Labeled("Floor", C::Floor, vec![C::Floor, C::FloorStructural]),
                Labeled("Curtain\nGrid", C::CurtainGrid, vec![]),
            ],
        ),
        panel("Circulation", vec![Big(C::Railing), Big(C::Stair)]),
        panel("Model", vec![Labeled("Model\nLine", C::ModelLine, vec![]), Labeled("Model\nGroup", C::PlaceGroup, vec![C::PlaceGroup, C::CreateGroup])]),
        panel(
            "Room & Area",
            vec![
                Big(C::Room),
                Labeled("Room\nSeparator", C::RoomSeparator, vec![]),
                Labeled("Tag\nRoom", C::RoomTag, vec![C::RoomTag, C::TagAll]),
                Big(C::Area),
                Labeled("Area\nBoundary", C::AreaBoundary, vec![]),
                Labeled("Tag\nArea", C::AreaTag, vec![]),
            ],
        ),
        panel("Opening", vec![Big(C::Shaft), Labeled("Wall", C::WallOpening, vec![])]),
        panel("Datum", vec![Big(C::Level), Big(C::Grid)]),
        panel("Work Plane", vec![Labeled("Ref\nPlane", C::RefPlane, vec![])]),
    ]
}

fn structure() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel(
            "Structure",
            vec![Big(C::Beam), Labeled("Wall", C::WallStructural, vec![C::WallStructural, C::Wall]), Labeled("Column", C::StructColumn, vec![]), Labeled("Floor", C::FloorStructural, vec![C::FloorStructural, C::Floor])],
        ),
        panel("Foundation", vec![Labeled("Isolated", C::IsolatedFoundation, vec![]), Labeled("Wall", C::WallFoundation, vec![]), Labeled("Slab", C::FloorStructural, vec![])]),
        panel("Model", vec![Labeled("Component", C::Component, vec![]), Labeled("Model\nLine", C::ModelLine, vec![]), Labeled("Model\nGroup", C::PlaceGroup, vec![C::PlaceGroup, C::CreateGroup])]),
        panel("Opening", vec![Big(C::Shaft), Labeled("Wall", C::WallOpening, vec![])]),
        panel("Datum", vec![Big(C::Level), Big(C::Grid)]),
        panel("Work Plane", vec![Labeled("Ref\nPlane", C::RefPlane, vec![])]),
    ]
}

fn insert() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Link", vec![Big(C::LinkCad), Big(C::ManageLinks)]),
        panel("Import", vec![Big(C::ImportCad), Big(C::ImportIfc)]),
        panel("Load from Library", vec![Big(C::LoadFamily), Big(C::NewFamily)]),
    ]
}

fn annotate() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel(
            "Dimension",
            vec![
                Big(C::DimAligned),
                Big(C::DimLinear),
                Big(C::DimAngular),
                Big(C::DimRadial),
                Big(C::DimDiameter),
                Labeled("Arc\nLength", C::DimArcLength, vec![]),
                Labeled("Spot\nElevation", C::SpotElevation, vec![]),
            ],
        ),
        panel(
            "Detail",
            vec![Labeled("Detail\nLine", C::DetailLine, vec![]), Labeled("Region", C::FilledRegion, vec![C::FilledRegion, C::MaskingRegion]), Labeled("Revision\nCloud", C::RevisionCloud, vec![])],
        ),
        panel("Text", vec![Big(C::Text)]),
        panel("Tag", vec![Labeled("Tag by\nCategory", C::TagByCategory, vec![]), Labeled("Tag\nAll", C::TagAll, vec![]), Stack(vec![C::RoomTag, C::AreaTag])]),
        panel("Symbol", vec![Big(C::Symbol)]),
    ]
}

fn analyze() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Color Fill", vec![Labeled("Color Fill\nLegend", C::ColorFillLegend, vec![])]),
        panel("Reports & Schedules", vec![Labeled("Schedule/\nQuantities", C::Schedule, vec![C::Schedule, C::MaterialTakeoff])]),
    ]
}

fn massing_site() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Conceptual Mass", vec![Labeled("Show\nMass", C::ShowMass, vec![]), Labeled("In-Place\nMass", C::InPlaceMass, vec![])]),
        panel(
            "Model by Face",
            vec![Labeled("Curtain\nSystem", C::CurtainSystemByFace, vec![]), Labeled("Roof", C::RoofByFace, vec![]), Labeled("Wall", C::WallByFace, vec![]), Labeled("Floor", C::FloorByFace, vec![])],
        ),
        panel(
            "Model Site",
            vec![
                Big(C::Toposolid),
                Labeled("Site\nComponent", C::SiteComponent, vec![]),
                Labeled("Parking\nComponent", C::ParkingComponent, vec![]),
                Labeled("Property\nLine", C::PropertyLine, vec![]),
            ],
        ),
        panel("Modify Site", vec![Labeled("Modify Sub\nElements", C::ModifySubElements, vec![])]),
    ]
}

fn view_tab(_app: &App) -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel(
            "Graphics",
            vec![
                Labeled("View\nTemplates", C::ViewTemplates, vec![C::ViewTemplates, C::TemplateFromView]),
                Labeled("Visibility/\nGraphics", C::VisibilityGraphics, vec![]),
                Labeled("Thin\nLines", C::ThinLines, vec![]),
            ],
        ),
        panel(
            "Create",
            vec![
                Labeled("3D\nView", C::Default3D, vec![]),
                Big(C::Section),
                Big(C::Callout),
                Labeled("Plan\nViews", C::NewFloorPlan, vec![C::NewFloorPlan, C::NewCeilingPlan, C::NewAreaPlan]),
                Labeled("Elevation", C::ElevationView, vec![]),
                Labeled("Drafting\nView", C::DraftingView, vec![]),
                Labeled("Duplicate\nView", C::DuplicateView, vec![C::DuplicateView, C::DuplicateWithDetailing]),
                Labeled("Legends", C::Legend, vec![]),
                Labeled("Schedules", C::Schedule, vec![C::Schedule, C::MaterialTakeoff, C::SheetList]),
            ],
        ),
        panel("Sheet Composition", vec![Labeled("Sheet", C::NewSheet, vec![]), Labeled("View", C::PlaceView, vec![]), Big(C::Revisions)]),
        panel(
            "Windows",
            vec![
                Labeled("Close\nInactive", C::CloseInactive, vec![]),
                Labeled("Tab\nViews", C::TabViews, vec![]),
                Labeled("Tile\nViews", C::TileViews, vec![]),
                Labeled(
                    "User\nInterface",
                    C::ToggleProperties,
                    vec![C::ToggleProperties, C::ToggleBrowser, C::ToggleStatusBar, C::ToggleOptionsBar, C::ToggleViewCube, C::ToggleNavBar, C::KeyboardShortcuts],
                ),
            ],
        ),
    ]
}

fn manage() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Settings", vec![Big(C::Materials), Stack(vec![C::ObjectStyles, C::Snaps, C::ProjectInfo]), Stack(vec![C::ProjectUnits, C::Purge])]),
        panel("Project Location", vec![Labeled("Sun\nSettings", C::Sun, vec![])]),
        panel("Design Options", vec![Labeled("Design\nOptions", C::DesignOptions, vec![])]),
        panel("Manage Project", vec![Labeled("Manage\nLinks", C::ManageLinks, vec![])]),
        panel("Phasing", vec![Big(C::Phases)]),
        panel("Inquiry", vec![Stack(vec![C::IdsOfSelection, C::SelectById, C::Warnings])]),
    ]
}

fn modify_panels() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Properties", vec![Big(C::TypeProperties), Big(C::ToggleProperties)]),
        panel("Clipboard", vec![Split(C::Paste, vec![C::Paste, C::PasteSameLevel]), Stack(vec![C::Cut, C::CopyClip, C::MatchType])]),
        panel("Geometry", vec![Stack(vec![C::Demolish, C::WallJoinToggle])]),
        panel(
            "Modify",
            vec![Icons(vec![
                C::Align, C::Offset, C::MirrorPick, C::MirrorDraw, C::Split, C::Pin, C::Move, C::Copy, C::Rotate, C::TrimCorner, C::Array, C::Unpin, C::Scale, C::TrimSingle,
                C::TrimMulti, C::Delete,
            ])],
        ),
        panel("View", vec![Split(C::HideElements, vec![C::HideElements, C::HideCategory, C::UnhideElements]), Big(C::OverrideElements)]),
        panel("Measure", vec![Big(C::Measure), Big(C::DimAligned)]),
        panel("Create", vec![Stack(vec![C::CreateGroup, C::CreateSimilar])]),
    ]
}

fn draw_panel(app: &App) -> Option<Panel> {
    let kind = app.tool.kind;
    let modes: Vec<Cmd> = if app.sketch.is_some() && (kind == ToolKind::SketchLine || kind == ToolKind::Select) {
        canvas_tools::modes_for(ToolKind::SketchLine).iter().map(|m| mode_cmd(*m)).collect()
    } else {
        canvas_tools::modes_for(kind).iter().map(|m| mode_cmd(*m)).collect()
    };
    if modes.is_empty() {
        return None;
    }
    Some(panel("Draw", vec![Icons(modes)]))
}

fn mode_cmd(m: DrawMode) -> Cmd {
    match m {
        DrawMode::Line => C::DrawLine,
        DrawMode::Rect => C::DrawRect,
        DrawMode::PolyIn => C::DrawPolyIn,
        DrawMode::PolyCirc => C::DrawPolyCirc,
        DrawMode::Circle => C::DrawCircle,
        DrawMode::Arc3 => C::DrawArc3,
        DrawMode::ArcCenter => C::DrawArcCenter,
        DrawMode::ArcTangent => C::DrawArcTangent,
        DrawMode::Fillet => C::DrawFillet,
        DrawMode::PickLines => C::PickLines,
        DrawMode::PickWalls => C::PickWalls,
    }
}

fn cmd_mode(c: Cmd) -> Option<DrawMode> {
    Some(match c {
        C::DrawLine => DrawMode::Line,
        C::DrawRect => DrawMode::Rect,
        C::DrawPolyIn => DrawMode::PolyIn,
        C::DrawPolyCirc => DrawMode::PolyCirc,
        C::DrawCircle => DrawMode::Circle,
        C::DrawArc3 => DrawMode::Arc3,
        C::DrawArcCenter => DrawMode::ArcCenter,
        C::DrawArcTangent => DrawMode::ArcTangent,
        C::DrawFillet => DrawMode::Fillet,
        C::PickLines => DrawMode::PickLines,
        C::PickWalls => DrawMode::PickWalls,
        _ => return None,
    })
}

/// The contextual tab: (title, extra panels) for the current selection/tool/sketch.
fn contextual(app: &App) -> Option<(String, Vec<Panel>)> {
    if let Some(sk) = &app.sketch {
        let mut v = vec![panel("Mode", vec![Big(C::FinishSketch), Big(C::CancelSketch)])];
        if let Some(d) = draw_panel(app) {
            v.push(d);
        }
        return Some((sk.kind.title().to_string(), v));
    }
    if app.group_edit.is_some() {
        return Some(("Edit Group".into(), vec![panel("Edit Group", vec![Big(C::FinishGroup), Big(C::CancelGroup)])]));
    }
    if !app.tool.is_select() {
        let kind = app.tool.kind;
        let mut v = Vec::new();
        if matches!(kind, ToolKind::Door | ToolKind::Window | ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting | ToolKind::Beam) {
            v.push(panel("Mode", vec![Big(C::LoadFamily)]));
        }
        if let Some(d) = draw_panel(app) {
            v.push(d);
        }
        if kind == ToolKind::CeilingAuto {
            v.push(panel("Ceiling", vec![Big(C::AutoCeiling), Big(C::SketchCeiling)]));
        }
        if matches!(kind, ToolKind::Door | ToolKind::Window | ToolKind::Room) {
            let on = if kind == ToolKind::Room { app.opts.room_tag } else { app.opts.tag_on_placement };
            v.push(panel("Tag", vec![Toggle(C::TagByCategory, on)]));
        }
        let title = match kind {
            ToolKind::Move | ToolKind::Copy | ToolKind::Rotate | ToolKind::Align | ToolKind::Offset | ToolKind::MirrorPick | ToolKind::MirrorDraw | ToolKind::Array | ToolKind::Scale | ToolKind::TrimCorner | ToolKind::TrimSingle | ToolKind::TrimMulti | ToolKind::Split | ToolKind::SplitGap => {
                return None;
            }
            ToolKind::Dimension(_) => "Place Dimensions".to_string(),
            k => format!("Place {}", k.name()),
        };
        return Some((title, v));
    }
    if app.active_view().is_some_and(|v| matches!(v.kind, ViewKind::Schedule(_))) {
        return Some((
            "Schedule/Quantities".into(),
            vec![panel("Parameters", vec![Big(C::ScheduleFields), Big(C::ScheduleFilter), Big(C::ScheduleSorting)]), panel("Element", vec![Big(C::HighlightInModel)])],
        ));
    }
    if app.selection.is_empty() {
        return None;
    }
    let p = &app.doc.data;
    let cats: Vec<Category> = {
        let mut c: Vec<Category> = app.selection.iter().filter_map(|id| app.el(*id).map(|e| e.category())).collect();
        c.sort();
        c.dedup();
        c
    };
    let views = app.selection.iter().any(|id| p.view(*id).is_some());
    let title = if cats.len() == 1 && !views {
        cats[0].label().to_string()
    } else if cats.is_empty() && views {
        "Views".to_string()
    } else {
        "Multi-Select".to_string()
    };
    let mut v = Vec::new();
    let has = |c: Category| cats.contains(&c);
    if has(Category::Walls) {
        v.push(panel("Mode", vec![Big(C::EditFamily)]));
        v.pop();
        v.push(panel("Modify Wall", vec![Big(C::WallOpening), Stack(vec![C::AttachTop, C::Detach, C::FlipWall])]));
    }
    if cats.iter().any(|c| matches!(c, Category::Floors | Category::Roofs | Category::Ceilings | Category::FilledRegions)) && cats.len() == 1 {
        v.push(panel("Mode", vec![Big(C::EditBoundary)]));
    }
    if cats.iter().any(|c| matches!(c, Category::Doors | Category::Windows)) {
        v.push(panel("Host", vec![Big(C::PickNewHost), Stack(vec![C::FlipFacing, C::FlipHand])]));
    }
    let family_cats = [
        Category::Doors, Category::Windows, Category::Furniture, Category::Casework, Category::PlumbingFixtures, Category::SpecialtyEquipment, Category::GenericModels,
        Category::Columns, Category::StructuralColumns, Category::StructuralFraming, Category::StructuralFoundations,
    ];
    if cats.len() == 1 && family_cats.contains(&cats[0]) && app.selection.len() == 1 {
        v.push(panel("Mode", vec![Big(C::EditFamily)]));
    }
    if has(Category::Groups) {
        v.push(panel("Group", vec![Big(C::EditGroup), Big(C::Ungroup)]));
    }
    if views {
        v.push(panel("View", vec![Big(C::GoToView)]));
    }
    Some((title, v))
}

// ---------------------------------------------------------------- widgets

fn tooltip(ui: &mut egui::Ui, app: &App, cmd: Cmd) {
    let info = cmd.info();
    ui.set_max_width(320.0);
    ui.label(egui::RichText::new(info.label.replace('\n', " ")).strong());
    ui.add_space(2.0);
    ui.label(info.tip);
    let keys = app.settings.shortcuts.keys(cmd);
    if !keys.is_empty() {
        ui.add_space(4.0);
        ui.label(egui::RichText::new(format!("Keyboard shortcut: {keys}")).color(style::text_dim()).small());
    }
}

fn button_bg(ui: &egui::Ui, rect: Rect, resp: &egui::Response, active: bool) {
    let p = ui.painter();
    if active {
        p.rect_filled(rect, 0.0, style::accent_light());
        p.rect_stroke(rect, 0.0, Stroke::new(1.0, Color32::from_rgb(120, 174, 222)), egui::StrokeKind::Inside);
    } else if resp.hovered() {
        p.rect_filled(rect, 0.0, style::hover());
        p.rect_stroke(rect, 0.0, Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    }
}

fn is_active(app: &App, cmd: Cmd) -> bool {
    use crate::tools::ToolKind as T;
    let k = app.tool.kind;
    if let Some(m) = cmd_mode(cmd) {
        return (k.uses_draw_modes() || app.sketch.is_some()) && app.opts.draw_mode == m && !(app.sketch.is_some() && k == T::Select);
    }
    match cmd {
        C::Modify => k == T::Select,
        C::Wall => k == T::Wall && !app.opts.wall_structural,
        C::WallStructural => k == T::Wall && app.opts.wall_structural,
        C::Door => k == T::Door,
        C::Window => k == T::Window,
        C::Component => k == T::Component,
        C::Column => k == T::Column,
        C::StructColumn => k == T::StructColumn,
        C::Beam => k == T::Beam,
        C::Room => k == T::Room,
        C::AutoCeiling => k == T::CeilingAuto,
        C::Grid => k == T::Grid,
        C::Level => k == T::Level,
        C::RefPlane => k == T::RefPlane,
        C::Move => k == T::Move,
        C::Copy => k == T::Copy,
        C::Rotate => k == T::Rotate,
        C::Align => k == T::Align,
        C::Offset => k == T::Offset,
        C::MirrorPick => k == T::MirrorPick,
        C::MirrorDraw => k == T::MirrorDraw,
        C::TrimCorner => k == T::TrimCorner,
        C::TrimSingle => k == T::TrimSingle,
        C::TrimMulti => k == T::TrimMulti,
        C::Split => k == T::Split,
        C::Array => k == T::Array,
        C::Scale => k == T::Scale,
        C::Measure => k == T::Measure,
        C::DimAligned => k == T::Dimension(DimKind::Aligned),
        C::DimLinear => k == T::Dimension(DimKind::Linear),
        C::Text => k == T::Text,
        C::TagByCategory => k == T::Tag,
        C::DetailLine => k == T::DetailLine,
        C::ModelLine => k == T::ModelLine,
        C::Section => k == T::Section,
        C::ToggleProperties => app.settings.show_properties,
        C::ThinLines => app.thin_lines,
        C::ShowMass => app.show_mass,
        C::ModifySubElements => k == T::TopoPoints,
        C::ColorFillLegend => k == T::ColorLegend,
        _ => false,
    }
}

const RIBBON_FONT: f32 = 12.0;
const BIG_H: f32 = 64.0;

fn big_button(ui: &mut egui::Ui, app: &mut App, cmd: Cmd, label: Option<&str>, dropdown: Option<&[Cmd]>, toggled: Option<bool>) {
    let info = cmd.info();
    let label = label.unwrap_or(info.label);
    let font = style::font(RIBBON_FONT);
    let lines: Vec<&str> = split_label(label);
    let widths: Vec<f32> = lines.iter().map(|l| ui.painter().layout_no_wrap(l.to_string(), font.clone(), Color32::BLACK).size().x).collect();
    let arrow_extra = if dropdown.is_some() && lines.len() > 1 { 10.0 } else { 0.0 };
    let text_w = widths.iter().copied().fold(0.0f32, f32::max).max(widths.last().copied().unwrap_or(0.0) + arrow_extra);
    let w = (text_w + 8.0).max(36.0);
    let (rect, resp) = ui.allocate_exact_size(vec2(w, BIG_H), Sense::click());
    let enabled = actions::enabled(app, cmd);
    let active = toggled.unwrap_or_else(|| is_active(app, cmd));
    button_bg(ui, rect, &resp, active);
    let icon_rect = Rect::from_center_size(pos2(rect.center().x, rect.top() + 19.0), vec2(32.0, 32.0));
    icons::paint(ui.painter(), icon_rect, info.icon, enabled);
    let color = if enabled { style::text() } else { style::text_dim() };
    for (k, l) in lines.iter().enumerate() {
        ui.painter().text(pos2(rect.center().x - if k + 1 == lines.len() { arrow_extra / 2.0 } else { 0.0 }, rect.top() + 37.0 + k as f32 * 13.0), egui::Align2::CENTER_TOP, l, font.clone(), color);
    }
    if let Some(alts) = dropdown {
        let c = if lines.len() > 1 {
            pos2(rect.center().x - arrow_extra / 2.0 + widths[lines.len() - 1] / 2.0 + 6.0, rect.top() + 57.0)
        } else {
            pos2(rect.center().x, rect.top() + 57.0)
        };
        ui.painter().add(egui::Shape::convex_polygon(vec![c + vec2(-3.0, -1.5), c + vec2(3.0, -1.5), c + vec2(0.0, 1.5)], style::text(), Stroke::NONE));
        let hot = Rect::from_min_max(pos2(rect.left(), rect.top() + if lines.len() > 1 { 49.0 } else { 51.0 }), rect.max);
        let pointer = ui.input(|i| i.pointer.interact_pos());
        let on_arrow = pointer.is_some_and(|p| hot.contains(p));
        if resp.hovered() && on_arrow {
            ui.painter().line_segment([pos2(rect.left() + 1.0, hot.top()), pos2(rect.right() - 1.0, hot.top())], Stroke::new(1.0, style::hover_stroke()));
        }
        let toggle = if resp.clicked() && on_arrow {
            Some(egui::SetOpenCommand::Toggle)
        } else {
            if resp.clicked() {
                actions::exec(app, cmd);
            }
            None
        };
        egui::Popup::menu(&resp).open_memory(toggle).close_behavior(egui::PopupCloseBehavior::CloseOnClick).show(|ui| {
            ui.set_min_width(200.0);
            for a in alts {
                if menu_item(ui, app, *a) {
                    actions::exec(app, *a);
                }
            }
        });
    } else if resp.clicked() {
        actions::exec(app, cmd);
    }
    if app.settings.tooltips {
        let app_ref: &App = app;
        resp.on_hover_ui(|ui| tooltip(ui, app_ref, cmd));
    }
}

fn split_label(label: &str) -> Vec<&str> {
    if let Some((a, b)) = label.split_once('\n') {
        return vec![a, b];
    }
    if label.len() > 11 {
        if let Some(i) = label[..label.len().min(14)].rfind(' ').or_else(|| label.find(' ')) {
            return vec![&label[..i], label[i + 1..].trim()];
        }
    }
    vec![label]
}

fn menu_item(ui: &mut egui::Ui, app: &App, cmd: Cmd) -> bool {
    let info = cmd.info();
    let enabled = actions::enabled(app, cmd);
    let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width().max(200.0), 24.0), Sense::click());
    if resp.hovered() {
        ui.painter().rect_filled(rect, 2.0, style::hover());
    }
    icons::paint(ui.painter(), Rect::from_min_size(rect.min + vec2(4.0, 4.0), vec2(16.0, 16.0)), info.icon, enabled);
    ui.painter().text(rect.left_center() + vec2(26.0, 0.0), egui::Align2::LEFT_CENTER, info.label.replace('\n', " "), egui::FontId::proportional(12.0), if enabled { style::text() } else { style::text_dim() });
    let keys = app.settings.shortcuts.keys(cmd);
    if !keys.is_empty() {
        ui.painter().text(rect.right_center() - vec2(6.0, 0.0), egui::Align2::RIGHT_CENTER, keys, egui::FontId::proportional(11.0), style::text_dim());
    }
    resp.clicked()
}

fn small_button(ui: &mut egui::Ui, app: &mut App, cmd: Cmd, width: f32) {
    let info = cmd.info();
    let (rect, resp) = ui.allocate_exact_size(vec2(width, 20.0), Sense::click());
    let enabled = actions::enabled(app, cmd);
    button_bg(ui, rect, &resp, is_active(app, cmd));
    icons::paint(ui.painter(), Rect::from_min_size(rect.min + vec2(2.0, 2.0), vec2(16.0, 16.0)), info.icon, enabled);
    ui.painter().text(rect.left_center() + vec2(21.0, 0.0), egui::Align2::LEFT_CENTER, info.label.replace('\n', " "), style::font(RIBBON_FONT), if enabled { style::text() } else { style::text_dim() });
    if resp.clicked() {
        actions::exec(app, cmd);
    }
    if app.settings.tooltips {
        let app_ref: &App = app;
        resp.on_hover_ui(|ui| tooltip(ui, app_ref, cmd));
    }
}

fn icon_button(ui: &mut egui::Ui, app: &mut App, cmd: Cmd, size: f32) {
    let info = cmd.info();
    let (rect, resp) = ui.allocate_exact_size(vec2(size, size), Sense::click());
    let enabled = actions::enabled(app, cmd);
    button_bg(ui, rect, &resp, is_active(app, cmd));
    icons::paint(ui.painter(), rect.shrink(size * 0.14), info.icon, enabled);
    if resp.clicked() {
        actions::exec(app, cmd);
    }
    if app.settings.tooltips {
        let app_ref: &App = app;
        resp.on_hover_ui(|ui| tooltip(ui, app_ref, cmd));
    }
}

fn show_panels(ui: &mut egui::Ui, app: &mut App, panels: Vec<Panel>) {
    ui.horizontal_top(|ui| {
        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
        for p in panels.into_iter() {
            let title_w = ui.painter().layout_no_wrap(p.title.to_string(), style::font(11.5), Color32::BLACK).size().x + 14.0;
            let resp = ui.vertical(|ui| {
                ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                ui.horizontal_top(|ui| {
                    ui.set_min_height(BIG_H + 2.0);
                    ui.set_min_width(title_w);
                    ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
                    ui.add_space(3.0);
                    for item in &p.items {
                        ui.vertical(|ui| {
                            ui.add_space(2.0);
                            match item {
                                Big(c) => big_button(ui, app, *c, None, None, None),
                                Toggle(c, on) => big_button(ui, app, *c, None, None, Some(*on)),
                                Split(c, alts) => big_button(ui, app, *c, None, Some(alts), None),
                                // "User Interface" is a menu, not a toggle.
                                Labeled(label, c, alts) => big_button(ui, app, *c, Some(label), if alts.is_empty() { None } else { Some(alts) }, label.starts_with("User").then_some(false)),
                                Stack(cs) => {
                                    let w = cs
                                        .iter()
                                        .map(|c| ui.painter().layout_no_wrap(c.info().label.replace('\n', " "), style::font(RIBBON_FONT), Color32::BLACK).size().x + 26.0)
                                        .fold(60.0f32, f32::max);
                                    ui.spacing_mut().item_spacing = vec2(0.0, 1.0);
                                    for c in cs {
                                        small_button(ui, app, *c, w);
                                    }
                                }
                                Icons(cs) => {
                                    let rows = if cs.len() > 6 { 3 } else { 2 };
                                    let cols = cs.len().div_ceil(rows);
                                    let size = if rows == 3 { 21.0 } else { 26.0 };
                                    ui.spacing_mut().item_spacing = vec2(1.0, 1.0);
                                    for r in 0..rows {
                                        ui.horizontal(|ui| {
                                            ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
                                            for c in 0..cols {
                                                if let Some(cmd) = cs.get(r * cols + c) {
                                                    icon_button(ui, app, *cmd, size);
                                                }
                                            }
                                        });
                                    }
                                }
                            }
                        });
                    }
                    ui.add_space(3.0);
                });
                // Panel title strip.
                let w = ui.min_rect().width().max(40.0);
                let (r, _) = ui.allocate_exact_size(vec2(w, 15.0), Sense::hover());
                ui.painter().text(r.center() - vec2(0.0, 1.0), egui::Align2::CENTER_CENTER, p.title, style::font(11.5), Color32::from_rgb(70, 70, 70));
            });
            let r = resp.response.rect;
            ui.painter().line_segment([r.right_top() + vec2(0.5, 4.0), r.right_bottom() + vec2(0.5, -3.0)], Stroke::new(1.0, Color32::from_rgb(214, 216, 218)));
        }
    });
}

// ---------------------------------------------------------------- file menu and QAT

/// One big entry of the File menu's left column (icon, label, ▸ when it has a submenu).
fn file_entry(ui: &mut egui::Ui, icon: icons::Icon, label: &str, sub: bool, hot: bool) -> egui::Response {
    let (r, resp) = ui.allocate_exact_size(vec2(112.0, 46.0), Sense::click());
    let p = ui.painter();
    if hot || resp.hovered() {
        p.rect_filled(r, 0.0, style::hover());
        p.rect_stroke(r, 0.0, Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    }
    icons::paint(p, Rect::from_min_size(r.min + vec2(8.0, 7.0), vec2(30.0, 30.0)), icon, true);
    p.text(r.left_center() + vec2(46.0, 0.0), egui::Align2::LEFT_CENTER, label, style::font(12.0), style::text());
    if sub {
        let c = r.right_center() - vec2(10.0, 0.0);
        p.add(egui::Shape::convex_polygon(vec![c + vec2(-2.0, -4.0), c + vec2(2.5, 0.0), c + vec2(-2.0, 4.0)], style::text(), Stroke::NONE));
    }
    resp
}

/// The File (application) menu: big commands on the left, Recent Documents or the hovered
/// submenu on the right, Options and Exit at the bottom.
fn file_menu(ui: &mut egui::Ui, app: &mut App) {
    let mut close = false;
    let sub_id = egui::Id::new("file-menu-sub");
    let mut sub: u8 = ui.memory(|m| m.data.get_temp(sub_id)).unwrap_or(0);
    ui.horizontal_top(|ui| {
        ui.vertical(|ui| {
            ui.spacing_mut().item_spacing.y = 2.0;
            let entries: [(icons::Icon, &str, u8, Option<Cmd>); 7] = [
                (icons::Icon::New, "New", 1, None),
                (icons::Icon::Open, "Open", 2, None),
                (icons::Icon::Save, "Save", 0, Some(C::Save)),
                (icons::Icon::Save, "Save As", 3, None),
                (C::ExportPdf.info().icon, "Export", 4, None),
                (icons::Icon::Sheet, "Print", 5, None),
                (icons::Icon::CloseInactive, "Close", 0, None),
            ];
            for (k, (icon, label, s, cmd)) in entries.into_iter().enumerate() {
                if k == 2 || k == 4 || k == 6 {
                    let (r, _) = ui.allocate_exact_size(vec2(112.0, 5.0), Sense::hover());
                    ui.painter().line_segment([r.left_center() + vec2(6.0, 0.0), r.right_center() - vec2(6.0, 0.0)], Stroke::new(1.0, style::border()));
                }
                let resp = file_entry(ui, icon, label, s != 0, s != 0 && sub == s);
                if resp.hovered() {
                    sub = s;
                }
                if resp.clicked() {
                    match (cmd, label) {
                        (Some(c), _) => {
                            close = true;
                            actions::exec(app, c);
                        }
                        (None, "Close") => {
                            close = true;
                            if app.confirm_discard(crate::dialogs::Pending::New) {
                                app.dialogs.home = true;
                            }
                        }
                        _ => sub = s,
                    }
                }
            }
        });
        let (sep, _) = ui.allocate_exact_size(vec2(1.0, 380.0), Sense::hover());
        ui.painter().line_segment([sep.center_top(), sep.center_bottom()], Stroke::new(1.0, style::border()));
        ui.vertical(|ui| {
            ui.set_width(300.0);
            ui.set_min_height(340.0);
            let items: &[Cmd] = match sub {
                1 => &[C::New, C::NewFamily],
                2 => &[C::Open, C::ImportIfc, C::OpenSample, C::LoadFamily],
                3 => &[C::SaveAs],
                4 => &[C::ExportIfc, C::ExportDxf, C::ExportPdf, C::ExportImage, C::ExportCsv],
                5 => &[C::ExportPdf],
                _ => &[],
            };
            if items.is_empty() {
                ui.label(egui::RichText::new("Recent Documents").font(style::bold(12.5)));
                ui.label(egui::RichText::new("By Ordered List").color(style::text_dim()).size(11.5));
                ui.add_space(6.0);
                if app.settings.recent.is_empty() {
                    ui.label(egui::RichText::new("No recent documents.").color(style::text_dim()));
                }
                for r in app.settings.recent.clone() {
                    let name = std::path::Path::new(&r).file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or(r.clone());
                    if ui.add(egui::Button::new(egui::RichText::new(name)).frame(false)).on_hover_text(&r).clicked() {
                        close = true;
                        if app.confirm_discard(crate::dialogs::Pending::OpenPath(r.clone())) {
                            app.open_path(std::path::Path::new(&r));
                        }
                    }
                }
            } else {
                let title = ["", "Create a new project or family", "Open a project or family", "Save the current project", "Export the current project or view", "Print to PDF"][sub as usize];
                ui.label(egui::RichText::new(title).font(style::bold(12.5)));
                ui.add_space(6.0);
                for c in items {
                    let info = c.info();
                    let (r, resp) = ui.allocate_exact_size(vec2(300.0, 40.0), Sense::click());
                    if resp.hovered() {
                        ui.painter().rect_filled(r, 0.0, style::hover());
                    }
                    icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(6.0, 6.0), vec2(28.0, 28.0)), info.icon, actions::enabled(app, *c));
                    ui.painter().text(r.min + vec2(42.0, 5.0), egui::Align2::LEFT_TOP, info.label.replace('\n', " "), style::bold(12.0), style::text());
                    let tip: String = info.tip.chars().take(52).collect();
                    ui.painter().text(r.min + vec2(42.0, 22.0), egui::Align2::LEFT_TOP, tip, style::font(11.0), style::text_dim());
                    if resp.clicked() {
                        close = true;
                        actions::exec(app, *c);
                    }
                }
            }
            ui.with_layout(egui::Layout::bottom_up(egui::Align::Max), |ui| {
                ui.horizontal(|ui| {
                    if ui.add(egui::Button::new("Exit RevitCraft").min_size(vec2(96.0, 24.0))).clicked() {
                        close = true;
                        actions::exec(app, C::Exit);
                    }
                    if ui.add(egui::Button::new("Options").min_size(vec2(70.0, 24.0))).clicked() {
                        close = true;
                        actions::exec(app, C::Options);
                    }
                });
            });
        });
    });
    ui.memory_mut(|m| m.data.insert_temp(sub_id, sub));
    if close {
        app.file_menu = false;
        ui.memory_mut(|m| m.data.insert_temp(sub_id, 0u8));
    }
}

fn qat(ui: &mut egui::Ui, app: &mut App) {
    for c in [C::Home, C::Open, C::Save, C::Undo, C::Redo, C::Measure, C::DimAligned, C::TagByCategory, C::Text, C::Default3D, C::Section, C::ThinLines, C::CloseInactive] {
        icon_button(ui, app, c, 20.0);
    }
    // Switch windows.
    let (r, resp) = ui.allocate_exact_size(vec2(26.0, 20.0), Sense::click());
    if resp.hovered() {
        ui.painter().rect_filled(r, 0.0, style::hover());
    }
    icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(2.0, 2.0), vec2(16.0, 16.0)), icons::Icon::TileViews, true);
    let c = r.right_center() - vec2(4.0, 0.0);
    ui.painter().add(egui::Shape::convex_polygon(vec![c + vec2(-2.5, -1.0), c + vec2(2.5, -1.0), c + vec2(0.0, 1.5)], style::text(), Stroke::NONE));
    let resp = resp.on_hover_text("Switch Windows");
    egui::Popup::menu(&resp).show(|ui| {
        for t in app.open_tabs() {
            let title = app.view_title(t);
            if ui.selectable_label(app.active == Some(t), title).clicked() {
                app.open_view(t);
            }
        }
    });
}

// ---------------------------------------------------------------- the ribbon

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    let ctx = contextual(app);
    // The contextual tab opens when a tool, selection or sketch begins and the previous tab
    // comes back when it ends.
    let key = ctx.as_ref().map(|(t, _)| t.clone());
    let mem_id = egui::Id::new("ribbon-context");
    let ret_id = egui::Id::new("ribbon-return");
    let prev: Option<String> = ui.memory(|m| m.data.get_temp(mem_id)).flatten();
    if key.is_some() && key != prev {
        if prev.is_none() && app.ribbon_tab != Tab::Modify {
            let t = app.ribbon_tab;
            ui.memory_mut(|m| m.data.insert_temp(ret_id, t));
        }
        app.ribbon_tab = Tab::Modify;
    } else if key.is_none() && prev.is_some() && app.ribbon_tab == Tab::Modify {
        app.ribbon_tab = ui.memory(|m| m.data.get_temp(ret_id)).unwrap_or(Tab::Architecture);
    }
    ui.memory_mut(|m| m.data.insert_temp(mem_id, key.clone()));
    let sketch = app.sketch.is_some();

    // Row 1: Quick Access Toolbar.
    egui::Frame::new().inner_margin(egui::Margin { left: 4, right: 4, top: 1, bottom: 1 }).show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
            qat(ui, app);
        });
    });
    // Row 2: tabs.
    let file_resp = ui
        .horizontal(|ui| {
            ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
            ui.add_space(2.0);
            let (r, resp) = ui.allocate_exact_size(vec2(44.0, 20.0), Sense::click());
            ui.painter().rect_filled(r, 0.0, if resp.hovered() || app.file_menu { Color32::from_rgb(24, 100, 166) } else { style::ACCENT });
            ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, "File", style::font(12.0), Color32::WHITE);
            if resp.clicked() {
                app.file_menu = !app.file_menu;
            }
            for t in Tab::ALL {
                match (&ctx, t) {
                    (Some((title, _)), Tab::Modify) => tab_button(ui, app, t, &format!("Modify | {title}"), Some(if sketch { style::SKETCH_TAB } else { style::CONTEXT })),
                    _ => tab_button(ui, app, t, t.label(), None),
                }
            }
            resp
        })
        .inner;
    if app.file_menu {
        let area = egui::Area::new(egui::Id::new("file-menu")).order(egui::Order::Foreground).fixed_pos(file_resp.rect.left_bottom() + vec2(0.0, 1.0)).show(ui.ctx(), |ui| {
            egui::Frame::popup(ui.style()).inner_margin(6).show(ui, |ui| file_menu(ui, app));
        });
        let clicked_outside = ui.input(|i| i.pointer.any_click()) && !area.response.rect.contains(ui.input(|i| i.pointer.interact_pos()).unwrap_or_default()) && !file_resp.clicked();
        if clicked_outside || ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            app.file_menu = false;
        }
    }
    // Row 3: panels.
    let tinted = app.ribbon_tab == Tab::Modify && ctx.is_some();
    let body = if tinted { style::ribbon_tint(sketch) } else { style::ribbon() };
    let frame = egui::Frame::new().fill(body).inner_margin(egui::Margin { left: 2, right: 2, top: 0, bottom: 0 });
    let r = frame
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::horizontal().id_salt("ribbon-scroll").scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden).show(ui, |ui| {
                ui.set_min_height(BIG_H + 17.0);
                match app.ribbon_tab {
                    Tab::Architecture => show_panels(ui, app, architecture()),
                    Tab::Structure => show_panels(ui, app, structure()),
                    Tab::Insert => show_panels(ui, app, insert()),
                    Tab::Annotate => show_panels(ui, app, annotate()),
                    Tab::Analyze => show_panels(ui, app, analyze()),
                    Tab::MassingSite => show_panels(ui, app, massing_site()),
                    Tab::View => {
                        let p = view_tab(app);
                        show_panels(ui, app, p)
                    }
                    Tab::Manage => show_panels(ui, app, manage()),
                    Tab::Modify => {
                        let mut panels = modify_panels();
                        if let Some((_, extra)) = contextual(app) {
                            // Tool- and element-specific panels follow the standard Modify panels.
                            panels.extend(extra);
                        }
                        show_panels(ui, app, panels)
                    }
                }
            });
        })
        .response
        .rect;
    ui.painter().line_segment([r.left_top(), r.right_top()], Stroke::new(1.0, style::border()));
    ui.painter().line_segment([r.left_bottom(), r.right_bottom()], Stroke::new(1.0, style::border()));
    // The active tab merges into the ribbon body.
    if let Some(tab_rect) = ui.memory(|m| m.data.get_temp::<Rect>(egui::Id::new("ribbon-active-tab"))) {
        if ctx.is_none() || app.ribbon_tab != Tab::Modify {
            ui.painter().line_segment([pos2(tab_rect.left() + 1.0, r.top()), pos2(tab_rect.right() - 1.0, r.top())], Stroke::new(1.0, body));
        }
    }
}

fn tab_button(ui: &mut egui::Ui, app: &mut App, t: Tab, label: &str, context: Option<Color32>) {
    let font = style::font(12.0);
    let w = ui.painter().layout_no_wrap(label.to_string(), font.clone(), Color32::BLACK).size().x + 18.0;
    let (r, resp) = ui.allocate_exact_size(vec2(w, 20.0), Sense::click());
    let selected = app.ribbon_tab == t;
    let p = ui.painter();
    if let Some(fill) = context {
        let fill = if selected || resp.hovered() { fill } else { fill.gamma_multiply(0.85) };
        p.rect_filled(r.shrink2(vec2(1.0, 0.0)), 0.0, fill);
    } else if selected {
        p.rect_filled(r, 0.0, style::ribbon());
        let st = Stroke::new(1.0, style::border());
        p.line_segment([r.left_bottom(), r.left_top()], st);
        p.line_segment([r.left_top(), r.right_top()], st);
        p.line_segment([r.right_top(), r.right_bottom()], st);
    } else if resp.hovered() {
        p.rect_filled(r.shrink(1.0), 0.0, Color32::from_rgb(232, 232, 232));
    }
    if selected {
        ui.memory_mut(|m| m.data.insert_temp(egui::Id::new("ribbon-active-tab"), r));
    }
    p.text(r.center(), egui::Align2::CENTER_CENTER, label, font, style::text());
    if resp.clicked() {
        app.ribbon_tab = t;
        app.file_menu = false;
    }
}
