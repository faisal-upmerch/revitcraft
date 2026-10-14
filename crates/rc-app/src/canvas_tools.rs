//! What each tool does with cursor moves and clicks in a 2D view: previews, temporary
//! dimensions, prompts and the model changes.

use crate::app::App;
use crate::canvas::{self, Drag, Xf, temp_dim};
use crate::style;
use crate::tools::{self, DrawMode, Seg, ToolKind};
use eframe::egui::{self, Color32, Pos2, Rect, Stroke, vec2};
use rc_core::analysis;
use rc_core::edit;
use rc_core::geom::{self, DVec2};
use rc_core::model::*;
use rc_core::plan::{Dash, Drawing};

fn preview_stroke() -> Stroke {
    Stroke::new(1.6, style::PREVIEW)
}

fn draw_segs(painter: &egui::Painter, xf: &Xf, segs: &[Seg], stroke: Stroke) {
    for s in segs {
        let pts: Vec<Pos2> = s.points().iter().map(|q| xf.s(*q)).collect();
        painter.add(egui::Shape::line(pts, stroke));
    }
}

/// The last picked point of the active tool (rubber-band origin for snapping and typing).
pub fn reference_point(app: &App) -> Option<DVec2> {
    let t = &app.tool;
    match t.kind {
        ToolKind::Rotate => t.pts.first().copied(),
        ToolKind::Select => None,
        _ if t.kind.uses_draw_modes() => match app.opts.draw_mode {
            DrawMode::ArcTangent => t.tangent.map(|x| x.0).or(t.pts.last().copied()),
            DrawMode::PolyIn | DrawMode::PolyCirc | DrawMode::Circle | DrawMode::ArcCenter => t.pts.first().copied(),
            _ => t.pts.last().copied(),
        },
        _ => t.pts.last().copied(),
    }
}

/// Curve of a line-like element (walls, grids, reference planes, lines, separations, beams).
pub fn element_curve(e: &Element) -> Option<Seg> {
    let arc_or_line = |a: DVec2, m: Option<DVec2>, b: DVec2| match m {
        Some(m) => Seg::Arc(a, m, b),
        None => Seg::Line(a, b),
    };
    match &e.kind {
        ElementKind::Wall(w) => Some(arc_or_line(w.start, w.arc_mid, w.end)),
        ElementKind::Grid(g) => Some(arc_or_line(g.start, g.arc_mid, g.end)),
        ElementKind::RefPlane(r) => Some(Seg::Line(r.start, r.end)),
        ElementKind::Line(l) if l.pts.len() == 2 => Some(arc_or_line(l.pts[0], l.arc_mid, l.pts[1])),
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => Some(Seg::Line(s.start, s.end)),
        ElementKind::Instance(i) => i.end.map(|end| Seg::Line(i.location, end)),
        _ => None,
    }
}

fn hover_of(app: &App, view: &View, d: &Drawing, c: DVec2, xf: &Xf, pred: &dyn Fn(&Element) -> bool) -> Option<Id> {
    canvas::pick_candidates(app, view, d, c, xf.len(8.0)).into_iter().find(|id| app.el(*id).is_some_and(pred))
}

/// Allowed draw modes for a tool (the ribbon shows only these).
pub fn modes_for(kind: ToolKind) -> &'static [DrawMode] {
    use DrawMode::*;
    match kind {
        ToolKind::Wall => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, PickLines],
        ToolKind::SketchLine => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, PickLines, PickWalls],
        ToolKind::ModelLine | ToolKind::DetailLine | ToolKind::RoomSeparator | ToolKind::AreaBoundary => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, PickLines],
        ToolKind::Grid => &[Line, Arc3, ArcCenter, PickLines],
        ToolKind::RefPlane | ToolKind::Beam => &[Line, PickLines],
        _ => &[],
    }
}

fn effective_mode(app: &App) -> DrawMode {
    let allowed = modes_for(app.tool.kind);
    if allowed.contains(&app.opts.draw_mode) { app.opts.draw_mode } else { DrawMode::Line }
}

// ---------------------------------------------------------------- prompts

pub fn prompt(app: &App) -> String {
    let t = &app.tool;
    let n = t.pts.len();
    let mode = effective_mode(app);
    match t.kind {
        k if k.uses_draw_modes() => match mode {
            DrawMode::PickLines => "Pick a line, edge, wall or grid to create from it.".into(),
            DrawMode::PickWalls => "Pick walls to create the boundary (the face on the cursor side is used).".into(),
            DrawMode::Fillet => if t.picked.is_empty() { "Pick the first element for the fillet.".into() } else { "Pick the second element.".into() },
            DrawMode::Rect => if n == 0 { "Click to enter the first corner of the rectangle.".into() } else { "Click to enter the opposite corner.".into() },
            DrawMode::PolyIn | DrawMode::PolyCirc | DrawMode::Circle => if n == 0 { "Click to enter the center.".into() } else { "Click to enter the radius (or type it).".into() },
            DrawMode::Arc3 => ["Click the arc start.", "Click the arc end.", "Click a point on the arc to set its radius."][n.min(2)].into(),
            DrawMode::ArcCenter => ["Click the arc center.", "Click the arc start (radius).", "Click the arc end."][n.min(2)].into(),
            DrawMode::ArcTangent => "Click the end point of the tangent arc.".into(),
            DrawMode::Line => {
                let what = if k == ToolKind::Wall { "wall" } else { "line" };
                if n == 0 {
                    format!("Click to enter {what} start point.")
                } else {
                    match app.interact.snap.as_ref().and_then(canvas::axis_label) {
                        Some(axis) => format!("{}. Space flips orientation.", axis.to_uppercase()),
                        None => format!("Enter {what} end point. Space flips orientation."),
                    }
                }
            }
        },
        ToolKind::Door => "Click on Wall to place Door (Space Bar to flip the instance left/right)".into(),
        ToolKind::Window => "Click on Wall to place Window (Space Bar to flip the instance)".into(),
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting => "Click to place. Space rotates by 90°.".into(),
        ToolKind::PlaceGroup => "Click to place the group origin.".into(),
        ToolKind::Room => "Click to place room".into(),
        ToolKind::CeilingAuto => "Click inside a room bounded by walls to place a ceiling, or choose Sketch Ceiling.".into(),
        ToolKind::Area => "Click inside a region enclosed by area boundaries.".into(),
        ToolKind::RoomTag | ToolKind::AreaTag | ToolKind::Tag => "Click an element to tag it.".into(),
        ToolKind::Level => if n == 0 { "Click the start of the level line (in a section or elevation).".into() } else { "Click the end of the level line.".into() },
        ToolKind::Text => "Click to place the text, type, then click outside the box to finish.".into(),
        ToolKind::Dimension(DimKind::Aligned) | ToolKind::Dimension(DimKind::Linear) => {
            if t.refs.len() < 2 { "Pick references: wall faces or centers, grids, reference planes, or points. Tab cycles.".into() } else { "Pick more references, or click in empty space to place the dimension.".into() }
        }
        ToolKind::Dimension(DimKind::Angular) => ["Pick the first line.", "Pick the second line.", "Click to place the arc."][t.refs.len().min(2)].into(),
        ToolKind::Dimension(DimKind::Radial) | ToolKind::Dimension(DimKind::Diameter) => "Pick an arc or circle, then click to place.".into(),
        ToolKind::Dimension(DimKind::ArcLength) => "Pick an arc, then click to place the dimension.".into(),
        ToolKind::Dimension(DimKind::SpotElevation) => "Click a point to show its elevation.".into(),
        ToolKind::Symbol => "Click to place the symbol.".into(),
        ToolKind::Section => if n == 0 { "Click the start of the section line.".into() } else { "Click the end of the section line.".into() },
        ToolKind::Callout => if n == 0 { "Click the first corner of the callout.".into() } else { "Click the opposite corner.".into() },
        ToolKind::ElevationMarker => "Click to place the elevation marker; it looks towards the building.".into(),
        ToolKind::CurtainGrid => "Click on a curtain wall to add a grid line.".into(),
        ToolKind::WallOpening => if n == 0 { "Click a wall at one side of the opening.".into() } else { "Click the other side of the opening.".into() },
        ToolKind::WallFoundation => "Pick a wall to add a wall foundation under it.".into(),
        ToolKind::Align => if n == 0 { "Pick the reference line or point to align to.".into() } else { "Pick the entity to align.".into() },
        ToolKind::Offset => "Hover a wall or line; click to offset to the cursor side.".into(),
        ToolKind::MirrorPick => "Pick a line, wall or grid as the mirror axis.".into(),
        ToolKind::MirrorDraw => if n == 0 { "Click the start of the mirror axis.".into() } else { "Click the end of the mirror axis.".into() },
        ToolKind::Move | ToolKind::Copy => if n == 0 { "Click the start point (move from).".into() } else { "Click the end point (move to), or type a distance.".into() },
        ToolKind::Rotate => {
            if t.picked.first() == Some(&u32::MAX) {
                "Click to place the center of rotation.".into()
            } else if n <= 1 {
                "Click to set the start ray (or type an angle and press Enter).".into()
            } else {
                "Click to set the end ray.".into()
            }
        }
        ToolKind::TrimCorner => if t.picked.is_empty() { "Pick the first element (the part to keep).".into() } else { "Pick the second element (the part to keep).".into() },
        ToolKind::TrimSingle | ToolKind::TrimMulti => if t.picked.is_empty() { "Pick the boundary.".into() } else { "Pick the element to trim/extend (click the part to keep).".into() },
        ToolKind::Split | ToolKind::SplitGap => "Click a wall or line where it should be split.".into(),
        ToolKind::Array => if n == 0 { "Click the start point of the array.".into() } else { "Click the end point (second item, or last with 'Move to: Last').".into() },
        ToolKind::Scale => "Click the origin; elements scale by the factor in the Options Bar.".into(),
        ToolKind::MatchType => if t.picked.is_empty() { "Pick the element whose type to copy.".into() } else { "Pick elements to change to that type.".into() },
        ToolKind::Measure => if n == 0 { "Click the first point to measure.".into() } else { "Click the second point.".into() },
        ToolKind::ZoomRegion => "Drag a rectangle (or click two corners) to zoom into.".into(),
        ToolKind::AttachTop | ToolKind::AttachBase => "Pick a roof, floor or ceiling to attach the selected walls to.".into(),
        ToolKind::PickHost => "Pick a wall to host the selected door or window.".into(),
        ToolKind::Paste => "Click to place the pasted elements.".into(),
        _ => String::new(),
    }
}

// ---------------------------------------------------------------- dispatch

pub fn handle(app: &mut App, ui: &egui::Ui, resp: &egui::Response, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    app.interact.prompt = prompt(app);
    let enter = std::mem::take(&mut app.interact.pending_enter);
    let clicked = clicked || (enter && point.is_some());
    let kind = app.tool.kind;
    match kind {
        k if k.uses_draw_modes() => draw_tool(app, painter, xf, view, d, cursor, point, clicked),
        ToolKind::Door | ToolKind::Window => hosted_tool(app, painter, xf, view, d, cursor, clicked),
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting => free_tool(app, painter, xf, view, point, clicked),
        ToolKind::PlaceGroup => group_tool(app, painter, xf, view, point, clicked),
        ToolKind::Room | ToolKind::Area | ToolKind::CeilingAuto => room_tool(app, painter, xf, view, cursor, clicked),
        ToolKind::RoomTag | ToolKind::AreaTag | ToolKind::Tag => tag_tool(app, painter, xf, view, d, cursor, clicked),
        ToolKind::Level => level_tool(app, painter, xf, view, point, clicked),
        ToolKind::Text => text_tool(app, ui, xf, view, point, clicked),
        ToolKind::Dimension(k) => dim_tool(app, painter, xf, view, d, k, cursor, point, clicked),
        ToolKind::Symbol => {
            if let Some(pt) = point {
                painter.circle_stroke(xf.s(pt), 10.0, preview_stroke());
                if clicked {
                    let (kind, rot, vid) = (app.opts.symbol_kind, app.opts.rotation, view.id);
                    if let Some(id) = app.run("Place Symbol", |p| {
                        let id = edit::add_symbol(p, vid, kind, pt);
                        if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                            s.rotation_deg = rot;
                        }
                        Ok(id)
                    }) {
                        app.select(vec![id]);
                    }
                }
            }
        }
        ToolKind::Section | ToolKind::Callout | ToolKind::ElevationMarker => view_marker_tool(app, painter, xf, view, point, clicked),
        ToolKind::CurtainGrid | ToolKind::WallOpening | ToolKind::WallFoundation => wall_pick_tool(app, painter, xf, view, d, cursor, point, clicked),
        _ => modify_tool(app, ui, resp, painter, xf, view, d, cursor, point, clicked),
    }
}

/// Enter: ends chains, applies typed values.
pub fn enter(app: &mut App) {
    if !app.typed.trim().is_empty() {
        app.interact.pending_enter = true;
        return;
    }
    match app.tool.kind {
        k if k.uses_draw_modes() => {
            if app.tool.in_progress() || app.tool.tangent.is_some() {
                app.tool.reset();
            } else if app.sketch.is_some() {
                crate::actions::exec(app, crate::commands::Cmd::FinishSketch);
            }
        }
        ToolKind::Rotate if app.tool.pts.len() >= 1 => app.interact.pending_enter = true,
        _ => app.tool.reset(),
    }
}

// ---------------------------------------------------------------- draw-mode tools

fn draw_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    let mode = effective_mode(app);
    if mode.is_pick() {
        pick_draw_tool(app, painter, xf, view, d, mode, cursor, clicked);
        return;
    }
    let Some(pt) = point else { return };
    let kind = app.tool.kind;
    let sides = app.opts.poly_sides;
    let tangent = app.tool.tangent;
    let segs = tools::preview(mode, &app.tool.pts, pt, sides, tangent);
    // Preview, with the wall thickness for walls.
    if kind == ToolKind::Wall {
        let t = app.doc.data.sys_type(app.opts.wall_type).map(|t| t.thickness()).unwrap_or(200.0);
        let (lo, hi) = location_span(app, t);
        for s in &segs {
            let s = s.offset(app.opts.offset);
            let a = s.offset(lo).points();
            let mut b = s.offset(hi).points();
            b.reverse();
            let mut outline: Vec<Pos2> = a.iter().chain(b.iter()).map(|q| xf.s(*q)).collect();
            outline.push(outline[0]);
            painter.add(egui::Shape::line(outline, preview_stroke()));
            draw_segs(painter, xf, &[s], Stroke::new(1.0, style::PREVIEW.gamma_multiply(0.6)));
        }
    } else {
        let color = if app.sketch.is_some() { style::SKETCH } else { style::PREVIEW };
        draw_segs(painter, xf, &segs, Stroke::new(1.6, color));
    }
    // Temporary dimensions: length and angle of the rubber band.
    if let (Some(a), DrawMode::Line) = (app.tool.pts.first().copied(), mode) {
        let units = app.doc.data.units.clone();
        canvas::temp_dim_ex(painter, xf, a, pt, &units.length(a.distance(pt)), -24.0, true);
        // Angle from the previous segment (or the horizontal) with its arc.
        let reference = app.tool.tangent.map(|t| t.1).unwrap_or(DVec2::X).normalize_or_zero();
        angle_arc(painter, xf, a, reference, pt, &units);
    }
    if let (Some(a), DrawMode::Rect) = (app.tool.pts.first().copied(), mode) {
        let units = app.doc.data.units.clone();
        temp_dim(painter, xf, a, DVec2::new(pt.x, a.y), &units.length((pt.x - a.x).abs()), -22.0);
        temp_dim(painter, xf, DVec2::new(pt.x, a.y), pt, &units.length((pt.y - a.y).abs()), -22.0);
    }
    if let (Some(c), DrawMode::Circle | DrawMode::PolyIn | DrawMode::PolyCirc) = (app.tool.pts.first().copied(), mode) {
        let units = app.doc.data.units.clone();
        temp_dim(painter, xf, c, pt, &format!("R {}", units.length(c.distance(pt))), -18.0);
    }
    if !clicked {
        return;
    }
    let chain = app.opts.chain || matches!(mode, DrawMode::Arc3);
    let mut pts = std::mem::take(&mut app.tool.pts);
    let res = tools::draw_step(mode, &mut pts, pt, sides, tangent, chain && kind != ToolKind::Grid && kind != ToolKind::RefPlane);
    app.tool.pts = pts;
    app.typed.clear();
    if let Some(segs) = res {
        if commit_segs(app, view, &segs) {
            if let Some(last) = segs.last() {
                app.tool.tangent = if chain && !matches!(mode, DrawMode::Rect | DrawMode::PolyIn | DrawMode::PolyCirc | DrawMode::Circle) { Some((last.end(), last.end_tangent())) } else { None };
            }
        } else {
            app.tool.reset();
        }
    }
}

/// The angle between `reference` and the rubber band `a`→`pt`: a grey reference line, a
/// light-blue arc and the value, skipped when the band runs along the reference.
fn angle_arc(painter: &egui::Painter, xf: &Xf, a: DVec2, reference: DVec2, pt: DVec2, units: &rc_core::units::Units) {
    let v = pt - a;
    let len = v.length();
    if len < 1e-6 || reference == DVec2::ZERO {
        return;
    }
    let t0 = reference.y.atan2(reference.x);
    let mut sweep = v.y.atan2(v.x) - t0;
    while sweep > std::f64::consts::PI {
        sweep -= std::f64::consts::TAU;
    }
    while sweep < -std::f64::consts::PI {
        sweep += std::f64::consts::TAU;
    }
    let deg = sweep.abs().to_degrees();
    if deg < 0.5 || (180.0 - deg) < 0.5 {
        return;
    }
    let r_px = ((len * xf.zoom) as f32 * 0.5).clamp(24.0, 140.0);
    let r = xf.len(r_px);
    painter.line_segment([xf.s(a), xf.s(a + reference * (r * 1.35))], Stroke::new(1.0, Color32::from_gray(120)));
    let n = 32;
    let pts: Vec<Pos2> = (0..=n).map(|k| {
        let t = t0 + sweep * k as f64 / n as f64;
        xf.s(a + DVec2::new(t.cos(), t.sin()) * r)
    }).collect();
    painter.add(egui::Shape::line(pts, Stroke::new(1.0, style::TEMP_DIM_LINE)));
    let tm = t0 + sweep / 2.0;
    let q = xf.s(a + DVec2::new(tm.cos(), tm.sin()) * (r + xf.len(12.0)));
    let text = units.format(deg, ParamKind::Angle);
    let galley = painter.layout_no_wrap(text, style::font(12.0), style::TEMP_DIM);
    let rect = Rect::from_center_size(q, galley.size());
    painter.rect_filled(rect.expand(1.0), 0.0, Color32::from_rgba_unmultiplied(255, 255, 255, 200));
    painter.galley(rect.min, galley, style::TEMP_DIM);
}

/// Offsets of the wall faces relative to the drawn line for the current location line:
/// returns (left, right) offsets.
fn location_span(app: &App, t: f64) -> (f64, f64) {
    let ty = app.doc.data.sys_type(app.opts.wall_type);
    let off = ty.map(|ty| analysis::location_line_offset(ty, app.opts.location_line)).unwrap_or(0.0);
    // The wall centre is `-off` from the location line (towards the interior for positive).
    (t / 2.0 - off, -t / 2.0 - off)
}

/// Creates elements from drawn segments. Returns false when nothing was created.
fn commit_segs(app: &mut App, view: &View, segs: &[Seg]) -> bool {
    let kind = app.tool.kind;
    let level = view.plan_level();
    let o = app.opts.clone();
    let vid = view.id;
    match kind {
        ToolKind::SketchLine => {
            if let Some(sk) = app.sketch.as_mut() {
                for s in segs {
                    sk.push(s.offset(o.offset), o.defines_slope);
                }
                return true;
            }
            false
        }
        ToolKind::Wall => {
            let Some(level) = level else { return false };
            let segs: Vec<Seg> = segs.iter().map(|s| s.offset(o.offset)).collect();
            app.run("Create Wall", |p| {
                for s in &segs {
                    let (a, b, m) = match *s {
                        Seg::Line(a, b) => (a, b, None),
                        Seg::Arc(a, m, b) => (a, b, Some(m)),
                    };
                    let id = edit::add_wall_ex(p, level, o.wall_type, a, b, m, o.wall_height, o.location_line, false)?;
                    let w = p.element_mut(id).and_then(Element::as_wall_mut).unwrap();
                    w.structural = o.wall_structural;
                    w.room_bounding = o.wall_room_bounding;
                    if o.wall_depth {
                        w.base_offset = -o.wall_height;
                        w.top_level = Some(level);
                        w.top_offset = 0.0;
                    } else if let Some(t) = o.wall_top {
                        w.base_offset = o.wall_base_offset;
                        w.top_level = Some(t);
                        w.top_offset = o.wall_top_offset;
                    } else {
                        w.base_offset = o.wall_base_offset;
                        w.top_level = None;
                        w.unconnected_height = o.wall_height;
                    }
                }
                Ok(())
            })
            .is_some()
        }
        ToolKind::Beam => {
            let Some(level) = level else { return false };
            app.run("Create Beam", |p| {
                for s in segs {
                    match *s {
                        Seg::Line(a, b) => {
                            edit::add_beam(p, o.beam_type, level, a, b)?;
                        }
                        Seg::Arc(..) => return Err("Curved beams are not supported; draw straight segments.".into()),
                    }
                }
                Ok(())
            })
            .is_some()
        }
        ToolKind::Grid => app
            .run("Create Grid", |p| {
                for s in segs {
                    match *s {
                        Seg::Line(a, b) => edit::add_grid_ex(p, a, b, None)?,
                        Seg::Arc(a, m, b) => edit::add_grid_ex(p, a, b, Some(m))?,
                    };
                }
                Ok(())
            })
            .is_some(),
        ToolKind::RefPlane => app
            .run("Create Reference Plane", |p| {
                for s in segs {
                    edit::add_ref_plane(p, s.start(), s.end())?;
                }
                Ok(())
            })
            .is_some(),
        ToolKind::ModelLine | ToolKind::DetailLine => {
            let (v, lv) = if kind == ToolKind::DetailLine { (Some(vid), None) } else { (None, level) };
            if kind == ToolKind::ModelLine && level.is_none() {
                app.error("Model lines are drawn in plan views. Use Detail Line in this view.");
                return false;
            }
            app.run(if kind == ToolKind::DetailLine { "Create Detail Lines" } else { "Create Model Lines" }, |p| {
                for s in segs {
                    let (pts, m) = match *s {
                        Seg::Line(a, b) => (vec![a, b], None),
                        Seg::Arc(a, m, b) => (vec![a, b], Some(m)),
                    };
                    edit::add_line(p, v, lv, pts, m, o.line_style)?;
                }
                Ok(())
            })
            .is_some()
        }
        ToolKind::RoomSeparator | ToolKind::AreaBoundary => {
            let Some(level) = level else { return false };
            let scheme = match view.kind {
                ViewKind::AreaPlan { scheme, .. } => Some(scheme),
                _ => None,
            };
            if kind == ToolKind::AreaBoundary && scheme.is_none() {
                app.error("Area boundaries are drawn in area plans.");
                return false;
            }
            app.run(if scheme.is_some() { "Area Boundary" } else { "Room Separation" }, |p| {
                for s in segs {
                    let pts = s.points();
                    for w in pts.windows(2) {
                        edit::add_separation(p, level, w[0], w[1], scheme)?;
                    }
                }
                Ok(())
            })
            .is_some()
        }
        _ => false,
    }
}

fn pick_draw_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, mode: DrawMode, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let kind = app.tool.kind;
    // Sketch segments can be filleted too.
    let sketch_hover = app.sketch.as_ref().and_then(|sk| {
        sk.segs.iter().enumerate().map(|(k, s)| (s.distance_to(c), k)).filter(|(dd, _)| *dd <= xf.len(8.0)).min_by(|a, b| a.0.total_cmp(&b.0)).map(|x| x.1)
    });
    let walls_only = mode == DrawMode::PickWalls;
    let hover = hover_of(app, view, d, c, xf, &|e| element_curve(e).is_some() && (!walls_only || matches!(e.kind, ElementKind::Wall(_))));
    if mode == DrawMode::Fillet {
        // Pick two straight elements (or sketch lines); radius from the Options Bar.
        let target: Option<(Option<Id>, Option<usize>, Seg)> = match (sketch_hover, hover) {
            (Some(k), _) if kind == ToolKind::SketchLine => app.sketch.as_ref().map(|s| (None, Some(k), s.segs[k])),
            (_, Some(id)) => app.el(id).and_then(element_curve).map(|s| (Some(id), None, s)),
            _ => None,
        };
        if let Some((_, _, s)) = &target {
            draw_segs(painter, xf, &[*s], Stroke::new(3.0, style::PRESELECT));
        }
        if clicked {
            if let Some((id, k, s)) = target {
                if !matches!(s, Seg::Line(..)) {
                    app.error("Fillet works on straight elements.");
                    return;
                }
                app.tool.pts.push(s.start());
                app.tool.pts.push(s.end());
                app.tool.picked.push(id.unwrap_or(u32::MAX - k.unwrap_or(0) as u32));
                if app.tool.picked.len() == 2 {
                    do_fillet(app, view);
                    app.tool.reset();
                }
            }
        }
        return;
    }
    let Some(id) = hover else { return };
    // Tab over a wall picks the whole chain of joined walls, like the reference app.
    let chain_key = egui::Id::new("pick-chain");
    let mut chain: Option<Id> = painter.ctx().memory(|m| m.data.get_temp(chain_key)).flatten();
    if std::mem::take(&mut app.interact.tab_pressed) && mode == DrawMode::PickWalls {
        chain = if chain == Some(id) { None } else { Some(id) };
    }
    let walls = if chain.is_some() { wall_chain(&app.doc.data, chain.unwrap()) } else { vec![] };
    if chain.is_some() && !walls.contains(&id) {
        chain = None;
    }
    painter.ctx().memory_mut(|m| m.data.insert_temp(chain_key, chain));
    if chain.is_some() && walls.len() > 1 {
        app.interact.prompt = "Chain of walls or lines".into();
        let p = &app.doc.data;
        let mids: Vec<DVec2> = walls.iter().filter_map(|w| p.wall(*w)).map(|w| (w.start + w.end) / 2.0).collect();
        let centroid = mids.iter().fold(DVec2::ZERO, |a, b| a + *b) / mids.len().max(1) as f64;
        let w0 = p.wall(id).cloned();
        let inside = w0.is_some_and(|w0| (c - w0.start).dot(w0.normal()) * (centroid - w0.start).dot(w0.normal()) > 0.0);
        let roof = app.sketch.as_ref().is_some_and(|s| s.kind.is_roof());
        let segs: Vec<Seg> = walls
            .iter()
            .filter_map(|wid| {
                let w = p.wall(*wid)?;
                let e = p.element(*wid)?;
                let seg = element_curve(e)?;
                let t = analysis::wall_thickness(p, w);
                let toward = if (centroid - w.start).dot(w.normal()) >= 0.0 { 1.0 } else { -1.0 };
                let side = if inside { toward } else { -toward };
                Some(seg.offset(side * (t / 2.0 + if roof { app.opts.overhang } else { 0.0 })))
            })
            .collect();
        draw_segs(painter, xf, &segs, Stroke::new(2.5, style::PRESELECT));
        if clicked && kind == ToolKind::SketchLine {
            if let Some(sk) = app.sketch.as_mut() {
                for s in segs {
                    sk.push(s, app.opts.defines_slope);
                }
                join_sketch_corners(sk);
            }
            painter.ctx().memory_mut(|m| m.data.insert_temp::<Option<Id>>(chain_key, None));
        }
        return;
    }
    let Some(e) = app.el(id).cloned() else { return };
    let Some(mut seg) = element_curve(&e) else { return };
    let mut extra = app.opts.offset;
    if let (DrawMode::PickWalls, ElementKind::Wall(w)) = (mode, &e.kind) {
        let t = analysis::wall_thickness(&app.doc.data, w);
        let side = if (c - w.start).dot(w.normal()) >= 0.0 { 1.0 } else { -1.0 };
        let roof = app.sketch.as_ref().is_some_and(|s| s.kind.is_roof());
        extra = side * (t / 2.0 + if roof { app.opts.overhang } else { 0.0 });
        let _ = &mut seg;
    }
    let shown = seg.offset(extra);
    draw_segs(painter, xf, &[shown], Stroke::new(2.5, style::PRESELECT));
    if clicked {
        let segs = vec![shown];
        if kind == ToolKind::SketchLine {
            if let Some(sk) = app.sketch.as_mut() {
                sk.push(shown, app.opts.defines_slope);
                join_sketch_corners(sk);
            }
        } else {
            let saved = app.opts.offset;
            app.opts.offset = 0.0;
            commit_segs(app, view, &segs);
            app.opts.offset = saved;
        }
    }
}

/// Walls joined end to end with `start` (same base level), in no particular order.
fn wall_chain(p: &Project, start: Id) -> Vec<Id> {
    let Some(level) = p.wall(start).map(|w| w.base_level) else { return vec![] };
    let mut out = vec![start];
    let mut k = 0;
    while k < out.len() {
        if let Some(w) = p.wall(out[k]).cloned() {
            for pt in [w.start, w.end] {
                for (other, _) in crate::grips::walls_joined_at(p, pt, out[k]) {
                    if !out.contains(&other) && p.wall(other).is_some_and(|o| o.base_level == level) {
                        out.push(other);
                    }
                }
            }
        }
        k += 1;
    }
    out
}

/// Trims/extends sketch lines whose ends nearly meet so picked walls form closed loops.
pub fn join_sketch_corners(sk: &mut tools::Sketch) {
    let n = sk.segs.len();
    let reach = 1500.0;
    for i in 0..n {
        for j in 0..n {
            if i == j {
                continue;
            }
            let (Seg::Line(a0, a1), Seg::Line(b0, b1)) = (sk.segs[i], sk.segs[j]) else { continue };
            let da = (a1 - a0).normalize_or_zero();
            let db = (b1 - b0).normalize_or_zero();
            if da.dot(db).abs() > 0.999 {
                continue;
            }
            let Some(x) = geom::line_intersection(a0, da, b0, db) else { continue };
            // Move the nearer end of each line to the corner when both are close.
            let (ai, ad) = if a0.distance(x) < a1.distance(x) { (0, a0.distance(x)) } else { (1, a1.distance(x)) };
            let (bi, bd) = if b0.distance(x) < b1.distance(x) { (0, b0.distance(x)) } else { (1, b1.distance(x)) };
            if ad < reach && bd < reach && (ad > 1e-6 || bd > 1e-6) {
                if let Seg::Line(p0, p1) = &mut sk.segs[i] {
                    if ai == 0 { *p0 = x } else { *p1 = x }
                }
                if let Seg::Line(q0, q1) = &mut sk.segs[j] {
                    if bi == 0 { *q0 = x } else { *q1 = x }
                }
            }
        }
    }
}

fn do_fillet(app: &mut App, view: &View) {
    let r = app.opts.radius;
    let a = (app.tool.pts[0], app.tool.pts[1]);
    let b = (app.tool.pts[2], app.tool.pts[3]);
    let Some((pa, pb, arc)) = tools::fillet(a, b, r) else {
        app.error("These elements cannot be filleted (parallel or too short for the radius).");
        return;
    };
    let ids = app.tool.picked.clone();
    let corner = geom::line_intersection(a.0, (a.1 - a.0).normalize_or_zero(), b.0, (b.1 - b.0).normalize_or_zero()).unwrap_or(pa);
    // Sketch lines.
    if ids.iter().all(|i| *i > u32::MAX - 100_000) {
        if let Some(sk) = app.sketch.as_mut() {
            for (k, newp) in [(u32::MAX - ids[0], pa), (u32::MAX - ids[1], pb)] {
                if let Some(Seg::Line(s0, s1)) = sk.segs.get_mut(k as usize) {
                    if s0.distance(corner) < s1.distance(corner) { *s0 = newp } else { *s1 = newp }
                }
            }
            sk.push(arc, app.opts.defines_slope);
        }
        return;
    }
    let level = view.plan_level();
    let wall_type = app.doc.data.wall(ids[0]).map(|w| w.type_id);
    app.run("Fillet", |p| {
        for (id, newp) in [(ids[0], pa), (ids[1], pb)] {
            match p.element_mut(id).map(|e| &mut e.kind) {
                Some(ElementKind::Wall(w)) => {
                    if w.start.distance(corner) < w.end.distance(corner) { w.start = newp } else { w.end = newp }
                }
                Some(ElementKind::Line(l)) if l.pts.len() == 2 => {
                    if l.pts[0].distance(corner) < l.pts[1].distance(corner) { l.pts[0] = newp } else { l.pts[1] = newp }
                }
                _ => return Err("Fillet works on walls and lines.".into()),
            }
        }
        let Seg::Arc(s, m, e) = arc else { return Ok(()) };
        match (wall_type, level) {
            (Some(t), Some(l)) => {
                let h = p.wall(ids[0]).map(|w| w.unconnected_height).unwrap_or(3000.0);
                let top = p.wall(ids[0]).and_then(|w| w.top_level);
                let id = edit::add_wall_ex(p, l, t, s, e, Some(m), h, LocationLine::WallCenterline, false)?;
                if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
                    w.top_level = top;
                }
            }
            _ => {
                let style = match p.element(ids[0]).map(|e| &e.kind) {
                    Some(ElementKind::Line(l)) => l.style,
                    _ => LineStyle::Medium,
                };
                let (v, lv) = match p.element(ids[0]) {
                    Some(e) => (e.view, e.level()),
                    None => (None, None),
                };
                edit::add_line(p, v, lv, vec![s, e], Some(m), style)?;
            }
        }
        Ok(())
    });
}

// ---------------------------------------------------------------- doors and windows

fn hosted_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let Some(level) = view.plan_level() else { return };
    let is_door = app.tool.kind == ToolKind::Door;
    let type_id = if is_door { app.opts.door_type } else { app.opts.window_type };
    let wall = hover_of(app, view, d, c, xf, &|e| matches!(&e.kind, ElementKind::Wall(w) if w.base_level == level));
    let Some(wall_id) = wall else {
        if clicked {
            app.error(format!("{} must be hosted by a wall. Hover over a wall in this plan.", if is_door { "Doors" } else { "Windows" }));
        }
        return;
    };
    let p = &app.doc.data;
    let w = p.wall(wall_id).unwrap().clone();
    let width = p
        .family_type(type_id)
        .map(|(f, t)| rc_core::family_params::Resolver::for_type(f, t))
        .map(|r| r.num("Rough Width", r.num("Width", r.num("Diameter", 900.0))))
        .unwrap_or(900.0);
    let (mut along, side) = analysis::wall_project(&w, c);
    let len = w.length();
    // Snap the centre to the wall middle, else to round increments; keep it inside the wall.
    if (along - len / 2.0).abs() < xf.len(8.0) {
        along = len / 2.0;
    } else {
        let step = crate::snap::length_increment(xf.zoom, p.units.system == rc_core::units::UnitSystem::Imperial).max(10.0);
        along = (along / step).round() * step;
    }
    along = along.clamp(width / 2.0, (len - width / 2.0).max(width / 2.0));
    let (center, dir) = analysis::wall_point(&w, along);
    let n = geom::perp(dir);
    let t = analysis::wall_thickness(p, &w) / 2.0 + 20.0;
    let q = [center - dir * (width / 2.0) - n * t, center + dir * (width / 2.0) - n * t, center + dir * (width / 2.0) + n * t, center - dir * (width / 2.0) + n * t];
    painter.add(egui::Shape::closed_line(q.iter().map(|x| xf.s(*x)).collect(), Stroke::new(2.0, style::PREVIEW)));
    let flip = (side > 0.0) != app.opts.place_flip;
    if is_door {
        let s = if flip { 1.0 } else { -1.0 };
        let hinge = center - dir * (width / 2.0) + n * (s * t);
        let arc: Vec<Pos2> = (0..=16)
            .map(|k| {
                let a = std::f64::consts::FRAC_PI_2 * k as f64 / 16.0;
                xf.s(hinge + dir * (width * a.cos()) + n * (s * width * a.sin()))
            })
            .collect();
        painter.add(egui::Shape::line(arc, Stroke::new(1.0, style::PREVIEW)));
    }
    let units = p.units.clone();
    let (s0, _) = analysis::wall_point(&w, 0.0);
    let (s1, _) = analysis::wall_point(&w, len);
    temp_dim(painter, xf, s0, center, &units.length(along), 26.0);
    temp_dim(painter, xf, center, s1, &units.length(len - along), 26.0);
    if clicked {
        let tag = app.opts.tag_on_placement;
        let vid = view.id;
        let name = if is_door { "Place Door" } else { "Place Window" };
        let offset = n * (t + 600.0 * view.scale / 100.0) * if flip { 1.0 } else { -1.0 };
        let sill = if is_door { None } else { app.opts.window_sill };
        // Like the reference app, the tool stays active and nothing gets selected.
        app.run(name, |p| {
            let id = edit::place_hosted(p, type_id, wall_id, along, flip)?;
            if let Some(s) = sill {
                if let Some(i) = p.element_mut(id).and_then(|e| e.as_instance_mut()) {
                    i.elevation = s;
                }
            }
            if tag {
                edit::add_tag(p, vid, id, center + offset, false)?;
            }
            Ok(id)
        });
    }
}

// ---------------------------------------------------------------- free components

fn free_type(app: &App) -> Id {
    match app.tool.kind {
        ToolKind::Column => app.opts.column_type,
        ToolKind::StructColumn => app.opts.struct_column_type,
        ToolKind::IsolatedFooting => app.opts.footing_type,
        _ => app.opts.component_type,
    }
}

fn free_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, point: Option<DVec2>, clicked: bool) {
    let Some(pt) = point else { return };
    let Some(level) = view.plan_level() else { return };
    let ty = free_type(app);
    let Some((f, _)) = app.doc.data.family_type(ty) else {
        if clicked {
            app.error("Load or choose a family type first (Type Selector in Properties).");
        }
        return;
    };
    let inst = FamilyInstance { family_id: f.id, type_id: ty, category: f.category, level, location: pt, rotation_deg: app.opts.rotation, ..Default::default() };
    let outline = rc_core::family_geom::instance_outline(&app.doc.data, &inst);
    if outline.len() >= 2 {
        painter.add(egui::Shape::closed_line(outline.iter().map(|q| xf.s(*q)).collect(), preview_stroke()));
    } else {
        painter.circle_stroke(xf.s(pt), 8.0, preview_stroke());
    }
    if clicked {
        let rot = app.opts.rotation;
        let top = if matches!(app.tool.kind, ToolKind::Column | ToolKind::StructColumn) { app.opts.column_top } else { None };
        let height = app.opts.column_height;
        let name = format!("Place {}", app.tool.kind.name());
        if let Some(id) = app.run(&name, |p| {
            let id = edit::place_free(p, ty, level, pt, rot)?;
            if let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) {
                if let Some(t) = top {
                    i.top_level = Some(t);
                    i.top_offset = 0.0;
                } else if i.top_level.is_none() && matches!(i.category, Category::Columns | Category::StructuralColumns) {
                    i.values.insert("Height".into(), rc_core::units::to_stored(height));
                }
            }
            Ok(id)
        }) {
            app.select(vec![id]);
        }
    }
}

fn group_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, point: Option<DVec2>, clicked: bool) {
    let Some(pt) = point else { return };
    let Some(level) = view.plan_level() else { return };
    let ty = app.opts.group_type;
    if let Some(gt) = app.doc.data.group_types.iter().find(|g| g.id == ty) {
        // Preview: member wall/line axes offset to the cursor.
        for m in &gt.members {
            if let Some(s) = element_curve(m) {
                draw_segs(painter, xf, &[s.translated(pt)], preview_stroke());
            }
        }
    }
    painter.circle_stroke(xf.s(pt), 6.0, preview_stroke());
    if clicked {
        if let Some(id) = app.run("Place Group", |p| edit::place_group(p, ty, pt, level)) {
            app.select(vec![id]);
        }
    }
}

// ---------------------------------------------------------------- rooms, areas and tags

fn room_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let Some(level) = view.plan_level() else { return };
    let is_area = app.tool.kind == ToolKind::Area;
    let region = if is_area {
        match view.kind {
            ViewKind::AreaPlan { scheme, .. } => analysis::area_regions(&app.doc.data, level, scheme).into_iter().find(|r| geom::contains(&r.centerline, c)).map(|r| r.centerline),
            _ => None,
        }
    } else {
        analysis::find_enclosure(&app.doc.data, level, c).map(|b| b.interior)
    };
    if let Some(poly) = &region {
        if app.tool.kind == ToolKind::Room {
            canvas::paint_room_reference(painter, xf, poly, Color32::from_rgb(80, 170, 220));
            // The room tag follows the cursor.
            if app.opts.room_tag {
                // Same size as the placed tag (paper-scaled text).
                let p0 = xf.s(c);
                let (hn, hb) = (xf.text_px(3.0).max(6.0), xf.text_px(2.5).max(5.0));
                let name = painter.text(p0 + vec2(0.0, -hn * 0.15), egui::Align2::CENTER_BOTTOM, "Room", style::font(hn), Color32::from_gray(60));
                let num = painter.layout_no_wrap(rc_core::edit::next_room_number(&app.doc.data), style::font(hb), Color32::from_gray(60));
                let bx = egui::Rect::from_center_size(p0 + vec2(0.0, hb * 0.75), vec2(num.size().x.max(name.width() * 0.5) + hb, hb * 1.3));
                painter.rect_stroke(bx, 0.0, Stroke::new(1.0, Color32::from_gray(90)), egui::StrokeKind::Inside);
                painter.galley(bx.center() - num.size() / 2.0, num, Color32::from_gray(60));
            }
            style::canvas_tooltip(painter, xf.s(c) + vec2(4.0, 22.0), "Click to place room");
        } else {
            let tris = geom::triangulate(poly);
            let mut mesh = egui::Mesh::default();
            for [a, b, cc] in tris {
                let i = mesh.vertices.len() as u32;
                for q in [poly[a], poly[b], poly[cc]] {
                    mesh.colored_vertex(xf.s(q), Color32::from_rgba_unmultiplied(40, 120, 255, 40));
                }
                mesh.add_triangle(i, i + 1, i + 2);
            }
            painter.add(egui::Shape::mesh(mesh));
            painter.add(egui::Shape::closed_line(poly.iter().map(|q| xf.s(*q)).collect(), Stroke::new(1.5, style::PREVIEW)));
        }
    }
    if clicked {
        let tag = app.opts.room_tag;
        let vid = view.id;
        let upper = app.opts.room_upper;
        if app.tool.kind == ToolKind::CeilingAuto {
            let Some(poly) = region else {
                app.error("There is no enclosed region here. Click inside a room bounded by walls, or use Sketch Ceiling.");
                return;
            };
            let ty = app.opts.ceiling_type;
            let h = if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { 2438.4 } else { 2600.0 };
            if let Some(id) = app.run("Create Ceiling", |p| edit::add_ceiling(p, level, ty, poly, h)) {
                app.select(vec![id]);
            }
            return;
        }
        if is_area {
            let ViewKind::AreaPlan { scheme, .. } = view.kind else {
                app.error("Areas are placed in area plans. Create one with View > Plan Views > Area Plan.");
                return;
            };
            if let Some(id) = app.run("Place Area", |p| {
                let id = edit::add_area(p, level, scheme, c)?;
                if tag {
                    edit::add_tag(p, vid, id, c, false)?;
                }
                Ok(id)
            }) {
                app.select(vec![id]);
            }
        } else if let Some(id) = app.run("Place Room", |p| {
            let id = edit::add_room(p, level, c)?;
            if let Some(ElementKind::Room(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                r.upper_offset = upper;
            }
            if tag {
                edit::add_tag(p, vid, id, c, false)?;
            }
            Ok(id)
        }) {
            app.select(vec![id]);
        }
    }
}

fn tag_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let kind = app.tool.kind;
    let host = hover_of(app, view, d, c, xf, &|e| match kind {
        ToolKind::RoomTag => matches!(e.kind, ElementKind::Room(_)),
        ToolKind::AreaTag => matches!(e.kind, ElementKind::Area(_)),
        _ => e.view.is_none() && !matches!(e.kind, ElementKind::Level(_) | ElementKind::Grid(_) | ElementKind::RefPlane(_) | ElementKind::Room(_) | ElementKind::Area(_)) || matches!(e.kind, ElementKind::Room(_)),
    });
    let Some(h) = host else { return };
    let hp = app.el(h).map(|e| rc_core::annotation::host_point(&app.doc.data, e)).unwrap_or(c);
    let leader = app.opts.tag_leader;
    let at = if leader { c } else if matches!(kind, ToolKind::RoomTag | ToolKind::AreaTag) { c } else { hp };
    painter.circle_stroke(xf.s(at), 10.0, preview_stroke());
    if leader {
        painter.line_segment([xf.s(hp), xf.s(at)], preview_stroke());
    }
    if clicked {
        let vid = view.id;
        let horizontal = app.opts.tag_horizontal;
        if let Some(id) = app.run("Tag", |p| {
            let id = edit::add_tag(p, vid, h, at, leader)?;
            if leader {
                if let Some(ElementKind::Tag(t)) = p.element_mut(id).map(|e| &mut e.kind) {
                    t.leader_end = Some(hp);
                }
            }
            let _ = horizontal;
            Ok(id)
        }) {
            app.select(vec![id]);
        }
    }
}

// ---------------------------------------------------------------- levels, text

fn level_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, point: Option<DVec2>, clicked: bool) {
    if view.plan_level().is_some() || !view.is_graphical() || matches!(view.kind, ViewKind::Drafting | ViewKind::Legend) {
        app.interact.prompt = "Levels are added in sections and elevations. Open one from the Project Browser.".into();
        return;
    }
    let Some(pt) = point else { return };
    let y = pt.y;
    let a = app.tool.pts.first().copied().unwrap_or(pt);
    painter.extend(egui::Shape::dashed_line(&[xf.s(DVec2::new(a.x, y)), xf.s(DVec2::new(pt.x, y))], Stroke::new(1.5, style::PREVIEW), 10.0, 4.0));
    let units = app.doc.data.units.clone();
    painter.text(xf.s(pt) + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, units.length(y), egui::FontId::proportional(12.0), style::TEMP_DIM);
    if !clicked {
        return;
    }
    if app.tool.pts.is_empty() {
        app.tool.pts.push(pt);
        return;
    }
    app.tool.reset();
    let make_plan = app.opts.make_plan;
    app.run("Create Level", |p| {
        let n = p.levels().len() + 1;
        let name = edit::unique_name(p.levels().iter().map(|(_, l)| l.name.clone()), &format!("Level {n}"));
        if p.levels().iter().any(|(_, l)| (l.elevation - y).abs() < 1.0) {
            return Err("A level already exists at this elevation.".into());
        }
        Ok(rc_core::defaults::add_level(p, &name, y, make_plan))
    });
}

fn text_tool(app: &mut App, ui: &egui::Ui, xf: &Xf, view: &View, point: Option<DVec2>, clicked: bool) {
    if clicked && app.interact.text_input.is_none() {
        if let Some(pt) = point {
            app.interact.text_input = Some((pt, String::new(), true));
            return;
        }
    }
    let Some((pos, mut text, focus)) = app.interact.text_input.clone() else { return };
    let mut commit = false;
    let mut cancel = false;
    let screen = xf.s(pos);
    egui::Area::new(egui::Id::new("text-input"))
        .fixed_pos(screen)
        .order(egui::Order::Foreground)
        .show(ui.ctx(), |ui| {
            egui::Frame::popup(ui.style()).show(ui, |ui| {
                let r = ui.add(egui::TextEdit::multiline(&mut text).desired_width(220.0).desired_rows(2).hint_text("Type the note"));
                if focus {
                    r.request_focus();
                }
                ui.horizontal(|ui| {
                    if ui.button("Close").clicked() {
                        commit = true;
                    }
                    if ui.button("Cancel").clicked() {
                        cancel = true;
                    }
                });
                if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                    cancel = true;
                }
            });
        });
    if cancel {
        app.interact.text_input = None;
        return;
    }
    if commit || (clicked && !text.trim().is_empty()) {
        app.interact.text_input = None;
        if !text.trim().is_empty() {
            let (vid, size, bold, rot) = (view.id, app.opts.text_size, app.opts.text_bold, app.opts.rotation);
            if let Some(id) = app.run("Text", |p| {
                let id = edit::add_text(p, vid, pos, &text, size)?;
                if let Some(ElementKind::Text(t)) = p.element_mut(id).map(|e| &mut e.kind) {
                    t.bold = bold;
                    t.rotation_deg = rot;
                }
                Ok(id)
            }) {
                app.select(vec![id]);
            }
        }
        return;
    }
    app.interact.text_input = Some((pos, text, false));
}

// ---------------------------------------------------------------- dimensions

/// A dimension reference under the cursor and the line to highlight.
fn dim_ref_at(app: &App, view: &View, d: &Drawing, c: DVec2, xf: &Xf) -> Option<(DimRef, (DVec2, DVec2))> {
    let p = &app.doc.data;
    let tol = xf.len(8.0);
    let snap = app.interact.snap.as_ref();
    // Points from snaps (endpoints, intersections, centres) win when close.
    if let Some(s) = snap.filter(|s| matches!(s.kind, crate::snap::SnapKind::Endpoint | crate::snap::SnapKind::Intersection | crate::snap::SnapKind::Center | crate::snap::SnapKind::Midpoint)) {
        if s.point.distance(c) <= tol * 0.6 {
            let r = DimRef { element: None, part: RefPart::Point, point: s.point };
            return Some((r, (s.point, s.point)));
        }
    }
    if canvas::is_plan(view) {
        for id in canvas::pick_candidates(app, view, d, c, tol) {
            let Some(e) = app.el(id) else { continue };
            match &e.kind {
                ElementKind::Wall(w) if w.arc_mid.is_none() => {
                    let dir = w.direction();
                    let n = w.normal();
                    let ext = rc_core::annotation::wall_face_offset(p, w, true);
                    let int = rc_core::annotation::wall_face_offset(p, w, false);
                    let off = (c - w.start).dot(n);
                    let mut cands = vec![(RefPart::WallCenter, 0.0), (RefPart::WallExterior, ext), (RefPart::WallInterior, int)];
                    let prefer_faces = matches!(app.opts.dim_prefer, crate::tools::WallRefPref::Faces | crate::tools::WallRefPref::CoreFaces);
                    cands.sort_by(|a, b| {
                        let pa = (a.0 == RefPart::WallCenter) == prefer_faces;
                        let pb = (b.0 == RefPart::WallCenter) == prefer_faces;
                        ((a.1 - off).abs() + if pa { tol } else { 0.0 }).total_cmp(&((b.1 - off).abs() + if pb { tol } else { 0.0 }))
                    });
                    let (part, o) = cands[0].clone();
                    let a = w.start + n * o;
                    let b = w.end + n * o;
                    let foot = a + dir * (c - a).dot(dir);
                    return Some((DimRef { element: Some(id), part, point: foot }, (a, b)));
                }
                ElementKind::Grid(g) if g.arc_mid.is_none() => {
                    let dir = (g.end - g.start).normalize_or_zero();
                    let foot = g.start + dir * (c - g.start).dot(dir);
                    return Some((DimRef { element: Some(id), part: RefPart::GridLine, point: foot }, (g.start, g.end)));
                }
                ElementKind::RefPlane(r) => {
                    let dir = (r.end - r.start).normalize_or_zero();
                    let foot = r.start + dir * (c - r.start).dot(dir);
                    return Some((DimRef { element: Some(id), part: RefPart::RefPlane, point: foot }, (r.start, r.end)));
                }
                ElementKind::Instance(i) if i.host.is_none() && i.end.is_none() => {
                    let loc = analysis::instance_location(p, i);
                    return Some((DimRef { element: Some(id), part: RefPart::InstanceCenter, point: loc }, (loc, loc)));
                }
                ElementKind::Instance(i) if i.host.is_some() => {
                    let loc = analysis::instance_location(p, i);
                    return Some((DimRef { element: Some(id), part: RefPart::InstanceCenter, point: loc }, (loc, loc)));
                }
                _ => {}
            }
        }
    }
    // Straight lines in the drawing (sections, details): a point on the line.
    if let Some(s) = snap.filter(|s| s.kind == crate::snap::SnapKind::Nearest) {
        return Some((DimRef { element: None, part: RefPart::Point, point: s.point }, (s.point, s.point)));
    }
    None
}

fn ref_dir(app: &App, r: &DimRef) -> Option<DVec2> {
    rc_core::annotation::resolve(&app.doc.data, r).dir
}

fn dim_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, kind: DimKind, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let units = app.doc.data.units.clone();
    match kind {
        DimKind::SpotElevation => {
            let Some(pt) = point else { return };
            let z = spot_elevation(app, view, pt);
            painter.text(xf.s(pt) + vec2(12.0, -12.0), egui::Align2::LEFT_BOTTOM, units.length(z), egui::FontId::proportional(12.0), style::TEMP_DIM);
            painter.circle_stroke(xf.s(pt), 5.0, preview_stroke());
            if clicked {
                let vid = view.id;
                let txt = units.length(z);
                if let Some(id) = app.run("Spot Elevation", |p| {
                    let id = edit::add_symbol(p, vid, SymbolKind::SpotElevation, pt);
                    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                        s.value = txt;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
            }
            return;
        }
        DimKind::Radial | DimKind::Diameter | DimKind::ArcLength => {
            // Pick an arc (arc walls, arc lines, arc grids), then place.
            if app.tool.picked.is_empty() {
                let arc_el = hover_of(app, view, d, c, xf, &|e| element_curve(e).is_some_and(|s| matches!(s, Seg::Arc(..))));
                if let Some(id) = arc_el {
                    if let Some(s) = app.el(id).and_then(element_curve) {
                        draw_segs(painter, xf, &[s], Stroke::new(2.5, style::PRESELECT));
                        if clicked {
                            app.tool.picked.push(id);
                            if let Seg::Arc(a, m, b) = s {
                                app.tool.pts = vec![a, m, b];
                            }
                        }
                    }
                }
                return;
            }
            let (a, m, b) = (app.tool.pts[0], app.tool.pts[1], app.tool.pts[2]);
            let Some(arc) = geom::Arc2::through(a, m, b) else {
                app.tool.reset();
                return;
            };
            let dir = (c - arc.center).normalize_or_zero();
            let on = arc.center + dir * arc.radius;
            let (refs, preview): (Vec<DVec2>, String) = match kind {
                DimKind::Radial => (vec![arc.center, on], format!("R {}", units.length(arc.radius))),
                DimKind::Diameter => (vec![arc.center - dir * arc.radius, on], format!("⌀ {}", units.length(arc.radius * 2.0))),
                _ => (vec![a, m, b], units.length(arc.length())),
            };
            painter.line_segment([xf.s(refs[0]), xf.s(*refs.last().unwrap())], preview_stroke());
            painter.text(xf.s(c) + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, preview, egui::FontId::proportional(12.0), style::TEMP_DIM);
            if clicked {
                let vid = view.id;
                let rr: Vec<DimRef> = refs.iter().map(|q| DimRef { element: None, part: RefPart::Point, point: *q }).collect();
                if let Some(id) = app.run("Dimension", |p| {
                    let id = edit::add_dimension(p, vid, rr, DVec2::X, c)?;
                    if let Some(ElementKind::Dimension(dd)) = p.element_mut(id).map(|e| &mut e.kind) {
                        dd.kind = kind;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
                app.tool.reset();
            }
            return;
        }
        DimKind::Angular => {
            // Pick two lines; their intersection is the vertex; then place the arc.
            if app.tool.pts.len() < 4 {
                let line_el = hover_of(app, view, d, c, xf, &|e| element_curve(e).is_some_and(|s| matches!(s, Seg::Line(..))));
                let seg = line_el.and_then(|id| app.el(id).and_then(element_curve)).or_else(|| {
                    // Straight drawing lines (sections, details).
                    app.interact.snap.as_ref().filter(|s| s.kind == crate::snap::SnapKind::Nearest).and_then(|_| None)
                });
                if let Some(s) = seg {
                    draw_segs(painter, xf, &[s], Stroke::new(2.5, style::PRESELECT));
                    if clicked {
                        // Keep the picked side: the end nearer the click becomes the ray point.
                        let (a, b) = (s.start(), s.end());
                        let pick = c;
                        app.tool.pts.push(a);
                        app.tool.pts.push(b);
                        app.tool.refs.push(DimRef { element: None, part: RefPart::Point, point: pick });
                    }
                }
                return;
            }
            let (a0, a1, b0, b1) = (app.tool.pts[0], app.tool.pts[1], app.tool.pts[2], app.tool.pts[3]);
            let Some(v) = geom::line_intersection(a0, (a1 - a0).normalize_or_zero(), b0, (b1 - b0).normalize_or_zero()) else {
                app.error("The lines are parallel.");
                app.tool.reset();
                return;
            };
            // Rays towards the picked points; flipped to the cursor's quadrant.
            let pa = app.tool.refs[0].point;
            let pb = app.tool.refs[1].point;
            let mut da = (pa - v).normalize_or_zero();
            let mut db = (pb - v).normalize_or_zero();
            let cv = (c - v).normalize_or_zero();
            if cv.dot(da) < 0.0 && cv.dot(-da) > cv.dot(db) {
                da = -da;
            }
            if cv.dot(db) < 0.0 && cv.dot(-db) > cv.dot(da) {
                db = -db;
            }
            let r = c.distance(v);
            let ang = da.angle_to(db).abs().to_degrees();
            let arc: Vec<Pos2> = (0..=24).map(|k| xf.s(v + DVec2::from_angle(da.to_angle() + da.angle_to(db) * k as f64 / 24.0) * r)).collect();
            painter.add(egui::Shape::line(arc, preview_stroke()));
            painter.text(xf.s(c) + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, units.format(ang, ParamKind::Angle), egui::FontId::proportional(12.0), style::TEMP_DIM);
            if clicked {
                let vid = view.id;
                let rr = vec![
                    DimRef { element: None, part: RefPart::Point, point: v + da * r.max(1.0) },
                    DimRef { element: None, part: RefPart::Point, point: v },
                    DimRef { element: None, part: RefPart::Point, point: v + db * r.max(1.0) },
                ];
                if let Some(id) = app.run("Angular Dimension", |p| {
                    let id = edit::add_dimension(p, vid, rr, DVec2::X, c)?;
                    if let Some(ElementKind::Dimension(dd)) = p.element_mut(id).map(|e| &mut e.kind) {
                        dd.kind = DimKind::Angular;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
                app.tool.reset();
            }
            return;
        }
        _ => {}
    }
    // Aligned / linear.
    let hover = dim_ref_at(app, view, d, c, xf);
    if let Some((_, (a, b))) = &hover {
        if a.distance(*b) < 1e-6 {
            painter.circle_stroke(xf.s(*a), 6.0, Stroke::new(2.0, style::PRESELECT));
        } else {
            painter.line_segment([xf.s(*a), xf.s(*b)], Stroke::new(3.0, style::PRESELECT));
        }
    }
    let refs = app.tool.refs.clone();
    // Measuring direction.
    let dir = if refs.is_empty() {
        None
    } else if kind == DimKind::Linear {
        let lo = refs.iter().map(|r| rc_core::annotation::resolve(&app.doc.data, r).point).fold(DVec2::splat(f64::MAX), |a, b| a.min(b));
        let hi = refs.iter().map(|r| rc_core::annotation::resolve(&app.doc.data, r).point).fold(DVec2::splat(f64::MIN), |a, b| a.max(b));
        let mid = (lo + hi) / 2.0;
        Some(if (c.y - mid.y).abs() > (c.x - mid.x).abs() { DVec2::X } else { DVec2::Y })
    } else {
        match ref_dir(app, &refs[0]) {
            Some(d0) => Some(geom::perp(d0)),
            None if refs.len() >= 2 => {
                let a = rc_core::annotation::resolve(&app.doc.data, &refs[0]).point;
                let b = rc_core::annotation::resolve(&app.doc.data, &refs[1]).point;
                Some((b - a).normalize_or_zero())
            }
            None => hover.as_ref().map(|(r, _)| (rc_core::annotation::resolve(&app.doc.data, r).point - rc_core::annotation::resolve(&app.doc.data, &refs[0]).point).normalize_or_zero()),
        }
    };
    // Preview of the dimension line through the cursor.
    if let Some(dir) = dir.filter(|d| *d != DVec2::ZERO) {
        let mut all = refs.clone();
        if let Some((r, _)) = &hover {
            all.push(r.clone());
        }
        if all.len() >= 2 {
            let n = geom::perp(dir);
            let off = c.dot(n);
            let mut coords: Vec<f64> = all.iter().map(|r| rc_core::annotation::resolve(&app.doc.data, r).point.dot(dir)).collect();
            for (k, r) in all.iter().enumerate() {
                let q = rc_core::annotation::resolve(&app.doc.data, r).point;
                painter.line_segment([xf.s(q), xf.s(dir * coords[k] + n * off)], Stroke::new(1.0, style::PREVIEW));
            }
            coords.sort_by(f64::total_cmp);
            for w in coords.windows(2) {
                let a = dir * w[0] + n * off;
                let b = dir * w[1] + n * off;
                temp_dim(painter, xf, a, b, &units.length(w[1] - w[0]), 0.0);
            }
        }
    }
    if !clicked {
        return;
    }
    match hover {
        Some((r, _)) => {
            // Parallel check for aligned dims.
            if kind == DimKind::Aligned && !refs.is_empty() {
                if let (Some(d0), Some(d1)) = (ref_dir(app, &refs[0]), ref_dir(app, &r)) {
                    if d0.dot(d1).abs() < 0.999 {
                        app.error("Aligned dimensions need parallel references.");
                        return;
                    }
                }
            }
            app.tool.refs.push(r);
        }
        None => {
            if refs.len() >= 2 {
                let Some(dir) = dir.filter(|d| *d != DVec2::ZERO) else { return };
                let vid = view.id;
                if let Some(id) = app.run("Dimension", |p| {
                    let id = edit::add_dimension(p, vid, refs, dir, c)?;
                    if let Some(ElementKind::Dimension(dd)) = p.element_mut(id).map(|e| &mut e.kind) {
                        dd.kind = kind;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
                app.tool.reset();
            }
        }
    }
}

/// Elevation at a plan point: the top of a floor under it, else the level.
fn spot_elevation(app: &App, view: &View, pt: DVec2) -> f64 {
    let p = &app.doc.data;
    let Some(level) = view.plan_level() else { return pt.y };
    let mut z = p.level_elevation(level);
    for e in &p.elements {
        if let ElementKind::Floor(f) = &e.kind {
            if f.level == level && geom::contains(&f.boundary, pt) {
                z = analysis::floor_top_at(p, f, pt);
            }
        }
    }
    z
}

// ---------------------------------------------------------------- view markers

fn view_marker_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, point: Option<DVec2>, clicked: bool) {
    let Some(pt) = point else { return };
    let kind = app.tool.kind;
    let a = app.tool.pts.first().copied();
    match (kind, a) {
        (ToolKind::Section, Some(a)) => {
            let d = (pt - a).normalize_or_zero();
            let look = -geom::perp(d);
            let depth = app.opts.section_depth;
            painter.line_segment([xf.s(a), xf.s(pt)], Stroke::new(2.0, style::PREVIEW));
            let far = [a + look * depth, pt + look * depth];
            painter.extend(egui::Shape::dashed_line(&[xf.s(a), xf.s(far[0]), xf.s(far[1]), xf.s(pt)], Stroke::new(1.0, style::PREVIEW), 6.0, 4.0));
        }
        (ToolKind::Callout, Some(a)) => {
            painter.rect_stroke(egui::Rect::from_two_pos(xf.s(a), xf.s(pt)), 0.0, Stroke::new(1.5, style::PREVIEW), egui::StrokeKind::Middle);
        }
        (ToolKind::ElevationMarker, _) => {
            let dir = elevation_dir_toward(app, pt);
            let look = dir.look().truncate();
            let r = 5.0 * view.scale;
            painter.circle_stroke(xf.s(pt), (r * xf.zoom) as f32, preview_stroke());
            painter.line_segment([xf.s(pt), xf.s(pt + look * r * 1.8)], preview_stroke());
        }
        _ => {}
    }
    if !clicked {
        return;
    }
    match (kind, a) {
        (ToolKind::Section, None) | (ToolKind::Callout, None) => app.tool.pts.push(pt),
        (ToolKind::Section, Some(a)) => {
            app.tool.reset();
            let depth = app.opts.section_depth;
            if let Some(id) = app.run("Create Section", |p| edit::new_section(p, a, pt, depth)) {
                app.select(vec![id]);
            }
        }
        (ToolKind::Callout, Some(a)) => {
            app.tool.reset();
            let parent = view.id;
            if let Some(id) = app.run("Create Callout", |p| edit::new_callout(p, parent, a, pt)) {
                app.select(vec![id]);
            }
        }
        (ToolKind::ElevationMarker, _) => {
            let dir = elevation_dir_toward(app, pt);
            let scale = view.scale;
            if let Some(id) = app.run("Create Elevation", |p| {
                let id = p.new_id();
                let n = p.views.iter().filter(|v| matches!(v.kind, ViewKind::Elevation { .. })).count() + 1;
                let name = edit::unique_name(p.views.iter().map(|v| v.name.clone()), &format!("Elevation {n} - {}", dir.label()));
                let mut v = View::new(id, name, scale, ViewKind::Elevation { dir });
                v.marker = Some((pt, dir.look().truncate()));
                p.views.push(v);
                Ok(id)
            }) {
                app.select(vec![id]);
            }
        }
        _ => {}
    }
}

fn elevation_dir_toward(app: &App, pt: DVec2) -> ElevationDir {
    let c = app.cache.bounds.flatten().map(|(mn, mx)| ((mn + mx) / 2.0).truncate()).unwrap_or(DVec2::ZERO);
    let v = c - pt;
    if v.x.abs() > v.y.abs() {
        if v.x > 0.0 { ElevationDir::West } else { ElevationDir::East }
    } else if v.y > 0.0 {
        ElevationDir::South
    } else {
        ElevationDir::North
    }
}

// ---------------------------------------------------------------- wall-picking tools

fn wall_pick_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let Some(level) = view.plan_level() else { return };
    let kind = app.tool.kind;
    let curtain_only = kind == ToolKind::CurtainGrid;
    let first_wall = app.tool.picked.first().copied();
    let wall = match first_wall {
        Some(w) if kind == ToolKind::WallOpening => Some(w),
        _ => {
            let p = &app.doc.data;
            hover_of(app, view, d, c, xf, &|e| matches!(&e.kind, ElementKind::Wall(w) if w.base_level == level && (!curtain_only || analysis::is_curtain(p, w))))
        }
    };
    let Some(wid) = wall else { return };
    let p = &app.doc.data;
    let w = p.wall(wid).unwrap().clone();
    let t = analysis::wall_thickness(p, &w);
    let units = p.units.clone();
    let at = point.unwrap_or(c);
    let (u, _) = analysis::wall_project(&w, at);
    let (q, dir) = analysis::wall_point(&w, u.clamp(0.0, w.length()));
    let n = geom::perp(dir);
    match kind {
        ToolKind::WallFoundation => {
            draw_segs(painter, xf, &[element_curve(app.el(wid).unwrap()).unwrap()], Stroke::new(3.0, style::PRESELECT));
            if clicked {
                let ft = app.opts.foundation_type;
                if let Some(id) = app.run("Wall Foundation", |p| edit::add_wall_foundation(p, wid, ft)) {
                    app.select(vec![id]);
                }
            }
        }
        ToolKind::CurtainGrid => {
            painter.line_segment([xf.s(q - n * (t / 2.0 + 200.0)), xf.s(q + n * (t / 2.0 + 200.0))], Stroke::new(2.0, Color32::from_rgb(220, 40, 40)));
            temp_dim(painter, xf, analysis::wall_point(&w, 0.0).0, q, &units.length(u), 22.0);
            if clicked {
                app.run("Add Curtain Grid", |p| {
                    let (gu, gv) = rc_core::build3d::curtain_grid(p, &w);
                    let wall = p.element_mut(wid).and_then(Element::as_wall_mut).ok_or("Wall not found.")?;
                    let grid = wall.curtain.get_or_insert_with(|| CurtainGrid { u: gu, v: gv, panels: Default::default() });
                    if grid.u.iter().any(|x| (x - u).abs() < 50.0) {
                        return Err("There is already a grid line here.".into());
                    }
                    grid.u.push(u);
                    grid.u.sort_by(f64::total_cmp);
                    Ok(())
                });
            }
        }
        ToolKind::WallOpening => {
            painter.line_segment([xf.s(q - n * (t / 2.0 + 100.0)), xf.s(q + n * (t / 2.0 + 100.0))], Stroke::new(2.0, style::PREVIEW));
            if let Some(u0) = app.tool.pts.first().map(|p| p.x) {
                let (q0, _) = analysis::wall_point(&w, u0);
                temp_dim(painter, xf, q0, q, &units.length((u - u0).abs()), 22.0);
            }
            if clicked {
                if app.tool.picked.is_empty() {
                    app.tool.picked.push(wid);
                    app.tool.pts.push(DVec2::new(u, 0.0));
                } else {
                    let u0 = app.tool.pts[0].x;
                    let (z0, z1) = (app.opts.opening_sill, app.opts.opening_sill + app.opts.opening_height);
                    app.run("Wall Opening", |p| edit::add_wall_opening(p, wid, u0, u, z0, z1));
                    app.tool.reset();
                }
            }
        }
        _ => {}
    }
}

// ---------------------------------------------------------------- modify tools

fn selection_center(app: &App) -> DVec2 {
    let p = &app.doc.data;
    let fp = app.footprints();
    let pts: Vec<DVec2> = app
        .selection
        .iter()
        .filter_map(|id| p.element(*id))
        .flat_map(|e| rc_core::plan::element_outline(p, e, &fp).into_iter().flatten())
        .collect();
    if pts.is_empty() {
        return DVec2::ZERO;
    }
    let (mn, mx) = geom::bounds(pts);
    (mn + mx) / 2.0
}

fn modify_tool(app: &mut App, ui: &egui::Ui, resp: &egui::Response, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let kind = app.tool.kind;
    let units = app.doc.data.units.clone();
    let tol = xf.len(8.0);
    let linear = |e: &Element| element_curve(e).is_some();
    match kind {
        ToolKind::Move | ToolKind::Copy | ToolKind::Paste => {
            let Some(pt) = point else { return };
            let start = if kind == ToolKind::Paste { app.clipboard.as_ref().map(|c| c.base) } else { app.tool.pts.first().copied() };
            if let Some(a) = start {
                let pt = if app.opts.constrain { constrain_ortho(a, pt) } else { pt };
                let delta = pt - a;
                if kind != ToolKind::Paste {
                    painter.line_segment([xf.s(a), xf.s(pt)], preview_stroke());
                    temp_dim(painter, xf, a, pt, &units.length(a.distance(pt)), -18.0);
                }
                ghost_selection(app, painter, xf, d, delta, kind == ToolKind::Paste);
                if clicked {
                    match kind {
                        ToolKind::Paste => {
                            crate::actions::paste_at(app, delta, view.plan_level());
                            app.set_tool(ToolKind::Select);
                        }
                        ToolKind::Copy => {
                            let ids = app.tool.ids.clone();
                            if let Some(new) = app.run("Copy", |p| Ok(edit::copy_elements(p, &ids, delta))) {
                                if !app.opts.copy_multiple {
                                    app.select(new);
                                    app.set_tool(ToolKind::Select);
                                }
                            }
                        }
                        _ => {
                            let ids = app.tool.ids.clone();
                            app.run("Move", |p| {
                                edit::move_elements(p, &ids, delta);
                                Ok(())
                            });
                            app.set_tool(ToolKind::Select);
                        }
                    }
                    app.typed.clear();
                }
            } else if clicked {
                app.tool.pts.push(pt);
            }
        }
        ToolKind::Rotate => {
            if app.tool.pts.is_empty() && app.tool.picked.first() != Some(&u32::MAX) {
                app.tool.pts.push(selection_center(app));
            }
            let Some(pt) = point else { return };
            if app.tool.picked.first() == Some(&u32::MAX) {
                painter.circle_stroke(xf.s(pt), 6.0, preview_stroke());
                if clicked {
                    app.tool.picked.clear();
                    app.tool.pts = vec![pt];
                }
                return;
            }
            let center = app.tool.pts[0];
            painter.circle_stroke(xf.s(center), 7.0, Stroke::new(2.0, style::SELECT));
            painter.circle_filled(xf.s(center), 2.5, style::SELECT);
            if app.tool.pts.len() == 1 {
                painter.line_segment([xf.s(center), xf.s(pt)], preview_stroke());
                // Typed angle relative to the x axis with Enter.
                if app.interact.pending_enter || (clicked && !app.typed.is_empty()) {
                    if let Some(a) = units.parse(app.typed.trim(), ParamKind::Angle) {
                        rotate_now(app, center, a);
                    }
                    return;
                }
                if clicked {
                    app.tool.pts.push(pt);
                }
            } else {
                let start = app.tool.pts[1];
                let a0 = (start - center).y.atan2((start - center).x);
                let a1 = (pt - center).y.atan2((pt - center).x);
                let mut ang = (a1 - a0).to_degrees();
                if ang > 180.0 {
                    ang -= 360.0;
                }
                if ang < -180.0 {
                    ang += 360.0;
                }
                let r = center.distance(pt);
                painter.line_segment([xf.s(center), xf.s(start)], preview_stroke());
                painter.line_segment([xf.s(center), xf.s(pt)], preview_stroke());
                let arc: Vec<Pos2> = (0..=24).map(|k| xf.s(center + DVec2::from_angle(a0 + (ang.to_radians()) * k as f64 / 24.0) * r * 0.6)).collect();
                painter.add(egui::Shape::line(arc, preview_stroke()));
                painter.text(xf.s(pt) + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, units.format(ang, ParamKind::Angle), egui::FontId::proportional(12.0), style::TEMP_DIM);
                ghost_rotate(app, painter, xf, d, center, ang);
                if clicked {
                    rotate_now(app, center, ang);
                }
            }
        }
        ToolKind::MirrorDraw => {
            let Some(pt) = point else { return };
            if let Some(a) = app.tool.pts.first().copied() {
                painter.extend(egui::Shape::dashed_line(&[xf.s(a), xf.s(pt)], preview_stroke(), 8.0, 4.0));
                if clicked {
                    mirror_now(app, a, pt);
                }
            } else if clicked {
                app.tool.pts.push(pt);
            }
        }
        ToolKind::MirrorPick => {
            let axis = hover_of(app, view, d, c, xf, &linear).and_then(|id| app.el(id).and_then(element_curve));
            if let Some(Seg::Line(a, b)) = axis {
                painter.line_segment([xf.s(a), xf.s(b)], Stroke::new(3.0, style::PRESELECT));
                if clicked {
                    mirror_now(app, a, b);
                }
            }
        }
        ToolKind::Align => {
            let line = align_ref_at(app, view, d, c, xf);
            if let Some((a, b)) = line {
                if a.distance(b) > 1e-6 {
                    painter.line_segment([xf.s(a), xf.s(b)], Stroke::new(2.5, style::PRESELECT));
                }
            }
            if app.tool.pts.len() == 2 {
                let (ra, rb) = (app.tool.pts[0], app.tool.pts[1]);
                painter.extend(egui::Shape::dashed_line(&[xf.s(ra), xf.s(rb)], Stroke::new(1.5, Color32::from_rgb(220, 40, 40)), 8.0, 4.0));
            }
            if clicked {
                if app.tool.pts.len() < 2 {
                    if let Some((a, b)) = line {
                        let b = if a.distance(b) < 1e-6 { a + DVec2::Y } else { b };
                        app.tool.pts = vec![a, b];
                    }
                } else if let Some(target) = canvas::pick_candidates(app, view, d, c, tol).first().copied() {
                    let (ra, rb) = (app.tool.pts[0], app.tool.pts[1]);
                    app.run("Align", |p| edit::align(p, ra, rb, target, c));
                    if !app.opts.align_multiple {
                        app.tool.reset();
                    }
                }
            }
        }
        ToolKind::Offset => {
            let target = hover_of(app, view, d, c, xf, &linear);
            if let Some(id) = target {
                if let Some(s) = app.el(id).and_then(element_curve) {
                    let dist = app.opts.offset_dist;
                    // Side of the cursor.
                    let side = match s {
                        Seg::Line(a, b) => if geom::cross2(b - a, c - a) >= 0.0 { 1.0 } else { -1.0 },
                        Seg::Arc(..) => 1.0,
                    };
                    draw_segs(painter, xf, &[s], Stroke::new(2.5, style::PRESELECT));
                    draw_segs(painter, xf, &[s.offset(side * dist)], Stroke::new(1.5, style::PREVIEW));
                    if clicked {
                        let copy = app.opts.offset_copy;
                        app.run("Offset", |p| edit::offset_elements(p, &[id], dist, c, copy).map(|_| ()));
                    }
                }
            }
        }
        ToolKind::TrimCorner | ToolKind::TrimSingle | ToolKind::TrimMulti => {
            let target = hover_of(app, view, d, c, xf, &|e| matches!(element_curve(e), Some(Seg::Line(..))));
            if let Some(s) = target.and_then(|id| app.el(id).and_then(element_curve)) {
                draw_segs(painter, xf, &[s], Stroke::new(2.5, style::PRESELECT));
            }
            for id in &app.tool.picked {
                if let Some(s) = app.el(*id).and_then(element_curve) {
                    draw_segs(painter, xf, &[s], Stroke::new(2.5, style::SELECT));
                }
            }
            if clicked {
                let Some(id) = target else { return };
                if app.tool.picked.is_empty() {
                    app.tool.picked.push(id);
                    app.tool.pts.push(c);
                    return;
                }
                let first = app.tool.picked[0];
                let keep0 = app.tool.pts[0];
                match kind {
                    ToolKind::TrimCorner => {
                        app.run("Trim/Extend", |p| edit::trim_extend_corner(p, first, keep0, id, c));
                        app.tool.reset();
                    }
                    ToolKind::TrimSingle => {
                        app.run("Trim/Extend", |p| edit::trim_extend_to(p, first, &[(id, c)]));
                        app.tool.reset();
                    }
                    _ => {
                        app.run("Trim/Extend", |p| edit::trim_extend_to(p, first, &[(id, c)]));
                    }
                }
            }
        }
        ToolKind::Split | ToolKind::SplitGap => {
            let target = hover_of(app, view, d, c, xf, &|e| matches!(element_curve(e), Some(Seg::Line(..))));
            if let Some(s) = target.and_then(|id| app.el(id).and_then(element_curve)) {
                let (q, _) = geom::closest_on_segment(s.start(), s.end(), point.unwrap_or(c));
                let dir = (s.end() - s.start()).normalize_or_zero();
                let n = geom::perp(dir);
                painter.line_segment([xf.s(q - n * xf.len(12.0)), xf.s(q + n * xf.len(12.0))], Stroke::new(2.0, Color32::from_rgb(220, 40, 40)));
                temp_dim(painter, xf, s.start(), q, &units.length(s.start().distance(q)), 18.0);
                if clicked {
                    let id = target.unwrap();
                    let gap = if kind == ToolKind::SplitGap { app.opts.split_gap } else { 0.0 };
                    app.run("Split", |p| edit::split_element(p, id, q, gap).map(|_| ()));
                }
            }
        }
        ToolKind::Array => {
            let Some(pt) = point else { return };
            let n = app.opts.array_count.max(2) as usize;
            if app.opts.array_radial {
                let center = *app.tool.pts.first().unwrap_or(&selection_center(app));
                if app.tool.pts.is_empty() {
                    app.tool.pts.push(center);
                }
                if app.tool.pts.len() == 1 {
                    painter.line_segment([xf.s(center), xf.s(pt)], preview_stroke());
                    if clicked {
                        app.tool.pts.push(pt);
                    }
                } else {
                    let start = app.tool.pts[1];
                    let a0 = (start - center).y.atan2((start - center).x);
                    let a1 = (pt - center).y.atan2((pt - center).x);
                    let mut ang = (a1 - a0).to_degrees();
                    if ang <= 0.0 {
                        ang += 360.0;
                    }
                    painter.text(xf.s(pt) + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, units.format(ang, ParamKind::Angle), egui::FontId::proportional(12.0), style::TEMP_DIM);
                    if clicked {
                        let ids = app.tool.ids.clone();
                        app.run("Radial Array", |p| edit::array_radial(p, &ids, center, ang, n).map(|_| ()));
                        app.set_tool(ToolKind::Select);
                    }
                }
            } else if let Some(a) = app.tool.pts.first().copied() {
                let pt = if app.opts.constrain { constrain_ortho(a, pt) } else { pt };
                let step = if app.opts.array_last { (pt - a) / (n - 1) as f64 } else { pt - a };
                for k in 1..n {
                    ghost_selection(app, painter, xf, d, step * k as f64, false);
                }
                temp_dim(painter, xf, a, pt, &units.length(a.distance(pt)), -18.0);
                if clicked {
                    let ids = app.tool.ids.clone();
                    app.run("Array", |p| edit::array_linear(p, &ids, step, n).map(|_| ()));
                    app.set_tool(ToolKind::Select);
                }
            } else if clicked {
                app.tool.pts.push(pt);
            }
        }
        ToolKind::Scale => {
            let Some(pt) = point else { return };
            painter.circle_stroke(xf.s(pt), 6.0, preview_stroke());
            if clicked {
                let ids = app.tool.ids.clone();
                let f = app.opts.scale_factor;
                app.run("Scale", |p| edit::scale_elements(p, &ids, pt, f));
                app.set_tool(ToolKind::Select);
            }
        }
        ToolKind::MatchType => {
            let target = canvas::pick_candidates(app, view, d, c, tol).into_iter().find(|id| app.el(*id).is_some_and(|e| app.doc.data.type_of(e).is_some()));
            if let Some(id) = target {
                if let Some(e) = app.el(id) {
                    app.interact.prompt = format!("{}  —  {}", crate::canvas_tools::prompt(app), app.doc.data.display_name(e));
                }
            }
            if clicked {
                if let Some(id) = target {
                    if app.tool.picked.is_empty() {
                        app.tool.picked.push(id);
                    } else {
                        let src = app.tool.picked[0];
                        app.run("Match Type", |p| edit::match_type(p, src, &[id]));
                    }
                }
            }
        }
        ToolKind::Measure => {
            let Some(pt) = point else { return };
            if let Some(a) = app.tool.pts.first().copied() {
                temp_dim(painter, xf, a, pt, &units.length(a.distance(pt)), -18.0);
                if clicked {
                    app.interact.measure = Some((a, pt));
                    app.info(format!("Length: {}   ΔX: {}   ΔY: {}", units.length(a.distance(pt)), units.length((pt.x - a.x).abs()), units.length((pt.y - a.y).abs())));
                    app.tool.reset();
                }
            } else if clicked {
                app.interact.measure = None;
                app.tool.pts.push(pt);
            }
        }
        ToolKind::ZoomRegion => {
            if resp.drag_started_by(egui::PointerButton::Primary) {
                if let Some(s) = ui.input(|i| i.pointer.press_origin()) {
                    app.interact.drag = Some(Drag::ZoomRegion { start: xf.w(s) });
                }
            }
            let start = match &app.interact.drag {
                Some(Drag::ZoomRegion { start }) => Some(*start),
                _ => app.tool.pts.first().copied(),
            };
            if let Some(a) = start {
                painter.rect_stroke(egui::Rect::from_two_pos(xf.s(a), xf.s(c)), 0.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Middle);
                if resp.drag_stopped() || (clicked && app.interact.drag.is_none()) {
                    zoom_to(app, view.id, xf, a, c);
                    app.interact.drag = None;
                    app.set_tool(ToolKind::Select);
                }
            } else if clicked {
                app.tool.pts.push(c);
            }
        }
        ToolKind::AttachTop | ToolKind::AttachBase => {
            let target = hover_of(app, view, d, c, xf, &|e| matches!(e.kind, ElementKind::Roof(_) | ElementKind::Floor(_) | ElementKind::Ceiling(_)));
            if let Some(t) = target {
                app.interact.hover = Some(t);
                if clicked {
                    let walls: Vec<Id> = app.tool.ids.iter().copied().filter(|id| app.doc.data.wall(*id).is_some()).collect();
                    let top = kind == ToolKind::AttachTop;
                    app.run(if top { "Attach Top" } else { "Attach Base" }, |p| edit::attach_walls(p, &walls, t, top));
                    app.set_tool(ToolKind::Select);
                }
            }
        }
        ToolKind::PickHost => {
            let Some(level) = view.plan_level() else { return };
            let wall = hover_of(app, view, d, c, xf, &|e| matches!(&e.kind, ElementKind::Wall(w) if w.base_level == level));
            if let (Some(wid), true) = (wall, clicked) {
                let ids = app.tool.ids.clone();
                app.run("Pick New Host", |p| {
                    let w = p.wall(wid).ok_or("Wall not found.")?.clone();
                    let (along, _) = analysis::wall_project(&w, c);
                    for id in &ids {
                        let inst = p.element(*id).and_then(Element::as_instance).cloned().ok_or("Select doors or windows.")?;
                        if inst.host.is_none() {
                            continue;
                        }
                        let (ow, oh) = analysis::opening_size(p, &inst);
                        edit::check_opening_fits(p, &w, wid, Some(*id), along, ow, inst.elevation, oh)?;
                        let i = p.element_mut(*id).and_then(Element::as_instance_mut).unwrap();
                        i.host = Some(wid);
                        i.offset_along_host = along;
                        i.level = w.base_level;
                    }
                    Ok(())
                });
                app.set_tool(ToolKind::Select);
            }
        }
        _ => {}
    }
}

fn constrain_ortho(a: DVec2, pt: DVec2) -> DVec2 {
    let d = pt - a;
    if d.x.abs() >= d.y.abs() { DVec2::new(pt.x, a.y) } else { DVec2::new(a.x, pt.y) }
}

fn rotate_now(app: &mut App, center: DVec2, ang: f64) {
    let ids = app.tool.ids.clone();
    let copy = app.opts.rotate_copy;
    app.run("Rotate", |p| {
        let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
        edit::rotate_elements(p, &targets, center, ang);
        Ok(())
    });
    app.typed.clear();
    app.set_tool(ToolKind::Select);
}

fn mirror_now(app: &mut App, a: DVec2, b: DVec2) {
    let ids = app.tool.ids.clone();
    let copy = app.opts.mirror_copy;
    app.run("Mirror", |p| {
        let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
        edit::mirror_elements(p, &targets, a, b);
        Ok(())
    });
    app.set_tool(ToolKind::Select);
}

/// Reference line for Align: wall faces/centres, grids, ref planes, lines, or snapped points.
fn align_ref_at(app: &App, view: &View, d: &Drawing, c: DVec2, xf: &Xf) -> Option<(DVec2, DVec2)> {
    if let Some((r, line)) = dim_ref_at(app, view, d, c, xf) {
        let res = rc_core::annotation::resolve(&app.doc.data, &r);
        if line.0.distance(line.1) > 1e-6 {
            return Some(line);
        }
        return Some((res.point, res.point));
    }
    hover_of(app, view, d, c, xf, &|e| element_curve(e).is_some()).and_then(|id| app.el(id).and_then(element_curve)).map(|s| (s.start(), s.end()))
}

fn ghost_selection(app: &App, painter: &egui::Painter, xf: &Xf, d: &Drawing, delta: DVec2, clipboard: bool) {
    let st = Stroke::new(1.2, style::PREVIEW);
    if clipboard {
        if let Some(cb) = &app.clipboard {
            for e in &cb.elements {
                if let Some(s) = element_curve(e) {
                    draw_segs(painter, xf, &[s.translated(delta)], st);
                }
            }
        }
        return;
    }
    let ids: std::collections::HashSet<Id> = app.tool.ids.iter().copied().collect();
    for (id, prim) in &d.prims {
        if !id.is_some_and(|i| ids.contains(&i)) {
            continue;
        }
        if let rc_core::plan::Prim::Line { pts, closed, .. } = prim {
            let v: Vec<Pos2> = pts.iter().map(|q| xf.s(*q + delta)).collect();
            canvas::paint_polyline(painter, &v, *closed, st, Dash::Solid, xf);
        }
    }
}

fn ghost_rotate(app: &App, painter: &egui::Painter, xf: &Xf, d: &Drawing, center: DVec2, deg: f64) {
    let ids: std::collections::HashSet<Id> = app.tool.ids.iter().copied().collect();
    let r = DVec2::from_angle(deg.to_radians());
    let st = Stroke::new(1.2, style::PREVIEW);
    for (id, prim) in &d.prims {
        if !id.is_some_and(|i| ids.contains(&i)) {
            continue;
        }
        if let rc_core::plan::Prim::Line { pts, closed, .. } = prim {
            let v: Vec<Pos2> = pts.iter().map(|q| xf.s(center + r.rotate(*q - center))).collect();
            canvas::paint_polyline(painter, &v, *closed, st, Dash::Solid, xf);
        }
    }
}

pub fn zoom_to(app: &mut App, view: Id, xf: &Xf, a: DVec2, b: DVec2) {
    let size = (b - a).abs().max(DVec2::splat(100.0));
    let zoom = (xf.rect.width() as f64 / size.x).min(xf.rect.height() as f64 / size.y);
    app.cams.insert(view, canvas::Cam2 { center: (a + b) / 2.0, zoom, fitted: true });
}
