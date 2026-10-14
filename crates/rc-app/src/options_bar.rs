//! The Options Bar under the ribbon: settings of the active tool (and selection hints).

use crate::app::App;
use crate::style;
use crate::tools::{DrawMode, SketchKind, ToolKind, WallRefPref};
use eframe::egui;
use rc_core::model::*;

/// A length text box that shows project units and parses on Enter/focus loss.
pub fn length_field(ui: &mut egui::Ui, app: &App, id: &str, value: &mut f64, width: f32) -> bool {
    let key = egui::Id::new(("len-field", id));
    let mut text: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| app.doc.data.units.length(*value));
    let r = ui.add(egui::TextEdit::singleline(&mut text).desired_width(width));
    let mut changed = false;
    if r.lost_focus() {
        if let Some(v) = app.doc.data.units.parse(text.trim(), ParamKind::Length) {
            if (v - *value).abs() > 1e-9 {
                *value = v;
                changed = true;
            }
        }
        ui.memory_mut(|m| m.data.remove::<String>(key));
    } else if r.has_focus() {
        ui.memory_mut(|m| m.data.insert_temp(key, text));
    } else {
        ui.memory_mut(|m| m.data.remove::<String>(key));
    }
    changed
}

fn number_field(ui: &mut egui::Ui, value: &mut f64, speed: f64, range: std::ops::RangeInclusive<f64>, suffix: &str) {
    ui.add(egui::DragValue::new(value).speed(speed).range(range).suffix(suffix).max_decimals(2));
}

fn level_combo(ui: &mut egui::Ui, app: &App, id: &str, value: &mut Option<Id>, none_label: &str) {
    let p = &app.doc.data;
    let label = value.map(|l| p.level_name(l)).unwrap_or_else(|| none_label.to_string());
    egui::ComboBox::from_id_salt(id).selected_text(label).width(120.0).show_ui(ui, |ui| {
        ui.selectable_value(value, None, none_label);
        for (lid, l) in p.levels() {
            ui.selectable_value(value, Some(lid), &l.name);
        }
    });
}

fn sep(ui: &mut egui::Ui) {
    ui.add_space(12.0);
}

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    ui.horizontal_centered(|ui| {
        ui.spacing_mut().item_spacing.x = 6.0;
        // Like the reference layout: the bar names the tool or selection, and stays empty when idle
        // (sketch mode shows only the draw options).
        let title = if app.sketch.is_some() {
            None
        } else if app.tool.is_select() {
            if app.selection.is_empty() { None } else { Some(format!("Modify | {}", selection_label(app))) }
        } else {
            Some(format!("Modify | Place {}", app.tool.kind.name()))
        };
        if let Some(title) = title {
            ui.label(egui::RichText::new(title).color(style::text()));
            ui.add_space(14.0);
        }
        let kind = app.tool.kind;
        let mode = app.opts.draw_mode;
        match kind {
            ToolKind::Select => select_options(app, ui),
            ToolKind::Wall => {
                let mut depth = app.opts.wall_depth;
                egui::ComboBox::from_id_salt("wall-hd").selected_text(if depth { "Depth" } else { "Height" }).width(70.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut depth, false, "Height");
                    ui.selectable_value(&mut depth, true, "Depth");
                });
                app.opts.wall_depth = depth;
                let mut top = app.opts.wall_top;
                level_combo(ui, app, "wall-top", &mut top, "Unconnected");
                app.opts.wall_top = top;
                if top.is_none() || depth {
                    let mut h = app.opts.wall_height;
                    if length_field(ui, app, "wall-h", &mut h, 70.0) {
                        app.opts.wall_height = h.max(10.0);
                    }
                }
                sep(ui);
                ui.label("Location Line:");
                let mut ll = app.opts.location_line;
                egui::ComboBox::from_id_salt("wall-ll").selected_text(ll.label()).width(150.0).show_ui(ui, |ui| {
                    for l in LocationLine::ALL {
                        ui.selectable_value(&mut ll, l, l.label());
                    }
                });
                app.opts.location_line = ll;
                draw_common(app, ui, mode, true);
            }
            ToolKind::Beam | ToolKind::Grid | ToolKind::RefPlane | ToolKind::RoomSeparator | ToolKind::AreaBoundary => draw_common(app, ui, mode, kind != ToolKind::Grid && kind != ToolKind::RefPlane),
            ToolKind::ModelLine | ToolKind::DetailLine => {
                ui.label("Line Style:");
                let mut s = app.opts.line_style;
                let styles = app.doc.data.all_line_styles();
                let names: Vec<String> = styles.iter().map(|l| app.doc.data.line_style_name(*l)).collect();
                egui::ComboBox::from_id_salt("line-style").selected_text(app.doc.data.line_style_name(s)).width(120.0).show_ui(ui, |ui| {
                    for (l, n) in styles.iter().zip(&names) {
                        ui.selectable_value(&mut s, *l, n);
                    }
                });
                app.opts.line_style = s;
                draw_common(app, ui, mode, true);
            }
            ToolKind::SketchLine => {
                let sk_kind = app.sketch.as_ref().map(|s| s.kind);
                if sk_kind.is_some_and(|k| k.is_roof()) {
                    ui.checkbox(&mut app.opts.defines_slope, "Defines slope");
                    ui.label("Overhang:");
                    let mut o = app.opts.overhang;
                    if length_field(ui, app, "roof-oh", &mut o, 60.0) {
                        app.opts.overhang = o.max(0.0);
                    }
                    ui.label("Slope:");
                    number_field(ui, &mut app.opts.roof_slope, 0.5, 1.0..=80.0, "°");
                    sep(ui);
                }
                if sk_kind == Some(SketchKind::Mass) {
                    ui.label("Height:");
                    let mut h = app.opts.mass_height;
                    if length_field(ui, app, "mass-h", &mut h, 80.0) {
                        app.opts.mass_height = h.max(100.0);
                    }
                    sep(ui);
                }
                if sk_kind == Some(SketchKind::Toposolid) {
                    ui.label("Height Offset From Level:");
                    let mut h = app.opts.topo_height;
                    if length_field(ui, app, "topo-h", &mut h, 80.0) {
                        app.opts.topo_height = h;
                    }
                    ui.label("Thickness:");
                    let mut t = app.opts.topo_thickness;
                    if length_field(ui, app, "topo-t", &mut t, 80.0) {
                        app.opts.topo_thickness = t.max(10.0);
                    }
                    sep(ui);
                }
                if sk_kind == Some(SketchKind::Stair) {
                    ui.label("Location Line: Run: Center");
                    ui.label("Actual Run Width:");
                    let mut w = app.opts.stair_width;
                    if length_field(ui, app, "stair-w", &mut w, 70.0) {
                        app.opts.stair_width = w.max(300.0);
                    }
                    sep(ui);
                }
                if matches!(sk_kind, Some(SketchKind::Region { masking: false }) | Some(SketchKind::EditRegion(_))) {
                    ui.label("Pattern:");
                    let mut pat = app.opts.fill_pattern;
                    egui::ComboBox::from_id_salt("fill-pat").selected_text(pat.label()).width(120.0).show_ui(ui, |ui| {
                        for f in FillPattern::ALL {
                            ui.selectable_value(&mut pat, f, f.label());
                        }
                    });
                    app.opts.fill_pattern = pat;
                    let mut c = app.opts.fill_color;
                    ui.color_edit_button_srgb(&mut c);
                    app.opts.fill_color = c;
                    sep(ui);
                }
                draw_common(app, ui, mode, true);
            }
            ToolKind::TopoPoints => {
                ui.label("Elevation:");
                let mut h = app.opts.topo_point_height;
                if length_field(ui, app, "topo-pt", &mut h, 80.0) {
                    app.opts.topo_point_height = h;
                }
                ui.label(egui::RichText::new("(relative to the toposolid level)").color(style::text_dim()));
            }
            ToolKind::Door | ToolKind::Window => {
                ui.checkbox(&mut app.opts.tag_on_placement, "Tag on Placement");
                ui.checkbox(&mut app.opts.tag_leader, "Leader");
            }
            ToolKind::Component | ToolKind::IsolatedFooting | ToolKind::PlaceGroup => {
                ui.label("Rotation:");
                number_field(ui, &mut app.opts.rotation, 1.0, 0.0..=360.0, "°");
                ui.label(egui::RichText::new("Space rotates by 90°.").color(style::text_dim()));
            }
            ToolKind::Column | ToolKind::StructColumn => {
                ui.label("Height:");
                let mut top = app.opts.column_top;
                level_combo(ui, app, "col-top", &mut top, "Unconnected");
                app.opts.column_top = top;
                if top.is_none() {
                    let mut h = app.opts.column_height;
                    if length_field(ui, app, "col-h", &mut h, 70.0) {
                        app.opts.column_height = h.max(100.0);
                    }
                }
                sep(ui);
                ui.label("Rotation:");
                number_field(ui, &mut app.opts.rotation, 1.0, 0.0..=360.0, "°");
            }
            ToolKind::Room => {
                ui.label("Upper Offset:");
                let mut h = app.opts.room_upper;
                if length_field(ui, app, "room-up", &mut h, 70.0) {
                    app.opts.room_upper = h.max(100.0);
                }
                ui.checkbox(&mut app.opts.room_tag, "Tag on placement");
            }
            ToolKind::Area | ToolKind::AreaTag | ToolKind::RoomTag | ToolKind::Tag => {
                let mut hz = app.opts.tag_horizontal;
                egui::ComboBox::from_id_salt("tag-or").selected_text(if hz { "Horizontal" } else { "Vertical" }).width(90.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut hz, true, "Horizontal");
                    ui.selectable_value(&mut hz, false, "Vertical");
                });
                app.opts.tag_horizontal = hz;
                ui.checkbox(&mut app.opts.tag_leader, "Leader");
                if kind == ToolKind::Area {
                    ui.checkbox(&mut app.opts.room_tag, "Tag on placement");
                }
            }
            ToolKind::Insulation => {
                ui.label("Width:");
                let imperial = app.doc.data.units.system == rc_core::units::UnitSystem::Imperial;
                let presets: Vec<f64> = if imperial { vec![25.4, 50.8, 76.2, 101.6, 152.4] } else { vec![25.0, 50.0, 75.0, 100.0, 150.0] };
                let mut w = app.opts.insulation_width;
                let units = app.doc.data.units.clone();
                egui::ComboBox::from_id_salt("ins-w").selected_text(units.length(w)).width(90.0).show_ui(ui, |ui| {
                    for p in &presets {
                        ui.selectable_value(&mut w, *p, units.length(*p));
                    }
                });
                if length_field(ui, app, "ins-w-edit", &mut w, 70.0) {
                    w = w.max(5.0);
                }
                app.opts.insulation_width = w;
            }
            ToolKind::JoinGeometry => {
                ui.checkbox(&mut app.opts.join_multiple, "Multiple Join");
            }
            ToolKind::DetailComponent => {
                ui.label("Type:");
                let mut k = app.opts.detail_component;
                egui::ComboBox::from_id_salt("dc-type").selected_text(DETAIL_COMPONENTS[k.min(DETAIL_COMPONENTS.len() - 1)]).width(220.0).show_ui(ui, |ui| {
                    for (i, n) in DETAIL_COMPONENTS.iter().enumerate() {
                        ui.selectable_value(&mut k, i, *n);
                    }
                });
                app.opts.detail_component = k;
            }
            ToolKind::Text => {
                ui.label("Size:");
                number_field(ui, &mut app.opts.text_size, 0.1, 1.0..=20.0, " mm");
                ui.checkbox(&mut app.opts.text_bold, "Bold");
                ui.label("Rotation:");
                number_field(ui, &mut app.opts.rotation, 1.0, 0.0..=360.0, "°");
            }
            ToolKind::Dimension(k) => {
                if matches!(k, DimKind::Aligned | DimKind::Linear) {
                    ui.label("Prefer:");
                    let mut pr = app.opts.dim_prefer;
                    egui::ComboBox::from_id_salt("dim-pref").selected_text(pr.label()).width(130.0).show_ui(ui, |ui| {
                        for w in WallRefPref::ALL {
                            ui.selectable_value(&mut pr, w, w.label());
                        }
                    });
                    app.opts.dim_prefer = pr;
                    ui.label(format!("References picked: {}", app.tool.refs.len()));
                }
            }
            ToolKind::Level => {
                ui.checkbox(&mut app.opts.make_plan, "Make Plan View");
            }
            ToolKind::Section => {
                ui.label("Far Clip Offset:");
                let mut d = app.opts.section_depth;
                if length_field(ui, app, "sec-depth", &mut d, 80.0) {
                    app.opts.section_depth = d.max(100.0);
                }
            }
            ToolKind::Symbol => {
                let mut k = app.opts.symbol_kind;
                let label = |k: SymbolKind| match k {
                    SymbolKind::NorthArrow => "North Arrow",
                    SymbolKind::Revision => "Revision Tag",
                    SymbolKind::SpotElevation => "Spot Elevation",
                    SymbolKind::BreakLine => "Break Line",
                    SymbolKind::SpotCoordinate => "Spot Coordinate",
                    SymbolKind::SpotSlope => "Spot Slope",
                    SymbolKind::Insulation => "Insulation",
                    SymbolKind::DetailComponent => "Detail Component",
                };
                egui::ComboBox::from_id_salt("sym-kind").selected_text(label(k)).width(120.0).show_ui(ui, |ui| {
                    for s in [SymbolKind::NorthArrow, SymbolKind::BreakLine, SymbolKind::SpotElevation] {
                        ui.selectable_value(&mut k, s, label(s));
                    }
                });
                app.opts.symbol_kind = k;
                ui.label("Rotation:");
                number_field(ui, &mut app.opts.rotation, 1.0, 0.0..=360.0, "°");
            }
            ToolKind::WallOpening => {
                ui.label("Sill:");
                let mut s = app.opts.opening_sill;
                if length_field(ui, app, "op-sill", &mut s, 70.0) {
                    app.opts.opening_sill = s.max(0.0);
                }
                ui.label("Height:");
                let mut h = app.opts.opening_height;
                if length_field(ui, app, "op-h", &mut h, 70.0) {
                    app.opts.opening_height = h.max(10.0);
                }
            }
            ToolKind::Move | ToolKind::Copy => {
                ui.checkbox(&mut app.opts.constrain, "Constrain");
                if kind == ToolKind::Copy {
                    ui.checkbox(&mut app.opts.copy_multiple, "Multiple");
                }
            }
            ToolKind::Rotate => {
                // Copy | Angle | Center of rotation: Place / Default, as in the reference options bar.
                ui.checkbox(&mut app.opts.rotate_copy, "Copy");
                ui.label("Angle:");
                let key = egui::Id::new("rotate-angle");
                let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_default();
                let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(60.0));
                if r.has_focus() {
                    ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
                }
                if r.lost_focus() {
                    ui.memory_mut(|m| m.data.remove::<String>(key));
                    if let Some(a) = app.doc.data.units.parse(s.trim(), ParamKind::Angle) {
                        let center = app.tool.pts.first().copied().unwrap_or_else(|| crate::canvas_tools::selection_center(app));
                        crate::canvas_tools::rotate_now(app, center, a);
                    }
                }
                ui.label("Center of rotation:");
                if ui.button("Place").clicked() {
                    app.tool.pts.clear();
                    app.tool.picked = vec![u32::MAX];
                }
                if ui.button("Default").clicked() {
                    app.tool.pts.clear();
                    app.tool.picked.clear();
                }
            }
            ToolKind::MirrorPick | ToolKind::MirrorDraw => {
                ui.checkbox(&mut app.opts.mirror_copy, "Copy");
            }
            ToolKind::Array => {
                ui.selectable_value(&mut app.opts.array_radial, false, "Linear");
                ui.selectable_value(&mut app.opts.array_radial, true, "Radial");
                sep(ui);
                ui.label("Number:");
                let mut n = app.opts.array_count as f64;
                number_field(ui, &mut n, 0.2, 2.0..=200.0, "");
                app.opts.array_count = n.round() as u32;
                if !app.opts.array_radial {
                    ui.label("Move To:");
                    ui.selectable_value(&mut app.opts.array_last, false, "2nd");
                    ui.selectable_value(&mut app.opts.array_last, true, "Last");
                    ui.checkbox(&mut app.opts.constrain, "Constrain");
                }
            }
            ToolKind::Scale => {
                ui.label("Scale:");
                number_field(ui, &mut app.opts.scale_factor, 0.01, 0.01..=100.0, "");
            }
            ToolKind::Offset => {
                ui.radio_value(&mut app.opts.offset_graphical, true, "Graphical");
                ui.radio_value(&mut app.opts.offset_graphical, false, "Numerical");
                ui.label("Offset:");
                let mut d = app.opts.offset_dist;
                if length_field(ui, app, "off-d", &mut d, 80.0) {
                    app.opts.offset_dist = d.max(1.0);
                }
                ui.checkbox(&mut app.opts.offset_copy, "Copy");
            }
            ToolKind::Align => {
                ui.checkbox(&mut app.opts.align_multiple, "Multiple Alignment");
                ui.label("Prefer:");
                let mut pr = app.opts.align_prefer;
                egui::ComboBox::from_id_salt("align-pref").selected_text(pr.label()).width(130.0).show_ui(ui, |ui| {
                    for w in WallRefPref::ALL {
                        ui.selectable_value(&mut pr, w, w.label());
                    }
                });
                app.opts.align_prefer = pr;
            }
            ToolKind::SplitGap => {
                ui.label("Joint Gap:");
                let mut g = app.opts.split_gap;
                if length_field(ui, app, "split-gap", &mut g, 70.0) {
                    app.opts.split_gap = g.clamp(1.0, 1000.0);
                }
            }
            _ => {}
        }
        if let Some(o) = app.snap_override {
            sep(ui);
            let t = match o {
                crate::snap::Override::Off => "Snaps off for the next pick".to_string(),
                crate::snap::Override::Only(k) => format!("Snap override: {}", k.label()),
            };
            ui.label(egui::RichText::new(t).color(style::SNAP));
        }
    });
}

fn draw_common(app: &mut App, ui: &mut egui::Ui, mode: DrawMode, with_offset: bool) {
    sep(ui);
    if mode == DrawMode::PolyIn || mode == DrawMode::PolyCirc {
        ui.label("Edges:");
        let mut n = app.opts.poly_sides as f64;
        number_field(ui, &mut n, 0.2, 3.0..=64.0, "");
        app.opts.poly_sides = n.round() as u32;
    }
    if !matches!(mode, DrawMode::Rect | DrawMode::PolyIn | DrawMode::PolyCirc | DrawMode::Circle | DrawMode::Fillet | DrawMode::PickLines | DrawMode::PickWalls) {
        ui.checkbox(&mut app.opts.chain, "Chain");
    }
    if with_offset && !matches!(mode, DrawMode::Fillet) {
        ui.label("Offset:");
        let mut o = app.opts.offset;
        if length_field(ui, app, "draw-off", &mut o, 70.0) {
            app.opts.offset = o;
        }
    }
    if mode == DrawMode::Fillet {
        ui.label("Radius:");
        let mut r = app.opts.radius;
        if length_field(ui, app, "draw-rad", &mut r, 70.0) {
            app.opts.radius = r.max(1.0);
        }
    }
}

fn selection_label(app: &App) -> String {
    let p = &app.doc.data;
    let mut cats: Vec<Category> = app.selection.iter().filter_map(|id| app.el(*id).map(|e| e.category())).collect();
    cats.sort();
    cats.dedup();
    if cats.len() == 1 {
        cats[0].label().to_string()
    } else if cats.is_empty() && app.selection.iter().any(|id| p.view(*id).is_some()) {
        "Views".into()
    } else {
        "Multi-Select".into()
    }
}

fn select_options(_app: &mut App, _ui: &mut egui::Ui) {}
