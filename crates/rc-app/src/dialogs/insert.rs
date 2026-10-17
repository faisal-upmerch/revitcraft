//! Insert tab dialogs (Link/Import PDF, DWF Markup, Insert 2D Elements, Load Autodesk Family),
//! Manage > Structural Settings, and View > Cloud Rendering, Render Gallery and Twinmotion.

use super::{dlg_button, manage, window};
use crate::app::App;
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::geom::DVec2;
use rc_core::model::*;

pub fn show(app: &mut App, ctx: &egui::Context) {
    pdf_dialog(app, ctx);
    markup_dialog(app, ctx);
    insert_2d_dialog(app, ctx);
    autodesk_family_dialog(app, ctx);
    structural_dialog(app, ctx);
    cloud_render_dialog(app, ctx);
    gallery_dialog(app, ctx);
}

fn ok_cancel(ui: &mut egui::Ui, ok_label: &str, ok_enabled: bool) -> (bool, bool) {
    let (mut ok, mut cancel) = (false, false);
    ui.add_space(8.0);
    ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
        ui.spacing_mut().item_spacing.x = 8.0;
        if dlg_button(ui, "Cancel", false, true) {
            cancel = true;
        }
        if dlg_button(ui, ok_label, true, ok_enabled) {
            ok = true;
        }
    });
    (ok, cancel)
}

/// Today's date as the reference app writes it (MM/DD/YYYY).
pub fn today() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) as i64;
    let z = secs / 86_400 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{m:02}/{d:02}/{y}")
}

// ---------------------------------------------------------------- PDF

pub struct PdfState {
    pub path: std::path::PathBuf,
    pub pages: u32,
    pub page: u32,
    pub dpi: u32,
    pub link: bool,
}

/// Link PDF / Import PDF: the page and resolution, then the page is placed like an image.
fn pdf_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.pdf.take() else {
        return;
    };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    let title = if st.link { "Link PDF" } else { "Import PDF" };
    window(title).open(&mut open).resizable(false).default_width(340.0).show(ctx, |ui| {
        ui.label(st.path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default());
        ui.add_space(4.0);
        manage::group(ui, "Page", |ui| {
            ui.horizontal(|ui| {
                ui.label("Page:");
                let mut n = st.page + 1;
                ui.add(egui::DragValue::new(&mut n).range(1..=st.pages.max(1)));
                st.page = n.saturating_sub(1);
                ui.label(format!("of {}", st.pages));
            });
        });
        manage::group(ui, "Resolution", |ui| {
            ui.horizontal(|ui| {
                ui.label("Resolution:");
                egui::ComboBox::from_id_salt("pdf-dpi").selected_text(format!("{} DPI", st.dpi)).width(100.0).show_ui(ui, |ui| {
                    for d in [72u32, 150, 300, 600] {
                        ui.selectable_value(&mut st.dpi, d, format!("{d} DPI"));
                    }
                });
            });
        });
        (ok, cancel) = ok_cancel(ui, "OK", true);
    });
    if ok {
        let id = app.doc.data.next_id;
        match crate::pdf_import::render_page(&st.path, st.page, st.dpi as f64, id) {
            Ok(asset) => {
                let px = st.dpi as f64 / 25.4;
                let made = app.run(title, |p| {
                    let id = p.new_id();
                    p.images.push(ImageAsset { id, ..asset });
                    Ok(id)
                });
                if let Some(id) = made {
                    app.opts.image_asset = id;
                    // The page keeps its printed size.
                    app.opts.image_width = app.doc.data.images.iter().find(|a| a.id == id).map(|a| a.width as f64 / px);
                    app.set_tool(crate::tools::ToolKind::PlaceImage);
                }
            }
            Err(e) => app.error(e),
        }
    }
    if open && !ok && !cancel {
        app.dialogs.pdf = Some(st);
    }
}

// ---------------------------------------------------------------- DWF markup

pub struct MarkupState {
    pub file: String,
    pub pages: Vec<rc_core::markup::MarkupPage>,
    /// The sheet each page is placed on (None: not linked).
    pub sheets: Vec<Option<Id>>,
}

impl MarkupState {
    pub fn new(app: &App, file: String, pages: Vec<rc_core::markup::MarkupPage>) -> Self {
        let sheets: Vec<(Id, String)> = sheet_list(app);
        let active = app.active.filter(|v| sheets.iter().any(|(id, _)| id == v));
        let pick = |pg: &rc_core::markup::MarkupPage| {
            let n = pg.name.to_lowercase();
            sheets.iter().find(|(_, name)| n.contains(&name.to_lowercase()) || name.to_lowercase().contains(&n)).map(|(id, _)| *id).or(active)
        };
        let sheets = pages.iter().map(pick).collect();
        MarkupState { file, pages, sheets }
    }
}

fn sheet_list(app: &App) -> Vec<(Id, String)> {
    app.doc
        .data
        .views
        .iter()
        .filter_map(|v| match &v.kind {
            ViewKind::Sheet(sh) => Some((v.id, format!("{} - {}", sh.number, v.name))),
            _ => None,
        })
        .collect()
}

/// DWF Markup: each marked-up page goes onto a sheet.
fn markup_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.markup.take() else {
        return;
    };
    let sheets = sheet_list(app);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Link Markups").open(&mut open).resizable(false).default_width(460.0).show(ctx, |ui| {
        ui.label(format!("DWF file: {}", st.file));
        ui.add_space(4.0);
        egui::Grid::new("markup-grid").num_columns(2).striped(true).spacing(vec2(16.0, 6.0)).show(ui, |ui| {
            ui.label(egui::RichText::new("DWF Sheet").strong());
            ui.label(egui::RichText::new("Revit Sheet").strong());
            ui.end_row();
            for (k, pg) in st.pages.iter().enumerate() {
                ui.label(&pg.name);
                let text = st.sheets[k].and_then(|s| sheets.iter().find(|(id, _)| *id == s)).map(|(_, n)| n.clone()).unwrap_or_else(|| "(None)".into());
                egui::ComboBox::from_id_salt(("markup-sheet", k)).selected_text(text).width(240.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut st.sheets[k], None, "(None)");
                    for (id, n) in &sheets {
                        ui.selectable_value(&mut st.sheets[k], Some(*id), n);
                    }
                });
                ui.end_row();
            }
        });
        (ok, cancel) = ok_cancel(ui, "OK", st.sheets.iter().any(|s| s.is_some()));
    });
    if ok {
        let file = st.file.clone();
        let jobs: Vec<(Id, rc_core::markup::MarkupPage)> = st.pages.iter().zip(&st.sheets).filter_map(|(pg, s)| s.map(|s| (s, pg.clone()))).collect();
        let n = jobs.len();
        if app
            .run("DWF Markup", |p| {
                for (sheet, pg) in &jobs {
                    rc_core::edit::add_markup(p, *sheet, pg, &file)?;
                }
                Ok(())
            })
            .is_some()
        {
            app.info(format!("Linked {n} marked-up sheet(s)."));
        }
    }
    if open && !ok && !cancel {
        app.dialogs.markup = Some(st);
    }
}

// ---------------------------------------------------------------- Insert 2D Elements

pub struct Insert2DState {
    pub src: Project,
    pub views: Vec<(Id, String)>,
    pub pick: usize,
}

/// Insert 2D Elements: a drafting view or legend of another project, copied into the
/// current view.
fn insert_2d_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.insert_2d.take() else {
        return;
    };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Insert 2D Elements").open(&mut open).resizable(false).default_width(360.0).show(ctx, |ui| {
        ui.label("Select a view to insert its 2D elements from:");
        ui.add_space(4.0);
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
                for (k, (_, name)) in st.views.iter().enumerate() {
                    if ui.selectable_label(st.pick == k, name).clicked() {
                        st.pick = k;
                    }
                }
            });
        });
        (ok, cancel) = ok_cancel(ui, "OK", !st.views.is_empty());
    });
    if ok {
        let (Some(dst), Some((src_view, _))) = (app.active, st.views.get(st.pick).cloned()) else {
            return;
        };
        let src = &st.src;
        if let Some(ids) = app.run("Insert 2D Elements", |p| rc_core::edit::insert_2d_elements(p, src, src_view, dst)) {
            app.select(ids);
        }
    }
    if open && !ok && !cancel {
        app.dialogs.insert_2d = Some(st);
    }
}

// ---------------------------------------------------------------- Load Autodesk Family

#[derive(Default)]
pub struct AdskState {
    pub search: String,
    pub sel: Option<usize>,
}

/// Load Autodesk Family: the bundled family library by category, loaded on demand.
fn autodesk_family_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.autodesk_family.take() else {
        return;
    };
    let units = app.doc.data.units.system;
    let mut cat = rc_core::library::catalog(units);
    cat.extend(rc_core::library::library_catalog(units));
    cat.sort_by_key(|(_, t, _)| t.category().label());
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Load Autodesk Family").open(&mut open).resizable(false).default_width(560.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Search:");
            ui.add(egui::TextEdit::singleline(&mut st.search).desired_width(260.0).hint_text("Search families"));
        });
        ui.add_space(4.0);
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::vertical().max_height(340.0).show(ui, |ui| {
                let mut last: Option<Category> = None;
                let q = st.search.to_lowercase();
                for (k, (name, template, types)) in cat.iter().enumerate() {
                    if !q.is_empty() && !name.to_lowercase().contains(&q) && !template.category().label().to_lowercase().contains(&q) {
                        continue;
                    }
                    if last != Some(template.category()) {
                        last = Some(template.category());
                        ui.add_space(2.0);
                        ui.label(egui::RichText::new(template.category().label()).strong());
                    }
                    // In the family editor: loaded into the family being edited.
                    let loaded = match app.family_editor.as_ref() {
                        Some(fe) => fe.def().is_some_and(|d| d.loaded.iter().any(|f| f.name == *name)),
                        None => app.doc.data.families.iter().any(|f| f.name == *name),
                    };
                    let text = format!("    {name}  ({} type{}){}", types.len(), if types.len() == 1 { "" } else { "s" }, if loaded { "  - loaded" } else { "" });
                    if ui.selectable_label(st.sel == Some(k), text).clicked() {
                        st.sel = Some(k);
                    }
                }
            });
        });
        (ok, cancel) = ok_cancel(ui, "Load", st.sel.is_some());
    });
    if ok {
        if let Some((name, template, types)) = st.sel.and_then(|k| cat.into_iter().nth(k)) {
            if app.family_editor.is_some() {
                // In the family editor the family is loaded into the family being edited.
                let mut tmp = rc_core::model::Project::empty();
                rc_core::defaults::add_catalog_family(&mut tmp, name, template, types);
                if let Some(f) = tmp.families.pop() {
                    if let Some(n) = app.family_editor.as_mut().and_then(|fe| fe.load_nested(f)) {
                        app.info(format!("Loaded family '{n}'. Place it with Create > Component."));
                    }
                }
            } else if app.doc.data.families.iter().any(|f| f.name == name) {
                app.info(format!("The family '{name}' is already in the project."));
            } else if app
                .run("Load Autodesk Family", |p| {
                    rc_core::defaults::add_catalog_family(p, name, template, types);
                    Ok(())
                })
                .is_some()
            {
                app.info(format!("Loaded family '{name}'."));
                if let Some(t) = app.doc.data.families.iter().find(|f| f.name == name).and_then(|f| f.types.first()).map(|t| t.id) {
                    app.opts.component_type = t;
                }
            }
        }
    }
    if open && !ok && !cancel {
        app.dialogs.autodesk_family = Some(st);
    }
}

// ---------------------------------------------------------------- Structural Settings

pub struct StructuralState {
    pub s: StructuralSettings,
    pub tab: u8,
    pub texts: [String; 4],
}

impl StructuralState {
    pub fn new(app: &App) -> Self {
        let s = app.doc.data.structural.clone();
        let f = |v: f64| format!("{v:.2} mm");
        StructuralState { texts: [f(s.brace_cutback), f(s.beam_cutback), f(s.column_cutback), f(s.brace_offset)], s, tab: 0 }
    }
}

const STRUCT_TABS: [&str; 3] = ["Symbolic Representation Settings", "Load Cases", "Load Combinations"];
const LOAD_NATURES: [&str; 8] = ["Dead", "Live", "Wind", "Snow", "Roof Live", "Accidental", "Temperature", "Seismic"];

/// Manage > Structural Settings.
fn structural_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.structural.take() else {
        return;
    };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Structural Settings").open(&mut open).resizable(false).default_width(560.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            for (k, t) in STRUCT_TABS.iter().enumerate() {
                if ui.selectable_label(st.tab == k as u8, *t).clicked() {
                    st.tab = k as u8;
                }
            }
        });
        ui.separator();
        match st.tab {
            0 => {
                manage::group(ui, "Symbolic Cutback Distance", |ui| {
                    egui::Grid::new("cutbacks").num_columns(2).spacing(vec2(16.0, 6.0)).show(ui, |ui| {
                        for (k, l) in ["Brace:", "Beam/Truss:", "Column:"].iter().enumerate() {
                            ui.label(*l);
                            ui.add(egui::TextEdit::singleline(&mut st.texts[k]).desired_width(100.0));
                            ui.end_row();
                        }
                    });
                });
                manage::group(ui, "Brace Symbols", |ui| {
                    ui.horizontal(|ui| {
                        ui.label("Plan representation:");
                        egui::ComboBox::from_id_salt("brace-rep").selected_text(if st.s.brace_parallel { "Parallel Line" } else { "Line w/Angle" }).width(140.0).show_ui(ui, |ui| {
                            ui.selectable_value(&mut st.s.brace_parallel, true, "Parallel Line");
                            ui.selectable_value(&mut st.s.brace_parallel, false, "Line w/Angle");
                        });
                    });
                    ui.horizontal(|ui| {
                        ui.label("Parallel line offset:");
                        ui.add(egui::TextEdit::singleline(&mut st.texts[3]).desired_width(100.0));
                    });
                    style::check(ui, &mut st.s.kicker_symbol, "Show brace above");
                });
            }
            1 => {
                egui::Grid::new("load-cases").num_columns(3).striped(true).spacing(vec2(16.0, 4.0)).show(ui, |ui| {
                    ui.label(egui::RichText::new("").strong());
                    ui.label(egui::RichText::new("Name").strong());
                    ui.label(egui::RichText::new("Nature").strong());
                    ui.end_row();
                    let mut remove = None;
                    for (k, (name, nature)) in st.s.load_cases.iter_mut().enumerate() {
                        if ui.small_button("✕").clicked() {
                            remove = Some(k);
                        }
                        ui.add(egui::TextEdit::singleline(name).desired_width(160.0));
                        egui::ComboBox::from_id_salt(("lc-nature", k)).selected_text(nature.clone()).width(130.0).show_ui(ui, |ui| {
                            for n in LOAD_NATURES {
                                ui.selectable_value(nature, n.to_string(), n);
                            }
                        });
                        ui.end_row();
                    }
                    if let Some(k) = remove {
                        st.s.load_cases.remove(k);
                    }
                });
                if ui.button("Add").clicked() {
                    let n = st.s.load_cases.len() + 1;
                    st.s.load_cases.push((format!("LC{n}"), "Dead".into()));
                }
            }
            _ => {
                egui::Grid::new("load-combos").num_columns(3).striped(true).spacing(vec2(16.0, 4.0)).show(ui, |ui| {
                    ui.label("");
                    ui.label(egui::RichText::new("Name").strong());
                    ui.label(egui::RichText::new("Formula").strong());
                    ui.end_row();
                    let mut remove = None;
                    for (k, (name, formula)) in st.s.load_combinations.iter_mut().enumerate() {
                        if ui.small_button("✕").clicked() {
                            remove = Some(k);
                        }
                        ui.add(egui::TextEdit::singleline(name).desired_width(140.0));
                        ui.add(egui::TextEdit::singleline(formula).desired_width(220.0));
                        ui.end_row();
                    }
                    if let Some(k) = remove {
                        st.s.load_combinations.remove(k);
                    }
                });
                if ui.button("Add").clicked() {
                    let n = st.s.load_combinations.len() + 1;
                    let f = st.s.load_cases.iter().map(|(n, _)| format!("1.0*{n}")).take(2).collect::<Vec<_>>().join(" + ");
                    st.s.load_combinations.push((format!("Combination {n}"), f));
                }
            }
        }
        (ok, cancel) = ok_cancel(ui, "OK", true);
    });
    if ok {
        let parse = |t: &str| t.trim().trim_end_matches("mm").trim().parse::<f64>().ok().filter(|v| *v >= 0.0);
        match (parse(&st.texts[0]), parse(&st.texts[1]), parse(&st.texts[2]), parse(&st.texts[3])) {
            (Some(a), Some(b), Some(c), Some(o)) => {
                let mut s = st.s.clone();
                (s.brace_cutback, s.beam_cutback, s.column_cutback, s.brace_offset) = (a, b, c, o);
                app.run("Structural Settings", |p| {
                    p.structural = s;
                    Ok(())
                });
            }
            _ => {
                app.error("Enter the cutback distances as lengths on paper, such as 2.38 mm.");
                ok = false;
            }
        }
    }
    if open && !ok && !cancel {
        app.dialogs.structural = Some(st);
    }
}

// ---------------------------------------------------------------- Cloud Rendering

pub struct CloudState {
    pub views: Vec<(Id, String, bool)>,
    /// Standard or Final.
    pub final_quality: bool,
    /// Image size: 0 small (1 MP), 1 medium (4 MP), 2 large (8 MP).
    pub size: u8,
}

impl CloudState {
    pub fn new(app: &App) -> Self {
        let views = app.doc.data.views.iter().filter(|v| matches!(v.kind, ViewKind::ThreeD { .. }) && !v.is_template).map(|v| (v.id, v.name.clone(), Some(v.id) == app.active)).collect();
        CloudState { views, final_quality: false, size: 1 }
    }
}

const CLOUD_SIZES: [(&str, u32, u32); 3] = [("Small (1 MP)", 1200, 900), ("Medium (4 MP)", 2400, 1600), ("Large (8 MP)", 3456, 2304)];

/// Render in Cloud: the chosen 3D views are rendered (here, on this machine) and kept in the
/// Render Gallery.
fn cloud_render_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.cloud_render.take() else {
        return;
    };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Render in Cloud").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
        ui.label("3D View:");
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::vertical().max_height(180.0).show(ui, |ui| {
                for (_, name, on) in st.views.iter_mut() {
                    style::check(ui, on, name.as_str());
                }
            });
        });
        ui.add_space(6.0);
        egui::Grid::new("cloud-grid").num_columns(2).spacing(vec2(16.0, 6.0)).show(ui, |ui| {
            ui.label("Output Type:");
            ui.label("Still Image");
            ui.end_row();
            ui.label("Render Quality:");
            egui::ComboBox::from_id_salt("cloud-q").selected_text(if st.final_quality { "Final" } else { "Standard" }).width(160.0).show_ui(ui, |ui| {
                ui.selectable_value(&mut st.final_quality, false, "Standard");
                ui.selectable_value(&mut st.final_quality, true, "Final");
            });
            ui.end_row();
            ui.label("Image Size:");
            egui::ComboBox::from_id_salt("cloud-size").selected_text(CLOUD_SIZES[st.size.min(2) as usize].0).width(160.0).show_ui(ui, |ui| {
                for (k, (l, ..)) in CLOUD_SIZES.iter().enumerate() {
                    ui.selectable_value(&mut st.size, k as u8, *l);
                }
            });
            ui.end_row();
            ui.label("Exposure:");
            ui.label("Advanced");
            ui.end_row();
            ui.label("File Format:");
            ui.label("PNG (lossless)");
            ui.end_row();
        });
        (ok, cancel) = ok_cancel(ui, "Start Rendering", st.views.iter().any(|v| v.2));
    });
    if ok {
        let (_, w, h) = CLOUD_SIZES[st.size.min(2) as usize];
        let (w, h) = if st.final_quality { (w, h) } else { (w * 3 / 4, h * 3 / 4) };
        let date = today();
        let mut done = 0;
        for (view, name, _) in st.views.iter().filter(|v| v.2) {
            let Some(img) = crate::view3d::render_realistic(app, *view, w, h) else {
                continue;
            };
            let (iw, ih, rgb) = (img.width, img.height, img.rgb);
            let (name, date, view) = (name.clone(), date.clone(), *view);
            if app
                .run("Render in Cloud", move |p| {
                    let asset = p.new_id();
                    p.images.push(ImageAsset::from_rgb(asset, &format!("{name} (rendering)"), iw, ih, &rgb));
                    p.renders.push(RenderRecord { image: asset, view, name, date });
                    Ok(())
                })
                .is_some()
            {
                done += 1;
            }
        }
        if done > 0 {
            app.info(format!("{done} rendering(s) finished. Open them from View > Render Gallery."));
            app.dialogs.gallery = true;
        } else {
            app.error("The views could not be rendered.");
        }
    }
    if open && !ok && !cancel {
        app.dialogs.cloud_render = Some(st);
    }
}

// ---------------------------------------------------------------- Render Gallery

/// Render Gallery: the finished renderings, to view, export, place in the project or delete.
fn gallery_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.gallery {
        return;
    }
    let mut open = true;
    let renders = app.doc.data.renders.clone();
    let (mut export, mut place, mut delete) = (None, None, None);
    window("Render Gallery").open(&mut open).default_size(vec2(620.0, 460.0)).show(ctx, |ui| {
        if renders.is_empty() {
            ui.label("No renderings yet. Use View > Cloud Rendering to render 3D views.");
            return;
        }
        egui::ScrollArea::vertical().max_height(420.0).show(ui, |ui| {
            for r in &renders {
                ui.horizontal(|ui| {
                    if let Some(tex) = thumbnail(app, ctx, r.image) {
                        let s = tex.size_vec2();
                        let w = 180.0;
                        ui.add(egui::Image::new((tex.id(), vec2(w, w * s.y / s.x.max(1.0)))));
                    }
                    ui.vertical(|ui| {
                        ui.label(egui::RichText::new(&r.name).strong());
                        ui.label(format!("Still Image  ·  {}", r.date));
                        if let Some(a) = app.doc.data.images.iter().find(|a| a.id == r.image) {
                            ui.label(format!("{} x {} pixels", a.width, a.height));
                        }
                        ui.horizontal(|ui| {
                            if ui.button("Download as PNG...").clicked() {
                                export = Some(r.image);
                            }
                            if ui.button("Save to Project").clicked() {
                                place = Some(r.image);
                            }
                            if ui.button("Delete").clicked() {
                                delete = Some(r.image);
                            }
                        });
                    });
                });
                ui.separator();
            }
        });
    });
    if let Some(id) = export {
        if let Some(a) = app.doc.data.images.iter().find(|a| a.id == id).cloned() {
            if let Some(mut path) = crate::files::FileDialog::new().add_filter("PNG image", &["png"]).set_file_name(&format!("{}.png", a.name)).save_file() {
                if path.extension().is_none() {
                    path.set_extension("png");
                }
                let rgb = a.rgb().unwrap_or_default();
                match std::fs::write(&path, rc_core::png::encode(a.width, a.height, 3, &rgb)) {
                    Ok(()) => app.info(format!("Exported {}", path.display())),
                    Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
                }
            }
        }
    }
    if let Some(id) = place {
        let made = app.run("Save Rendering to Project", |p| {
            let a = p.images.iter().find(|a| a.id == id).cloned().ok_or("The rendering is missing.")?;
            let name = rc_core::edit::unique_name(p.views.iter().map(|v| v.name.clone()), &a.name);
            let vid = p.new_id();
            p.views.push(View::new(vid, name, 1.0, ViewKind::Drafting));
            rc_core::edit::add_image(p, vid, id, DVec2::ZERO, a.width as f64 * 0.25)?;
            Ok(vid)
        });
        if made.is_some() {
            app.info("The rendering was saved to the project as a drafting view.");
        }
    }
    if let Some(id) = delete {
        app.run("Delete Rendering", |p| {
            p.renders.retain(|r| r.image != id);
            // The image stays while a view still shows it.
            if !p.elements.iter().any(|e| matches!(&e.kind, ElementKind::RasterImage(im) if im.asset == id)) {
                p.images.retain(|a| a.id != id);
            }
            Ok(())
        });
    }
    if !open {
        app.dialogs.gallery = false;
    }
}

fn thumbnail(app: &App, ctx: &egui::Context, image: Id) -> Option<egui::TextureHandle> {
    let key = egui::Id::new(("render-thumb", image));
    if let Some(t) = ctx.data(|m| m.get_temp::<egui::TextureHandle>(key)) {
        return Some(t);
    }
    let a = app.doc.data.images.iter().find(|a| a.id == image)?;
    let rgb = a.rgb()?;
    let ci = egui::ColorImage::from_rgb([a.width as usize, a.height as usize], &rgb);
    let t = ctx.load_texture(format!("render-{image}"), ci, egui::TextureOptions::LINEAR);
    ctx.data_mut(|m| m.insert_temp(key, t.clone()));
    Some(t)
}

// ---------------------------------------------------------------- Twinmotion / OBJ

/// The model elements shown in 3D as an OBJ file and its material library.
pub fn model_obj(app: &App, mtl_name: &str) -> (String, String) {
    let p = &app.doc.data;
    let fp = rc_core::analysis::wall_footprints(p);
    let meshes: Vec<(Id, rc_core::mesh::MeshSet)> = p
        .elements
        .iter()
        .filter(|e| e.view.is_none() && !matches!(e.kind, ElementKind::Level(_) | ElementKind::Grid(_) | ElementKind::RefPlane(_) | ElementKind::Room(_) | ElementKind::Area(_)))
        .map(|e| (e.id, rc_core::build3d::element_mesh(p, e, &fp)))
        .filter(|(_, m)| m.by_material.values().any(|m| m.triangle_count() > 0))
        .collect();
    rc_core::imports::write_obj(p, &meshes, mtl_name)
}

/// Writes the model as `path` (.obj) with its .mtl beside it.
pub fn write_obj_files(app: &App, path: &std::path::Path) -> Result<(), String> {
    let mtl_path = path.with_extension("mtl");
    let mtl_name = mtl_path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| "model.mtl".into());
    let (obj, mtl) = model_obj(app, &mtl_name);
    std::fs::write(path, obj).map_err(|e| format!("Could not write {}: {e}", path.display()))?;
    std::fs::write(&mtl_path, mtl).map_err(|e| format!("Could not write {}: {e}", mtl_path.display()))?;
    Ok(())
}

/// Twinmotion's executable, when it is installed.
pub fn twinmotion_exe() -> Option<std::path::PathBuf> {
    let roots = [std::env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".into())];
    for root in roots {
        let base = std::path::Path::new(&root).join("Epic Games");
        let Ok(dirs) = std::fs::read_dir(&base) else {
            continue;
        };
        let mut found: Vec<std::path::PathBuf> = dirs
            .flatten()
            .map(|d| d.path())
            .filter(|d| d.file_name().is_some_and(|n| n.to_string_lossy().starts_with("Twinmotion")))
            .flat_map(|d| [d.join("Twinmotion.exe"), d.join(r"Engine\Binaries\Win64\Twinmotion.exe"), d.join(r"Twinmotion\Binaries\Win64\Twinmotion.exe")])
            .filter(|p| p.exists())
            .collect();
        found.sort();
        if let Some(p) = found.pop() {
            return Some(p);
        }
    }
    None
}
