//! Navigation wheels: the 2D Wheel (Zoom, Pan, Rewind) of plans, sections and sheets, and the
//! Full Navigation Wheel of 3D views (outer: Zoom, Pan, Rewind, Orbit; inner: Center, Look,
//! Up/Down, Walk). The wheel floats under the cursor; pressing a wedge and dragging runs it.

use eframe::egui::{self, Color32, Pos2, Stroke, vec2};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Wedge {
    Zoom,
    Pan,
    Rewind,
    Orbit,
    Center,
    Look,
    Walk,
    UpDown,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct WheelState {
    pub on: bool,
    /// Wheel centre on screen (follows the cursor while no wedge is held).
    pub center: Option<Pos2>,
    pub drag: Option<Wedge>,
    /// Accumulated horizontal drag for Rewind steps.
    pub accum: f32,
}

pub const R_OUT: f32 = 78.0;
const R_MID: f32 = 40.0;
const R_HOLE: f32 = 12.0;

/// (start°, end°, inner r, outer r, wedge, label) with screen angles (0° = right, -90° = up).
fn sectors(full: bool) -> Vec<(f32, f32, f32, f32, Wedge, &'static str)> {
    if full {
        vec![
            (-135.0, -45.0, R_MID, R_OUT, Wedge::Zoom, "ZOOM"),
            (-45.0, 45.0, R_MID, R_OUT, Wedge::Pan, "PAN"),
            (45.0, 135.0, R_MID, R_OUT, Wedge::Rewind, "REWIND"),
            (135.0, 225.0, R_MID, R_OUT, Wedge::Orbit, "ORBIT"),
            (-135.0, -45.0, R_HOLE, R_MID, Wedge::Center, "CENTER"),
            (-45.0, 45.0, R_HOLE, R_MID, Wedge::Look, "LOOK"),
            (45.0, 135.0, R_HOLE, R_MID, Wedge::UpDown, "UP/DOWN"),
            (135.0, 225.0, R_HOLE, R_MID, Wedge::Walk, "WALK"),
        ]
    } else {
        vec![
            (-150.0, -30.0, R_HOLE + 10.0, R_OUT - 6.0, Wedge::Zoom, "ZOOM"),
            (-30.0, 30.0, R_HOLE + 10.0, R_OUT - 6.0, Wedge::Pan, "PAN"),
            (30.0, 150.0, R_HOLE + 10.0, R_OUT - 6.0, Wedge::Rewind, "REWIND"),
            (150.0, 210.0, R_HOLE + 10.0, R_OUT - 6.0, Wedge::Pan, "PAN"),
        ]
    }
}

fn in_range(ang: f32, a0: f32, a1: f32) -> bool {
    let mut a = ang;
    while a < a0 {
        a += 360.0;
    }
    a < a1
}

pub fn wedge_at(full: bool, c: Pos2, p: Pos2) -> Option<Wedge> {
    let v = p - c;
    let d = v.length();
    let ang = v.y.atan2(v.x).to_degrees();
    sectors(full).into_iter().find(|(a0, a1, r0, r1, _, _)| d >= *r0 && d <= *r1 && in_range(ang, *a0, *a1)).map(|s| s.4)
}

pub fn load(ui: &egui::Ui, view: u32) -> WheelState {
    ui.memory(|m| m.data.get_temp(egui::Id::new(("nav-wheel", view)))).unwrap_or_default()
}

pub fn store(ui: &egui::Ui, view: u32, s: WheelState) {
    ui.memory_mut(|m| m.data.insert_temp(egui::Id::new(("nav-wheel", view)), s));
}

/// Keeps the wheel under the cursor: it moves only when the cursor pushes past its rim.
pub fn follow(s: &mut WheelState, p: Pos2) -> Pos2 {
    let c = s.center.unwrap_or(p);
    let v = p - c;
    let c = if v.length() > R_OUT - 14.0 { p - v.normalized() * (R_OUT - 14.0) } else { c };
    s.center = Some(c);
    c
}

fn sector_mesh(c: Pos2, a0: f32, a1: f32, r0: f32, r1: f32, color: Color32) -> egui::Mesh {
    let mut m = egui::Mesh::default();
    let n = 16;
    for k in 0..=n {
        let a = (a0 + (a1 - a0) * k as f32 / n as f32).to_radians();
        let d = vec2(a.cos(), a.sin());
        m.colored_vertex(c + d * r0, color);
        m.colored_vertex(c + d * r1, color);
    }
    for k in 0..n {
        let i = (k * 2) as u32;
        m.add_triangle(i, i + 1, i + 2);
        m.add_triangle(i + 1, i + 3, i + 2);
    }
    m
}

pub fn paint(p: &egui::Painter, c: Pos2, full: bool, hot: Option<Wedge>, held: Option<Wedge>) {
    p.circle_filled(c + vec2(2.0, 3.0), R_OUT + 1.0, Color32::from_black_alpha(40));
    for (a0, a1, r0, r1, w, label) in sectors(full) {
        let inner = r1 <= R_MID + 0.1 && full;
        let base = if inner { Color32::from_rgba_unmultiplied(70, 76, 86, 225) } else { Color32::from_rgba_unmultiplied(44, 48, 56, 215) };
        let fill = if held == Some(w) {
            Color32::from_rgba_unmultiplied(40, 110, 200, 235)
        } else if hot == Some(w) {
            Color32::from_rgba_unmultiplied(70, 130, 210, 225)
        } else {
            base
        };
        p.add(egui::Shape::mesh(sector_mesh(c, a0, a1, r0, r1, fill)));
        let edge = Stroke::new(1.0, Color32::from_rgba_unmultiplied(255, 255, 255, 70));
        for a in [a0, a1] {
            let d = vec2(a.to_radians().cos(), a.to_radians().sin());
            p.line_segment([c + d * r0, c + d * r1], edge);
        }
        let am = ((a0 + a1) / 2.0).to_radians();
        let at = c + vec2(am.cos(), am.sin()) * ((r0 + r1) / 2.0);
        p.text(at, egui::Align2::CENTER_CENTER, label, crate::style::bold(if inner { 8.5 } else { 10.0 }), Color32::WHITE);
    }
    p.circle_stroke(c, R_OUT, Stroke::new(1.0, Color32::from_rgba_unmultiplied(255, 255, 255, 90)));
    p.circle_filled(c, 3.0, Color32::from_rgba_unmultiplied(255, 255, 255, 200));
    // Close cross at the top right of the wheel.
    let x = c + vec2(R_OUT * 0.72, -R_OUT * 0.72);
    p.circle_filled(x, 8.0, Color32::from_rgba_unmultiplied(44, 48, 56, 230));
    let st = Stroke::new(1.3, Color32::WHITE);
    p.line_segment([x + vec2(-3.0, -3.0), x + vec2(3.0, 3.0)], st);
    p.line_segment([x + vec2(3.0, -3.0), x + vec2(-3.0, 3.0)], st);
}

/// Is `p` on the wheel's close button?
pub fn on_close(c: Pos2, p: Pos2) -> bool {
    p.distance(c + vec2(R_OUT * 0.72, -R_OUT * 0.72)) <= 9.0
}

pub fn prompt(w: Option<Wedge>) -> &'static str {
    match w {
        Some(Wedge::Zoom) => "Zoom: drag up to zoom in, down to zoom out.",
        Some(Wedge::Pan) => "Pan: drag to move the view.",
        Some(Wedge::Rewind) => "Rewind: drag left to step back through previous views, right to step forward.",
        Some(Wedge::Orbit) => "Orbit: drag to rotate the view around its pivot.",
        Some(Wedge::Center) => "Center: click a point on the model to make it the pivot.",
        Some(Wedge::Look) => "Look: drag to turn the view direction.",
        Some(Wedge::Walk) => "Walk: drag up to move forward, down to move back.",
        Some(Wedge::UpDown) => "Up/Down: drag to move the view up or down.",
        None => "Navigation wheel: press a wedge and drag. Esc or the cross closes it.",
    }
}

