//! Original vector icons for the ribbon, toolbars and palettes, drawn with the egui painter so
//! they stay crisp at any size and follow the light/dark theme.

use crate::style;
use eframe::egui::{self, Color32, Painter, Pos2, Rect, Stroke, pos2};
use std::f32::consts::{FRAC_PI_2, PI, TAU};

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
#[allow(dead_code)]
pub enum Icon {
    Modify,
    Wall,
    WallStructural,
    Door,
    Window,
    Component,
    Column,
    StructColumn,
    RoofFootprint,
    RoofExtrusion,
    Ceiling,
    Floor,
    FloorStructural,
    CurtainWall,
    CurtainGrid,
    Railing,
    Stair,
    ModelLine,
    ModelText,
    PlaceGroup,
    CreateGroup,
    Room,
    RoomSeparator,
    RoomTag,
    Area,
    AreaBoundary,
    AreaTag,
    Shaft,
    WallOpening,
    VerticalOpening,
    DormerOpening,
    PrintPreview,
    FeControl,
    FeCategory,
    PrintSetup,
    Subdivide,
    Mullion,
    SlantedColumn,
    MullionGridLine,
    MullionSegment,
    MullionAllLines,
    Level,
    Grid,
    RefPlane,
    WorkPlane,
    Beam,
    Globe,
    Picture,
    LoadAsGroup,
    TransferStandards,
    TreadNumber,
    StartingView,
    Brace,
    Truss,
    BeamSystem,
    WallFoundation,
    IsolatedFoundation,
    DimAligned,
    DimLinear,
    DimAngular,
    DimRadial,
    DimDiameter,
    DimArcLength,
    SpotElevation,
    DetailLine,
    FilledRegion,
    MaskingRegion,
    RevisionCloud,
    Text,
    TagByCategory,
    TagAll,
    Symbol,
    NorthArrow,
    View3D,
    Section,
    Callout,
    FloorPlan,
    CeilingPlan,
    AreaPlan,
    Elevation,
    DraftingView,
    DuplicateView,
    Legend,
    Schedule,
    MaterialTakeoff,
    SheetList,
    Sheet,
    PlaceView,
    Revisions,
    ViewTemplates,
    VisibilityGraphics,
    ThinLines,
    SwitchWindows,
    CloseInactive,
    TabViews,
    TileViews,
    UserInterface,
    Materials,
    ObjectStyles,
    Snaps,
    ProjectInfo,
    ProjectUnits,
    Purge,
    Phases,
    DesignOptions,
    Sun,
    LinkCad,
    LinkRevit,
    ImportCad,
    ImportIfc,
    LoadFamily,
    Align,
    Offset,
    MirrorPick,
    MirrorDraw,
    Move,
    Copy,
    Rotate,
    TrimCorner,
    TrimSingle,
    TrimMulti,
    Split,
    SplitGap,
    Pin,
    Unpin,
    Array,
    Scale,
    Delete,
    MatchType,
    Measure,
    Cut,
    CopyClip,
    Paste,
    TypeProperties,
    Properties,
    HideInView,
    OverrideGraphics,
    CreateSimilar,
    Finish,
    Cancel,
    DrawLine,
    DrawRect,
    DrawPolyIn,
    DrawPolyCirc,
    DrawSpline,
    ModelInPlace,
    BoundaryLine,
    SlopeArrow,
    SpanDirection,
    AlignEaves,
    StairRun,
    Ramp,
    PlaceRoomsAuto,
    HighlightBoundaries,
    RampRiser,
    StairLanding,
    StairSupport,
    StairStraight,
    ConnectLevels,
    PickNewHost,
    AdjustHeight,
    AdjustOverhang,
    WorkPlaneShow,
    WorkPlaneViewer,
    DrawEllipse,
    DrawPartialEllipse,
    DrawCircle,
    DrawArc3,
    DrawArcCenter,
    DrawArcTangent,
    DrawFillet,
    PickLines,
    PickWalls,
    EditBoundary,
    AttachTop,
    Detach,
    EditGroup,
    Ungroup,
    EditFamily,
    Undo,
    Redo,
    Save,
    Open,
    New,
    Close,
    Print,
    Export,
    Image,
    Pdf,
    Dxf,
    Ifc,
    Filter,
    SelectLinks,
    SelectUnderlay,
    SelectPinned,
    SelectByFace,
    DragOnSelect,
    Shadows,
    Crop,
    CropShow,
    TempHide,
    RevealHidden,
    DetailLevel,
    VisualStyle,
    Home,
    ZoomFit,
    ZoomRegion,
    Orbit,
    Pan,
    Ids,
    Warnings,
    Options,
    Keyboard,
    Info,
    Wireframe,
    HiddenLine,
    Shaded,
    Consistent,
    Realistic,
    Demolish,
    WallJoins,
    JoinGeometry,
    SectionBox,
    Camera,
    FamilyTypes,
    Extrusion,
    Blend,
    Revolve,
    Sweep,
    VoidForm,
    Label,
    LoadIntoProject,
    ViewRange,
    Search,
    Mass,
    ShowMass,
    WallByFace,
    FloorByFace,
    RoofByFace,
    CurtainByFace,
    Toposolid,
    SiteComponent,
    ParkingComponent,
    PropertyLine,
    SubElements,
    ColorLegend,
    ProjectParams,
    ViewFilters,
    LineStyles,
    AdditionalSettings,
    SelSave,
    SelLoad,
    SelEdit,
    SpotCoordinate,
    SpotSlope,
    FindReplace,
    ScopeBox,
    Insulation,
    DetailComponent,
    MultiTag,
    MaterialTag,
    UnjoinGeometry,
    CanvasTheme,
    ShowHidden,
    RemoveHidden,
    GlobalParams,
    DetailGroup,
    Keynote,
    ActivateView,
    GuideGrid,
    TitleBlock,
    Matchline,
    ViewReference,
    Paint,
}

const BLUE: Color32 = Color32::from_rgb(40, 112, 205);
const LBLUE: Color32 = Color32::from_rgb(168, 204, 240);
const GREEN: Color32 = Color32::from_rgb(56, 150, 66);
const LGREEN: Color32 = Color32::from_rgb(192, 226, 182);
const ORANGE: Color32 = Color32::from_rgb(232, 140, 36);
const YELLOW: Color32 = Color32::from_rgb(246, 204, 64);
const RED: Color32 = Color32::from_rgb(208, 52, 52);
const GREY: Color32 = Color32::from_rgb(150, 152, 158);
const LGREY: Color32 = Color32::from_rgb(214, 216, 222);
const BROWN: Color32 = Color32::from_rgb(176, 124, 78);
const LBROWN: Color32 = Color32::from_rgb(226, 196, 160);
const PURPLE: Color32 = Color32::from_rgb(132, 82, 176);
const MAGENTA: Color32 = Color32::from_rgb(200, 40, 160);
const CYAN: Color32 = Color32::from_rgb(0, 160, 170);
// Shaded "solid" palette of the building tools: soft greys with blue accents.
const OUTLINE: Color32 = Color32::from_rgb(104, 107, 112);
const G0: Color32 = Color32::from_rgb(248, 248, 249);
const G1: Color32 = Color32::from_rgb(226, 227, 230);
const G2: Color32 = Color32::from_rgb(196, 198, 202);
const G3: Color32 = Color32::from_rgb(160, 162, 168);
const G4: Color32 = Color32::from_rgb(120, 123, 130);
const SKY: Color32 = Color32::from_rgb(92, 166, 236);
const LSKY: Color32 = Color32::from_rgb(170, 210, 246);

fn mix(a: Color32, b: Color32, t: f32) -> Color32 {
    let t = t.clamp(0.0, 1.0);
    let f = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t).round() as u8;
    Color32::from_rgb(f(a.r(), b.r()), f(a.g(), b.g()), f(a.b(), b.b()))
}

struct Pen<'a> {
    p: &'a Painter,
    r: Rect,
    ink: Color32,
    w: f32,
}

type Pt = (f32, f32);

impl Pen<'_> {
    fn at(&self, (x, y): Pt) -> Pos2 {
        pos2(self.r.left() + x * self.r.width(), self.r.top() + y * self.r.height())
    }
    fn s(&self, k: f32) -> f32 {
        k * self.r.width()
    }
    fn st(&self, c: Color32) -> Stroke {
        Stroke::new(self.w, c)
    }
    fn thin(&self, c: Color32) -> Stroke {
        Stroke::new((self.w * 0.65).max(0.8), c)
    }
    fn line(&self, pts: &[Pt], c: Color32) {
        self.p.add(egui::Shape::line(pts.iter().map(|q| self.at(*q)).collect(), self.st(c)));
    }
    fn line_w(&self, pts: &[Pt], c: Color32, w: f32) {
        self.p.add(egui::Shape::line(pts.iter().map(|q| self.at(*q)).collect(), Stroke::new(w, c)));
    }
    fn thin_line(&self, pts: &[Pt], c: Color32) {
        self.p.add(egui::Shape::line(pts.iter().map(|q| self.at(*q)).collect(), self.thin(c)));
    }
    fn dashed(&self, a: Pt, b: Pt, c: Color32) {
        let d = self.s(0.09);
        self.p.extend(egui::Shape::dashed_line(&[self.at(a), self.at(b)], self.thin(c), d, d * 0.6));
    }
    fn dashdot(&self, a: Pt, b: Pt, c: Color32) {
        let d = self.s(0.14);
        self.p.extend(egui::Shape::dashed_line(&[self.at(a), self.at(b)], self.thin(c), d, d * 0.45));
    }
    fn poly(&self, pts: &[Pt], fill: Color32, stroke: Color32) {
        let v: Vec<Pos2> = pts.iter().map(|q| self.at(*q)).collect();
        self.p.add(egui::Shape::convex_polygon(v, fill, self.st(stroke)));
    }
    fn poly_fill(&self, pts: &[Pt], fill: Color32) {
        let v: Vec<Pos2> = pts.iter().map(|q| self.at(*q)).collect();
        self.p.add(egui::Shape::convex_polygon(v, fill, Stroke::NONE));
    }
    fn closed(&self, pts: &[Pt], c: Color32) {
        self.p.add(egui::Shape::closed_line(pts.iter().map(|q| self.at(*q)).collect(), self.st(c)));
    }
    fn rect(&self, x0: f32, y0: f32, x1: f32, y1: f32, fill: Color32, stroke: Color32) {
        let r = Rect::from_min_max(self.at((x0, y0)), self.at((x1, y1)));
        self.p.rect_filled(r, 0.0, fill);
        if stroke != Color32::TRANSPARENT {
            self.p.rect_stroke(r, 0.0, self.st(stroke), egui::StrokeKind::Middle);
        }
    }
    fn rect_thin(&self, x0: f32, y0: f32, x1: f32, y1: f32, fill: Color32, stroke: Color32) {
        let r = Rect::from_min_max(self.at((x0, y0)), self.at((x1, y1)));
        self.p.rect_filled(r, 0.0, fill);
        self.p.rect_stroke(r, 0.0, self.thin(stroke), egui::StrokeKind::Middle);
    }
    fn circle(&self, c: Pt, rad: f32, fill: Color32, stroke: Color32) {
        self.p.circle(self.at(c), self.s(rad), fill, if stroke == Color32::TRANSPARENT { Stroke::NONE } else { self.st(stroke) });
    }
    fn dot(&self, c: Pt, rad: f32, fill: Color32) {
        self.p.circle_filled(self.at(c), self.s(rad).max(1.2), fill);
    }
    fn arc(&self, c: Pt, rad: f32, a0: f32, a1: f32, col: Color32) {
        let n = 20;
        let pts: Vec<Pos2> = (0..=n)
            .map(|k| {
                let a = a0 + (a1 - a0) * k as f32 / n as f32;
                self.at((c.0 + rad * a.cos(), c.1 + rad * a.sin()))
            })
            .collect();
        self.p.add(egui::Shape::line(pts, self.st(col)));
    }
    fn arrow_head(&self, tip: Pt, from: Pt, col: Color32, size: f32) {
        let d = (tip.0 - from.0, tip.1 - from.1);
        let len = (d.0 * d.0 + d.1 * d.1).sqrt().max(1e-6);
        let (ux, uy) = (d.0 / len, d.1 / len);
        let (nx, ny) = (-uy, ux);
        let b = (tip.0 - ux * size, tip.1 - uy * size);
        self.poly_fill(&[tip, (b.0 + nx * size * 0.55, b.1 + ny * size * 0.55), (b.0 - nx * size * 0.55, b.1 - ny * size * 0.55)], col);
    }
    fn arrow(&self, a: Pt, b: Pt, col: Color32) {
        self.line(&[a, b], col);
        self.arrow_head(b, a, col, 0.16);
    }
    fn text(&self, c: Pt, s: &str, size: f32, col: Color32) {
        self.p.text(self.at(c), egui::Align2::CENTER_CENTER, s, egui::FontId::proportional(self.s(size)), col);
    }
    fn text_bold(&self, c: Pt, s: &str, size: f32, col: Color32) {
        // Faux bold: two passes.
        self.text(c, s, size, col);
        self.text((c.0 + 0.012, c.1), s, size, col);
    }
    fn wall_plan(&self, y0: f32, y1: f32) {
        self.rect(0.08, y0, 0.92, y1, LGREY, self.ink);
        self.hatch(0.08, y0, 0.92, y1);
    }
    fn hatch(&self, x0: f32, y0: f32, x1: f32, y1: f32) {
        let h = y1 - y0;
        let mut x = x0 + h * 0.6;
        while x < x1 + h {
            let a = (x - h, y1);
            let b = (x, y0);
            let (ax, ay) = if a.0 < x0 { (x0, y1 - (x0 - a.0)) } else { a };
            let (bx, by) = if b.0 > x1 { (x1, y0 + (b.0 - x1)) } else { b };
            if ax < bx {
                self.thin_line(&[(ax, ay), (bx, by)], GREY);
            }
            x += h * 0.7;
        }
    }
    fn cube(&self, ox: f32, oy: f32, s: f32, top: Color32, left: Color32, right: Color32) {
        let a = (ox, oy - s * 0.55);
        let b = (ox + s * 0.5, oy - s * 0.3);
        let c = (ox, oy - s * 0.05);
        let d = (ox - s * 0.5, oy - s * 0.3);
        self.poly(&[a, b, c, d], top, self.ink);
        self.poly(&[d, c, (ox, oy + s * 0.5), (ox - s * 0.5, oy + s * 0.25)], left, self.ink);
        self.poly(&[c, b, (ox + s * 0.5, oy + s * 0.25), (ox, oy + s * 0.5)], right, self.ink);
    }
    fn sheet(&self, x0: f32, y0: f32, x1: f32, y1: f32) {
        self.rect(x0, y0, x1, y1, Color32::WHITE, self.ink);
        self.rect_thin(x1 - (x1 - x0) * 0.32, y1 - (y1 - y0) * 0.28, x1, y1, LBLUE, self.ink);
    }
    fn plan_tile(&self, accent: Color32) {
        self.rect(0.1, 0.12, 0.9, 0.88, Color32::WHITE, self.ink);
        self.line(&[(0.22, 0.26), (0.78, 0.26), (0.78, 0.74), (0.22, 0.74), (0.22, 0.26)], accent);
        self.line(&[(0.5, 0.26), (0.5, 0.5)], accent);
    }
    fn pencil(&self, x: f32, y: f32, s: f32) {
        // A small pencil at the bottom right: the "draw" marker.
        let a = (x, y);
        let b = (x + s, y - s);
        self.line_w(&[a, b], ORANGE, self.w * 1.8);
        self.dot(a, 0.035, self.ink);
    }
    /// A convex face shaded from c0 at the top to c1 at the bottom (or left to right when
    /// horizontal), with a soft outline.
    fn shade(&self, pts: &[Pt], c0: Color32, c1: Color32, horizontal: bool) {
        let v: Vec<Pos2> = pts.iter().map(|q| self.at(*q)).collect();
        let key = |p: &Pos2| if horizontal { p.x } else { p.y };
        let lo = v.iter().map(key).fold(f32::MAX, f32::min);
        let hi = v.iter().map(key).fold(f32::MIN, f32::max);
        let mut m = egui::Mesh::default();
        for p in &v {
            m.colored_vertex(*p, mix(c0, c1, (key(p) - lo) / (hi - lo).max(1e-3)));
        }
        for k in 1..v.len().saturating_sub(1) {
            m.add_triangle(0, k as u32, k as u32 + 1);
        }
        self.p.add(m);
        self.outline(&v);
    }
    /// Edges drawn one by one: sharp corners would otherwise grow long miter spikes.
    fn outline(&self, v: &[Pos2]) {
        for k in 0..v.len() {
            self.p.line_segment([v[k], v[(k + 1) % v.len()]], self.thin(OUTLINE));
        }
    }
    /// A curved band between two polylines, shaded along its length.
    fn band(&self, top: &[Pt], bot: &[Pt], c0: Color32, c1: Color32) {
        let n = top.len();
        let mut m = egui::Mesh::default();
        for k in 0..n {
            let c = mix(c0, c1, k as f32 / (n - 1).max(1) as f32);
            m.colored_vertex(self.at(top[k]), c);
            m.colored_vertex(self.at(bot[k]), c);
        }
        for k in 0..n as u32 - 1 {
            m.add_triangle(2 * k, 2 * k + 1, 2 * k + 2);
            m.add_triangle(2 * k + 1, 2 * k + 3, 2 * k + 2);
        }
        self.p.add(m);
        let mut outline: Vec<Pos2> = top.iter().map(|q| self.at(*q)).collect();
        outline.extend(bot.iter().rev().map(|q| self.at(*q)));
        self.outline(&outline);
    }
    /// An isometric box from its front bottom corner: w runs right-up, d left-up.
    fn solid_box(&self, ox: f32, oy: f32, w: f32, d: f32, h: f32) {
        let f = (ox, oy);
        let r = (ox + w * 0.87, oy - w * 0.5);
        let l = (ox - d * 0.87, oy - d * 0.5);
        let back = (r.0 + l.0 - ox, r.1 + l.1 - oy);
        let up = |p: Pt| (p.0, p.1 - h);
        self.shade(&[l, f, up(f), up(l)], G1, G2, false);
        self.shade(&[f, r, up(r), up(f)], G2, G3, false);
        self.shade(&[up(f), up(r), up(back), up(l)], G0, G1, false);
    }
    fn ellipse_pts(&self, c: Pt, rx: f32, ry: f32, a0: f32, a1: f32, n: usize) -> Vec<Pt> {
        (0..=n)
            .map(|k| {
                let a = a0 + (a1 - a0) * k as f32 / n as f32;
                (c.0 + rx * a.cos(), c.1 + ry * a.sin())
            })
            .collect()
    }
    fn star(&self, c: Pt, r: f32, col: Color32) {
        let pts: Vec<Pt> = (0..10)
            .map(|k| {
                let a = -FRAC_PI_2 + k as f32 * PI / 5.0;
                let rr = if k % 2 == 0 { r } else { r * 0.45 };
                (c.0 + rr * a.cos(), c.1 + rr * a.sin())
            })
            .collect();
        for k in 0..10 {
            if k % 2 == 0 {
                self.poly_fill(&[c, pts[k], pts[(k + 1) % 10]], col);
                self.poly_fill(&[c, pts[k], pts[(k + 9) % 10]], col);
            }
        }
    }
}

/// Paints `icon` filling `rect`.
pub fn paint(p: &Painter, rect: Rect, icon: Icon, enabled: bool) {
    let ink = if enabled { style::icon_ink() } else { GREY };
    let w = (rect.width() / 18.0).clamp(1.0, 2.2);
    let pen = Pen { p, r: rect, ink, w };
    draw(&pen, icon);
    if !enabled {
        p.rect_filled(rect, 0.0, if style::is_dark() { Color32::from_rgba_unmultiplied(56, 59, 65, 150) } else { Color32::from_rgba_unmultiplied(250, 250, 251, 150) });
    }
}

fn draw(g: &Pen, icon: Icon) {
    let ink = g.ink;
    use Icon::*;
    match icon {
        Modify => {
            g.poly(&[(0.3, 0.1), (0.3, 0.8), (0.45, 0.64), (0.57, 0.9), (0.67, 0.85), (0.55, 0.6), (0.76, 0.6)], Color32::WHITE, ink);
        }
        Wall => {
            // A gently curved wall: shaded face, lit top, darker end.
            let n = 10;
            let front: Vec<Pt> = (0..=n)
                .map(|k| {
                    let t = k as f32 / n as f32;
                    (0.1 + 0.62 * t, 0.36 - 0.16 * t + 0.16 * t * (1.0 - t))
                })
                .collect();
            let back: Vec<Pt> = front.iter().map(|p| (p.0 + 0.14, p.1 - 0.08)).collect();
            let bottom: Vec<Pt> = front.iter().map(|p| (p.0, p.1 + 0.46)).collect();
            g.band(&back, &front, G0, G1);
            let (e, eb) = (front[n], back[n]);
            g.shade(&[e, eb, (eb.0, eb.1 + 0.46), (e.0, e.1 + 0.46)], G3, G4, false);
            g.band(&front, &bottom, G1, G3);
        }
        WallStructural => {
            draw(g, Wall);
            g.line_w(&[(0.2, 0.62), (0.52, 0.49)], BLUE, g.w * 1.6);
        }
        CurtainWall => {
            // A curved glazed wall with a mullion grid.
            let n = 12;
            let curve = |t: f32| (0.1 + 0.8 * t, 0.26 - 0.08 * t + 0.2 * t * (1.0 - t));
            let top: Vec<Pt> = (0..=n).map(|k| curve(k as f32 / n as f32)).collect();
            let bot: Vec<Pt> = top.iter().map(|p| (p.0, p.1 + 0.56)).collect();
            g.band(&top, &bot, LSKY, SKY);
            for k in [3, 6, 9] {
                g.thin_line(&[top[k], bot[k]], BLUE);
            }
            let mid: Vec<Pt> = top.iter().map(|p| (p.0, p.1 + 0.28)).collect();
            g.thin_line(&mid, BLUE);
            g.line(&top, BLUE);
            g.line(&bot, BLUE);
        }
        Door => {
            // Frame, dark opening and a leaf swung towards the viewer.
            g.shade(&[(0.24, 0.08), (0.74, 0.08), (0.74, 0.92), (0.24, 0.92)], G1, G2, false);
            g.shade(&[(0.3, 0.14), (0.68, 0.14), (0.68, 0.92), (0.3, 0.92)], G3, G4, false);
            g.shade(&[(0.3, 0.14), (0.54, 0.22), (0.54, 0.98), (0.3, 0.92)], G0, G2, true);
            g.dot((0.5, 0.58), 0.03, G4);
        }
        Window => {
            // Frame with four lights over a projecting sill.
            g.shade(&[(0.16, 0.1), (0.84, 0.1), (0.84, 0.8), (0.16, 0.8)], G2, G3, false);
            for (x0, x1) in [(0.23, 0.47), (0.53, 0.77)] {
                for (y0, y1) in [(0.17, 0.42), (0.48, 0.74)] {
                    g.shade(&[(x0, y0), (x1, y0), (x1, y1), (x0, y1)], G0, G1, false);
                }
            }
            g.shade(&[(0.08, 0.8), (0.92, 0.8), (0.88, 0.9), (0.12, 0.9)], G1, G3, false);
        }
        Component => {
            // Two stacked blocks: a loadable "thing".
            g.solid_box(0.5, 0.92, 0.42, 0.42, 0.26);
            g.solid_box(0.6, 0.55, 0.22, 0.22, 0.3);
        }
        Column => {
            // A round column: shaft shaded across, lit top.
            let (cx, rx, ry, y0, y1) = (0.5, 0.17, 0.06, 0.16, 0.86);
            let xs: Vec<f32> = (0..=12).map(|k| cx - rx + 2.0 * rx * k as f32 / 12.0).collect();
            let top: Vec<Pt> = xs.iter().map(|x| (*x, y0)).collect();
            let bot: Vec<Pt> = xs
                .iter()
                .map(|x| {
                    let u = (x - cx) / rx;
                    (*x, y1 + ry * (1.0 - u * u).max(0.0).sqrt())
                })
                .collect();
            g.band(&top, &bot, G1, G4);
            g.shade(&g.ellipse_pts((cx, y0), rx, ry, 0.0, TAU, 24), G0, G1, false);
        }
        StructColumn => {
            g.rect(0.3, 0.1, 0.7, 0.18, BLUE, ink);
            g.rect(0.3, 0.82, 0.7, 0.9, BLUE, ink);
            g.rect(0.45, 0.18, 0.55, 0.82, BLUE, ink);
        }
        RoofFootprint => {
            // A hip roof over its eaves.
            let (a, b, c, d) = ((0.06, 0.6), (0.54, 0.84), (0.94, 0.62), (0.46, 0.38));
            let (r1, r2) = ((0.36, 0.24), (0.62, 0.34));
            let low = |p: Pt| (p.0, p.1 + 0.06);
            g.shade(&[d, r1, r2, c], G2, G2, false);
            g.shade(&[a, b, low(b), low(a)], G3, G4, false);
            g.shade(&[b, c, low(c), low(b)], G4, G4, false);
            g.shade(&[a, r1, d], G0, G1, false);
            g.shade(&[a, b, r2, r1], G1, G2, false);
            g.shade(&[b, c, r2], G2, G3, false);
        }
        RoofExtrusion => {
            // A gable roof: lit slope, shaded slope and fascia.
            let (a, b, ridge0, c, d, ridge1) = ((0.08, 0.66), (0.4, 0.82), (0.24, 0.36), (0.92, 0.56), (0.6, 0.4), (0.76, 0.1));
            let low = |p: Pt| (p.0, p.1 + 0.07);
            g.shade(&[ridge0, ridge1, d, a], G0, G1, false);
            g.shade(&[a, b, low(b), low(a)], G3, G4, false);
            g.shade(&[ridge0, b, a], G1, G2, false);
            g.shade(&[ridge0, ridge1, c, b], G1, G3, false);
            g.shade(&[b, c, low(c), low(b)], G4, G4, false);
        }
        Ceiling => {
            // A thin slab with a blue gridded patch and a light below.
            let (a, b, c, d) = ((0.18, 0.2), (0.94, 0.2), (0.82, 0.5), (0.06, 0.5));
            let low = |p: Pt| (p.0, p.1 + 0.06);
            g.shade(&[d, c, low(c), low(d)], G2, G3, false);
            g.shade(&[c, b, low(b), low(c)], G3, G3, false);
            g.shade(&[a, b, c, d], G0, G1, false);
            let p = |u: f32, v: f32| (a.0 + (b.0 - a.0) * u + (d.0 - a.0) * v, a.1 + (d.1 - a.1) * v);
            g.shade(&[p(0.3, 0.3), p(0.9, 0.3), p(0.9, 0.9), p(0.3, 0.9)], LSKY, SKY, false);
            for k in 1..4 {
                let t = 0.3 + 0.6 * k as f32 / 4.0;
                g.thin_line(&[p(t, 0.3), p(t, 0.9)], Color32::WHITE);
            }
            g.thin_line(&[p(0.3, 0.6), p(0.9, 0.6)], Color32::WHITE);
            g.thin_line(&[(0.5, 0.56), (0.5, 0.74)], G3);
            g.circle((0.5, 0.79), 0.05, YELLOW, OUTLINE);
        }
        Floor => {
            // A slab with a blue hatched patch on top.
            let (a, b, c, d) = ((0.26, 0.34), (0.96, 0.34), (0.76, 0.64), (0.04, 0.64));
            let low = |p: Pt| (p.0, p.1 + 0.1);
            g.shade(&[d, c, low(c), low(d)], G2, G3, false);
            g.shade(&[c, b, low(b), low(c)], G3, G4, false);
            g.shade(&[a, b, c, d], G0, G1, false);
            let p = |u: f32, v: f32| (a.0 + (b.0 - a.0) * u + (d.0 - a.0) * v, a.1 + (d.1 - a.1) * v);
            g.shade(&[p(0.3, 0.35), p(0.85, 0.35), p(0.85, 0.85), p(0.3, 0.85)], LSKY, SKY, false);
            for k in 0..4 {
                let u = 0.36 + 0.13 * k as f32;
                g.thin_line(&[p(u, 0.82), p(u + 0.1, 0.38)], Color32::WHITE);
            }
        }
        FloorStructural => {
            draw(g, Floor);
            g.line_w(&[(0.12, 0.69), (0.7, 0.69)], BLUE, g.w * 1.6);
        }
        CurtainGrid => {
            // A panel divided by blue grid lines.
            g.shade(&[(0.14, 0.1), (0.86, 0.1), (0.86, 0.9), (0.14, 0.9)], G0, G1, false);
            for x in [0.38, 0.62] {
                g.line(&[(x, 0.1), (x, 0.9)], SKY);
            }
            g.line(&[(0.14, 0.5), (0.86, 0.5)], SKY);
            g.closed(&[(0.14, 0.1), (0.86, 0.1), (0.86, 0.9), (0.14, 0.9)], BLUE);
        }
        Railing => {
            // Blue rails and balusters in slight perspective.
            let top = |t: f32| (0.08 + 0.84 * t, 0.3 - 0.1 * t);
            let bot = |t: f32| (0.08 + 0.84 * t, 0.84 - 0.1 * t);
            for k in 0..=6 {
                let t = k as f32 / 6.0;
                g.line(&[top(t), bot(t)], SKY);
            }
            g.line_w(&[top(0.0), top(1.0)], BLUE, g.w * 1.6);
            g.line(&[bot(0.0), bot(1.0)], BLUE);
        }
        Stair => {
            // Four steps: lit treads, light risers, shaded side.
            let (dx, dy) = (0.14, -0.1);
            let steps = 4;
            let (x0, y0, run, rise) = (0.06, 0.9, 0.17, 0.16);
            for k in 0..steps {
                let x = x0 + run * k as f32;
                let y = y0 - rise * (k + 1) as f32;
                g.shade(&[(x, y + rise), (x, y), (x + dx, y + dy), (x + dx, y + rise + dy)], G1, G2, false);
                g.shade(&[(x, y), (x + run, y), (x + run + dx, y + dy), (x + dx, y + dy)], G0, G0, false);
            }
            let xe = x0 + run * steps as f32;
            let ye = y0 - rise * steps as f32;
            g.shade(&[(xe, ye), (xe + dx, ye + dy), (xe + dx, y0 + dy), (xe, y0)], G3, G4, false);
            // The side profile is concave: fill it as columns under each tread.
            let mut side: Vec<Pt> = vec![(x0, y0)];
            for k in 0..steps {
                let x = x0 + run * k as f32;
                let y = y0 - rise * (k + 1) as f32;
                g.poly_fill(&[(x, y), (x + run, y), (x + run, y0), (x, y0)], mix(G2, G3, k as f32 / steps as f32));
                side.push((x, y));
                side.push((x + run, y));
            }
            side.push((xe, y0));
            g.closed(&side, OUTLINE);
        }
        ModelLine => {
            g.line(&[(0.12, 0.8), (0.78, 0.2)], GREEN);
            g.rect_thin(0.08, 0.76, 0.16, 0.84, Color32::WHITE, ink);
            g.rect_thin(0.74, 0.16, 0.82, 0.24, Color32::WHITE, ink);
        }
        PlaceGroup | CreateGroup => {
            g.rect(0.12, 0.2, 0.52, 0.56, LBLUE, ink);
            g.circle((0.66, 0.66), 0.2, LGREEN, ink);
            g.dashed((0.06, 0.12), (0.94, 0.12), ink);
            g.dashed((0.94, 0.12), (0.94, 0.92), ink);
            g.dashed((0.94, 0.92), (0.06, 0.92), ink);
            g.dashed((0.06, 0.92), (0.06, 0.12), ink);
            if icon == CreateGroup {
                g.star((0.84, 0.22), 0.12, YELLOW);
            }
        }
        Room => {
            g.rect(0.1, 0.14, 0.9, 0.86, Color32::from_rgb(220, 236, 250), ink);
            g.thin_line(&[(0.14, 0.18), (0.86, 0.82)], BLUE);
            g.thin_line(&[(0.14, 0.82), (0.86, 0.18)], BLUE);
        }
        RoomSeparator => {
            g.rect(0.1, 0.14, 0.9, 0.86, Color32::from_rgb(220, 236, 250), ink);
            g.line_w(&[(0.5, 0.14), (0.5, 0.86)], GREEN, g.w * 1.3);
        }
        RoomTag | AreaTag => {
            g.rect(0.1, 0.14, 0.9, 0.86, if icon == RoomTag { Color32::from_rgb(220, 236, 250) } else { LGREEN }, ink);
            g.text((0.5, 0.42), if icon == RoomTag { "Room" } else { "Area" }, 0.24, ink);
            g.text((0.5, 0.66), "101", 0.22, ink);
        }
        Area => {
            g.rect(0.12, 0.2, 0.88, 0.62, LGREEN, Color32::TRANSPARENT);
            g.rect(0.12, 0.62, 0.56, 0.86, LGREEN, Color32::TRANSPARENT);
            g.closed(&[(0.12, 0.2), (0.88, 0.2), (0.88, 0.62), (0.56, 0.62), (0.56, 0.86), (0.12, 0.86)], ink);
            g.text((0.36, 0.48), "m²", 0.26, GREEN);
        }
        AreaBoundary => {
            g.rect(0.1, 0.14, 0.9, 0.86, LGREEN, ink);
            g.line_w(&[(0.1, 0.5), (0.9, 0.5)], PURPLE, g.w * 1.4);
        }
        Shaft => {
            g.rect(0.26, 0.08, 0.74, 0.92, Color32::WHITE, ink);
            g.thin_line(&[(0.26, 0.08), (0.74, 0.92)], ink);
            g.thin_line(&[(0.74, 0.08), (0.26, 0.92)], ink);
        }
        SlantedColumn => {
            g.shade(&[(0.14, 0.92), (0.36, 0.92), (0.86, 0.08), (0.64, 0.08)], G1, G3, true);
            g.closed(&[(0.14, 0.92), (0.36, 0.92), (0.86, 0.08), (0.64, 0.08)], ink);
            g.line(&[(0.04, 0.92), (0.5, 0.92)], ink);
            g.line(&[(0.5, 0.08), (0.96, 0.08)], ink);
        }
        Mullion => {
            g.rect(0.08, 0.08, 0.92, 0.92, LBLUE, ink);
            g.rect(0.44, 0.08, 0.56, 0.92, G2, ink);
            g.rect(0.08, 0.44, 0.92, 0.56, G2, ink);
        }
        MullionGridLine => {
            g.rect(0.12, 0.08, 0.88, 0.92, LBLUE, ink);
            g.dashed((0.12, 0.36), (0.88, 0.36), ink);
            g.dashed((0.12, 0.64), (0.88, 0.64), ink);
            g.rect(0.44, 0.08, 0.56, 0.92, BLUE, ink);
        }
        MullionSegment => {
            g.rect(0.12, 0.08, 0.88, 0.92, LBLUE, ink);
            g.dashed((0.12, 0.36), (0.88, 0.36), ink);
            g.dashed((0.12, 0.64), (0.88, 0.64), ink);
            g.dashed((0.5, 0.08), (0.5, 0.92), ink);
            g.rect(0.44, 0.36, 0.56, 0.64, BLUE, ink);
        }
        MullionAllLines => {
            g.rect(0.12, 0.08, 0.88, 0.92, LBLUE, ink);
            for x in [0.36f32, 0.64] {
                g.rect(x - 0.05, 0.08, x + 0.05, 0.92, BLUE, ink);
            }
            g.rect(0.12, 0.45, 0.88, 0.55, BLUE, ink);
        }
        ModelText => {
            // A raised "A" in perspective.
            g.shade(&[(0.12, 0.88), (0.42, 0.1), (0.58, 0.1), (0.88, 0.88), (0.7, 0.88), (0.5, 0.32), (0.3, 0.88)], G1, G3, false);
            g.closed(&[(0.12, 0.88), (0.42, 0.1), (0.58, 0.1), (0.88, 0.88), (0.7, 0.88), (0.5, 0.32), (0.3, 0.88)], ink);
            g.line(&[(0.36, 0.62), (0.64, 0.62)], ink);
            g.line(&[(0.58, 0.1), (0.66, 0.05), (0.96, 0.82), (0.88, 0.88)], BLUE);
        }
        FeControl => {
            // Two opposed flip arrows.
            g.line_w(&[(0.1, 0.36), (0.9, 0.36)], BLUE, g.w * 1.4);
            g.arrow_head((0.92, 0.36), (0.5, 0.36), BLUE, 0.16);
            g.line_w(&[(0.1, 0.66), (0.9, 0.66)], BLUE, g.w * 1.4);
            g.arrow_head((0.08, 0.66), (0.5, 0.66), BLUE, 0.16);
        }
        FeCategory => {
            g.rect(0.12, 0.1, 0.62, 0.6, LBLUE, ink);
            g.rect(0.4, 0.4, 0.9, 0.9, G1, ink);
            g.thin_line(&[(0.5, 0.55), (0.8, 0.55)], ink);
            g.thin_line(&[(0.5, 0.7), (0.8, 0.7)], ink);
        }
        PrintPreview => {
            g.sheet(0.12, 0.06, 0.7, 0.86);
            g.circle((0.62, 0.62), 0.18, Color32::WHITE, ink);
            g.line_w(&[(0.75, 0.75), (0.94, 0.94)], ink, g.w * 2.0);
        }
        PrintSetup => {
            g.sheet(0.12, 0.06, 0.7, 0.86);
            g.circle((0.68, 0.7), 0.16, G2, ink);
            g.dot((0.68, 0.7), 0.06, Color32::WHITE);
        }
        DormerOpening => {
            // A pitched roof with a small dormer gable rising out of it.
            g.shade(&[(0.04, 0.86), (0.5, 0.2), (0.96, 0.86)], G0, G2, false);
            g.closed(&[(0.04, 0.86), (0.5, 0.2), (0.96, 0.86)], ink);
            g.poly(&[(0.4, 0.86), (0.4, 0.62), (0.56, 0.48), (0.72, 0.62), (0.72, 0.86)], G1, ink);
            g.rect(0.5, 0.66, 0.62, 0.8, LBLUE, ink);
        }
        Subdivide => {
            g.shade(&[(0.04, 0.6), (0.5, 0.34), (0.96, 0.56), (0.5, 0.86)], Color32::from_rgb(214, 196, 160), Color32::from_rgb(176, 160, 132), false);
            g.poly(&[(0.3, 0.6), (0.52, 0.48), (0.72, 0.58), (0.5, 0.7)], Color32::from_rgb(120, 170, 90), ink);
            g.closed(&[(0.04, 0.6), (0.5, 0.34), (0.96, 0.56), (0.5, 0.86)], ink);
        }
        VerticalOpening => {
            // A slab in perspective with a hole cut through it.
            g.shade(&[(0.04, 0.56), (0.5, 0.3), (0.96, 0.5), (0.5, 0.76)], G0, G2, false);
            g.shade(&[(0.04, 0.56), (0.5, 0.76), (0.5, 0.86), (0.04, 0.66)], G2, G3, false);
            g.shade(&[(0.5, 0.76), (0.96, 0.5), (0.96, 0.6), (0.5, 0.86)], G1, G2, false);
            g.poly(&[(0.32, 0.53), (0.52, 0.42), (0.7, 0.51), (0.5, 0.62)], Color32::WHITE, ink);
            g.line(&[(0.5, 0.06), (0.5, 0.36)], BLUE);
            g.arrow_head((0.5, 0.42), (0.5, 0.06), BLUE, 0.12);
        }
        WallOpening => {
            g.rect(0.08, 0.16, 0.92, 0.84, LGREY, ink);
            g.rect(0.34, 0.34, 0.66, 0.84, Color32::WHITE, ink);
        }
        Level => {
            g.line(&[(0.06, 0.56), (0.7, 0.56)], BLUE);
            g.poly(&[(0.7, 0.56), (0.8, 0.44), (0.9, 0.56), (0.8, 0.68)], Color32::WHITE, BLUE);
            g.poly_fill(&[(0.7, 0.56), (0.8, 0.44), (0.8, 0.56)], BLUE);
            g.poly_fill(&[(0.8, 0.56), (0.9, 0.56), (0.8, 0.68)], BLUE);
            g.dashed((0.06, 0.3), (0.62, 0.3), GREY);
        }
        Grid => {
            g.dashdot((0.5, 0.36), (0.5, 0.96), BLUE);
            g.circle((0.5, 0.2), 0.16, Color32::WHITE, BLUE);
            g.text((0.5, 0.2), "1", 0.2, BLUE);
        }
        RefPlane => {
            g.dashdot((0.1, 0.9), (0.9, 0.1), GREEN);
            g.line(&[(0.1, 0.9), (0.24, 0.76)], GREEN);
            g.line(&[(0.76, 0.24), (0.9, 0.1)], GREEN);
        }
        WorkPlane => {
            g.poly(&[(0.24, 0.3), (0.94, 0.3), (0.76, 0.7), (0.06, 0.7)], Color32::from_rgba_unmultiplied(120, 180, 240, 120), BLUE);
            for k in 1..4 {
                let t = k as f32 / 4.0;
                g.thin_line(&[(0.24 + 0.7 * t, 0.3), (0.06 + 0.7 * t, 0.7)], BLUE);
            }
        }
        Beam => {
            g.poly(&[(0.06, 0.48), (0.7, 0.26), (0.94, 0.36), (0.3, 0.58)], LBLUE, ink);
            g.poly(&[(0.06, 0.48), (0.3, 0.58), (0.3, 0.74), (0.06, 0.64)], BLUE, ink);
            g.poly(&[(0.3, 0.58), (0.94, 0.36), (0.94, 0.52), (0.3, 0.74)], Color32::from_rgb(90, 150, 220), ink);
        }
        TreadNumber => {
            // A stair run in plan with numbered treads.
            g.rect(0.2, 0.08, 0.8, 0.92, Color32::WHITE, ink);
            for k in 1..4 {
                let y = 0.08 + 0.21 * k as f32;
                g.thin_line(&[(0.2, y), (0.8, y)], ink);
            }
            for (k, t) in ["1", "2", "3", "4"].iter().enumerate() {
                g.text((0.5, 0.18 + 0.21 * k as f32), t, 0.16, BLUE);
            }
        }
        LoadAsGroup => {
            // A dashed group box of two blocks, with a green load arrow.
            g.rect(0.18, 0.4, 0.5, 0.86, LGREY, ink);
            g.rect(0.56, 0.52, 0.86, 0.86, LBLUE, ink);
            let green = Color32::from_rgb(40, 150, 70);
            g.line(&[(0.66, 0.08), (0.66, 0.38)], green);
            g.poly(&[(0.56, 0.3), (0.76, 0.3), (0.66, 0.44)], green, green);
        }
        TransferStandards => {
            // Two project sheets with an arrow from one to the other.
            g.rect(0.06, 0.1, 0.46, 0.62, Color32::WHITE, ink);
            g.rect(0.54, 0.38, 0.94, 0.9, Color32::WHITE, ink);
            g.thin_line(&[(0.14, 0.24), (0.38, 0.24)], ink);
            g.thin_line(&[(0.14, 0.36), (0.38, 0.36)], ink);
            g.line(&[(0.3, 0.72), (0.3, 0.8), (0.5, 0.8)], BLUE);
            g.poly(&[(0.46, 0.73), (0.54, 0.8), (0.46, 0.87)], BLUE, BLUE);
        }
        LinkRevit => {
            // A building block with a chain link.
            g.poly(&[(0.1, 0.36), (0.44, 0.18), (0.78, 0.36), (0.44, 0.54)], LBLUE, ink);
            g.poly(&[(0.1, 0.36), (0.44, 0.54), (0.44, 0.86), (0.1, 0.68)], BLUE, ink);
            g.poly(&[(0.44, 0.54), (0.78, 0.36), (0.78, 0.68), (0.44, 0.86)], Color32::from_rgb(90, 150, 220), ink);
            let link = Color32::from_rgb(40, 110, 200);
            g.arc((0.74, 0.8), 0.1, 0.0, TAU, link);
            g.arc((0.88, 0.8), 0.1, 0.0, TAU, link);
        }
        Picture => {
            // A framed picture: sky, sun and hills.
            g.rect(0.08, 0.16, 0.92, 0.84, Color32::from_rgb(200, 225, 250), ink);
            g.circle((0.68, 0.36), 0.08, Color32::from_rgb(250, 200, 60), ink);
            g.poly(&[(0.1, 0.82), (0.36, 0.46), (0.56, 0.7), (0.7, 0.56), (0.9, 0.82)], Color32::from_rgb(90, 160, 90), ink);
        }
        Globe => {
            // A globe with a meridian and the equator.
            g.circle((0.5, 0.5), 0.38, LBLUE, ink);
            g.thin_line(&[(0.12, 0.5), (0.88, 0.5)], ink);
            let m = g.ellipse_pts((0.5, 0.5), 0.16, 0.38, 0.0, TAU, 24);
            g.thin_line(&m, ink);
        }
        StartingView => {
            // A view with a play mark.
            g.rect(0.1, 0.18, 0.9, 0.82, Color32::WHITE, ink);
            g.poly(&[(0.4, 0.34), (0.66, 0.5), (0.4, 0.66)], Color32::from_rgb(40, 150, 70), ink);
        }
        Brace => {
            // A diagonal member between two posts.
            g.rect(0.1, 0.12, 0.2, 0.9, LGREY, ink);
            g.rect(0.8, 0.12, 0.9, 0.9, LGREY, ink);
            g.poly(&[(0.2, 0.78), (0.26, 0.86), (0.8, 0.26), (0.74, 0.18)], BLUE, ink);
        }
        Truss => {
            // Top and bottom chords with a zigzag of diagonals.
            g.rect(0.06, 0.24, 0.94, 0.32, BLUE, ink);
            g.rect(0.06, 0.7, 0.94, 0.78, BLUE, ink);
            g.line(&[(0.1, 0.72), (0.3, 0.3), (0.5, 0.72), (0.7, 0.3), (0.9, 0.72)], BLUE);
        }
        BeamSystem => {
            // A bay with parallel beams.
            g.poly(&[(0.06, 0.5), (0.5, 0.22), (0.94, 0.5), (0.5, 0.78)], LGREY, ink);
            g.line(&[(0.22, 0.6), (0.62, 0.32)], BLUE);
            g.line(&[(0.38, 0.7), (0.78, 0.42)], BLUE);
        }
        WallFoundation => {
            g.rect(0.36, 0.1, 0.64, 0.6, LGREY, ink);
            g.rect(0.12, 0.6, 0.88, 0.86, GREY, ink);
        }
        IsolatedFoundation => {
            g.rect(0.42, 0.1, 0.58, 0.5, BLUE, ink);
            g.poly(&[(0.12, 0.66), (0.5, 0.5), (0.88, 0.66), (0.5, 0.82)], LGREY, ink);
            g.poly(&[(0.12, 0.66), (0.5, 0.82), (0.5, 0.92), (0.12, 0.76)], GREY, ink);
            g.poly(&[(0.5, 0.82), (0.88, 0.66), (0.88, 0.76), (0.5, 0.92)], GREY, ink);
        }
        DimAligned | DimLinear => {
            let (a, b) = if icon == DimAligned { ((0.12, 0.7), (0.82, 0.3)) } else { ((0.12, 0.5), (0.88, 0.5)) };
            g.line(&[a, b], BLUE);
            for q in [a, b] {
                g.line(&[(q.0 - 0.06, q.1 + 0.06), (q.0 + 0.06, q.1 - 0.06)], ink);
            }
            if icon == DimAligned {
                g.thin_line(&[(0.12, 0.7), (0.24, 0.9)], ink);
                g.thin_line(&[(0.82, 0.3), (0.94, 0.5)], ink);
            } else {
                g.thin_line(&[(0.12, 0.3), (0.12, 0.8)], ink);
                g.thin_line(&[(0.88, 0.3), (0.88, 0.8)], ink);
            }
            g.text((0.5, if icon == DimAligned { 0.36 } else { 0.32 }), "1.5", 0.22, BLUE);
        }
        DimAngular => {
            g.line(&[(0.12, 0.86), (0.9, 0.86)], ink);
            g.line(&[(0.12, 0.86), (0.66, 0.18)], ink);
            g.arc((0.12, 0.86), 0.5, -0.9, 0.0, BLUE);
            g.text((0.74, 0.56), "°", 0.3, BLUE);
        }
        DimRadial | DimDiameter => {
            g.circle((0.5, 0.5), 0.36, Color32::TRANSPARENT, ink);
            if icon == DimRadial {
                g.arrow((0.5, 0.5), (0.76, 0.24), BLUE);
                g.text((0.36, 0.7), "R", 0.26, BLUE);
            } else {
                g.arrow((0.24, 0.76), (0.76, 0.24), BLUE);
                g.arrow_head((0.24, 0.76), (0.76, 0.24), BLUE, 0.16);
                g.text((0.3, 0.32), "⌀", 0.26, BLUE);
            }
        }
        DimArcLength => {
            g.arc((0.5, 0.86), 0.5, -2.6, -0.54, ink);
            g.arc((0.5, 0.86), 0.66, -2.5, -0.64, BLUE);
            g.text((0.5, 0.52), "⌒", 0.24, BLUE);
        }
        SpotElevation => {
            g.line(&[(0.1, 0.8), (0.9, 0.8)], ink);
            g.poly(&[(0.5, 0.8), (0.38, 0.62), (0.62, 0.62)], Color32::WHITE, ink);
            g.text((0.5, 0.36), "+0.0", 0.24, BLUE);
        }
        DetailLine => {
            g.line(&[(0.12, 0.82), (0.82, 0.18)], ink);
            g.pencil(0.56, 0.86, 0.2);
        }
        FilledRegion | MaskingRegion => {
            g.rect(0.12, 0.16, 0.88, 0.84, if icon == FilledRegion { Color32::WHITE } else { Color32::from_rgb(250, 250, 250) }, ink);
            if icon == FilledRegion {
                g.hatch(0.12, 0.16, 0.88, 0.84);
            } else {
                g.dashed((0.2, 0.5), (0.8, 0.5), GREY);
            }
        }
        RevisionCloud => {
            let n = 7;
            for k in 0..n {
                let a = k as f32 / n as f32 * TAU;
                let c = (0.5 + 0.3 * a.cos(), 0.5 + 0.28 * a.sin());
                g.arc(c, 0.14, a - 1.6, a + 1.6, RED);
            }
        }
        Text => {
            g.text_bold((0.5, 0.52), "A", 0.62, ink);
            g.line(&[(0.2, 0.9), (0.8, 0.9)], BLUE);
        }
        TagByCategory | TagAll => {
            g.poly(&[(0.12, 0.3), (0.62, 0.3), (0.86, 0.5), (0.62, 0.7), (0.12, 0.7)], Color32::from_rgb(255, 244, 196), ink);
            g.closed(&[(0.12, 0.3), (0.62, 0.3), (0.86, 0.5), (0.62, 0.7), (0.12, 0.7)], ink);
            g.dot((0.66, 0.5), 0.04, ink);
            if icon == TagAll {
                g.text((0.36, 0.5), "ALL", 0.18, ink);
            } else {
                g.text((0.36, 0.5), "1", 0.24, ink);
            }
        }
        Symbol | NorthArrow => {
            g.circle((0.5, 0.56), 0.32, Color32::WHITE, ink);
            g.poly(&[(0.5, 0.18), (0.62, 0.7), (0.5, 0.6)], ink, ink);
            g.poly(&[(0.5, 0.18), (0.5, 0.6), (0.38, 0.7)], Color32::WHITE, ink);
            g.text((0.5, 0.1), "N", 0.18, ink);
        }
        View3D => {
            g.cube(0.5, 0.5, 0.78, Color32::WHITE, LBLUE, BLUE);
        }
        Camera => {
            g.rect(0.12, 0.34, 0.74, 0.78, GREY, ink);
            g.poly(&[(0.74, 0.46), (0.92, 0.36), (0.92, 0.76), (0.74, 0.66)], LGREY, ink);
            g.circle((0.3, 0.24), 0.1, Color32::WHITE, ink);
            g.circle((0.56, 0.24), 0.1, Color32::WHITE, ink);
        }
        Section => {
            g.dashdot((0.2, 0.5), (0.8, 0.5), ink);
            g.line(&[(0.08, 0.5), (0.26, 0.5)], ink);
            g.line(&[(0.74, 0.5), (0.92, 0.5)], ink);
            g.circle((0.14, 0.5), 0.1, BLUE, ink);
            g.poly_fill(&[(0.08, 0.5), (0.2, 0.5), (0.14, 0.7)], BLUE);
            g.circle((0.86, 0.5), 0.1, Color32::WHITE, ink);
        }
        Callout => {
            g.rect(0.14, 0.14, 0.7, 0.7, Color32::TRANSPARENT, ink);
            g.thin_line(&[(0.7, 0.7), (0.8, 0.8)], ink);
            g.circle((0.82, 0.82), 0.1, LBLUE, ink);
        }
        FloorPlan => g.plan_tile(BLUE),
        CeilingPlan => {
            g.plan_tile(GREY);
            g.circle((0.64, 0.6), 0.06, YELLOW, ink);
        }
        AreaPlan => {
            g.rect(0.1, 0.12, 0.9, 0.88, LGREEN, ink);
            g.line(&[(0.5, 0.12), (0.5, 0.88)], PURPLE);
        }
        Elevation => {
            g.poly(&[(0.16, 0.48), (0.5, 0.16), (0.84, 0.48), (0.84, 0.86), (0.16, 0.86)], Color32::WHITE, ink);
            g.rect_thin(0.42, 0.6, 0.58, 0.86, LBROWN, ink);
            g.rect_thin(0.24, 0.54, 0.36, 0.66, LBLUE, ink);
            g.rect_thin(0.64, 0.54, 0.76, 0.66, LBLUE, ink);
        }
        DraftingView => {
            g.sheet(0.12, 0.12, 0.84, 0.88);
            g.pencil(0.42, 0.7, 0.36);
        }
        DuplicateView => {
            g.rect(0.08, 0.08, 0.6, 0.6, Color32::WHITE, ink);
            g.rect(0.36, 0.36, 0.92, 0.92, Color32::WHITE, BLUE);
        }
        Legend => {
            g.rect(0.12, 0.1, 0.88, 0.9, Color32::WHITE, ink);
            for (k, c) in [RED, GREEN, BLUE].into_iter().enumerate() {
                let y = 0.24 + 0.24 * k as f32;
                g.rect_thin(0.2, y, 0.36, y + 0.12, c, ink);
                g.thin_line(&[(0.44, y + 0.06), (0.8, y + 0.06)], ink);
            }
        }
        Schedule | MaterialTakeoff | SheetList => {
            g.rect(0.1, 0.1, 0.9, 0.9, Color32::WHITE, ink);
            g.rect(0.1, 0.1, 0.9, 0.28, if icon == MaterialTakeoff { LBROWN } else { LBLUE }, ink);
            for y in [0.46, 0.64] {
                g.thin_line(&[(0.1, y), (0.9, y)], ink);
            }
            g.thin_line(&[(0.42, 0.1), (0.42, 0.9)], ink);
            if icon == SheetList {
                g.sheet(0.54, 0.5, 0.86, 0.86);
            }
        }
        Sheet => g.sheet(0.08, 0.16, 0.92, 0.84),
        PlaceView => {
            g.sheet(0.08, 0.16, 0.92, 0.84);
            g.rect(0.18, 0.26, 0.52, 0.6, LBLUE, BLUE);
        }
        Revisions => {
            g.sheet(0.08, 0.16, 0.92, 0.84);
            g.poly(&[(0.3, 0.3), (0.42, 0.52), (0.18, 0.52)], Color32::WHITE, RED);
            g.text((0.3, 0.45), "1", 0.14, RED);
        }
        ViewTemplates => {
            g.rect(0.08, 0.08, 0.66, 0.66, Color32::WHITE, ink);
            g.rect(0.22, 0.22, 0.8, 0.8, Color32::WHITE, ink);
            g.rect(0.36, 0.36, 0.94, 0.94, LBLUE, BLUE);
        }
        VisibilityGraphics => {
            g.circle((0.5, 0.5), 0.36, Color32::TRANSPARENT, ink);
            let eye: Vec<Pt> = (0..=24).map(|k| {
                let t = k as f32 / 24.0 * TAU;
                (0.5 + 0.3 * t.cos(), 0.5 + 0.16 * t.sin())
            }).collect();
            g.closed(&eye, BLUE);
            g.dot((0.5, 0.5), 0.08, BLUE);
        }
        ThinLines => {
            g.line_w(&[(0.1, 0.3), (0.9, 0.3)], ink, g.w * 2.0);
            g.thin_line(&[(0.1, 0.7), (0.9, 0.7)], BLUE);
            g.arrow((0.5, 0.38), (0.5, 0.62), GREY);
        }
        SwitchWindows => {
            g.rect(0.08, 0.14, 0.64, 0.6, Color32::WHITE, ink);
            g.rect(0.36, 0.4, 0.92, 0.86, LBLUE, ink);
        }
        CloseInactive => {
            g.rect(0.08, 0.14, 0.64, 0.6, Color32::WHITE, ink);
            g.rect(0.36, 0.4, 0.92, 0.86, Color32::WHITE, ink);
            g.line(&[(0.52, 0.52), (0.76, 0.76)], RED);
            g.line(&[(0.76, 0.52), (0.52, 0.76)], RED);
        }
        TabViews => {
            g.rect(0.08, 0.3, 0.92, 0.88, Color32::WHITE, ink);
            g.rect(0.08, 0.16, 0.36, 0.3, LBLUE, ink);
            g.rect(0.36, 0.2, 0.62, 0.3, LGREY, ink);
        }
        TileViews => {
            for (x, y) in [(0.08, 0.1), (0.52, 0.1), (0.08, 0.52), (0.52, 0.52)] {
                g.rect(x, y, x + 0.4, y + 0.38, Color32::WHITE, ink);
            }
        }
        UserInterface => {
            g.rect(0.08, 0.12, 0.92, 0.88, Color32::WHITE, ink);
            g.rect(0.08, 0.12, 0.92, 0.26, LBLUE, ink);
            g.rect(0.08, 0.26, 0.3, 0.88, LGREY, ink);
        }
        Materials => {
            g.circle((0.5, 0.5), 0.38, LBROWN, ink);
            g.circle((0.38, 0.4), 0.1, YELLOW, Color32::TRANSPARENT);
            g.circle((0.62, 0.42), 0.09, RED, Color32::TRANSPARENT);
            g.circle((0.48, 0.66), 0.09, BLUE, Color32::TRANSPARENT);
        }
        ObjectStyles => {
            g.line_w(&[(0.12, 0.24), (0.88, 0.24)], ink, g.w * 2.2);
            g.line(&[(0.12, 0.5), (0.88, 0.5)], BLUE);
            g.dashed((0.12, 0.76), (0.88, 0.76), RED);
        }
        Snaps => {
            g.line(&[(0.1, 0.8), (0.9, 0.8)], ink);
            g.line(&[(0.5, 0.8), (0.5, 0.14)], ink);
            g.rect(0.4, 0.04 + 0.66, 0.6, 0.9, Color32::TRANSPARENT, SNAP_C);
            g.poly(&[(0.5, 0.06), (0.62, 0.26), (0.38, 0.26)], Color32::TRANSPARENT, SNAP_C);
        }
        ProjectInfo | Info => {
            g.circle((0.5, 0.5), 0.38, LBLUE, BLUE);
            g.text_bold((0.5, 0.52), "i", 0.46, BLUE);
        }
        ProjectUnits => {
            g.rect(0.08, 0.36, 0.92, 0.64, LBROWN, ink);
            for k in 1..8 {
                let x = 0.08 + 0.84 * k as f32 / 8.0;
                g.thin_line(&[(x, 0.36), (x, if k % 2 == 0 { 0.52 } else { 0.46 })], ink);
            }
        }
        Purge => {
            g.line(&[(0.3, 0.2), (0.7, 0.2)], ink);
            g.poly(&[(0.24, 0.3), (0.76, 0.3), (0.68, 0.9), (0.32, 0.9)], LGREY, ink);
            for x in [0.42, 0.58] {
                g.thin_line(&[(x, 0.4), (x, 0.8)], ink);
            }
        }
        Phases => {
            for (k, c) in [GREY, ORANGE, GREEN].into_iter().enumerate() {
                let x = 0.08 + k as f32 * 0.29;
                g.poly(&[(x, 0.3), (x + 0.22, 0.3), (x + 0.3, 0.5), (x + 0.22, 0.7), (x, 0.7), (x + 0.08, 0.5)], c, ink);
            }
        }
        DesignOptions => {
            g.circle((0.5, 0.2), 0.1, BLUE, ink);
            g.line(&[(0.5, 0.3), (0.5, 0.5)], ink);
            g.line(&[(0.2, 0.5), (0.8, 0.5)], ink);
            g.line(&[(0.2, 0.5), (0.2, 0.66)], ink);
            g.line(&[(0.8, 0.5), (0.8, 0.66)], ink);
            g.rect(0.08, 0.66, 0.32, 0.88, LGREEN, ink);
            g.rect(0.68, 0.66, 0.92, 0.88, LBLUE, ink);
        }
        Sun | Shadows => {
            g.circle((0.4, 0.4), 0.16, YELLOW, ORANGE);
            for k in 0..8 {
                let a = k as f32 * TAU / 8.0;
                g.line(&[(0.4 + 0.22 * a.cos(), 0.4 + 0.22 * a.sin()), (0.4 + 0.3 * a.cos(), 0.4 + 0.3 * a.sin())], ORANGE);
            }
            if icon == Shadows {
                g.poly_fill(&[(0.5, 0.92), (0.94, 0.92), (0.94, 0.66), (0.72, 0.66)], GREY);
            }
        }
        LinkCad | ImportCad | Dxf => {
            g.rect(0.12, 0.08, 0.8, 0.92, Color32::WHITE, ink);
            g.text_bold((0.46, 0.4), if icon == Dxf { "DXF" } else { "CAD" }, 0.22, if icon == Dxf { ORANGE } else { RED });
            g.thin_line(&[(0.22, 0.62), (0.7, 0.62)], ink);
            g.thin_line(&[(0.22, 0.74), (0.6, 0.74)], ink);
            if icon == LinkCad {
                g.circle((0.78, 0.8), 0.08, Color32::TRANSPARENT, BLUE);
                g.circle((0.88, 0.8), 0.08, Color32::TRANSPARENT, BLUE);
            }
        }
        ImportIfc | Ifc => {
            g.rect(0.12, 0.08, 0.8, 0.92, Color32::WHITE, ink);
            g.text_bold((0.46, 0.4), "IFC", 0.24, BLUE);
            g.cube(0.46, 0.7, 0.26, Color32::WHITE, LBLUE, BLUE);
        }
        LoadFamily => {
            g.rect(0.08, 0.3, 0.6, 0.9, LBLUE, ink);
            g.text_bold((0.34, 0.6), "F", 0.34, BLUE);
            g.arrow((0.78, 0.08), (0.78, 0.56), GREEN);
        }
        LoadIntoProject => {
            g.rect(0.08, 0.3, 0.6, 0.9, LBLUE, ink);
            g.arrow((0.5, 0.2), (0.9, 0.6), GREEN);
        }
        Align => {
            g.line(&[(0.2, 0.08), (0.2, 0.92)], BLUE);
            g.rect(0.42, 0.2, 0.86, 0.42, LGREY, ink);
            g.rect(0.2, 0.58, 0.64, 0.8, LGREY, ink);
            g.arrow((0.42, 0.31), (0.26, 0.31), RED);
        }
        Offset => {
            g.line(&[(0.12, 0.3), (0.88, 0.3)], ink);
            g.line(&[(0.12, 0.72), (0.88, 0.72)], BLUE);
            g.arrow((0.5, 0.34), (0.5, 0.68), RED);
        }
        MirrorPick | MirrorDraw => {
            g.dashed((0.5, 0.06), (0.5, 0.94), if icon == MirrorPick { BLUE } else { ORANGE });
            g.poly(&[(0.42, 0.24), (0.42, 0.76), (0.1, 0.76)], LGREY, ink);
            g.poly(&[(0.58, 0.24), (0.9, 0.76), (0.58, 0.76)], LBLUE, ink);
            if icon == MirrorDraw {
                g.pencil(0.56, 0.98, 0.18);
            }
        }
        Move => {
            g.line(&[(0.5, 0.1), (0.5, 0.9)], ink);
            g.line(&[(0.1, 0.5), (0.9, 0.5)], ink);
            g.arrow_head((0.5, 0.06), (0.5, 0.5), ink, 0.16);
            g.arrow_head((0.5, 0.94), (0.5, 0.5), ink, 0.16);
            g.arrow_head((0.06, 0.5), (0.5, 0.5), ink, 0.16);
            g.arrow_head((0.94, 0.5), (0.5, 0.5), ink, 0.16);
        }
        Copy | CopyClip => {
            g.rect(0.12, 0.12, 0.6, 0.6, Color32::WHITE, ink);
            g.rect(0.4, 0.4, 0.88, 0.88, LBLUE, ink);
            if icon == CopyClip {
                g.rect_thin(0.56, 0.3, 0.72, 0.4, GREY, ink);
            }
        }
        Rotate => {
            g.arc((0.5, 0.5), 0.34, 0.4, 5.2, ink);
            g.arrow_head((0.5 + 0.34 * 0.4f32.cos(), 0.5 + 0.34 * 0.4f32.sin() + 0.02), (0.5 + 0.34 * 0.9f32.cos(), 0.5 + 0.34 * 0.9f32.sin()), ink, 0.18);
            g.dot((0.5, 0.5), 0.05, BLUE);
        }
        TrimCorner => {
            g.line(&[(0.2, 0.88), (0.2, 0.2), (0.88, 0.2)], ink);
            g.dashed((0.2, 0.2), (0.2, 0.06), RED);
            g.dashed((0.2, 0.2), (0.06, 0.2), RED);
            g.circle((0.2, 0.2), 0.06, Color32::TRANSPARENT, BLUE);
        }
        TrimSingle | TrimMulti => {
            g.line(&[(0.14, 0.2), (0.14, 0.88)], BLUE);
            g.line(&[(0.14, 0.4), (0.88, 0.4)], ink);
            if icon == TrimMulti {
                g.line(&[(0.14, 0.7), (0.88, 0.7)], ink);
            }
            g.dashed((0.14, 0.4), (0.04, 0.4), RED);
        }
        Split => {
            g.line(&[(0.08, 0.5), (0.92, 0.5)], ink);
            g.line(&[(0.62, 0.2), (0.38, 0.8)], RED);
        }
        SplitGap => {
            g.line(&[(0.08, 0.5), (0.4, 0.5)], ink);
            g.line(&[(0.6, 0.5), (0.92, 0.5)], ink);
            g.arrow((0.44, 0.3), (0.56, 0.3), RED);
        }
        Pin => {
            g.circle((0.5, 0.32), 0.2, RED, ink);
            g.line(&[(0.5, 0.52), (0.5, 0.92)], ink);
        }
        Unpin => {
            g.circle((0.5, 0.32), 0.2, LGREY, ink);
            g.line(&[(0.5, 0.52), (0.5, 0.92)], ink);
            g.line(&[(0.16, 0.86), (0.84, 0.14)], RED);
        }
        Array => {
            for k in 0..3 {
                let x = 0.08 + k as f32 * 0.3;
                g.rect(x, 0.36, x + 0.22, 0.64, if k == 0 { LBLUE } else { Color32::WHITE }, ink);
            }
        }
        Scale => {
            g.rect(0.1, 0.5, 0.42, 0.9, Color32::WHITE, ink);
            g.rect(0.1, 0.1, 0.9, 0.9, Color32::TRANSPARENT, BLUE);
            g.arrow((0.42, 0.5), (0.8, 0.18), RED);
        }
        Delete => {
            g.line_w(&[(0.2, 0.2), (0.8, 0.8)], RED, g.w * 1.6);
            g.line_w(&[(0.8, 0.2), (0.2, 0.8)], RED, g.w * 1.6);
        }
        MatchType => {
            g.rect(0.1, 0.5, 0.5, 0.9, LBLUE, ink);
            g.poly(&[(0.6, 0.1), (0.9, 0.4), (0.7, 0.6), (0.4, 0.3)], Color32::WHITE, ink);
            g.line_w(&[(0.62, 0.52), (0.4, 0.74)], BROWN, g.w * 1.6);
        }
        Measure => {
            g.rect(0.06, 0.38, 0.94, 0.62, YELLOW, ink);
            for k in 1..8 {
                let x = 0.06 + 0.88 * k as f32 / 8.0;
                g.thin_line(&[(x, 0.38), (x, if k % 2 == 0 { 0.52 } else { 0.46 })], ink);
            }
        }
        Cut => {
            g.circle((0.3, 0.76), 0.12, Color32::TRANSPARENT, ink);
            g.circle((0.7, 0.76), 0.12, Color32::TRANSPARENT, ink);
            g.line(&[(0.36, 0.66), (0.7, 0.12)], ink);
            g.line(&[(0.64, 0.66), (0.3, 0.12)], ink);
        }
        Paste => {
            g.rect(0.16, 0.14, 0.72, 0.9, LBROWN, ink);
            g.rect(0.32, 0.08, 0.56, 0.2, GREY, ink);
            g.rect(0.42, 0.42, 0.88, 0.94, Color32::WHITE, ink);
        }
        TypeProperties => {
            g.rect(0.12, 0.1, 0.88, 0.9, Color32::WHITE, ink);
            for y in [0.3, 0.5, 0.7] {
                g.thin_line(&[(0.2, y), (0.44, y)], ink);
                g.rect_thin(0.5, y - 0.06, 0.8, y + 0.06, LBLUE, ink);
            }
        }
        Properties => {
            g.rect(0.12, 0.1, 0.88, 0.9, Color32::WHITE, ink);
            g.rect(0.12, 0.1, 0.88, 0.26, LBLUE, ink);
            for y in [0.42, 0.58, 0.74] {
                g.thin_line(&[(0.2, y), (0.8, y)], ink);
            }
        }
        HideInView => {
            g.rect(0.12, 0.2, 0.62, 0.7, LGREY, ink);
            g.circle((0.68, 0.7), 0.2, Color32::WHITE, ink);
            g.line(&[(0.54, 0.84), (0.82, 0.56)], RED);
        }
        OverrideGraphics => {
            g.line_w(&[(0.1, 0.3), (0.6, 0.3)], RED, g.w * 2.0);
            g.line(&[(0.1, 0.6), (0.6, 0.6)], BLUE);
            g.poly(&[(0.7, 0.2), (0.9, 0.4), (0.62, 0.86), (0.54, 0.78)], YELLOW, ink);
        }
        CreateSimilar => {
            g.rect(0.12, 0.3, 0.58, 0.76, LBLUE, ink);
            g.star((0.72, 0.28), 0.18, YELLOW);
        }
        Finish => {
            g.line_w(&[(0.16, 0.52), (0.4, 0.78), (0.86, 0.2)], GREEN, g.w * 2.4);
        }
        Cancel => {
            g.line_w(&[(0.2, 0.2), (0.8, 0.8)], RED, g.w * 2.2);
            g.line_w(&[(0.8, 0.2), (0.2, 0.8)], RED, g.w * 2.2);
        }
        DrawLine => {
            g.line(&[(0.14, 0.84), (0.86, 0.16)], ink);
            g.dot((0.14, 0.84), 0.05, BLUE);
            g.dot((0.86, 0.16), 0.05, BLUE);
        }
        DrawRect => g.rect(0.14, 0.24, 0.86, 0.76, Color32::TRANSPARENT, ink),
        DrawPolyIn | DrawPolyCirc => {
            let hex: Vec<Pt> = (0..6).map(|k| {
                let a = k as f32 * TAU / 6.0;
                (0.5 + 0.36 * a.cos(), 0.5 + 0.36 * a.sin())
            }).collect();
            g.closed(&hex, ink);
            if icon == DrawPolyIn {
                g.circle((0.5, 0.5), 0.36, Color32::TRANSPARENT, BLUE);
            } else {
                g.circle((0.5, 0.5), 0.31, Color32::TRANSPARENT, BLUE);
            }
        }
        DrawCircle => {
            g.circle((0.5, 0.5), 0.36, Color32::TRANSPARENT, ink);
            g.dot((0.5, 0.5), 0.04, BLUE);
        }
        DrawSpline => {
            let pts: Vec<Pt> = (0..=20).map(|k| {
                let t = k as f32 / 20.0;
                (0.1 + 0.8 * t, 0.55 - 0.3 * (t * TAU).sin() * (1.0 - t * 0.3))
            }).collect();
            g.line(&pts, ink);
            for q in [(0.1, 0.55), (0.35, 0.25), (0.65, 0.8), (0.9, 0.52)] {
                g.dot(q, 0.04, BLUE);
            }
        }
        ModelInPlace => {
            g.solid_box(0.42, 0.9, 0.36, 0.36, 0.3);
            g.pencil(0.62, 0.5, 0.3);
        }
        BoundaryLine => {
            g.line(&[(0.16, 0.86), (0.16, 0.2), (0.84, 0.2)], MAGENTA);
            g.dot((0.16, 0.86), 0.05, ink);
            g.dot((0.84, 0.2), 0.05, ink);
        }
        SlopeArrow => {
            g.shade(&[(0.06, 0.66), (0.62, 0.42), (0.94, 0.56), (0.38, 0.8)], G0, G2, false);
            g.arrow((0.22, 0.68), (0.74, 0.46), MAGENTA);
        }
        Ramp => {
            // A sloped slab in perspective with its thickness shaded.
            g.shade(&[(0.06, 0.84), (0.66, 0.3), (0.94, 0.42), (0.34, 0.96)], G0, G2, false);
            g.shade(&[(0.66, 0.3), (0.94, 0.42), (0.94, 0.52), (0.66, 0.4)], G2, G3, false);
            g.shade(&[(0.34, 0.96), (0.94, 0.42), (0.94, 0.52), (0.34, 1.0)], G3, G4, false);
            g.line(&[(0.26, 0.86), (0.66, 0.5)], BLUE);
            g.arrow_head((0.7, 0.46), (0.26, 0.86), BLUE, 0.12);
        }
        PlaceRoomsAuto => {
            g.shade(&[(0.06, 0.1), (0.94, 0.1), (0.94, 0.9), (0.06, 0.9)], LBLUE, LBLUE, true);
            g.closed(&[(0.06, 0.1), (0.94, 0.1), (0.94, 0.9), (0.06, 0.9)], ink);
            g.line(&[(0.5, 0.1), (0.5, 0.9)], ink);
            for (x0, x1) in [(0.06f32, 0.5f32), (0.5, 0.94)] {
                g.thin_line(&[(x0, 0.1), (x1, 0.9)], ink);
                g.thin_line(&[(x0, 0.9), (x1, 0.1)], ink);
            }
            g.dot((0.78, 0.26), 0.09, BLUE);
        }
        HighlightBoundaries => {
            let o = Color32::from_rgb(240, 140, 40);
            g.line_w(&[(0.08, 0.12), (0.92, 0.12), (0.92, 0.88), (0.08, 0.88), (0.08, 0.12)], o, g.w * 2.2);
            g.thin_line(&[(0.08, 0.12), (0.92, 0.88)], ink);
            g.thin_line(&[(0.08, 0.88), (0.92, 0.12)], ink);
        }
        RampRiser => {
            g.thin_line(&[(0.3, 0.08), (0.3, 0.92)], ink);
            g.thin_line(&[(0.7, 0.08), (0.7, 0.92)], ink);
            g.line_w(&[(0.3, 0.08), (0.7, 0.08)], BLUE, g.w * 1.6);
            g.line_w(&[(0.3, 0.92), (0.7, 0.92)], BLUE, g.w * 1.6);
        }
        StairRun => {
            // A straight run in plan: outline and treads, with the walk arrow.
            g.shade(&[(0.3, 0.06), (0.7, 0.06), (0.7, 0.94), (0.3, 0.94)], G0, G1, true);
            for k in 1..6 {
                let y = 0.06 + 0.88 * k as f32 / 6.0;
                g.thin_line(&[(0.3, y), (0.7, y)], ink);
            }
            g.closed(&[(0.3, 0.06), (0.7, 0.06), (0.7, 0.94), (0.3, 0.94)], ink);
            g.line(&[(0.5, 0.86), (0.5, 0.16)], BLUE);
            g.arrow_head((0.5, 0.12), (0.5, 0.4), BLUE, 0.12);
        }
        StairLanding => {
            g.shade(&[(0.06, 0.4), (0.62, 0.4), (0.94, 0.62), (0.38, 0.62)], G0, G2, false);
            g.shade(&[(0.06, 0.4), (0.38, 0.62), (0.38, 0.72), (0.06, 0.5)], G2, G3, false);
            g.shade(&[(0.38, 0.62), (0.94, 0.62), (0.94, 0.72), (0.38, 0.72)], G1, G2, false);
        }
        StairSupport => {
            g.shade(&[(0.06, 0.86), (0.86, 0.14), (0.94, 0.22), (0.14, 0.94)], G1, G3, false);
            g.line(&[(0.06, 0.86), (0.86, 0.14)], ink);
        }
        StairStraight => {
            for k in 0..5 {
                let y = 0.1 + 0.8 * k as f32 / 4.0;
                g.thin_line(&[(0.28, y), (0.72, y)], ink);
            }
            g.closed(&[(0.28, 0.1), (0.72, 0.1), (0.72, 0.9), (0.28, 0.9)], ink);
            g.line(&[(0.5, 0.84), (0.5, 0.2)], BLUE);
            g.arrow_head((0.5, 0.14), (0.5, 0.4), BLUE, 0.12);
        }
        ConnectLevels => {
            for (k, y) in [0.24f32, 0.5, 0.76].iter().enumerate() {
                g.dashdot((0.04, *y), (0.96, *y), if k == 1 { BLUE } else { ink });
            }
            g.shade(&[(0.3, 0.76), (0.62, 0.24), (0.74, 0.24), (0.42, 0.76)], G1, G3, false);
        }
        PickNewHost => {
            g.shade(&[(0.06, 0.62), (0.54, 0.62), (0.54, 0.9), (0.06, 0.9)], G0, G2, true);
            g.line_w(&[(0.1, 0.34), (0.5, 0.34)], BLUE, g.w * 1.6);
            for x in [0.14f32, 0.3, 0.46] {
                g.line(&[(x, 0.34), (x, 0.62)], SKY);
            }
            g.arrow((0.92, 0.1), (0.6, 0.5), ink);
        }
        AlignEaves => {
            // A roof in elevation with its two eaves on one dashed line.
            g.shade(&[(0.08, 0.66), (0.5, 0.26), (0.92, 0.66), (0.82, 0.66), (0.5, 0.38), (0.18, 0.66)], G0, G2, false);
            g.line_w(&[(0.04, 0.8), (0.96, 0.8)], BLUE, g.w * 1.4);
            g.line(&[(0.13, 0.66), (0.13, 0.8)], ink);
            g.line(&[(0.87, 0.66), (0.87, 0.8)], ink);
        }
        AdjustHeight => {
            g.shade(&[(0.1, 0.7), (0.5, 0.34), (0.9, 0.7), (0.8, 0.7), (0.5, 0.46), (0.2, 0.7)], G0, G2, false);
            g.line(&[(0.5, 0.06), (0.5, 0.28)], ink);
            g.arrow_head((0.5, 0.28), (0.5, 0.06), ink, 0.12);
            g.arrow_head((0.5, 0.06), (0.5, 0.28), ink, 0.12);
        }
        AdjustOverhang => {
            g.shade(&[(0.1, 0.62), (0.5, 0.26), (0.9, 0.62), (0.8, 0.62), (0.5, 0.38), (0.2, 0.62)], G0, G2, false);
            g.line(&[(0.06, 0.84), (0.34, 0.84)], ink);
            g.arrow_head((0.34, 0.84), (0.06, 0.84), ink, 0.12);
            g.arrow_head((0.06, 0.84), (0.34, 0.84), ink, 0.12);
        }
        SpanDirection => {
            g.shade(&[(0.06, 0.62), (0.6, 0.38), (0.94, 0.52), (0.4, 0.76)], G0, G2, false);
            g.line(&[(0.18, 0.52), (0.72, 0.3)], ink);
            g.line(&[(0.28, 0.66), (0.82, 0.44)], ink);
            g.arrow_head((0.72, 0.3), (0.18, 0.52), ink, 0.12);
            g.arrow_head((0.18, 0.52), (0.72, 0.3), ink, 0.12);
        }
        WorkPlaneShow => {
            g.shade(&[(0.22, 0.24), (0.94, 0.24), (0.78, 0.76), (0.06, 0.76)], G0, G1, false);
            for k in 1..4 {
                let t = k as f32 / 4.0;
                g.thin_line(&[(0.22 + 0.72 * t, 0.24), (0.06 + 0.72 * t, 0.76)], SKY);
                g.thin_line(&[(0.22 - 0.16 * t, 0.24 + 0.52 * t), (0.94 - 0.16 * t, 0.24 + 0.52 * t)], SKY);
            }
            g.circle((0.8, 0.78), 0.12, YELLOW, OUTLINE);
        }
        WorkPlaneViewer => {
            g.shade(&[(0.1, 0.12), (0.9, 0.12), (0.9, 0.88), (0.1, 0.88)], G1, G2, false);
            g.shade(&[(0.16, 0.24), (0.84, 0.24), (0.84, 0.82), (0.16, 0.82)], G0, G0, false);
            g.solid_box(0.5, 0.74, 0.22, 0.22, 0.22);
        }
        DrawEllipse | DrawPartialEllipse => {
            let (a0, a1) = if icon == DrawEllipse { (0.0, TAU) } else { (PI, TAU) };
            let pts: Vec<Pt> = (0..=32).map(|k| {
                let a = a0 + (a1 - a0) * k as f32 / 32.0;
                (0.5 + 0.4 * a.cos(), 0.5 + 0.24 * a.sin())
            }).collect();
            g.line(&pts, ink);
            g.dot((0.5, 0.5), 0.04, BLUE);
        }
        DrawArc3 => {
            g.arc((0.5, 0.78), 0.4, PI + 0.1, TAU - 0.1, ink);
            for q in [(0.1, 0.74), (0.5, 0.38), (0.9, 0.74)] {
                g.dot(q, 0.045, BLUE);
            }
        }
        DrawArcCenter => {
            g.arc((0.4, 0.66), 0.42, -1.6, 0.0, ink);
            g.dot((0.4, 0.66), 0.05, BLUE);
            g.thin_line(&[(0.4, 0.66), (0.82, 0.66)], GREY);
        }
        DrawArcTangent => {
            g.line(&[(0.08, 0.8), (0.46, 0.8)], GREY);
            g.arc((0.46, 0.5), 0.3, FRAC_PI_2, -FRAC_PI_2 + 0.01 - PI, ink);
        }
        DrawFillet => {
            g.line(&[(0.16, 0.92), (0.16, 0.5)], ink);
            g.line(&[(0.5, 0.16), (0.92, 0.16)], ink);
            g.arc((0.5, 0.5), 0.34, PI, PI * 1.5, BLUE);
        }
        PickLines => {
            g.line(&[(0.1, 0.84), (0.86, 0.3)], BLUE);
            g.poly(&[(0.42, 0.2), (0.42, 0.66), (0.52, 0.56), (0.6, 0.76), (0.66, 0.74), (0.58, 0.54), (0.72, 0.54)], Color32::WHITE, ink);
        }
        PickWalls => {
            g.wall_plan(0.56, 0.76);
            g.poly(&[(0.42, 0.06), (0.42, 0.52), (0.52, 0.42), (0.6, 0.62), (0.66, 0.6), (0.58, 0.4), (0.72, 0.4)], Color32::WHITE, ink);
        }
        EditBoundary => {
            g.poly(&[(0.2, 0.3), (0.9, 0.3), (0.76, 0.7), (0.06, 0.7)], LBROWN, MAGENTA);
            g.pencil(0.54, 0.94, 0.3);
        }
        AttachTop => {
            g.poly(&[(0.5, 0.08), (0.92, 0.36), (0.08, 0.36)], Color32::from_rgb(196, 90, 60), ink);
            g.rect(0.3, 0.5, 0.7, 0.92, LGREY, ink);
            g.arrow((0.5, 0.66), (0.5, 0.4), GREEN);
        }
        Detach => {
            g.poly(&[(0.5, 0.08), (0.92, 0.36), (0.08, 0.36)], Color32::from_rgb(196, 90, 60), ink);
            g.rect(0.3, 0.56, 0.7, 0.92, LGREY, ink);
            g.arrow((0.5, 0.4), (0.5, 0.64), RED);
        }
        EditGroup => {
            draw(g, PlaceGroup);
            g.pencil(0.56, 0.94, 0.3);
        }
        Ungroup => {
            g.rect(0.08, 0.2, 0.42, 0.56, LBLUE, ink);
            g.circle((0.72, 0.68), 0.18, LGREEN, ink);
            g.dashed((0.5, 0.06), (0.5, 0.94), RED);
        }
        EditFamily | FamilyTypes => {
            g.rect(0.1, 0.1, 0.72, 0.86, LBLUE, ink);
            g.text_bold((0.41, 0.48), "F", 0.4, BLUE);
            if icon == EditFamily {
                g.pencil(0.6, 0.94, 0.32);
            } else {
                g.rect_thin(0.6, 0.6, 0.92, 0.92, Color32::WHITE, ink);
                g.thin_line(&[(0.66, 0.72), (0.86, 0.72)], ink);
                g.thin_line(&[(0.66, 0.82), (0.86, 0.82)], ink);
            }
        }
        Undo | Redo => {
            let (a0, a1, tip, from) = if icon == Undo {
                (-0.3, -2.9, (0.16, 0.42), (0.2, 0.3))
            } else {
                (PI + 0.3, PI + 2.9 - 0.0, (0.84, 0.42), (0.8, 0.3))
            };
            if icon == Undo {
                g.arc((0.52, 0.56), 0.32, a0, a1 + TAU, BLUE);
            } else {
                g.arc((0.48, 0.56), 0.32, a0 - TAU, a1 - TAU, BLUE);
            }
            g.arrow_head(tip, from, BLUE, 0.2);
        }
        Save => {
            g.rect(0.12, 0.12, 0.88, 0.88, BLUE, ink);
            g.rect(0.26, 0.12, 0.74, 0.4, Color32::WHITE, ink);
            g.rect(0.3, 0.58, 0.7, 0.88, LGREY, ink);
        }
        Open => {
            g.poly(&[(0.08, 0.26), (0.36, 0.26), (0.44, 0.34), (0.86, 0.34), (0.86, 0.84), (0.08, 0.84)], YELLOW, ink);
            g.poly(&[(0.2, 0.48), (0.96, 0.48), (0.86, 0.84), (0.08, 0.84)], Color32::from_rgb(252, 222, 120), ink);
        }
        New => {
            g.poly(&[(0.2, 0.08), (0.62, 0.08), (0.8, 0.26), (0.8, 0.92), (0.2, 0.92)], Color32::WHITE, ink);
            g.star((0.72, 0.24), 0.16, YELLOW);
        }
        Close => {
            g.rect(0.12, 0.12, 0.88, 0.88, Color32::WHITE, ink);
            g.line(&[(0.32, 0.32), (0.68, 0.68)], RED);
            g.line(&[(0.68, 0.32), (0.32, 0.68)], RED);
        }
        Print => {
            g.rect(0.26, 0.08, 0.74, 0.36, Color32::WHITE, ink);
            g.rect(0.1, 0.36, 0.9, 0.72, LGREY, ink);
            g.rect(0.26, 0.6, 0.74, 0.92, Color32::WHITE, ink);
        }
        Export => {
            g.rect(0.1, 0.24, 0.62, 0.9, Color32::WHITE, ink);
            g.arrow((0.4, 0.56), (0.92, 0.16), GREEN);
        }
        Image => {
            g.rect(0.1, 0.16, 0.9, 0.84, LBLUE, ink);
            g.poly(&[(0.1, 0.84), (0.42, 0.44), (0.66, 0.84)], GREEN, ink);
            g.circle((0.7, 0.36), 0.08, YELLOW, Color32::TRANSPARENT);
        }
        Pdf => {
            g.rect(0.14, 0.08, 0.86, 0.92, Color32::WHITE, ink);
            g.text_bold((0.5, 0.56), "PDF", 0.24, RED);
        }
        Filter => {
            g.poly(&[(0.1, 0.16), (0.9, 0.16), (0.58, 0.52), (0.58, 0.84), (0.42, 0.92), (0.42, 0.52)], LBLUE, ink);
        }
        SelectLinks => {
            g.circle((0.38, 0.5), 0.18, Color32::TRANSPARENT, BLUE);
            g.circle((0.62, 0.5), 0.18, Color32::TRANSPARENT, BLUE);
        }
        SelectUnderlay => {
            g.rect(0.1, 0.5, 0.9, 0.86, LGREY, GREY);
            g.rect(0.2, 0.18, 0.8, 0.6, Color32::WHITE, ink);
        }
        SelectPinned => draw(g, Pin),
        SelectByFace => {
            g.cube(0.5, 0.5, 0.76, LBLUE, Color32::WHITE, LGREY);
        }
        DragOnSelect => {
            draw(g, Move);
            g.rect_thin(0.62, 0.62, 0.92, 0.92, LBLUE, ink);
        }
        Crop => {
            g.line(&[(0.26, 0.06), (0.26, 0.74), (0.94, 0.74)], ink);
            g.line(&[(0.06, 0.26), (0.74, 0.26), (0.74, 0.94)], ink);
        }
        CropShow => {
            g.rect(0.12, 0.12, 0.88, 0.88, Color32::TRANSPARENT, ink);
            for q in [(0.12, 0.5), (0.88, 0.5), (0.5, 0.12), (0.5, 0.88)] {
                g.dot(q, 0.06, BLUE);
            }
        }
        TempHide => {
            // Glasses.
            g.circle((0.3, 0.56), 0.16, LBLUE, ink);
            g.circle((0.7, 0.56), 0.16, LBLUE, ink);
            g.line(&[(0.46, 0.54), (0.54, 0.54)], ink);
            g.line(&[(0.14, 0.52), (0.08, 0.34)], ink);
            g.line(&[(0.86, 0.52), (0.92, 0.34)], ink);
        }
        RevealHidden => {
            g.circle((0.5, 0.38), 0.24, YELLOW, ink);
            g.rect(0.4, 0.62, 0.6, 0.84, LGREY, ink);
            g.line(&[(0.4, 0.72), (0.6, 0.72)], ink);
            g.rect(0.04, 0.04, 0.96, 0.96, Color32::TRANSPARENT, MAGENTA);
        }
        DetailLevel => {
            g.line_w(&[(0.1, 0.26), (0.9, 0.26)], ink, g.w * 2.0);
            g.line(&[(0.1, 0.5), (0.9, 0.5)], ink);
            g.thin_line(&[(0.1, 0.74), (0.9, 0.74)], ink);
        }
        VisualStyle | Shaded => g.cube(0.5, 0.5, 0.78, Color32::from_rgb(232, 232, 236), Color32::from_rgb(170, 172, 180), Color32::from_rgb(120, 122, 130)),
        Wireframe => {
            let ox = 0.5;
            let oy = 0.5;
            let s = 0.78;
            let pts = [(ox, oy - s * 0.55), (ox + s * 0.5, oy - s * 0.3), (ox, oy - s * 0.05), (ox - s * 0.5, oy - s * 0.3)];
            g.closed(&pts, ink);
            g.line(&[(ox - s * 0.5, oy - s * 0.3), (ox - s * 0.5, oy + s * 0.25), (ox, oy + s * 0.5), (ox + s * 0.5, oy + s * 0.25), (ox + s * 0.5, oy - s * 0.3)], ink);
            g.line(&[(ox, oy - s * 0.05), (ox, oy + s * 0.5)], ink);
            g.dashed((ox, oy - s * 0.55), (ox, oy), GREY);
        }
        HiddenLine => g.cube(0.5, 0.5, 0.78, Color32::WHITE, Color32::WHITE, Color32::WHITE),
        Consistent => g.cube(0.5, 0.5, 0.78, LBLUE, LBLUE, LBLUE),
        Realistic => {
            g.cube(0.5, 0.5, 0.78, LBROWN, BROWN, Color32::from_rgb(140, 96, 60));
            g.star((0.82, 0.18), 0.1, YELLOW);
        }
        SectionBox => {
            g.cube(0.5, 0.5, 0.78, Color32::TRANSPARENT, Color32::TRANSPARENT, Color32::TRANSPARENT);
            g.cube(0.5, 0.56, 0.4, LBLUE, BLUE, BLUE);
        }
        Home => {
            g.poly(&[(0.5, 0.12), (0.9, 0.48), (0.1, 0.48)], LBLUE, ink);
            g.rect(0.22, 0.48, 0.78, 0.88, Color32::WHITE, ink);
            g.rect_thin(0.42, 0.62, 0.58, 0.88, LBROWN, ink);
        }
        ZoomFit | ZoomRegion => {
            g.circle((0.42, 0.42), 0.28, Color32::WHITE, ink);
            g.line_w(&[(0.62, 0.62), (0.9, 0.9)], ink, g.w * 1.8);
            if icon == ZoomRegion {
                g.rect_thin(0.3, 0.32, 0.54, 0.52, LBLUE, BLUE);
            } else {
                g.text((0.42, 0.42), "⛶", 0.26, BLUE);
            }
        }
        Orbit => {
            g.arc((0.5, 0.5), 0.36, 0.3, 5.6, BLUE);
            g.dot((0.5, 0.5), 0.06, ink);
        }
        Pan => {
            draw(g, Move);
        }
        Ids => {
            g.rect(0.08, 0.26, 0.92, 0.74, Color32::WHITE, ink);
            g.text_bold((0.5, 0.5), "ID", 0.3, BLUE);
        }
        Warnings => {
            g.poly(&[(0.5, 0.1), (0.92, 0.86), (0.08, 0.86)], YELLOW, ink);
            g.text_bold((0.5, 0.6), "!", 0.4, ink);
        }
        Options => {
            g.circle((0.5, 0.5), 0.3, LGREY, ink);
            for k in 0..8 {
                let a = k as f32 * TAU / 8.0;
                g.line_w(&[(0.5 + 0.3 * a.cos(), 0.5 + 0.3 * a.sin()), (0.5 + 0.42 * a.cos(), 0.5 + 0.42 * a.sin())], ink, g.w * 2.2);
            }
            g.circle((0.5, 0.5), 0.12, Color32::WHITE, ink);
        }
        Keyboard => {
            g.rect(0.06, 0.3, 0.94, 0.76, LGREY, ink);
            for (k, y) in [(0, 0.42), (1, 0.56)] {
                for i in 0..6 {
                    let x = 0.14 + i as f32 * 0.12 + k as f32 * 0.04;
                    g.rect_thin(x, y, x + 0.08, y + 0.08, Color32::WHITE, ink);
                }
            }
        }
        Demolish => {
            g.poly(&[(0.12, 0.72), (0.5, 0.34), (0.62, 0.46), (0.24, 0.84)], LBROWN, ink);
            g.rect(0.46, 0.1, 0.9, 0.32, GREY, ink);
        }
        WallJoins => {
            g.rect(0.1, 0.1, 0.9, 0.34, LGREY, ink);
            g.rect(0.1, 0.34, 0.34, 0.9, LGREY, ink);
            g.circle((0.22, 0.22), 0.1, Color32::TRANSPARENT, BLUE);
        }
        JoinGeometry => {
            g.rect(0.1, 0.3, 0.6, 0.7, LGREY, ink);
            g.rect(0.4, 0.14, 0.9, 0.56, LBLUE, ink);
        }
        Extrusion => {
            g.poly(&[(0.2, 0.36), (0.6, 0.2), (0.86, 0.32), (0.46, 0.48)], LBLUE, ink);
            g.poly(&[(0.2, 0.36), (0.46, 0.48), (0.46, 0.86), (0.2, 0.74)], BLUE, ink);
            g.poly(&[(0.46, 0.48), (0.86, 0.32), (0.86, 0.7), (0.46, 0.86)], Color32::from_rgb(90, 150, 220), ink);
        }
        Blend => {
            g.poly(&[(0.12, 0.84), (0.88, 0.84), (0.66, 0.24), (0.34, 0.24)], LBLUE, ink);
        }
        Revolve => {
            g.dashdot((0.5, 0.06), (0.5, 0.94), GREEN);
            g.arc((0.5, 0.5), 0.36, -2.6, 2.6, BLUE);
        }
        Sweep => {
            g.arc((0.2, 0.86), 0.62, -FRAC_PI_2, 0.0, BLUE);
            g.rect(0.12, 0.14, 0.32, 0.34, LBLUE, ink);
        }
        VoidForm => {
            g.cube(0.5, 0.5, 0.78, Color32::from_rgb(255, 230, 200), Color32::from_rgb(255, 210, 170), Color32::from_rgb(240, 180, 140));
        }
        Label => {
            g.line(&[(0.1, 0.6), (0.9, 0.6)], BLUE);
            g.text((0.5, 0.38), "W", 0.3, BLUE);
            g.line(&[(0.1, 0.5), (0.1, 0.7)], ink);
            g.line(&[(0.9, 0.5), (0.9, 0.7)], ink);
        }
        ViewRange => {
            g.dashed((0.08, 0.2), (0.92, 0.2), GREEN);
            g.line(&[(0.08, 0.48), (0.92, 0.48)], RED);
            g.dashed((0.08, 0.76), (0.92, 0.76), BLUE);
        }
        Search => {
            g.circle((0.42, 0.42), 0.26, Color32::TRANSPARENT, ink);
            g.line_w(&[(0.62, 0.62), (0.88, 0.88)], ink, g.w * 1.6);
        }
        Mass => {
            // A rounded block with a sparkle (in-place mass).
            g.poly(&[(0.12, 0.34), (0.56, 0.18), (0.56, 0.78), (0.12, 0.92)], LGREY, ink);
            g.poly(&[(0.56, 0.18), (0.84, 0.3), (0.84, 0.86), (0.56, 0.78)], GREY, ink);
            g.poly(&[(0.12, 0.34), (0.56, 0.18), (0.84, 0.3), (0.4, 0.46)], Color32::WHITE, ink);
            g.star((0.82, 0.14), 0.12, ORANGE);
        }
        ShowMass => {
            g.poly(&[(0.12, 0.34), (0.56, 0.18), (0.56, 0.78), (0.12, 0.92)], LGREY, ink);
            g.poly(&[(0.56, 0.18), (0.84, 0.3), (0.84, 0.86), (0.56, 0.78)], GREY, ink);
            g.poly(&[(0.12, 0.34), (0.56, 0.18), (0.84, 0.3), (0.4, 0.46)], Color32::WHITE, ink);
        }
        WallByFace | FloorByFace | RoofByFace | CurtainByFace => {
            g.poly(&[(0.1, 0.36), (0.5, 0.2), (0.5, 0.8), (0.1, 0.94)], Color32::WHITE, ink);
            g.poly(&[(0.5, 0.2), (0.9, 0.34), (0.9, 0.9), (0.5, 0.8)], LGREY, ink);
            match icon {
                WallByFace => g.poly(&[(0.5, 0.2), (0.9, 0.34), (0.9, 0.9), (0.5, 0.8)], LBLUE, BLUE),
                FloorByFace => g.poly(&[(0.1, 0.62), (0.5, 0.48), (0.9, 0.6), (0.5, 0.74)], LBLUE, BLUE),
                RoofByFace => g.poly(&[(0.1, 0.36), (0.5, 0.2), (0.9, 0.34), (0.5, 0.5)], LBLUE, BLUE),
                _ => {
                    for k in 1..4 {
                        let t = k as f32 / 4.0;
                        g.thin_line(&[(0.5 + 0.4 * t, 0.2 + 0.14 * t), (0.5 + 0.4 * t, 0.8 + 0.1 * t)], BLUE);
                    }
                    g.thin_line(&[(0.5, 0.5), (0.9, 0.62)], BLUE);
                }
            }
        }
        Toposolid => {
            g.poly(&[(0.06, 0.6), (0.3, 0.36), (0.52, 0.48), (0.74, 0.3), (0.94, 0.5), (0.94, 0.72), (0.06, 0.86)], LGREEN, ink);
            g.poly(&[(0.06, 0.86), (0.94, 0.72), (0.94, 0.84), (0.06, 0.96)], BROWN, ink);
        }
        SiteComponent => {
            g.rect(0.46, 0.6, 0.54, 0.92, BROWN, ink);
            g.poly(&[(0.5, 0.08), (0.84, 0.66), (0.16, 0.66)], LGREEN, GREEN);
        }
        ParkingComponent => {
            for x in [0.14f32, 0.5, 0.86] {
                g.line(&[(x, 0.12), (x, 0.88)], ink);
            }
            g.line(&[(0.14, 0.12), (0.86, 0.12)], ink);
        }
        PropertyLine => {
            g.dashdot((0.1, 0.2), (0.82, 0.12), ink);
            g.dashdot((0.82, 0.12), (0.9, 0.86), ink);
            g.dashdot((0.9, 0.86), (0.14, 0.9), ink);
            g.dashdot((0.14, 0.9), (0.1, 0.2), ink);
        }
        SubElements => {
            draw(g, Toposolid);
            for q in [(0.3, 0.36), (0.74, 0.3), (0.52, 0.48)] {
                g.dot(q, 0.06, BLUE);
            }
        }
        ColorLegend => {
            for (k, c) in [ORANGE, LGREEN, LBLUE].into_iter().enumerate() {
                let y = 0.14 + k as f32 * 0.28;
                g.rect(0.1, y, 0.36, y + 0.2, c, ink);
                g.thin_line(&[(0.46, y + 0.1), (0.9, y + 0.1)], ink);
            }
        }
        ProjectParams => {
            // A tag card with a "P" and a small plus.
            g.poly(&[(0.12, 0.3), (0.66, 0.3), (0.86, 0.5), (0.66, 0.7), (0.12, 0.7)], Color32::WHITE, ink);
            g.circle((0.7, 0.5), 0.04, Color32::TRANSPARENT, ink);
            g.text_bold((0.36, 0.5), "P", 0.3, BLUE);
            g.line_w(&[(0.78, 0.08), (0.78, 0.28)], GREEN, g.w * 1.4);
            g.line_w(&[(0.68, 0.18), (0.88, 0.18)], GREEN, g.w * 1.4);
        }
        ViewFilters => {
            g.poly(&[(0.06, 0.14), (0.66, 0.14), (0.42, 0.44), (0.42, 0.76), (0.3, 0.84), (0.3, 0.44)], LBLUE, ink);
            for (k, c) in [ink, BLUE, RED].into_iter().enumerate() {
                let y = 0.5 + k as f32 * 0.16;
                g.line(&[(0.56, y), (0.94, y)], c);
            }
        }
        LineStyles => {
            g.line_w(&[(0.12, 0.2), (0.88, 0.2)], ink, g.w * 2.4);
            g.line(&[(0.12, 0.44), (0.88, 0.44)], ink);
            g.dashed((0.12, 0.64), (0.88, 0.64), ink);
            g.pencil(0.62, 0.92, 0.22);
        }
        AdditionalSettings => {
            // A wrench.
            g.line_w(&[(0.22, 0.82), (0.62, 0.42)], GREY, g.w * 3.0);
            g.arc((0.7, 0.32), 0.18, 0.6, 5.0, ink);
        }
        SelSave | SelLoad | SelEdit => {
            g.rect(0.1, 0.1, 0.62, 0.62, Color32::TRANSPARENT, BLUE);
            g.poly(&[(0.2, 0.2), (0.2, 0.52), (0.29, 0.44), (0.36, 0.58), (0.42, 0.55), (0.35, 0.41), (0.46, 0.41)], Color32::WHITE, ink);
            match icon {
                SelSave => {
                    g.rect(0.52, 0.52, 0.92, 0.92, LBLUE, ink);
                    g.rect(0.6, 0.52, 0.84, 0.66, Color32::WHITE, ink);
                }
                SelLoad => {
                    g.arrow((0.92, 0.72), (0.6, 0.72), GREEN);
                }
                _ => g.pencil(0.62, 0.94, 0.26),
            }
        }
        SpotCoordinate => {
            g.line(&[(0.14, 0.86), (0.36, 0.64), (0.9, 0.64)], ink);
            g.circle((0.14, 0.86), 0.06, Color32::TRANSPARENT, ink);
            g.text((0.6, 0.28), "N", 0.22, BLUE);
            g.text((0.6, 0.5), "E", 0.22, BLUE);
        }
        SpotSlope => {
            g.line(&[(0.08, 0.86), (0.92, 0.42)], ink);
            g.arrow((0.2, 0.6), (0.72, 0.34), BLUE);
            g.text((0.36, 0.26), "%", 0.26, BLUE);
        }
        ScopeBox => {
            g.cube(0.5, 0.56, 0.62, Color32::TRANSPARENT, Color32::TRANSPARENT, Color32::TRANSPARENT);
            g.dashdot((0.12, 0.3), (0.88, 0.3), BLUE);
            g.dashdot((0.12, 0.3), (0.12, 0.86), BLUE);
            g.dashdot((0.88, 0.3), (0.88, 0.86), BLUE);
            g.dashdot((0.12, 0.86), (0.88, 0.86), BLUE);
        }
        Insulation => {
            g.line(&[(0.08, 0.22), (0.92, 0.22)], ink);
            g.line(&[(0.08, 0.78), (0.92, 0.78)], ink);
            for k in 0..3 {
                let x = 0.2 + k as f32 * 0.28;
                g.arc((x, 0.5), 0.14, -PI, PI, ORANGE);
            }
        }
        DetailComponent => {
            g.rect(0.28, 0.1, 0.72, 0.9, LBROWN, ink);
            g.line(&[(0.28, 0.1), (0.72, 0.9)], ink);
            g.line(&[(0.72, 0.1), (0.28, 0.9)], ink);
        }
        Matchline => {
            g.rect(0.08, 0.12, 0.92, 0.88, Color32::WHITE, GREY);
            g.dashdot((0.5, 0.06), (0.5, 0.94), PURPLE);
            g.line_w(&[(0.5, 0.06), (0.5, 0.94)], Color32::TRANSPARENT, g.w);
        }
        ViewReference => {
            g.poly(&[(0.1, 0.36), (0.78, 0.36), (0.92, 0.5), (0.78, 0.64), (0.1, 0.64)], Color32::WHITE, ink);
            g.text((0.46, 0.5), "1/A", 0.22, BLUE);
        }
        Paint => {
            g.rect(0.22, 0.1, 0.78, 0.36, ORANGE, ink);
            g.line_w(&[(0.5, 0.36), (0.5, 0.5)], ink, g.w * 1.6);
            g.line_w(&[(0.5, 0.5), (0.5, 0.9)], BROWN, g.w * 2.6);
        }
        ActivateView => {
            g.rect(0.08, 0.12, 0.92, 0.88, Color32::WHITE, ink);
            g.rect(0.2, 0.24, 0.62, 0.62, LBLUE, BLUE);
            g.poly(&[(0.5, 0.48), (0.5, 0.86), (0.6, 0.76), (0.68, 0.92), (0.74, 0.89), (0.66, 0.73), (0.79, 0.73)], Color32::WHITE, ink);
        }
        GuideGrid => {
            g.rect(0.08, 0.12, 0.92, 0.88, Color32::WHITE, ink);
            for t in [0.3, 0.5, 0.7] {
                g.dashed((t, 0.12), (t, 0.88), BLUE);
                g.dashed((0.08, t), (0.92, t), BLUE);
            }
        }
        TitleBlock => {
            g.rect(0.08, 0.12, 0.92, 0.88, Color32::WHITE, ink);
            g.rect(0.62, 0.12, 0.92, 0.88, LGREY, ink);
            for y in [0.3, 0.48, 0.66] {
                g.line(&[(0.62, y), (0.92, y)], ink);
            }
        }
        Keynote => {
            g.line(&[(0.1, 0.9), (0.42, 0.56)], ink);
            g.rect(0.42, 0.18, 0.92, 0.56, Color32::WHITE, ink);
            g.text_bold((0.67, 0.37), "1", 0.24, BLUE);
        }
        DetailGroup => {
            g.rect(0.08, 0.14, 0.92, 0.86, Color32::TRANSPARENT, GREY);
            g.line(&[(0.2, 0.7), (0.5, 0.3)], ink);
            g.line(&[(0.5, 0.3), (0.8, 0.7)], ink);
            g.dashed((0.2, 0.74), (0.8, 0.74), BLUE);
        }
        GlobalParams => {
            g.circle((0.42, 0.5), 0.3, LBLUE, ink);
            g.line(&[(0.12, 0.5), (0.72, 0.5)], ink);
            g.arc((0.42, 0.5), 0.14, -FRAC_PI_2, FRAC_PI_2, ink);
            g.arc((0.42, 0.5), 0.14, FRAC_PI_2, PI + FRAC_PI_2, ink);
            g.text_bold((0.8, 0.26), "π", 0.26, BLUE);
        }
        ShowHidden | RemoveHidden => {
            g.cube(0.42, 0.42, 0.56, Color32::WHITE, LGREY, GREY);
            g.dashed((0.3, 0.86), (0.92, 0.86), BLUE);
            g.dashed((0.92, 0.86), (0.92, 0.34), BLUE);
            if icon == RemoveHidden {
                g.line_w(&[(0.62, 0.62), (0.92, 0.92)], RED, g.w * 1.4);
                g.line_w(&[(0.92, 0.62), (0.62, 0.92)], RED, g.w * 1.4);
            }
        }
        CanvasTheme => {
            // Half-dark disc: light and dark canvas.
            g.circle((0.5, 0.5), 0.34, Color32::WHITE, ink);
            let pts: Vec<(f32, f32)> = (0..=16).map(|k| {
                let a = -FRAC_PI_2 + PI * k as f32 / 16.0;
                (0.5 + 0.34 * a.cos(), 0.5 + 0.34 * a.sin())
            }).collect();
            g.poly(&pts, Color32::from_rgb(45, 52, 60), ink);
            for k in 0..8 {
                let a = k as f32 * TAU / 8.0;
                g.line(&[(0.5 + 0.4 * a.cos(), 0.5 + 0.4 * a.sin()), (0.5 + 0.47 * a.cos(), 0.5 + 0.47 * a.sin())], ink);
            }
        }
        UnjoinGeometry => {
            draw(g, JoinGeometry);
            g.line_w(&[(0.62, 0.62), (0.92, 0.92)], RED, g.w * 1.4);
            g.line_w(&[(0.92, 0.62), (0.62, 0.92)], RED, g.w * 1.4);
        }
        MultiTag => {
            g.poly(&[(0.1, 0.36), (0.62, 0.36), (0.84, 0.56), (0.62, 0.76), (0.1, 0.76)], YELLOW, ink);
            g.text_bold((0.38, 0.56), "M", 0.22, ink);
            g.rect(0.56, 0.1, 0.9, 0.36, LBLUE, ink);
        }
        MaterialTag => {
            g.poly(&[(0.1, 0.3), (0.62, 0.3), (0.84, 0.5), (0.62, 0.7), (0.1, 0.7)], Color32::WHITE, ink);
            g.circle((0.36, 0.5), 0.12, LBROWN, ink);
            g.circle((0.33, 0.47), 0.03, RED, Color32::TRANSPARENT);
        }
        FindReplace => {
            g.text_bold((0.3, 0.36), "A", 0.4, ink);
            g.circle((0.62, 0.56), 0.18, Color32::from_rgba_unmultiplied(255, 255, 255, 120), ink);
            g.line_w(&[(0.75, 0.69), (0.92, 0.88)], ink, g.w * 1.8);
        }
    }
    let _ = (CYAN, LGREEN);
}

const SNAP_C: Color32 = Color32::from_rgb(230, 110, 0);
