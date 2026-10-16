//! Project Browser: views, schedules, sheets, families, groups and links.

use crate::app::App;
use crate::commands::Cmd;
use crate::icons::{self, Icon};
use crate::{actions, style};
use eframe::egui::{self, Rect, Sense, vec2};
use rc_core::edit;
use rc_core::model::*;

/// Drag payload: a view dragged from the browser (onto a sheet).
#[derive(Clone, Copy, Debug)]
pub struct DragView(pub Id);

fn matches(filter: &str, s: &str) -> bool {
    filter.is_empty() || s.to_lowercase().contains(&filter.to_lowercase())
}

fn view_icon(v: &View) -> Icon {
    match v.kind {
        ViewKind::FloorPlan { .. } => Icon::FloorPlan,
        ViewKind::CeilingPlan { .. } => Icon::CeilingPlan,
        ViewKind::AreaPlan { .. } => Icon::AreaPlan,
        ViewKind::ThreeD { .. } => Icon::View3D,
        ViewKind::Elevation { .. } => Icon::Elevation,
        ViewKind::Section { .. } => Icon::Section,
        ViewKind::Drafting => Icon::DraftingView,
        ViewKind::Legend => Icon::Legend,
        ViewKind::Schedule(ref d) if d.material_takeoff => Icon::MaterialTakeoff,
        ViewKind::Schedule(ref d) if d.sheet_list => Icon::SheetList,
        ViewKind::Schedule(_) => Icon::Schedule,
        ViewKind::Sheet(_) => Icon::Sheet,
    }
}

/// One clickable row: icon + text. Returns the response.
fn row(ui: &mut egui::Ui, icon: Icon, text: &str, selected: bool, bold: bool) -> egui::Response {
    let h = ROW_H;
    let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), h), Sense::click_and_drag());
    tree_register(ui, r, r.left() + 1.0);
    let font = if bold { style::bold(12.0) } else { style::font(12.0) };
    let tw = ui.painter().layout_no_wrap(text.to_string(), font.clone(), style::text()).size().x;
    let hi = Rect::from_min_size(r.min + vec2(19.0, 0.0), vec2((tw + 6.0).min(r.width() - 19.0), h));
    if selected {
        ui.painter().rect_filled(hi, 0.0, style::accent_light());
        ui.painter().rect_stroke(hi, 0.0, egui::Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    } else if resp.hovered() {
        ui.painter().rect_filled(hi, 0.0, style::hover());
    }
    icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(2.0, 1.0), vec2(15.0, 15.0)), icon, true);
    let galley = egui::WidgetText::from(egui::RichText::new(text).font(font)).into_galley(ui, Some(egui::TextWrapMode::Truncate), r.width() - 24.0, egui::TextStyle::Body);
    ui.painter().galley(r.min + vec2(22.0, (h - galley.size().y) / 2.0), galley, style::text());
    resp
}

// ---------------------------------------------------------------- tree with dotted connectors

const ROW_H: f32 = 17.0;
const INDENT: f32 = 13.0;

thread_local! {
    /// For each open tree node: the centre y of its last child row so far.
    static TREE: std::cell::RefCell<Vec<Option<f32>>> = const { std::cell::RefCell::new(Vec::new()) };
}

fn dotted(painter: &egui::Painter, a: egui::Pos2, b: egui::Pos2) {
    let len = a.distance(b);
    if len < 1.0 {
        return;
    }
    let d = (b - a) / len;
    let c = egui::Color32::from_gray(160);
    let mut t = 0.0;
    while t <= len {
        let q = a + d * t;
        painter.rect_filled(Rect::from_min_size(egui::pos2(q.x.round(), q.y.round()), vec2(1.0, 1.0)), 0.0, c);
        t += 2.0;
    }
}

/// Records a row in the enclosing node and draws its horizontal stub from the parent's line.
fn tree_register(ui: &egui::Ui, r: Rect, stub_end: f32) {
    let depth = TREE.with(|t| {
        let mut t = t.borrow_mut();
        let n = t.len();
        if let Some(last) = t.last_mut() {
            *last = Some(r.center().y);
        }
        n
    });
    if depth > 0 {
        let x = r.left() - INDENT + 4.5;
        dotted(ui.painter(), egui::pos2(x, r.center().y.round() + 0.5), egui::pos2(stub_end, r.center().y.round() + 0.5));
    }
}

/// A plain label row inside the tree.
fn tree_text(ui: &mut egui::Ui, text: &str) {
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), ROW_H), Sense::hover());
    tree_register(ui, r, r.left() + 1.0);
    ui.painter().text(r.left_center() + vec2(3.0, 0.0), egui::Align2::LEFT_CENTER, text, style::font(12.0), style::text_dim());
}

/// A collapsible tree node with a "-"/"+" expander and dotted lines to its children.
fn tree_node(ui: &mut egui::Ui, salt: impl std::hash::Hash + std::fmt::Debug, label: &str, icon: Option<Icon>, default_open: bool, force_open: bool, body: impl FnOnce(&mut egui::Ui)) -> egui::Response {
    let id = ui.make_persistent_id(salt);
    let mut state = egui::collapsing_header::CollapsingState::load_with_default_open(ui.ctx(), id, default_open);
    let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), ROW_H), Sense::click());
    tree_register(ui, r, r.left() + 1.0);
    let open = state.is_open() || force_open;
    let p = ui.painter();
    let c = egui::pos2(r.left() + 4.5, r.center().y.round() + 0.5);
    let ink = egui::Stroke::new(1.0, style::text());
    p.line_segment([c - vec2(3.5, 0.0), c + vec2(3.5, 0.0)], ink);
    if !open {
        p.line_segment([c - vec2(0.0, 3.5), c + vec2(0.0, 3.5)], ink);
    }
    let mut x = r.left() + 13.0;
    if let Some(icon) = icon {
        icons::paint(p, Rect::from_min_size(egui::pos2(x, r.top() + 1.0), vec2(15.0, 15.0)), icon, true);
        x += 19.0;
    }
    let tw = p.layout_no_wrap(label.to_string(), style::font(12.0), style::text()).size().x;
    if resp.hovered() {
        p.rect_filled(Rect::from_min_size(egui::pos2(x - 2.0, r.top()), vec2(tw + 5.0, ROW_H)), 0.0, style::hover());
    }
    p.text(egui::pos2(x, r.center().y), egui::Align2::LEFT_CENTER, label, style::font(12.0), style::text());
    if resp.clicked() && !force_open {
        state.toggle(ui);
    }
    let open = state.is_open() || force_open;
    state.store(ui.ctx());
    if open {
        TREE.with(|t| t.borrow_mut().push(None));
        ui.indent(id.with("body"), |ui| {
            ui.spacing_mut().indent = INDENT;
            body(ui)
        });
        let last = TREE.with(|t| t.borrow_mut().pop()).flatten();
        if let Some(y) = last {
            dotted(ui.painter(), egui::pos2(c.x, r.bottom() + 1.0), egui::pos2(c.x, y.round() + 0.5));
        }
    }
    resp
}

fn view_row(app: &mut App, ui: &mut egui::Ui, v: &View) {
    let active = app.active == Some(v.id);
    let selected = app.selection.contains(&v.id);
    let label = match &v.kind {
        ViewKind::Sheet(s) => format!("{} - {}", s.number, v.name),
        _ => v.name.clone(),
    };
    let resp = row(ui, view_icon(v), &label, selected, active);
    let resp = if !matches!(v.kind, ViewKind::Sheet(_) | ViewKind::Schedule(_)) || matches!(v.kind, ViewKind::Schedule(_)) {
        // Views can be dragged onto sheets.
        let id = v.id;
        if resp.drag_started() {
            egui::DragAndDrop::set_payload(ui.ctx(), DragView(id));
        }
        resp
    } else {
        resp
    };
    if resp.double_clicked() {
        app.open_view(v.id);
    } else if resp.clicked() {
        app.select(vec![v.id]);
    }
    let id = v.id;
    let is_sheet = matches!(v.kind, ViewKind::Sheet(_));
    resp.context_menu(|ui| {
        if ui.button("Open").clicked() {
            app.open_view(id);
            ui.close();
        }
        if !is_sheet {
            ui.menu_button("Duplicate View", |ui| {
                if ui.button("Duplicate").clicked() {
                    if let Some(n) = app.run("Duplicate View", |p| edit::duplicate_view(p, id, false)) {
                        app.open_view(n);
                    }
                    ui.close();
                }
                if ui.button("Duplicate with Detailing").clicked() {
                    if let Some(n) = app.run("Duplicate View", |p| edit::duplicate_view(p, id, true)) {
                        app.open_view(n);
                    }
                    ui.close();
                }
            });
            ui.menu_button("Apply Template", |ui| {
                let templates: Vec<(Id, String)> = app.doc.data.views.iter().filter(|t| t.is_template).map(|t| (t.id, t.name.clone())).collect();
                if templates.is_empty() {
                    ui.label("No view templates. Create one with View > View Templates.");
                }
                for (t, name) in templates {
                    if ui.button(name).clicked() {
                        app.run("Apply View Template", |p| edit::apply_template(p, id, t));
                        ui.close();
                    }
                }
            });
            if ui.button("Create View Template From View...").clicked() {
                app.activate(id);
                actions::exec(app, Cmd::TemplateFromView);
                ui.close();
            }
        }
        if ui.button("Rename...").clicked() {
            let name = app.doc.data.view(id).map(|v| v.name.clone()).unwrap_or_default();
            app.dialogs.rename_view = Some((id, name));
            ui.close();
        }
        if ui.button("Delete").clicked() {
            if app.run("Delete View", |p| edit::delete_view(p, id)).is_some() {
                app.close_view(id);
            }
            ui.close();
        }
        ui.separator();
        if ui.button("Properties").clicked() {
            app.select(vec![id]);
            app.settings.show_properties = true;
            ui.close();
        }
    });
}

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    if app.family_editor.is_some() {
        family_browser(app, ui);
        return;
    }
    let name = app.doc.path.as_ref().and_then(|p| p.file_stem()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Project1".into());
    if style::palette_title(ui, &format!("Project Browser - {name}")) {
        app.settings.show_browser = false;
    }
    let filter_id = egui::Id::new("browser-filter");
    let mut filter: String = ui.memory(|m| m.data.get_temp(filter_id)).unwrap_or_default();
    egui::Frame::new().inner_margin(egui::Margin::symmetric(6, 4)).show(ui, |ui| {
        ui.horizontal(|ui| {
            let (r, _) = ui.allocate_exact_size(vec2(16.0, 16.0), Sense::hover());
            icons::paint(ui.painter(), r, Icon::Search, true);
            ui.add(egui::TextEdit::singleline(&mut filter).hint_text("Search").desired_width(ui.available_width()));
        });
    });
    ui.memory_mut(|m| m.data.insert_temp(filter_id, filter.clone()));
    let f = filter.trim().to_string();
    egui::ScrollArea::vertical().auto_shrink([false, false]).id_salt("browser-scroll").show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        ui.spacing_mut().indent = INDENT;
        let p = app.snapshot();
        let open_default = !f.is_empty();
        tree_node(ui, "Views (all)", "Views (all)", Some(Icon::FloorPlan), true, open_default, |ui| {
            let groups: [(&str, fn(&View) -> bool); 9] = [
                ("Floor Plans", |v| matches!(v.kind, ViewKind::FloorPlan { .. })),
                ("Ceiling Plans", |v| matches!(v.kind, ViewKind::CeilingPlan { .. })),
                ("3D Views", |v| matches!(v.kind, ViewKind::ThreeD { .. })),
                ("Elevations (Building Elevation)", |v| matches!(v.kind, ViewKind::Elevation { .. })),
                ("Sections (Building Section)", |v| matches!(v.kind, ViewKind::Section { .. })),
                ("Drafting Views (Detail)", |v| matches!(v.kind, ViewKind::Drafting)),
                ("Area Plans", |v| matches!(v.kind, ViewKind::AreaPlan { .. })),
                ("Legends", |v| matches!(v.kind, ViewKind::Legend)),
                ("Schedules/Quantities (all)", |v| matches!(v.kind, ViewKind::Schedule(_))),
            ];
            for (title, pred) in groups {
                let mut views: Vec<&View> = p.views.iter().filter(|v| !v.is_template && pred(v) && matches(&f, &v.name)).collect();
                if views.is_empty() {
                    continue;
                }
                views.sort_by(|a, b| {
                    let ea = a.plan_level().map(|l| p.level_elevation(l)).unwrap_or(0.0);
                    let eb = b.plan_level().map(|l| p.level_elevation(l)).unwrap_or(0.0);
                    ea.total_cmp(&eb).then_with(|| a.name.cmp(&b.name))
                });
                tree_node(ui, title, title, None, title == "Floor Plans" || title == "3D Views" || title == "Elevations (Building Elevation)", open_default, |ui| {
                    for v in views {
                        view_row(app, ui, v);
                    }
                });
            }
        });
        let mut sheets: Vec<&View> = p.views.iter().filter(|v| matches!(v.kind, ViewKind::Sheet(_))).filter(|v| matches(&f, &v.name) || matches!(&v.kind, ViewKind::Sheet(s) if matches(&f, &s.number))).collect();
        sheets.sort_by_key(|v| match &v.kind {
            ViewKind::Sheet(s) => s.number.clone(),
            _ => String::new(),
        });
        let sheets_resp = tree_node(ui, "Sheets (all)", "Sheets (all)", Some(Icon::Sheet), true, open_default, |ui| {
            for s in sheets {
                view_row(app, ui, s);
                if let ViewKind::Sheet(sh) = &s.kind {
                    ui.indent(("sheet-vps", s.id), |ui| {
                        for vp in &sh.viewports {
                            if let Some(v) = p.view(vp.view) {
                                view_row(app, ui, v);
                            }
                        }
                    });
                }
            }
        });
        sheets_resp.context_menu(|ui| {
            if ui.button("New Sheet...").clicked() {
                app.dialogs.new_sheet = true;
                ui.close();
            }
        });
        // Families by category.
        tree_node(ui, "Families", "Families", Some(Icon::LoadFamily), false, open_default, |ui| {
            // System families first.
            let mut cats: Vec<Category> = p.types.iter().map(|t| t.category).collect();
            cats.extend(p.families.iter().map(|f| f.category));
            cats.sort();
            cats.dedup();
            for cat in cats {
                tree_node(ui, ("fam-cat", cat), cat.label(), None, false, open_default, |ui| {
                    // System types grouped by system family name.
                    let mut sys: Vec<&SystemType> = p.types.iter().filter(|t| t.category == cat && matches(&f, &t.name)).collect();
                    sys.sort_by(|a, b| a.family_name().cmp(b.family_name()).then(a.name.cmp(&b.name)));
                    let mut last = "";
                    for t in sys {
                        if t.family_name() != last {
                            last = t.family_name();
                            tree_text(ui, last);
                        }
                        type_row(app, ui, t.id, &t.name);
                    }
                    for fam in p.families.iter().filter(|fm| fm.category == cat) {
                        if !matches(&f, &fam.name) && !fam.types.iter().any(|t| matches(&f, &t.name)) {
                            continue;
                        }
                        let fid = fam.id;
                        let r = tree_node(ui, ("fam", fam.id), &fam.name, None, false, open_default, |ui| {
                            for t in &fam.types {
                                type_row(app, ui, t.id, &t.name);
                            }
                        });
                        r.context_menu(|ui| {
                            if ui.button("Edit...").clicked() {
                                crate::family_editor::open(app, fid);
                                ui.close();
                            }
                            if ui.button("Save...").clicked() {
                                save_family(app, fid);
                                ui.close();
                            }
                            if ui.button("Delete").clicked() {
                                app.run("Delete Family", |p| edit::delete_family(p, fid));
                                ui.close();
                            }
                            if ui.button("Select All Instances").clicked() {
                                let ids: Vec<Id> = app.doc.data.instances().filter(|(_, i)| i.family_id == fid).map(|(e, _)| e.id).collect();
                                app.select(ids);
                                ui.close();
                            }
                        });
                    }
                });
            }
        });
        if !p.group_types.is_empty() {
            tree_node(ui, "Groups", "Groups", Some(Icon::PlaceGroup), false, open_default, |ui| {
                tree_node(ui, "Groups-Model", "Model", None, true, false, |ui| {
                    for g in p.group_types.iter().filter(|g| matches(&f, &g.name)) {
                        let resp = row(ui, Icon::PlaceGroup, &g.name, false, false);
                        let gid = g.id;
                        if resp.double_clicked() {
                            app.opts.group_type = gid;
                            actions::exec(app, Cmd::PlaceGroup);
                        }
                        resp.context_menu(|ui| {
                            if ui.button("Place Instance").clicked() {
                                app.opts.group_type = gid;
                                actions::exec(app, Cmd::PlaceGroup);
                                ui.close();
                            }
                            if ui.button("Select All Instances").clicked() {
                                let ids: Vec<Id> = app.doc.data.elements.iter().filter(|e| matches!(&e.kind, ElementKind::GroupInstance(gi) if gi.type_id == gid)).map(|e| e.id).collect();
                                app.select(ids);
                                ui.close();
                            }
                        });
                    }
                });
            });
        }
        let cads: Vec<(Id, String)> = p.elements.iter().filter_map(|e| match &e.kind {
            ElementKind::Cad(c) => Some((e.id, c.name.clone())),
            _ => None,
        }).collect();
        if !cads.is_empty() {
            tree_node(ui, "CAD Links", "CAD Links", Some(Icon::LinkCad), false, false, |ui| {
                for (id, name) in cads {
                    if row(ui, Icon::LinkCad, &name, app.selection.contains(&id), false).clicked() {
                        app.select(vec![id]);
                    }
                }
            });
        }
    });
}

fn type_row(app: &mut App, ui: &mut egui::Ui, type_id: Id, name: &str) {
    let resp = row(ui, Icon::TypeProperties, name, false, false);
    if resp.double_clicked() {
        app.dialogs.type_props = Some(type_id);
    }
    resp.context_menu(|ui| {
        if ui.button("Type Properties...").clicked() {
            app.dialogs.type_props = Some(type_id);
            ui.close();
        }
        if ui.button("Duplicate...").clicked() {
            let name = format!("{name} 2");
            let is_sys = app.doc.data.sys_type(type_id).is_some();
            app.run("Duplicate Type", |p| if is_sys { edit::duplicate_system_type(p, type_id, &name) } else { edit::duplicate_family_type(p, type_id, &name) });
            ui.close();
        }
        if ui.button("Rename...").clicked() {
            app.dialogs.rename_type = Some((type_id, name.to_string()));
            ui.close();
        }
        if ui.button("Delete").clicked() {
            app.run("Delete Type", |p| edit::delete_type(p, type_id));
            ui.close();
        }
        if ui.button("Select All Instances").clicked() {
            let ids: Vec<Id> = app.doc.data.elements.iter().filter(|e| app.doc.data.type_of(e) == Some(type_id)).map(|e| e.id).collect();
            app.select(ids);
            ui.close();
        }
        if ui.button("Create Instance").clicked() {
            set_tool_type(app, type_id);
            ui.close();
        }
    });
}

/// Starts placing an element of `type_id`.
pub fn set_tool_type(app: &mut App, type_id: Id) {
    let p = &app.doc.data;
    if let Some(t) = p.sys_type(type_id) {
        let cmd = match t.category {
            Category::Walls => {
                app.opts.wall_type = type_id;
                Cmd::Wall
            }
            Category::Floors => {
                app.opts.floor_type = type_id;
                Cmd::Floor
            }
            Category::Roofs => {
                app.opts.roof_type = type_id;
                Cmd::RoofFootprint
            }
            Category::Ceilings => {
                app.opts.ceiling_type = type_id;
                Cmd::Ceiling
            }
            Category::Stairs => {
                app.opts.stair_type = type_id;
                Cmd::Stair
            }
            Category::Railings => {
                app.opts.railing_type = type_id;
                Cmd::Railing
            }
            Category::StructuralFoundations => {
                app.opts.foundation_type = type_id;
                Cmd::WallFoundation
            }
            _ => return,
        };
        actions::exec(app, cmd);
        return;
    }
    if let Some((f, _)) = p.family_type(type_id) {
        let cmd = match f.category {
            Category::Doors => {
                app.opts.door_type = type_id;
                Cmd::Door
            }
            Category::Windows => {
                app.opts.window_type = type_id;
                Cmd::Window
            }
            Category::Columns => {
                app.opts.column_type = type_id;
                Cmd::Column
            }
            Category::StructuralColumns => {
                app.opts.struct_column_type = type_id;
                Cmd::StructColumn
            }
            Category::StructuralFraming => {
                app.opts.beam_type = type_id;
                Cmd::Beam
            }
            Category::StructuralFoundations => {
                app.opts.footing_type = type_id;
                Cmd::IsolatedFoundation
            }
            _ => {
                app.opts.component_type = type_id;
                Cmd::Component
            }
        };
        actions::exec(app, cmd);
    }
}

pub fn save_family(app: &mut App, fid: Id) {
    let Some(fam) = app.doc.data.family(fid).cloned() else { return };
    let Some(mut path) = crate::files::FileDialog::new().add_filter("RevitCraft Family", &[rc_core::io::FAMILY_EXTENSION]).set_file_name(format!("{}.rcfa", fam.name)).save_file() else { return };
    if path.extension().is_none() {
        path.set_extension(rc_core::io::FAMILY_EXTENSION);
    }
    match rc_core::io::save_family(&app.doc.data, &fam, &path) {
        Ok(()) => app.info(format!("Saved family {}", path.display())),
        Err(e) => app.error(e),
    }
}

/// The Project Browser of an open family: its views (double-click opens one), its loaded
/// families and groups.
fn family_browser(app: &mut App, ui: &mut egui::Ui) {
    use crate::family_editor::FeView;
    let Some(fe) = app.family_editor.as_mut() else { return };
    if style::palette_title(ui, &format!("Project Browser - {}", fe.family.name)) {
        app.settings.show_browser = false;
        return;
    }
    egui::ScrollArea::vertical().auto_shrink([false, false]).id_salt("fe-browser-scroll").show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        ui.spacing_mut().indent = INDENT;
        let selected_id = egui::Id::new("fe-browser-sel");
        let mut selected: Option<FeView> = ui.memory(|m| m.data.get_temp(selected_id));
        let mut open: Option<FeView> = None;
        let active = fe.view;
        tree_node(ui, "fe-views", "Views (all)", Some(Icon::FloorPlan), true, false, |ui| {
            for (title, icon, views) in [
                ("Floor Plans", Icon::FloorPlan, vec![FeView::Plan]),
                ("Ceiling Plans", Icon::CeilingPlan, vec![FeView::Ceiling]),
                ("3D Views", Icon::View3D, vec![FeView::ThreeD]),
                ("Elevations (Elevation 1)", Icon::Elevation, vec![FeView::Back, FeView::Front, FeView::Left, FeView::Right]),
            ] {
                tree_node(ui, ("fe-group", title), title, None, true, false, |ui| {
                    for v in views {
                        let resp = row(ui, icon, v.label(), selected == Some(v), v == active);
                        if resp.double_clicked() {
                            open = Some(v);
                        } else if resp.clicked() {
                            selected = Some(v);
                        }
                    }
                });
            }
        });
        tree_node(ui, "fe-legends", "Legends", Some(Icon::Legend), false, false, |_| {});
        tree_node(ui, "fe-schedules", "Schedules/Quantities (all)", Some(Icon::Schedule), false, false, |_| {});
        tree_node(ui, "fe-sheets", "Sheets (all)", Some(Icon::Sheet), false, false, |_| {});
        tree_node(ui, "fe-families", "Families", Some(Icon::LoadFamily), false, false, |ui| {
            for cat in ["Annotation Symbols"] {
                tree_node(ui, ("fe-fam-cat", cat), cat, None, false, false, |_| {});
            }
        });
        tree_node(ui, "fe-groups", "Groups", Some(Icon::PlaceGroup), false, false, |_| {});
        tree_node(ui, "fe-links", "Revit Links", Some(Icon::LinkCad), false, false, |_| {});
        ui.memory_mut(|m| match selected {
            Some(v) => {
                m.data.insert_temp(selected_id, v);
            }
            None => m.data.remove::<FeView>(selected_id),
        });
        if let Some(v) = open {
            fe.view = v;
            fe.pts.clear();
            fe.closed = false;
            if !fe.open_views.contains(&v) {
                fe.open_views.push(v);
            }
        }
    });
}
