//! What each tool does with cursor moves and clicks in a 2D view: previews, temporary
//! dimensions, prompts and the model changes.

use crate::app::App;
use crate::canvas::{self, Drag, Xf, temp_dim};
use crate::style;
use crate::tools::{self, DrawMode, Seg, SketchKind, SketchSub, Tool, ToolKind};
use eframe::egui::{self, Color32, Pos2, Stroke, vec2};
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
        ToolKind::SketchLine => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, Spline, Ellipse, PartialEllipse, PickLines, PickWalls],
        ToolKind::ModelLine | ToolKind::DetailLine => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, Spline, Ellipse, PartialEllipse, PickLines],
        ToolKind::RoomSeparator | ToolKind::AreaBoundary => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, Spline, Ellipse, PartialEllipse, PickLines],
        ToolKind::Grid => &[Line, Arc3, ArcCenter, PickLines],
        ToolKind::RefPlane | ToolKind::Beam => &[Line, PickLines],
        _ => &[],
    }
}

/// The draw gallery for the current tool; sketches offer what their element accepts.
pub fn draw_modes(app: &App) -> &'static [DrawMode] {
    use DrawMode::*;
    match app.sketch.as_ref().map(|s| s.kind) {
        Some(SketchKind::Railing) if matches!(app.tool.kind, ToolKind::SketchLine | ToolKind::Select) => &[Line, Rect, PolyIn, PolyCirc, Circle, Arc3, ArcCenter, ArcTangent, Fillet, PickLines],
        Some(SketchKind::Stair) if matches!(app.tool.kind, ToolKind::SketchLine | ToolKind::Select) => &[Line],
        Some(_) if app.tool.kind == ToolKind::Select => modes_for(ToolKind::SketchLine),
        _ => modes_for(app.tool.kind),
    }
}

fn effective_mode(app: &App) -> DrawMode {
    let allowed = draw_modes(app);
    if allowed.contains(&app.opts.draw_mode) { app.opts.draw_mode } else { DrawMode::Line }
}

// ---------------------------------------------------------------- prompts

pub fn prompt(app: &App) -> String {
    let t = &app.tool;
    let n = t.pts.len();
    let mode = effective_mode(app);
    match t.kind {
        ToolKind::SketchLine if app.opts.sketch_sub == SketchSub::SlopeArrow => if n == 0 { "Click to enter the tail of the slope arrow.".into() } else { "Click to enter the head of the slope arrow.".into() },
        ToolKind::SketchLine if app.opts.sketch_sub == SketchSub::SpanDirection => "Pick a boundary line to set the span direction.".into(),
        ToolKind::SketchLine if app.opts.sketch_sub == SketchSub::PickHost => "Pick a stair to host the railing.".into(),
        ToolKind::SketchLine if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Stair) => if n == 0 { "Click to enter run start point.".into() } else { "Click to enter run end point.".into() },
        k if k.uses_draw_modes() => match mode {
            DrawMode::PickLines => "Pick a line, edge, wall or grid to create from it.".into(),
            DrawMode::PickWalls => "Pick walls to create lines.".into(),
            DrawMode::Fillet => if t.picked.is_empty() { "Pick the first element for the fillet.".into() } else { "Pick the second element.".into() },
            DrawMode::Rect => if n == 0 { "Click to enter the first corner of the rectangle.".into() } else { "Click to enter the opposite corner.".into() },
            DrawMode::PolyIn | DrawMode::PolyCirc | DrawMode::Circle => if n == 0 { "Click to enter the center.".into() } else { "Click to enter the radius (or type it).".into() },
            DrawMode::Arc3 => ["Click the arc start.", "Click the arc end.", "Click a point on the arc to set its radius."][n.min(2)].into(),
            DrawMode::ArcCenter => ["Click the arc center.", "Click the arc start (radius).", "Click the arc end."][n.min(2)].into(),
            DrawMode::ArcTangent => "Click the end point of the tangent arc.".into(),
            DrawMode::Spline => if n == 0 { "Click to enter the spline start point.".into() } else { "Click to add a control point. Click the last point again or press Enter to finish.".into() },
            DrawMode::Ellipse => ["Click to enter the ellipse center.", "Click to enter the end of the first axis.", "Click to enter the other radius."][n.min(2)].into(),
            DrawMode::PartialEllipse => ["Click to enter the start of the axis.", "Click to enter the end of the axis.", "Click to enter the other radius."][n.min(2)].into(),
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
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting => "Click to place a free instance (Space Bar to Rotate)".into(),
        ToolKind::PlaceGroup | ToolKind::PlaceDetailGroup => "Click to place the group origin.".into(),
        ToolKind::RepeatingDetail => if n == 0 { "Click to enter the start of the repeating detail.".into() } else { "Click to enter the end of the repeating detail.".into() },
        ToolKind::Matchline => if n == 0 { "Click the start of the matchline.".into() } else { "Click the end of the matchline.".into() },
        ToolKind::ViewReference => "Click to place the view reference.".into(),
        ToolKind::Paint => format!("Click a face to paint it with {}. Esc to finish.", app.opts.paint_material),
        ToolKind::RemovePaint => "Click a painted face to remove its paint. Esc to finish.".into(),
        ToolKind::Room => "Click to place room".into(),
        ToolKind::CeilingAuto => "Click in an area bounded by walls to create ceiling".into(),
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
        ToolKind::Dimension(DimKind::SpotCoordinate) => "Click a point to show its North/East coordinates.".into(),
        ToolKind::Dimension(DimKind::SpotSlope) => "Click a sloped floor, roof or toposolid to show its slope.".into(),
        ToolKind::Symbol => "Click to place the symbol.".into(),
        ToolKind::Section => if n == 0 { "Click the start of the section line.".into() } else { "Click the end of the section line.".into() },
        ToolKind::Callout => if n == 0 { "Click the first corner of the callout.".into() } else { "Click the opposite corner.".into() },
        ToolKind::ElevationMarker => "Click to place the elevation marker; it looks towards the building.".into(),
        ToolKind::CurtainGrid => "Click on a curtain wall to add a grid line.".into(),
        ToolKind::WallOpening => if n == 0 { "Click a wall at one side of the opening.".into() } else { "Click the other side of the opening.".into() },
        ToolKind::WallFoundation => "Pick a wall to add a wall foundation under it.".into(),
        ToolKind::Align => if n == 0 { "Please select line or point reference for alignment.".into() } else { "Select the entity to align.".into() },
        ToolKind::Offset => "Select a Wall or a Line to offset. Press TAB to select a chain of elements.".into(),
        ToolKind::MirrorPick => "Pick a line, wall or grid as the mirror axis.".into(),
        ToolKind::MirrorDraw => if n == 0 { "Click the start of the mirror axis.".into() } else { "Click the end of the mirror axis.".into() },
        ToolKind::Move | ToolKind::Copy => if n == 0 { "Click to enter move start point.".into() } else { "Click to enter move end point.".into() },
        ToolKind::Rotate => {
            if t.picked.first() == Some(&u32::MAX) {
                "Click to place the center of rotation.".into()
            } else if n <= 1 {
                "Click to enter rotate start ray or drag or click the rotation center control".into()
            } else {
                "Click to enter rotate end ray.".into()
            }
        }
        ToolKind::TrimCorner => if t.picked.is_empty() { "Select the first line or wall to trim/extend.  (Click on the part you want to keep)".into() } else { "Select the second line or wall to trim/extend.  (Click on the part you want to keep)".into() },
        ToolKind::TrimSingle | ToolKind::TrimMulti => if t.picked.is_empty() { "Pick the boundary.".into() } else { "Pick the element to trim/extend (click the part to keep).".into() },
        ToolKind::Split | ToolKind::SplitGap => "Select an element to split".into(),
        ToolKind::Array => if n == 0 { "Click the start point of the array.".into() } else { "Click the end point (second item, or last with 'Move to: Last').".into() },
        ToolKind::Scale => "Click the origin; elements scale by the factor in the Options Bar.".into(),
        ToolKind::MatchType => if t.picked.is_empty() { "Pick the element whose type to copy.".into() } else { "Pick elements to change to that type.".into() },
        ToolKind::Measure => if n == 0 { "Click the first point to measure.".into() } else { "Click the second point.".into() },
        ToolKind::ZoomRegion => "Drag a rectangle (or click two corners) to zoom into.".into(),
        ToolKind::AttachTop | ToolKind::AttachBase => "Pick a roof, floor or ceiling to attach the selected walls to.".into(),
        ToolKind::PickHost => "Pick a wall to host the selected door or window.".into(),
        ToolKind::Paste => "Click to place the pasted elements.".into(),
        ToolKind::TopoPoints => "Click a point to set its elevation, click inside to add a point, Shift+click deletes a point. Esc to finish.".into(),
        ToolKind::ColorLegend => "Click to place the color fill legend.".into(),
        ToolKind::ScopeBox => if n == 0 { "Click to enter the first corner of the scope box.".into() } else { "Click to enter the opposite corner.".into() },
        ToolKind::Insulation => if n == 0 { "Click to enter the insulation start point.".into() } else { "Click to enter the insulation end point.".into() },
        ToolKind::DetailComponent => "Click to place the detail component. Space rotates it.".into(),
        ToolKind::ShowHiddenLines | ToolKind::RemoveHiddenLines => if t.picked.is_empty() { "Select an element that is obscuring other elements.".into() } else { "Select element whose lines are hidden.".into() },
        ToolKind::JoinGeometry => if t.picked.is_empty() { "Select first geometry to join.".into() } else { "Select second geometry to join to the first.".into() },
        ToolKind::UnjoinGeometry => if t.picked.is_empty() { "Select geometry to unjoin.".into() } else { "Select the element to unjoin it from.".into() },
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
        ToolKind::StructColumn if app.opts.column_multi.is_some() => column_multi_tool(app, painter, xf, view, d, cursor, clicked),
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting => free_tool(app, painter, xf, view, point, clicked),
        ToolKind::PlaceGroup => group_tool(app, painter, xf, view, point, clicked),
        ToolKind::Paint | ToolKind::RemovePaint => {
            if clicked {
                let fp = app.footprints();
                let hit = rc_core::section::pick_face(&app.doc.data, view, cursor.unwrap_or_default(), &fp);
                match hit {
                    Some((id, q, n)) => {
                        let remove = app.tool.kind == ToolKind::RemovePaint;
                        let mat = app.opts.paint_material.clone();
                        app.run(if remove { "Remove Paint" } else { "Paint" }, |p| if remove { edit::remove_paint(p, id, n, q) } else { edit::paint_face(p, id, n, q, &mat) });
                    }
                    None => app.error("There is no face here."),
                }
            }
        }
        ToolKind::RepeatingDetail => {
            let Some(pt) = point else { return };
            let (name, comp, spacing) = REPEATING_DETAILS[app.opts.repeating_detail.min(REPEATING_DETAILS.len() - 1)];
            if let Some(a) = app.tool.pts.first().copied() {
                let len = a.distance(pt);
                let dir = (pt - a).normalize_or_zero();
                let lines = rc_core::plan::detail_component_lines(comp);
                for k in 0..((len / spacing).floor() as usize).min(400) {
                    let at = a + dir * (spacing * (k as f64 + 0.5));
                    for (pts, closed) in &lines {
                        let mut s: Vec<egui::Pos2> = pts.iter().map(|q| xf.s(at + dir * q.x + geom::perp(dir) * q.y)).collect();
                        if *closed {
                            s.push(s[0]);
                        }
                        painter.add(egui::Shape::line(s, preview_stroke()));
                    }
                }
                painter.line_segment([xf.s(a), xf.s(pt)], Stroke::new(1.0, style::PREVIEW));
            }
            if clicked {
                match app.tool.pts.first().copied() {
                    None => app.tool.pts.push(pt),
                    Some(a) => {
                        let vid = view.id;
                        app.tool.pts = vec![pt];
                        app.run("Repeating Detail", |p| edit::add_repeating_detail(p, vid, a, pt, name));
                    }
                }
            }
        }
        ToolKind::Matchline => {
            let Some(pt) = point else { return };
            if let Some(a) = app.tool.pts.first().copied() {
                painter.extend(egui::Shape::dashed_line(&[xf.s(a), xf.s(pt)], Stroke::new(2.0, Color32::from_rgb(80, 0, 120)), 14.0, 5.0));
            }
            if clicked {
                match app.tool.pts.first().copied() {
                    None => app.tool.pts.push(pt),
                    Some(a) => {
                        app.tool.reset();
                        if let Some(id) = app.run("Matchline", |p| edit::add_matchline(p, a, pt)) {
                            app.select(vec![id]);
                        }
                    }
                }
            }
        }
        ToolKind::ViewReference => {
            let Some(pt) = point else { return };
            let target = app.opts.view_ref_target;
            let label = rc_core::plan::view_reference_label(&app.doc.data, target);
            style::canvas_tooltip(painter, xf.s(pt) + vec2(10.0, 10.0), &label);
            if clicked && app.doc.data.view(target).is_some() {
                let vid = view.id;
                if let Some(id) = app.run("View Reference", |p| {
                    let id = edit::add_symbol(p, vid, SymbolKind::ViewReference, pt);
                    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                        s.value = target.to_string();
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
            }
        }
        ToolKind::PlaceDetailGroup => {
            let Some(pt) = point else { return };
            let ty = app.opts.group_type;
            if let Some(gt) = app.doc.data.group_types.iter().find(|g| g.id == ty) {
                for m in &gt.members {
                    if let Some(s) = element_curve(m) {
                        draw_segs(painter, xf, &[s.translated(pt)], preview_stroke());
                    }
                }
            }
            painter.circle_stroke(xf.s(pt), 6.0, preview_stroke());
            if clicked {
                let vid = view.id;
                if let Some(id) = app.run("Place Detail Group", |p| edit::place_detail_group(p, ty, vid, pt)) {
                    app.select(vec![id]);
                }
            }
        }
        ToolKind::Room | ToolKind::Area | ToolKind::CeilingAuto => room_tool(app, painter, xf, view, cursor, clicked),
        ToolKind::RoomTag | ToolKind::AreaTag | ToolKind::Tag => tag_tool(app, painter, xf, view, d, cursor, clicked),
        ToolKind::ScopeBox => {
            let Some(pt) = point else { return };
            if let Some(a) = app.tool.pts.first().copied() {
                let r = egui::Rect::from_two_pos(xf.s(a), xf.s(pt));
                painter.extend(egui::Shape::dashed_line(&[r.left_top(), r.right_top(), r.right_bottom(), r.left_bottom(), r.left_top()], Stroke::new(1.2, style::PREVIEW), 10.0, 4.0));
            }
            if clicked {
                match app.tool.pts.first().copied() {
                    None => app.tool.pts.push(pt),
                    Some(a) => {
                        app.tool.reset();
                        if let Some(id) = app.run("Scope Box", |p| edit::add_scope_box(p, a, pt)) {
                            app.select(vec![id]);
                        }
                    }
                }
            }
        }
        ToolKind::Insulation => {
            let Some(pt) = point else { return };
            let w = app.opts.insulation_width;
            if let Some(a) = app.tool.pts.first().copied() {
                let n = geom::perp((pt - a).normalize_or_zero()) * (w / 2.0);
                painter.line_segment([xf.s(a), xf.s(pt)], Stroke::new(1.0, style::PREVIEW));
                for s in [n, -n] {
                    painter.extend(egui::Shape::dashed_line(&[xf.s(a + s), xf.s(pt + s)], Stroke::new(1.0, style::PREVIEW), 6.0, 4.0));
                }
            }
            if clicked {
                match app.tool.pts.first().copied() {
                    None => app.tool.pts.push(pt),
                    Some(a) => {
                        let vid = view.id;
                        // Chain: the end becomes the next start, as with detail lines.
                        app.tool.pts = vec![pt];
                        app.run("Insulation", |p| edit::add_insulation(p, vid, a, pt, w));
                    }
                }
            }
        }
        ToolKind::DetailComponent => {
            let Some(pt) = point else { return };
            let name = DETAIL_COMPONENTS[app.opts.detail_component.min(DETAIL_COMPONENTS.len() - 1)];
            let rot = app.opts.rotation;
            let (ca, sa) = (rot.to_radians().cos(), rot.to_radians().sin());
            for (pts, closed) in rc_core::plan::detail_component_lines(name) {
                let mut s: Vec<egui::Pos2> = pts.iter().map(|q| xf.s(pt + DVec2::new(q.x * ca - q.y * sa, q.x * sa + q.y * ca))).collect();
                if closed {
                    s.push(s[0]);
                }
                painter.add(egui::Shape::line(s, preview_stroke()));
            }
            if clicked {
                let vid = view.id;
                if let Some(id) = app.run("Detail Component", |p| {
                    let id = edit::add_symbol(p, vid, SymbolKind::DetailComponent, pt);
                    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                        s.value = name.to_string();
                        s.rotation_deg = rot;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
            }
        }
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
        ToolKind::ColorLegend => {
            if let Some(pt) = point {
                let r = egui::Rect::from_min_size(xf.s(pt), vec2(90.0, 60.0));
                painter.rect_stroke(r, 0.0, Stroke::new(1.0, style::PREVIEW), egui::StrokeKind::Inside);
                painter.text(r.min + vec2(4.0, 4.0), egui::Align2::LEFT_TOP, "Room Legend", style::font(11.0), style::PREVIEW);
                if clicked {
                    let vid = view.id;
                    if let Some(id) = app.run("Color Fill Legend", |p| {
                        if let Some(ViewKind::FloorPlan { room_colors, .. }) = p.view_mut(vid).map(|v| &mut v.kind) {
                            *room_colors = true;
                        }
                        Ok(edit::add_color_legend(p, vid, pt))
                    }) {
                        app.select(vec![id]);
                        app.set_tool(ToolKind::Select);
                    }
                }
            }
        }
        ToolKind::TopoPoints => {
            // Boundary and interior points of every toposolid: click a point to give it the
            // Options Bar elevation, click inside to add one, Shift+click deletes an interior one.
            let Some(c) = cursor else { return };
            let shift = ui.input(|i| i.modifiers.shift);
            let mut best: Option<(f64, Id, usize)> = None;
            let mut inside: Option<Id> = None;
            let units = app.doc.data.units.clone();
            for e in &app.doc.data.elements {
                let ElementKind::Toposolid(t) = &e.kind else { continue };
                if geom::contains(&t.boundary, c) {
                    inside = Some(e.id);
                }
                let pts: Vec<(DVec2, f64, bool)> = t
                    .boundary
                    .iter()
                    .enumerate()
                    .map(|(k, q)| (*q, t.heights.get(k).copied().unwrap_or(0.0), false))
                    .chain(t.points.iter().map(|(q, h)| (*q, *h, true)))
                    .collect();
                for (k, (q, h, interior)) in pts.into_iter().enumerate() {
                    let sp = xf.s(q);
                    let hot = sp.distance(xf.s(c)) < 9.0;
                    let r = egui::Rect::from_center_size(sp, vec2(7.0, 7.0));
                    let fill = if hot { style::PRESELECT } else if interior { style::accent_light() } else { Color32::WHITE };
                    if interior {
                        painter.circle(sp, 4.0, fill, Stroke::new(1.2, style::SELECT));
                    } else {
                        painter.rect(r, 0.0, fill, Stroke::new(1.2, style::SELECT), egui::StrokeKind::Middle);
                    }
                    painter.text(sp + vec2(6.0, -6.0), egui::Align2::LEFT_BOTTOM, units.length(h), style::font(10.5), style::TEMP_DIM);
                    let dd = q.distance(c);
                    if hot && best.is_none_or(|b| dd < b.0) {
                        best = Some((dd, e.id, k));
                    }
                }
            }
            if best.is_none() && inside.is_some() {
                let sp = xf.s(c);
                painter.circle_stroke(sp, 4.0, Stroke::new(1.0, style::PREVIEW));
                style::canvas_tooltip(painter, sp + vec2(8.0, 10.0), "Click to add a point");
            }
            if clicked {
                let h = app.opts.topo_point_height;
                match (best, inside) {
                    (Some((_, id, k)), _) if shift => {
                        app.run("Delete Point", |p| edit::remove_topo_point(p, id, k));
                    }
                    (Some((_, id, k)), _) => {
                        app.run("Modify Sub Elements", |p| edit::set_topo_point(p, id, k, h));
                    }
                    (None, Some(id)) => {
                        app.run("Add Point", |p| edit::add_topo_point(p, id, c, h));
                    }
                    _ => app.error("Click a toposolid point, or inside a toposolid to add one."),
                }
            }
        }
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
        k if k.uses_draw_modes() && effective_mode(app) == DrawMode::Spline && app.tool.pts.len() >= 2 => app.interact.finish_spline = true,
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
    if app.sketch.as_ref().is_some_and(|s| s.view == view.id) && app.opts.sketch_sub == SketchSub::PickHost {
        pick_host_tool(app, painter, xf, view, d, cursor, clicked);
        return;
    }
    if app.sketch.as_ref().is_some_and(|s| s.view == view.id) && app.opts.sketch_sub != SketchSub::Boundary {
        sketch_sub_tool(app, painter, xf, cursor, point, clicked);
        return;
    }
    if app.sketch.as_ref().is_some_and(|s| s.view == view.id && s.kind == SketchKind::Stair) && app.tool.kind == ToolKind::SketchLine {
        stair_run_tool(app, painter, xf, point, clicked);
        return;
    }
    let mode = effective_mode(app);
    if mode.is_pick() {
        pick_draw_tool(app, painter, xf, view, d, mode, cursor, clicked);
        return;
    }
    let Some(pt) = point else { return };
    let kind = app.tool.kind;
    let sides = app.opts.poly_sides;
    let tangent = app.tool.tangent;
    // A spline finishes on Enter or when its last point is clicked again.
    if mode == DrawMode::Spline && app.tool.pts.len() >= 2 {
        let again = clicked && app.tool.pts.last().is_some_and(|l| l.distance(pt) <= xf.len(6.0));
        if std::mem::take(&mut app.interact.finish_spline) || again {
            let segs = tools::spline_segs(&app.tool.pts);
            app.tool.pts.clear();
            commit_segs(app, view, &segs);
            return;
        }
    }
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
            // The location line as a light-blue dashed alignment line running past both ends.
            let pts = s.points();
            if pts.len() >= 2 {
                let (p0, p1) = (xf.s(pts[0]), xf.s(pts[pts.len() - 1]));
                if matches!(s, Seg::Line(..)) && p0.distance(p1) > 1.0 {
                    let d = (p1 - p0).normalized();
                    canvas::reference_line(painter, p0 - d * 30.0, p1 + d * 30.0);
                } else {
                    for w in pts.windows(2) {
                        canvas::reference_line(painter, xf.s(w[0]), xf.s(w[1]));
                    }
                }
            }
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

/// The stair being sketched as it would be created (for its riser numbers).
pub fn sketch_stair(app: &App) -> Option<Stair> {
    let sk = app.sketch.as_ref().filter(|s| s.kind == SketchKind::Stair)?;
    let o = &app.opts;
    let runs = sk
        .segs
        .iter()
        .filter_map(|s| match s {
            Seg::Line(a, b) => Some(StairRun { start: *a, end: *b, width: o.stair_width }),
            _ => None,
        })
        .collect();
    let top_level = o.stair_top.or_else(|| app.doc.data.level_above(sk.level).map(|l| l.0));
    Some(Stair { base_level: sk.level, base_offset: o.stair_base_offset, top_level, top_offset: o.stair_top_offset, unconnected_height: 3000.0, runs, type_id: o.stair_type, desired_risers: o.stair_risers, railings: o.stair_railing.is_some() })
}

/// (desired risers, risers created so far, riser height, tread depth) of the stair sketch.
pub fn sketch_stair_numbers(app: &App) -> Option<(u32, u32, f64, f64)> {
    let s = sketch_stair(app)?;
    let (n, rh, tread, _) = analysis::stair_numbers(&app.doc.data, &s);
    let made = s.runs.iter().map(|r| analysis::run_risers(r.start.distance(r.end), tread)).sum();
    Some((n, made, rh, tread))
}

/// The stair Run tool: click the run start, then its end; the run snaps to whole risers and
/// reports the risers created and remaining, as in the reference app.
fn stair_run_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, point: Option<DVec2>, clicked: bool) {
    let Some(pt) = point else { return };
    let Some((n, made, _rh, tread)) = sketch_stair_numbers(app) else { return };
    let Some(a) = app.tool.pts.first().copied() else {
        if clicked {
            app.tool.pts.push(pt);
        }
        return;
    };
    let dir = (pt - a).normalize_or_zero();
    if dir == DVec2::ZERO {
        return;
    }
    let left = n as i64 - made as i64;
    let k = analysis::run_risers(a.distance(pt), tread).clamp(2, (left.max(2)) as u32);
    let len = (k - 1) as f64 * tread;
    let w = app.opts.stair_width;
    let nrm = geom::perp(dir);
    let shift = nrm * (app.opts.stair_location.center_shift(w) + app.opts.offset);
    let (cs, ce) = (a + shift, a + dir * len + shift);
    let half = nrm * (w / 2.0);
    // The run previews in grey with its treads, as in the reference app.
    let grey = Color32::from_gray(120);
    painter.add(egui::Shape::closed_line(vec![xf.s(cs - half), xf.s(ce - half), xf.s(ce + half), xf.s(cs + half)], Stroke::new(1.0, grey)));
    for j in 0..k {
        let q = cs + dir * (j as f64 * tread);
        painter.line_segment([xf.s(q - half), xf.s(q + half)], Stroke::new(1.0, Color32::from_gray(170)));
    }
    canvas::reference_line(painter, xf.s(a - dir * xf.len(30.0)), xf.s(a + dir * (len + xf.len(30.0))));
    let units = app.doc.data.units.clone();
    // Length along the left edge of the run; angle from the horizontal at the start.
    canvas::temp_dim_ex(painter, xf, cs + half, ce + half, &units.length(len), -18.0, true);
    angle_arc(painter, xf, a, DVec2::X, a + dir * len.max(xf.len(60.0)), &units);
    // "N RISERS CREATED, M REMAINING" in grey under the start of the run.
    let msg = format!("{} RISERS CREATED, {} REMAINING", made + k, (left - k as i64).max(0));
    let below = cs - dir * xf.len(14.0) + half;
    painter.text(xf.s(below), egui::Align2::LEFT_TOP, msg, egui::FontId::proportional(11.0), Color32::from_gray(150));
    if clicked {
        if let Some(sk) = app.sketch.as_mut() {
            sk.push(Seg::Line(cs, ce), true);
        }
        app.tool.pts.clear();
    }
}

/// Railings: Pick New Host — the stair the railing follows.
fn pick_host_tool(app: &mut App, _painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    let hit = hover_of(app, view, d, c, xf, &|e| matches!(e.kind, ElementKind::Stair(_)));
    app.interact.hover = hit;
    if !clicked {
        return;
    }
    match hit {
        Some(id) => {
            if let Some(sk) = app.sketch.as_mut() {
                sk.host = Some(id);
            }
            app.opts.sketch_sub = SketchSub::Boundary;
            app.tool = Tool::new(ToolKind::SketchLine);
        }
        None => app.error("Pick a stair to host the railing."),
    }
}

/// Slope arrows and span direction in floor sketches.
fn sketch_sub_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, cursor: Option<DVec2>, point: Option<DVec2>, clicked: bool) {
    match app.opts.sketch_sub {
        SketchSub::SlopeArrow => {
            let Some(pt) = point else { return };
            if let Some(a) = app.tool.pts.first().copied() {
                crate::canvas::paint_slope_arrow(painter, xf, a, pt, style::PREVIEW);
                temp_dim(painter, xf, a, pt, &app.doc.data.units.length(a.distance(pt)), -22.0);
                if clicked && a.distance(pt) > 1.0 {
                    if let Some(sk) = app.sketch.as_mut() {
                        sk.slope_arrow = Some((a, pt));
                    }
                    app.tool.pts.clear();
                    app.opts.sketch_sub = SketchSub::Boundary;
                    app.tool = Tool::select();
                }
            } else if clicked {
                app.tool.pts.push(pt);
            }
        }
        SketchSub::SpanDirection => {
            let Some(c) = cursor else { return };
            let hit = app.sketch.as_ref().and_then(|sk| {
                sk.segs.iter().enumerate().map(|(k, s)| (s.distance_to(c), k)).filter(|(dd, _)| *dd <= xf.len(8.0)).min_by(|a, b| a.0.total_cmp(&b.0)).map(|x| x.1)
            });
            if let (Some(k), Some(sk)) = (hit, app.sketch.as_ref()) {
                draw_segs(painter, xf, &[sk.segs[k]], Stroke::new(3.0, style::PRESELECT));
                if clicked {
                    if let Some(sk) = app.sketch.as_mut() {
                        if matches!(sk.segs[k], Seg::Line(..)) {
                            sk.span_edge = Some(k);
                        }
                    }
                    app.opts.sketch_sub = SketchSub::Boundary;
                    app.tool = Tool::select();
                }
            }
        }
        SketchSub::Boundary | SketchSub::PickHost => {}
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
    // The value sits outside the arc at its middle, written along the arc as the reference
    // app does.
    let tm = t0 + sweep / 2.0;
    let q = xf.s(a + DVec2::new(tm.cos(), tm.sin()) * (r + xf.len(9.0)));
    let text = units.format(deg, ParamKind::Angle);
    let galley = painter.layout_no_wrap(text, style::bold(11.0), style::TEMP_DIM);
    // Screen angle of the tangent, kept upright.
    let mut ang = -(tm as f32) + std::f32::consts::FRAC_PI_2;
    while ang > std::f32::consts::FRAC_PI_2 {
        ang -= std::f32::consts::PI;
    }
    while ang < -std::f32::consts::FRAC_PI_2 {
        ang += std::f32::consts::PI;
    }
    let size = galley.size();
    painter.add(egui::epaint::TextShape::new(q - size / 2.0, galley, style::TEMP_DIM).with_angle_and_anchor(ang, egui::Align2::CENTER_CENTER));
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
                    let s = s.offset(o.offset);
                    // "Radius": round the corner with the previous line of the chain.
                    if let (true, Some(Seg::Line(p0, p1)), Seg::Line(q0, q1)) = (o.use_radius, sk.segs.last().copied(), s) {
                        if let Some((pa, pb, arc)) = tools::chain_fillet((p0, p1), (q0, q1), o.radius) {
                            if let Some(last) = sk.segs.last_mut() {
                                *last = Seg::Line(p0, pa);
                            }
                            sk.push(arc, o.defines_slope);
                            sk.push(Seg::Line(pb, q1), o.defines_slope);
                            continue;
                        }
                    }
                    sk.push(s, o.defines_slope);
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
                    let (mut a, b, m) = match *s {
                        Seg::Line(a, b) => (a, b, None),
                        Seg::Arc(a, m, b) => (a, b, Some(m)),
                    };
                    // "Radius": round the corner with the straight wall this one continues.
                    if o.use_radius && m.is_none() {
                        let prev = p.elements.iter().rev().find_map(|e| match &e.kind {
                            ElementKind::Wall(w) if w.base_level == level && w.arc_mid.is_none() && w.end.distance(a) < 0.5 => Some((e.id, w.start, w.end)),
                            _ => None,
                        });
                        if let Some((pid, ws, we)) = prev {
                            if let Some((pa, pb, Seg::Arc(_, am, _))) = tools::chain_fillet((ws, we), (a, b), o.radius) {
                                let base = p.wall(pid).cloned();
                                if let Some(w) = p.element_mut(pid).and_then(Element::as_wall_mut) {
                                    w.end = pa;
                                }
                                let aid = edit::add_wall_ex(p, level, o.wall_type, pa, pb, Some(am), o.wall_height, o.location_line, false)?;
                                if let (Some(src), Some(w)) = (base, p.element_mut(aid).and_then(Element::as_wall_mut)) {
                                    (w.structural, w.room_bounding, w.base_offset, w.top_level, w.top_offset, w.unconnected_height) = (src.structural, src.room_bounding, src.base_offset, src.top_level, src.top_offset, src.unconnected_height);
                                }
                                a = pb;
                            }
                        }
                    }
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
        let segs: Vec<Seg> = walls
            .iter()
            .filter_map(|wid| {
                let w = p.wall(*wid)?;
                let e = p.element(*wid)?;
                let seg = element_curve(e)?;
                let toward = if (centroid - w.start).dot(w.normal()) >= 0.0 { 1.0 } else { -1.0 };
                let side = if inside { toward } else { -toward };
                Some(seg.offset(pick_wall_offset(app, w, side)))
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
        let side = if (c - w.start).dot(w.normal()) >= 0.0 { 1.0 } else { -1.0 };
        extra = pick_wall_offset(app, w, side);
        let _ = &mut seg;
    }
    // The wall being picked highlights and its name follows the cursor, as in the reference app.
    app.interact.hover = Some(id);
    painter.ctx().data_mut(|m| m.insert_temp(egui::Id::new("no-prompt-tip"), true));
    if painter.ctx().input(|i| i.pointer.time_since_last_movement()) > 0.35 {
        style::canvas_tooltip(painter, xf.s(c) + egui::vec2(12.0, 16.0), &crate::canvas::describe(app, id));
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

/// Offset from a picked wall's centreline to the sketch line on `side` (+1 = along the wall
/// normal): the finish face, or the core face with "Extend into wall (to core)"; roofs add
/// their overhang beyond it ("Extend to wall core" measures it from the core face).
fn pick_wall_offset(app: &App, w: &rc_core::model::Wall, side: f64) -> f64 {
    let p = &app.doc.data;
    let kind = app.sketch.as_ref().map(|s| s.kind);
    let roof = kind.is_some_and(|k| k.is_roof());
    let floorish = matches!(kind, Some(SketchKind::Floor { .. } | SketchKind::EditFloor(_) | SketchKind::Ceiling | SketchKind::EditCeiling(_)));
    let core = (floorish && app.opts.extend_to_core) || (roof && app.opts.roof_extend_to_core);
    let face = if core {
        let (plus, minus) = analysis::wall_core_offsets(p, w);
        if side > 0.0 { plus } else { minus }
    } else {
        side * analysis::wall_thickness(p, w) / 2.0
    };
    face + if roof { side * app.opts.overhang } else { 0.0 }
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

/// Doors and windows placed on a wall seen in an elevation or section: the cursor sets the
/// position along the wall; the sill follows the type (doors sit on the level).
fn hosted_tool_elevation(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, c: DVec2, clicked: bool) {
    let is_door = app.tool.kind == ToolKind::Door;
    let type_id = if is_door { app.opts.door_type } else { app.opts.window_type };
    // Wall edges under the cursor, else the wall face hit by the view ray.
    let wall = hover_of(app, view, d, c, xf, &|e| matches!(e.kind, ElementKind::Wall(_))).or_else(|| {
        let fp = app.footprints();
        rc_core::section::pick_face(&app.doc.data, view, c, &fp).map(|h| h.0).filter(|id| app.doc.data.wall(*id).is_some())
    });
    let Some(wall_id) = wall else {
        if clicked {
            app.error(format!("{} must be hosted by a wall. Hover over a wall.", if is_door { "Doors" } else { "Windows" }));
        }
        return;
    };
    let fp = app.footprints();
    let p = &app.doc.data;
    let Some(w) = p.wall(wall_id).cloned() else { return };
    let (Some((o, dir3)), Some(frame)) = (rc_core::section::view_ray(p, view, c, &fp), rc_core::section::view_frame(p, view, &fp)) else { return };
    // Where the view ray meets the wall's centre plane.
    let n3 = geom::at(w.normal(), 0.0);
    let denom = dir3.dot(n3);
    let hit = if denom.abs() > 1e-9 { o + dir3 * ((geom::at(w.start, 0.0) - o).dot(n3) / denom) } else { o };
    let (mut along, _) = analysis::wall_project(&w, hit.truncate());
    let r = p.family_type(type_id).map(|(f, t)| rc_core::family_params::Resolver::for_type(f, t));
    let width = r.as_ref().map(|r| r.num("Rough Width", r.num("Width", 900.0))).unwrap_or(900.0);
    let height = r.as_ref().map(|r| r.num("Rough Height", r.num("Height", if is_door { 2100.0 } else { 1200.0 }))).unwrap_or(2100.0);
    let default_sill = if is_door { 0.0 } else { r.as_ref().map(|r| r.num("Default Sill Height", 900.0)).unwrap_or(900.0) };
    let sill = if is_door { 0.0 } else { app.opts.window_sill.unwrap_or(default_sill) };
    let len = w.length();
    let step = crate::snap::length_increment(xf.zoom, p.units.system == rc_core::units::UnitSystem::Imperial).max(10.0);
    along = ((along / step).round() * step).clamp(width / 2.0, (len - width / 2.0).max(width / 2.0));
    let base = p.level_elevation(w.base_level) + w.base_offset;
    let (a, _) = analysis::wall_point(&w, along - width / 2.0);
    let (b, _) = analysis::wall_point(&w, along + width / 2.0);
    let corners = [(a, base + sill), (b, base + sill), (b, base + sill + height), (a, base + sill + height)];
    let pts: Vec<Pos2> = corners.iter().map(|(q, z)| xf.s(frame.to_view(geom::at(*q, *z)).0)).collect();
    painter.add(egui::Shape::closed_line(pts, Stroke::new(2.0, style::PREVIEW)));
    let units = p.units.clone();
    let (s0, _) = analysis::wall_point(&w, 0.0);
    let lo = frame.to_view(geom::at(s0, base)).0;
    let mid = frame.to_view(geom::at(analysis::wall_point(&w, along).0, base)).0;
    temp_dim(painter, xf, lo, mid, &units.length(along), -26.0);
    if clicked {
        let name = if is_door { "Place Door" } else { "Place Window" };
        let sill_set = if is_door { None } else { app.opts.window_sill };
        app.run(name, |p| {
            let id = edit::place_hosted(p, type_id, wall_id, along, false)?;
            if let Some(s) = sill_set {
                if let Some(i) = p.element_mut(id).and_then(|e| e.as_instance_mut()) {
                    i.elevation = s;
                }
            }
            Ok(id)
        });
    }
}

fn hosted_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, clicked: bool) {
    let Some(c) = cursor else { return };
    if matches!(view.kind, ViewKind::Elevation { .. } | ViewKind::Section { .. }) {
        hosted_tool_elevation(app, painter, xf, view, d, c, clicked);
        return;
    }
    let Some(level) = view.plan_level() else { return };
    let is_door = app.tool.kind == ToolKind::Door;
    let type_id = if is_door { app.opts.door_type } else { app.opts.window_type };
    let wall = hover_of(app, view, d, c, xf, &|e| matches!(&e.kind, ElementKind::Wall(w) if w.base_level == level));
    let Some(wall_id) = wall else {
        // Nothing to host it here: the "not allowed" cursor, as in the reference app.
        painter.ctx().set_cursor_icon(egui::CursorIcon::NotAllowed);
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
    let flip = (side > 0.0) != app.opts.place_flip;
    // As in the reference app the preview is the family's own plan symbol where it will go,
    // and the cursor tooltip only appears away from walls.
    painter.ctx().data_mut(|m| m.insert_temp(egui::Id::new("no-prompt-tip"), true));
    let probe = p.family_type(type_id).map(|(f, _)| FamilyInstance { family_id: f.id, type_id, category: f.category, level: w.base_level, host: Some(wall_id), offset_along_host: along, flip_facing: flip, ..Default::default() });
    if let Some(probe) = &probe {
        let cut_z = p.level_elevation(level) + view.view_range.cut;
        let probe = FamilyInstance { elevation: if is_door { 0.0 } else { app.opts.window_sill.unwrap_or(900.0) }, ..probe.clone() };
        for s in rc_core::family_geom::instance_symbol(p, &probe, cut_z) {
            let mut pts: Vec<Pos2> = s.pts.iter().map(|q| xf.s(*q)).collect();
            if s.closed && !pts.is_empty() {
                pts.push(pts[0]);
            }
            let w = if matches!(s.style, rc_core::family_geom::SymStyle::Cut) { 1.6 } else { 1.0 };
            painter.add(egui::Shape::line(pts, Stroke::new(w, Color32::from_gray(70))));
        }
        // Temporary dimensions from the opening's edges to the nearest references, on the
        // side it opens to.
        let facing = n * if flip { 1.0 } else { -1.0 };
        for td in crate::tempdims::hosted_dims_on(p, 0, &probe, &w, along, facing) {
            temp_dim(painter, xf, td.a, td.b, &p.units.length(td.value), td.offset_px * 3.0);
        }
    }
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

/// At Grids / At Columns: pick the grids or architectural columns, then Finish.
fn column_multi_tool(app: &mut App, painter: &egui::Painter, xf: &Xf, view: &View, d: &Drawing, cursor: Option<DVec2>, clicked: bool) {
    let Some(multi) = app.opts.column_multi else { return };
    let at_grids = multi == crate::tools::ColumnMulti::AtGrids;
    app.interact.prompt = if at_grids { "Select grids (CTRL adds), then click Finish.".into() } else { "Select architectural columns, then click Finish.".into() };
    // Picked elements stay highlighted; the columns-to-be preview at their places.
    for id in app.tool.picked.clone() {
        if let Some(e) = app.el(id) {
            if let Some(s) = element_curve(e) {
                draw_segs(painter, xf, &[s], Stroke::new(3.0, style::SELECT));
            }
        }
    }
    for q in column_multi_points(app) {
        painter.rect_stroke(egui::Rect::from_center_size(xf.s(q), egui::vec2(10.0, 10.0)), 0.0, preview_stroke(), egui::StrokeKind::Middle);
    }
    let Some(c) = cursor else { return };
    let hover = hover_of(app, view, d, c, xf, &|e| if at_grids { matches!(e.kind, ElementKind::Grid(_)) } else { e.category() == Category::Columns });
    if let Some(h) = hover {
        app.interact.hover = Some(h);
        if clicked {
            if let Some(k) = app.tool.picked.iter().position(|x| *x == h) {
                app.tool.picked.remove(k);
            } else {
                app.tool.picked.push(h);
            }
        }
    }
}

/// Where At Grids / At Columns would place columns.
fn column_multi_points(app: &App) -> Vec<DVec2> {
    let p = &app.doc.data;
    let mut out: Vec<DVec2> = Vec::new();
    match app.opts.column_multi {
        Some(crate::tools::ColumnMulti::AtGrids) => {
            let segs: Vec<(DVec2, DVec2)> = app.tool.picked.iter().filter_map(|id| match p.element(*id).map(|e| &e.kind) {
                Some(ElementKind::Grid(g)) if g.arc_mid.is_none() => Some((g.start, g.end)),
                _ => None,
            }).collect();
            for i in 0..segs.len() {
                for j in i + 1..segs.len() {
                    if let Some((t, u)) = geom::segment_intersection(segs[i].0, segs[i].1, segs[j].0, segs[j].1) {
                        if (0.0..=1.0).contains(&t) && (0.0..=1.0).contains(&u) {
                            let q = segs[i].0.lerp(segs[i].1, t);
                            if !out.iter().any(|o| o.distance(q) < 1.0) {
                                out.push(q);
                            }
                        }
                    }
                }
            }
        }
        Some(crate::tools::ColumnMulti::AtColumns) => {
            for id in &app.tool.picked {
                if let Some(i) = p.element(*id).and_then(|e| e.as_instance()) {
                    out.push(i.location);
                }
            }
        }
        None => {}
    }
    out
}

/// Multiple > Finish: places a structural column at each point.
pub fn finish_columns(app: &mut App) {
    let pts = column_multi_points(app);
    let Some(level) = app.active_level() else { return };
    let ty = app.opts.struct_column_type;
    if pts.is_empty() {
        app.error(if app.opts.column_multi == Some(crate::tools::ColumnMulti::AtGrids) { "Select at least two crossing grids." } else { "Select at least one architectural column." });
        return;
    }
    let o = app.opts.clone();
    let n = pts.len();
    app.run("Place Structural Columns", |p| {
        for q in &pts {
            let id = edit::place_free(p, ty, level, *q, 0.0)?;
            set_column_extent(p, id, level, &o);
        }
        Ok(())
    });
    app.info(format!("Placed {n} structural column{}.", if n == 1 { "" } else { "s" }));
    app.opts.column_multi = None;
    app.tool.picked.clear();
}

/// Applies the Options Bar's Depth/Height and level to a new column.
fn set_column_extent(p: &mut Project, id: Id, level: Id, o: &crate::tools::ToolOptions) {
    let structural = p.element(id).is_some_and(|e| e.category() == Category::StructuralColumns);
    let depth = structural && o.struct_column_depth;
    let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) else { return };
    i.moves_with_grids = structural && o.column_moves_grids;
    match (depth, o.column_top) {
        // Depth to a level below: the column runs from that level up to this one.
        (true, Some(t)) => {
            i.level = t;
            i.top_level = Some(level);
            i.top_offset = 0.0;
        }
        (true, None) => {
            i.elevation = -o.column_height;
            i.values.insert("Height".into(), rc_core::units::to_stored(o.column_height));
        }
        (false, Some(t)) => {
            i.top_level = Some(t);
            i.top_offset = 0.0;
        }
        (false, None) => {
            i.values.insert("Height".into(), rc_core::units::to_stored(o.column_height));
        }
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
    // Temporary dimensions to the nearest wall or grid across and along, as in the reference app.
    for dirs in [[DVec2::X, -DVec2::X], [DVec2::Y, -DVec2::Y]] {
        let best = dirs.iter().filter_map(|d| crate::tempdims::ray_hit(&app.doc.data, level, u32::MAX, pt, *d, 30000.0)).min_by(|a, b| a.1.total_cmp(&b.1));
        if let Some((hit, dist)) = best {
            temp_dim(painter, xf, hit, pt, &app.doc.data.units.length(dist), 0.0);
        }
    }
    if clicked {
        let rot = app.opts.rotation;
        let (offset, comments, mark) = (app.opts.component_offset, app.opts.place_comments.clone(), app.opts.place_mark.clone());
        let column = matches!(app.tool.kind, ToolKind::Column | ToolKind::StructColumn);
        let o = app.opts.clone();
        let tag = app.tool.kind == ToolKind::StructColumn && app.opts.column_tag;
        let vid = view.id;
        let name = format!("Place {}", app.tool.kind.name());
        if let Some(id) = app.run(&name, |p| {
            let id = edit::place_free(p, ty, level, pt, rot)?;
            if let Some(e) = p.element_mut(id) {
                e.comments = comments;
                e.mark = mark;
            }
            if column {
                set_column_extent(p, id, level, &o);
            } else if let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) {
                i.elevation = offset;
            }
            if tag {
                edit::add_tag(p, vid, id, pt + DVec2::new(0.0, 600.0), false)?;
            }
            Ok(id)
        }) {
            // Like the reference app the tool stays active with nothing selected, unless the
            // instance is to be rotated right away.
            if app.opts.rotate_after_placement {
                let back = app.tool.kind;
                app.select(vec![id]);
                app.set_tool(ToolKind::Rotate);
                app.opts.rotate_return = Some(back);
            }
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
        } else if app.tool.kind == ToolKind::CeilingAuto {
            // The boundary the ceiling would follow highlights in red, as in the reference app.
            painter.add(egui::Shape::closed_line(poly.iter().map(|q| xf.s(*q)).collect(), Stroke::new(2.0, Color32::from_rgb(230, 30, 30))));
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
            let (h, comments, mark) = (app.opts.ceiling_offset, app.opts.place_comments.clone(), app.opts.place_mark.clone());
            // The tool stays active with nothing selected, as in the reference app.
            app.run("Create Ceiling", |p| {
                let id = edit::add_ceiling(p, level, ty, poly, h)?;
                if let Some(e) = p.element_mut(id) {
                    e.comments = comments;
                    e.mark = mark;
                }
                Ok(id)
            });
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
        let param = match (kind, app.opts.tag_mode) {
            (ToolKind::Tag, 1) => "Family and Type",
            (ToolKind::Tag, 2) => "Material",
            (ToolKind::Tag, 3) => "Keynote",
            (ToolKind::Tag, 4) => "Material Keynote",
            (ToolKind::Tag, 5) => "User Keynote",
            _ => "",
        };
        if let Some(id) = app.run("Tag", |p| {
            let id = edit::add_tag(p, vid, h, at, leader)?;
            if !param.is_empty() {
                if let Some(ElementKind::Tag(t)) = p.element_mut(id).map(|e| &mut e.kind) {
                    t.parameter = param.to_string();
                }
            }
            if leader {
                if let Some(ElementKind::Tag(t)) = p.element_mut(id).map(|e| &mut e.kind) {
                    t.leader_end = Some(hp);
                }
            }
            let _ = horizontal;
            Ok(id)
        }) {
            app.select(vec![id]);
            // A keynote with no value yet asks for one, as the Keynotes dialog does.
            let empty = app.el(id).is_some_and(|e| matches!(&e.kind, ElementKind::Tag(t) if t.parameter.contains("Keynote") && rc_core::annotation::tag_text(&app.doc.data, t) == "?"));
            if empty {
                app.dialogs.keynote_pick = Some(id);
            }
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
        DimKind::SpotCoordinate => {
            let Some(pt) = point else { return };
            let txt = format!("N {}\nE {}", units.length(pt.y), units.length(pt.x));
            for (k, l) in txt.lines().enumerate() {
                painter.text(xf.s(pt) + vec2(14.0, -26.0 + k as f32 * 14.0), egui::Align2::LEFT_BOTTOM, l, egui::FontId::proportional(12.0), style::TEMP_DIM);
            }
            painter.circle_stroke(xf.s(pt), 5.0, preview_stroke());
            if clicked {
                let vid = view.id;
                if let Some(id) = app.run("Spot Coordinate", |p| {
                    let id = edit::add_symbol(p, vid, SymbolKind::SpotCoordinate, pt);
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
        DimKind::SpotSlope => {
            let Some(pt) = point else { return };
            let slope = surface_at(app, view, pt).map(|(_, g)| g).filter(|g| g.length() > 1e-4);
            let Some(g) = slope else {
                style::canvas_tooltip(painter, xf.s(pt) + vec2(12.0, 12.0), "Pick a sloped floor, roof or toposolid");
                return;
            };
            let down = -g.normalize();
            let txt = format!("{:.2}%", g.length() * 100.0);
            let half = 6.0 * view.scale;
            painter.arrow(xf.s(pt - down * half), xf.s(pt + down * half) - xf.s(pt - down * half), preview_stroke());
            painter.text(xf.s(pt) + vec2(12.0, -12.0), egui::Align2::LEFT_BOTTOM, &txt, egui::FontId::proportional(12.0), style::TEMP_DIM);
            if clicked {
                let vid = view.id;
                let rot = down.y.atan2(down.x).to_degrees();
                if let Some(id) = app.run("Spot Slope", |p| {
                    let id = edit::add_symbol(p, vid, SymbolKind::SpotSlope, pt);
                    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                        s.value = txt;
                        s.rotation_deg = rot;
                    }
                    Ok(id)
                }) {
                    app.select(vec![id]);
                }
            }
            return;
        }
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
                // Associative references: the dimension follows the arc element.
                let el = app.tool.picked.first().copied();
                let rr: Vec<DimRef> = match kind {
                    DimKind::Radial => vec![DimRef { element: el, part: RefPart::ArcCenter, point: refs[0] }, DimRef { element: el, part: RefPart::ArcPoint, point: refs[1] }],
                    DimKind::Diameter => refs.iter().map(|q| DimRef { element: el, part: RefPart::ArcPoint, point: *q }).collect(),
                    _ => {
                        let start_end = el.and_then(|id| app.el(id)).is_some_and(|e| matches!(e.kind, ElementKind::Wall(_) | ElementKind::Line(_)));
                        if start_end {
                            vec![DimRef { element: el, part: RefPart::EndStart, point: refs[0] }, DimRef { element: el, part: RefPart::ArcMid, point: refs[1] }, DimRef { element: el, part: RefPart::EndEnd, point: refs[2] }]
                        } else {
                            refs.iter().map(|q| DimRef { element: None, part: RefPart::Point, point: *q }).collect()
                        }
                    }
                };
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
                        let part = if line_el.and_then(|id| app.el(id)).is_some_and(|e| matches!(e.kind, ElementKind::Wall(_))) { RefPart::WallCenter } else { RefPart::Point };
                        app.tool.refs.push(DimRef { element: line_el, part, point: pick });
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
                // Ray references follow their lines; the vertex is their intersection.
                let (ea, eb) = (app.tool.refs[0].clone(), app.tool.refs[1].clone());
                let rr = vec![
                    DimRef { element: ea.element, part: ea.part, point: v + da * r.max(1.0) },
                    DimRef { element: None, part: RefPart::Point, point: v },
                    DimRef { element: eb.element, part: eb.part, point: v + db * r.max(1.0) },
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
/// The highest floor, roof or toposolid top surface over a plan point: its elevation and the
/// uphill gradient (rise over run in x and y).
fn surface_at(app: &App, view: &View, pt: DVec2) -> Option<(f64, DVec2)> {
    let p = &app.doc.data;
    let fp = std::collections::HashMap::new();
    let mut best: Option<(f64, DVec2)> = None;
    for e in &p.elements {
        if !matches!(e.kind, ElementKind::Floor(_) | ElementKind::Roof(_) | ElementKind::Toposolid(_)) || !analysis::visible_in(p, view, e) {
            continue;
        }
        let set = rc_core::build3d::element_mesh(p, e, &fp);
        for m in set.by_material.values() {
            for tri in m.indices.chunks(3) {
                let (a, b, c) = (m.positions[tri[0] as usize], m.positions[tri[1] as usize], m.positions[tri[2] as usize]);
                let n = (b - a).cross(c - a);
                if n.z.abs() < 1e-6 * n.length() {
                    continue;
                }
                let (a2, b2, c2) = (a.truncate(), b.truncate(), c.truncate());
                let s = [geom::cross2(b2 - a2, pt - a2), geom::cross2(c2 - b2, pt - b2), geom::cross2(a2 - c2, pt - c2)];
                if !(s.iter().all(|x| *x >= -1e-6) || s.iter().all(|x| *x <= 1e-6)) {
                    continue;
                }
                let z = a.z - (n.x * (pt.x - a.x) + n.y * (pt.y - a.y)) / n.z;
                if best.is_none_or(|bz| z > bz.0 + 1e-6) {
                    best = Some((z, DVec2::new(-n.x / n.z, -n.y / n.z)));
                }
            }
        }
    }
    best
}

fn spot_elevation(app: &App, view: &View, pt: DVec2) -> f64 {
    let p = &app.doc.data;
    let Some(level) = view.plan_level() else { return pt.y };
    if let Some((z, _)) = surface_at(app, view, pt) {
        return z;
    }
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
            let look = rc_core::section::section_look(a, pt);
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

pub(crate) fn selection_center(app: &App) -> DVec2 {
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
        ToolKind::Offset if app.opts.offset_graphical => {
            // Pick the element, then two points: their distance across the element is the offset.
            let picked = app.tool.picked.first().copied();
            let Some(id) = picked else {
                let target = hover_of(app, view, d, c, xf, &linear);
                if let Some(s) = target.and_then(|id| app.el(id).and_then(element_curve)) {
                    draw_segs(painter, xf, &[s], Stroke::new(2.5, style::PRESELECT));
                }
                if clicked {
                    if let Some(id) = target {
                        app.tool.picked.push(id);
                    }
                }
                return;
            };
            let Some(Seg::Line(a, b)) = app.el(id).and_then(element_curve) else {
                app.tool.reset();
                return;
            };
            draw_segs(painter, xf, &[Seg::Line(a, b)], Stroke::new(2.5, style::SELECT));
            let Some(pt) = point else { return };
            let n = geom::perp((b - a).normalize_or_zero());
            if app.tool.pts.is_empty() {
                if clicked {
                    app.tool.pts.push(pt);
                }
                return;
            }
            let s0 = app.tool.pts[0];
            let dist = (pt - s0).dot(n);
            draw_segs(painter, xf, &[Seg::Line(a, b).offset(dist)], Stroke::new(1.5, style::PREVIEW));
            temp_dim(painter, xf, s0, s0 + n * dist, &app.doc.data.units.length(dist.abs()), 16.0);
            if clicked && dist.abs() > 1.0 {
                let copy = app.opts.offset_copy;
                let side = (a + b) / 2.0 + n * dist;
                app.run("Offset", |p| edit::offset_elements(p, &[id], dist.abs(), side, copy).map(|_| ()));
                app.tool.reset();
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
            // As in the reference app: walls, lines, beams and railings split; grids and
            // reference planes do not. Walls win when several elements overlap.
            let splittable = |e: &Element| matches!(element_curve(e), Some(Seg::Line(..))) && !matches!(e.kind, ElementKind::Grid(_) | ElementKind::RefPlane(_));
            let cands = canvas::pick_candidates(app, view, d, c, xf.len(8.0));
            let target = cands
                .iter()
                .copied()
                .find(|id| app.el(*id).is_some_and(|e| matches!(e.kind, ElementKind::Wall(_)) && splittable(e)))
                .or_else(|| cands.iter().copied().find(|id| app.el(*id).is_some_and(splittable)));
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
        ToolKind::ShowHiddenLines | ToolKind::RemoveHiddenLines => {
            let target = canvas::pick_candidates(app, view, d, c, tol).into_iter().find(|id| app.el(*id).is_some_and(|e| e.view.is_none()));
            if clicked {
                if let Some(id) = target {
                    if app.tool.picked.is_empty() {
                        app.tool.picked.push(id);
                        app.select(vec![id]);
                    } else {
                        let show = app.tool.kind == ToolKind::ShowHiddenLines;
                        let vid = view.id;
                        let obscurer = app.tool.picked[0];
                        app.run(if show { "Show Hidden Lines" } else { "Remove Hidden Lines" }, |p| {
                            if obscurer == id {
                                return Err("Pick the element that is hidden by the first one.".into());
                            }
                            let v = p.view_mut(vid).ok_or("No view.")?;
                            let before = v.hidden_lines.len();
                            v.hidden_lines.retain(|h| *h != (obscurer, id));
                            if show {
                                v.hidden_lines.push((obscurer, id));
                            } else if v.hidden_lines.len() == before {
                                return Err("These elements have no hidden lines shown.".into());
                            }
                            Ok(())
                        });
                        app.tool.picked.clear();
                        app.select(vec![]);
                    }
                }
            }
        }
        ToolKind::JoinGeometry | ToolKind::UnjoinGeometry => {
            let target = canvas::pick_candidates(app, view, d, c, tol).into_iter().find(|id| app.el(*id).is_some_and(|e| e.view.is_none() && !e.category().is_annotation()));
            if clicked {
                if let Some(id) = target {
                    if app.tool.picked.is_empty() {
                        app.tool.picked.push(id);
                        app.select(vec![id]);
                    } else {
                        let first = app.tool.picked[0];
                        let join = app.tool.kind == ToolKind::JoinGeometry;
                        let ok = app
                            .run(if join { "Join Geometry" } else { "Unjoin Geometry" }, |p| if join { edit::join_geometry(p, first, id) } else { edit::unjoin_geometry(p, first, id) })
                            .is_some();
                        // Multiple join: keep the first pick and join more to it.
                        if !(ok && join && app.opts.join_multiple) {
                            app.tool.picked.clear();
                            app.select(vec![]);
                        }
                    }
                }
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

pub(crate) fn rotate_now(app: &mut App, center: DVec2, ang: f64) {
    let ids = app.tool.ids.clone();
    let copy = app.opts.rotate_copy;
    app.run("Rotate", |p| {
        let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
        edit::rotate_elements(p, &targets, center, ang);
        Ok(())
    });
    app.typed.clear();
    // Rotate after placement goes back to placing.
    match app.opts.rotate_return.take() {
        Some(back) => {
            app.select(vec![]);
            app.set_tool(back);
        }
        None => app.set_tool(ToolKind::Select),
    }
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
