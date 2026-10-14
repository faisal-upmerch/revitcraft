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
    let h = 20.0;
    let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), h), Sense::click_and_drag());
    if selected {
        ui.painter().rect_filled(r, 0.0, style::accent_light());
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 0.0, style::hover());
    }
    icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(2.0, 2.0), vec2(16.0, 16.0)), icon, true);
    let rt = egui::RichText::new(text).size(12.0);
    let rt = if bold { rt.strong() } else { rt };
    let galley = egui::WidgetText::from(rt).into_galley(ui, Some(egui::TextWrapMode::Truncate), r.width() - 24.0, egui::TextStyle::Body);
    ui.painter().galley(r.min + vec2(22.0, (h - galley.size().y) / 2.0), galley, style::text());
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
    let name = app.doc.path.as_ref().and_then(|p| p.file_stem()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Project1".into());
    style::palette_title(ui, &format!("Project Browser - {name}"));
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
        ui.spacing_mut().indent = 14.0;
        let p = app.snapshot();
        let open_default = !f.is_empty();
        egui::CollapsingHeader::new(egui::RichText::new("Views (all)").strong()).default_open(true).open(open_default.then_some(true)).show(ui, |ui| {
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
                egui::CollapsingHeader::new(title).id_salt(title).default_open(title == "Floor Plans" || title == "3D Views" || title == "Elevations (Building Elevation)").open(open_default.then_some(true)).show(ui, |ui| {
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
        let sheets_resp = egui::CollapsingHeader::new(egui::RichText::new("Sheets (all)").strong()).default_open(true).open(open_default.then_some(true)).show(ui, |ui| {
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
        sheets_resp.header_response.context_menu(|ui| {
            if ui.button("New Sheet...").clicked() {
                app.dialogs.new_sheet = true;
                ui.close();
            }
        });
        // Families by category.
        egui::CollapsingHeader::new(egui::RichText::new("Families").strong()).default_open(false).open(open_default.then_some(true)).show(ui, |ui| {
            // System families first.
            let mut cats: Vec<Category> = p.types.iter().map(|t| t.category).collect();
            cats.extend(p.families.iter().map(|f| f.category));
            cats.sort();
            cats.dedup();
            for cat in cats {
                egui::CollapsingHeader::new(cat.label()).id_salt(("fam-cat", cat)).default_open(false).open(open_default.then_some(true)).show(ui, |ui| {
                    // System types grouped by system family name.
                    let mut sys: Vec<&SystemType> = p.types.iter().filter(|t| t.category == cat && matches(&f, &t.name)).collect();
                    sys.sort_by(|a, b| a.family_name().cmp(b.family_name()).then(a.name.cmp(&b.name)));
                    let mut last = "";
                    for t in sys {
                        if t.family_name() != last {
                            last = t.family_name();
                            ui.label(egui::RichText::new(last).color(style::text_dim()).size(11.5));
                        }
                        type_row(app, ui, t.id, &t.name);
                    }
                    for fam in p.families.iter().filter(|fm| fm.category == cat) {
                        if !matches(&f, &fam.name) && !fam.types.iter().any(|t| matches(&f, &t.name)) {
                            continue;
                        }
                        let fid = fam.id;
                        let r = egui::CollapsingHeader::new(&fam.name).id_salt(("fam", fam.id)).default_open(false).open(open_default.then_some(true)).show(ui, |ui| {
                            for t in &fam.types {
                                type_row(app, ui, t.id, &t.name);
                            }
                        });
                        r.header_response.context_menu(|ui| {
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
            egui::CollapsingHeader::new(egui::RichText::new("Groups").strong()).default_open(false).open(open_default.then_some(true)).show(ui, |ui| {
                egui::CollapsingHeader::new("Model").default_open(true).show(ui, |ui| {
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
            egui::CollapsingHeader::new(egui::RichText::new("CAD Links").strong()).default_open(false).show(ui, |ui| {
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
    let Some(mut path) = rfd::FileDialog::new().add_filter("RevitCraft Family", &[rc_core::io::FAMILY_EXTENSION]).set_file_name(format!("{}.rcfa", fam.name)).save_file() else { return };
    if path.extension().is_none() {
        path.set_extension(rc_core::io::FAMILY_EXTENSION);
    }
    match rc_core::io::save_family(&app.doc.data, &fam, &path) {
        Ok(()) => app.info(format!("Saved family {}", path.display())),
        Err(e) => app.error(e),
    }
}
