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
    View,
    Manage,
    Modify,
}

impl Tab {
    const ALL: [Tab; 7] = [Tab::Architecture, Tab::Structure, Tab::Insert, Tab::Annotate, Tab::View, Tab::Manage, Tab::Modify];
    fn label(self) -> &'static str {
        match self {
            Tab::Architecture => "Architecture",
            Tab::Structure => "Structure",
            Tab::Insert => "Insert",
            Tab::Annotate => "Annotate",
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
                Split(C::Wall, vec![C::Wall, C::WallStructural]),
                Big(C::Door),
                Big(C::Window),
                Split(C::Component, vec![C::Component, C::LoadFamily, C::NewFamily]),
                Split(C::Column, vec![C::Column, C::StructColumn]),
                Split(C::RoofFootprint, vec![C::RoofFootprint, C::RoofExtrusion]),
                Big(C::Ceiling),
                Split(C::Floor, vec![C::Floor, C::FloorStructural]),
                Stack(vec![C::CurtainGrid]),
            ],
        ),
        panel("Circulation", vec![Big(C::Railing), Big(C::Stair)]),
        panel("Model", vec![Stack(vec![C::ModelLine, C::PlaceGroup, C::CreateGroup])]),
        panel("Room & Area", vec![Big(C::Room), Stack(vec![C::RoomSeparator, C::RoomTag]), Big(C::Area), Stack(vec![C::AreaBoundary, C::AreaTag])]),
        panel("Opening", vec![Big(C::Shaft), Big(C::WallOpening)]),
        panel("Datum", vec![Big(C::Level), Big(C::Grid)]),
        panel("Work Plane", vec![Big(C::RefPlane)]),
    ]
}

fn structure() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Structure", vec![Big(C::Beam), Big(C::WallStructural), Big(C::StructColumn), Big(C::FloorStructural)]),
        panel("Foundation", vec![Big(C::IsolatedFoundation), Big(C::WallFoundation), Big(C::FloorStructural)]),
        panel("Model", vec![Stack(vec![C::ModelLine, C::Component, C::PlaceGroup])]),
        panel("Opening", vec![Big(C::Shaft), Big(C::WallOpening)]),
        panel("Datum", vec![Big(C::Level), Big(C::Grid)]),
        panel("Work Plane", vec![Big(C::RefPlane)]),
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
            vec![Big(C::DimAligned), Big(C::DimLinear), Big(C::DimAngular), Big(C::DimRadial), Big(C::DimDiameter), Big(C::DimArcLength), Big(C::SpotElevation)],
        ),
        panel("Detail", vec![Big(C::DetailLine), Split(C::FilledRegion, vec![C::FilledRegion, C::MaskingRegion]), Big(C::RevisionCloud)]),
        panel("Text", vec![Big(C::Text)]),
        panel("Tag", vec![Big(C::TagByCategory), Big(C::TagAll), Stack(vec![C::RoomTag, C::AreaTag])]),
        panel("Symbol", vec![Big(C::Symbol)]),
    ]
}

fn view_tab(app: &App) -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Graphics", vec![Split(C::ViewTemplates, vec![C::ViewTemplates, C::TemplateFromView]), Big(C::VisibilityGraphics), Toggle(C::ThinLines, app.thin_lines)]),
        panel(
            "Create",
            vec![
                Big(C::Default3D),
                Big(C::Section),
                Big(C::Callout),
                Split(C::NewFloorPlan, vec![C::NewFloorPlan, C::NewCeilingPlan, C::NewAreaPlan]),
                Big(C::ElevationView),
                Big(C::DraftingView),
                Split(C::DuplicateView, vec![C::DuplicateView, C::DuplicateWithDetailing]),
                Big(C::Legend),
                Split(C::Schedule, vec![C::Schedule, C::MaterialTakeoff, C::SheetList]),
            ],
        ),
        panel("Sheet Composition", vec![Big(C::NewSheet), Big(C::PlaceView), Big(C::Revisions)]),
        panel(
            "Windows",
            vec![
                Stack(vec![C::CloseInactive, C::TabViews, C::TileViews]),
                Split(C::ToggleProperties, vec![C::ToggleProperties, C::ToggleBrowser, C::ToggleStatusBar, C::ToggleOptionsBar, C::ToggleViewCube, C::ToggleNavBar]),
            ],
        ),
    ]
}

fn manage() -> Vec<Panel> {
    vec![
        panel("Select", vec![Big(C::Modify)]),
        panel("Settings", vec![Big(C::Materials), Big(C::ObjectStyles), Big(C::Snaps), Big(C::ProjectInfo), Big(C::ProjectUnits), Big(C::Purge)]),
        panel("Project Location", vec![Big(C::Sun)]),
        panel("Design Options", vec![Big(C::DesignOptions)]),
        panel("Manage Project", vec![Big(C::ManageLinks)]),
        panel("Phasing", vec![Big(C::Phases)]),
        panel("Inquiry", vec![Stack(vec![C::IdsOfSelection, C::SelectById, C::Warnings])]),
        panel("Customize", vec![Big(C::KeyboardShortcuts), Big(C::Options)]),
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
                C::Align, C::Offset, C::MirrorPick, C::MirrorDraw, C::TrimCorner, C::Split, C::Pin, C::Delete, C::Move, C::Copy, C::Rotate, C::Array, C::Scale, C::TrimSingle,
                C::TrimMulti, C::Unpin,
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
        p.rect_filled(rect, 3.0, style::accent_light());
        p.rect_stroke(rect, 3.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Inside);
    } else if resp.hovered() {
        p.rect_filled(rect, 3.0, style::hover());
        p.rect_stroke(rect, 3.0, Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
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
        _ => false,
    }
}

fn big_button(ui: &mut egui::Ui, app: &mut App, cmd: Cmd, dropdown: Option<&[Cmd]>, toggled: Option<bool>) {
    let info = cmd.info();
    let label = info.label;
    let font = egui::FontId::proportional(11.0);
    let lines: Vec<&str> = split_label(label);
    let text_w = lines.iter().map(|l| ui.painter().layout_no_wrap(l.to_string(), font.clone(), Color32::BLACK).size().x).fold(0.0f32, f32::max);
    let w = (text_w + 10.0).max(46.0);
    let (rect, resp) = ui.allocate_exact_size(vec2(w, if dropdown.is_some() && lines.len() > 1 { 76.0 } else { 70.0 }), Sense::click());
    let enabled = actions::enabled(app, cmd);
    let active = toggled.unwrap_or_else(|| is_active(app, cmd));
    button_bg(ui, rect, &resp, active);
    let icon_rect = Rect::from_center_size(pos2(rect.center().x, rect.top() + 20.0), vec2(30.0, 30.0));
    icons::paint(ui.painter(), icon_rect, info.icon, enabled);
    let color = if enabled { style::text() } else { style::text_dim() };
    for (k, l) in lines.iter().enumerate() {
        ui.painter().text(pos2(rect.center().x, rect.top() + 43.0 + k as f32 * 12.0), egui::Align2::CENTER_TOP, l, font.clone(), color);
    }
    if let Some(alts) = dropdown {
        let tri_y = rect.bottom() - 4.0;
        let c = pos2(rect.center().x, tri_y);
        ui.painter().add(egui::Shape::convex_polygon(vec![c + vec2(-3.5, -2.0), c + vec2(3.5, -2.0), c + vec2(0.0, 2.0)], style::text_dim(), Stroke::NONE));
        let hot = Rect::from_min_max(pos2(rect.left(), rect.bottom() - 14.0), rect.max);
        let pointer = ui.input(|i| i.pointer.interact_pos());
        let on_arrow = pointer.is_some_and(|p| hot.contains(p));
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
    let (rect, resp) = ui.allocate_exact_size(vec2(width, 22.0), Sense::click());
    let enabled = actions::enabled(app, cmd);
    button_bg(ui, rect, &resp, is_active(app, cmd));
    icons::paint(ui.painter(), Rect::from_min_size(rect.min + vec2(3.0, 3.0), vec2(16.0, 16.0)), info.icon, enabled);
    ui.painter().text(rect.left_center() + vec2(23.0, 0.0), egui::Align2::LEFT_CENTER, info.label.replace('\n', " "), egui::FontId::proportional(11.5), if enabled { style::text() } else { style::text_dim() });
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
    icons::paint(ui.painter(), rect.shrink(size * 0.16), info.icon, enabled);
    if resp.clicked() {
        actions::exec(app, cmd);
    }
    if app.settings.tooltips {
        let app_ref: &App = app;
        resp.on_hover_ui(|ui| tooltip(ui, app_ref, cmd));
    }
}

fn show_panels(ui: &mut egui::Ui, app: &mut App, panels: Vec<Panel>, context: bool) {
    ui.horizontal_top(|ui| {
        ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
        for (pi, p) in panels.into_iter().enumerate() {
            let resp = ui.vertical(|ui| {
                ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
                ui.horizontal_top(|ui| {
                    ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
                    ui.add_space(3.0);
                    for item in &p.items {
                        match item {
                            Big(c) => big_button(ui, app, *c, None, None),
                            Toggle(c, on) => big_button(ui, app, *c, None, Some(*on)),
                            Split(c, alts) => big_button(ui, app, *c, Some(alts), None),
                            Stack(cs) => {
                                let w = cs
                                    .iter()
                                    .map(|c| ui.painter().layout_no_wrap(c.info().label.replace('\n', " "), egui::FontId::proportional(11.5), Color32::BLACK).size().x + 30.0)
                                    .fold(60.0f32, f32::max);
                                ui.vertical(|ui| {
                                    ui.spacing_mut().item_spacing = vec2(0.0, 1.0);
                                    ui.add_space(2.0);
                                    for c in cs {
                                        small_button(ui, app, *c, w);
                                    }
                                });
                            }
                            Icons(cs) => {
                                let rows = 2;
                                let cols = cs.len().div_ceil(rows);
                                ui.vertical(|ui| {
                                    ui.spacing_mut().item_spacing = vec2(1.0, 2.0);
                                    ui.add_space(4.0);
                                    for r in 0..rows {
                                        ui.horizontal(|ui| {
                                            ui.spacing_mut().item_spacing = vec2(1.0, 0.0);
                                            for c in 0..cols {
                                                if let Some(cmd) = cs.get(r * cols + c) {
                                                    icon_button(ui, app, *cmd, 30.0);
                                                }
                                            }
                                        });
                                    }
                                });
                            }
                        }
                    }
                    ui.add_space(3.0);
                });
                // Panel title bar.
                let w = ui.min_rect().width().max(40.0);
                let (r, _) = ui.allocate_exact_size(vec2(w, 16.0), Sense::hover());
                let fill = if context { Color32::from_rgba_unmultiplied(70, 150, 60, 40) } else { style::group_header() };
                ui.painter().rect_filled(r, 0.0, fill);
                ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, p.title, egui::FontId::proportional(10.5), style::text_dim());
            });
            let r = resp.response.rect;
            ui.painter().line_segment([r.right_top() + vec2(0.5, 2.0), r.right_bottom() + vec2(0.5, -2.0)], Stroke::new(1.0, style::border()));
            let _ = pi;
        }
    });
}

// ---------------------------------------------------------------- file menu and QAT

fn file_menu(ui: &mut egui::Ui, app: &mut App) {
    let mut close = false;
    ui.horizontal_top(|ui| {
        ui.vertical(|ui| {
            ui.set_width(210.0);
            for c in [C::New, C::Open, C::Save, C::SaveAs, C::OpenSample, C::ImportIfc] {
                if menu_item(ui, app, c) {
                    close = true;
                    actions::exec(app, c);
                }
            }
            ui.separator();
            ui.label(egui::RichText::new("Export").strong().color(style::text_dim()));
            for c in [C::ExportIfc, C::ExportDxf, C::ExportPdf, C::ExportImage, C::ExportCsv] {
                if menu_item(ui, app, c) {
                    close = true;
                    actions::exec(app, c);
                }
            }
            ui.separator();
            for c in [C::Options, C::Exit] {
                if menu_item(ui, app, c) {
                    close = true;
                    actions::exec(app, c);
                }
            }
        });
        ui.separator();
        ui.vertical(|ui| {
            ui.set_width(300.0);
            ui.label(egui::RichText::new("Recent Documents").strong());
            ui.add_space(4.0);
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
        });
    });
    if close {
        app.file_menu = false;
    }
}

fn qat(ui: &mut egui::Ui, app: &mut App) {
    for c in [C::Open, C::Save, C::Undo, C::Redo, C::Measure, C::DimAligned, C::TagByCategory, C::Text, C::Default3D, C::Section, C::ThinLines, C::CloseInactive] {
        icon_button(ui, app, c, 22.0);
    }
    // Switch windows.
    let resp = ui.add(egui::Button::new(egui::RichText::new("Switch Windows").size(11.0)).frame(false));
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
    // Switch to the contextual tab when a context appears.
    let key = ctx.as_ref().map(|(t, _)| t.clone());
    let mem_id = egui::Id::new("ribbon-context");
    let prev: Option<String> = ui.memory(|m| m.data.get_temp(mem_id)).flatten();
    if key.is_some() && prev.is_none() {
        app.ribbon_tab = Tab::Modify;
    }
    ui.memory_mut(|m| m.data.insert_temp(mem_id, key.clone()));

    // Row 1: QAT.
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing = vec2(2.0, 0.0);
        qat(ui, app);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            let name = app.doc.path.as_ref().and_then(|p| p.file_stem()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Project1".into());
            ui.label(egui::RichText::new(format!("{name}{}", if app.doc.dirty { " *" } else { "" })).color(style::text_dim()).size(11.5));
        });
    });
    // Row 2: tabs.
    let file_resp = ui
        .horizontal(|ui| {
            ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
            let (r, resp) = ui.allocate_exact_size(vec2(52.0, 24.0), Sense::click());
            ui.painter().rect_filled(r, 2.0, if resp.hovered() || app.file_menu { Color32::from_rgb(10, 100, 180) } else { style::ACCENT });
            ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, "File", egui::FontId::proportional(12.5), Color32::WHITE);
            if resp.clicked() {
                app.file_menu = !app.file_menu;
            }
            ui.add_space(4.0);
            for t in Tab::ALL {
                match (&ctx, t) {
                    (Some((title, _)), Tab::Modify) => tab_button(ui, app, t, &format!("Modify | {title}"), true),
                    _ => tab_button(ui, app, t, t.label(), false),
                }
            }
            resp
        })
        .inner;
    if app.file_menu {
        let area = egui::Area::new(egui::Id::new("file-menu")).order(egui::Order::Foreground).fixed_pos(file_resp.rect.left_bottom() + vec2(0.0, 2.0)).show(ui.ctx(), |ui| {
            egui::Frame::popup(ui.style()).inner_margin(10).show(ui, |ui| file_menu(ui, app));
        });
        let clicked_outside = ui.input(|i| i.pointer.any_click()) && !area.response.rect.contains(ui.input(|i| i.pointer.interact_pos()).unwrap_or_default()) && !file_resp.clicked();
        if clicked_outside || ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            app.file_menu = false;
        }
    }
    ui.add_space(1.0);
    // Row 3: panels.
    egui::ScrollArea::horizontal().id_salt("ribbon-scroll").show(ui, |ui| {
        ui.set_min_height(88.0);
        match app.ribbon_tab {
            Tab::Architecture => show_panels(ui, app, architecture(), false),
            Tab::Structure => show_panels(ui, app, structure(), false),
            Tab::Insert => show_panels(ui, app, insert(), false),
            Tab::Annotate => show_panels(ui, app, annotate(), false),
            Tab::View => {
                let p = view_tab(app);
                show_panels(ui, app, p, false)
            }
            Tab::Manage => show_panels(ui, app, manage(), false),
            Tab::Modify => {
                let mut panels = modify_panels();
                if let Some((_, extra)) = contextual(app) {
                    // Contextual panels go right after Select, like the standard layout.
                    let rest = panels.split_off(1);
                    panels.extend(extra);
                    panels.extend(rest);
                    show_panels(ui, app, panels, true)
                } else {
                    show_panels(ui, app, panels, false)
                }
            }
        }
    });
}

fn tab_button(ui: &mut egui::Ui, app: &mut App, t: Tab, label: &str, contextual_tab: bool) {
    let font = egui::FontId::proportional(12.5);
    let w = ui.painter().layout_no_wrap(label.to_string(), font.clone(), Color32::BLACK).size().x + 22.0;
    let (r, resp) = ui.allocate_exact_size(vec2(w, 24.0), Sense::click());
    let selected = app.ribbon_tab == t;
    let p = ui.painter();
    if contextual_tab {
        p.rect_filled(r, 2.0, if selected { Color32::from_rgb(222, 240, 214) } else { Color32::from_rgb(234, 245, 228) });
        p.line_segment([r.left_top(), r.right_top()], Stroke::new(3.0, style::CONTEXT));
    } else if selected {
        p.rect_filled(r, 2.0, style::ribbon());
        p.line_segment([r.left_bottom() + vec2(6.0, -1.5), r.right_bottom() + vec2(-6.0, -1.5)], Stroke::new(2.5, style::ACCENT));
    } else if resp.hovered() {
        p.rect_filled(r, 2.0, style::hover());
    }
    let color = if contextual_tab { Color32::from_rgb(40, 110, 30) } else if selected { style::ACCENT } else { style::text() };
    p.text(r.center(), egui::Align2::CENTER_CENTER, label, font, color);
    if resp.clicked() {
        app.ribbon_tab = t;
        app.file_menu = false;
    }
}
