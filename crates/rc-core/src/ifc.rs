//! IFC4 (STEP physical file) export and import.
//!
//! Export writes walls (swept solids with material layer sets, openings, voids/fills), slabs,
//! roofs, doors, windows, furniture and spaces in a site/building/storey structure. A custom
//! property set (`RevitCraft_Parameters`) carries the parameters needed for a lossless round trip.
//! Import reads files from this exporter and the common subset written by other BIM tools.

use crate::analysis;
use crate::build3d;
use crate::defaults;
use crate::edit;
use crate::geom::{self, DVec2, DVec3, Frame3};
use crate::mesh::Mesh;
use crate::model::*;
use std::collections::{BTreeMap, HashMap};
use std::fmt::Write as _;

const PSET: &str = "RevitCraft_Parameters";

// ---------------------------------------------------------------- GUIDs

const B64: &[u8; 64] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$";

/// Compresses a UUID to IFC's 22-character GlobalId.
pub fn compress_guid(uuid: &uuid::Uuid) -> String {
    let n = uuid.as_u128();
    let mut s = String::with_capacity(22);
    s.push(B64[((n >> 126) & 0x3) as usize] as char);
    for i in 1..22 {
        s.push(B64[((n >> (6 * (21 - i))) & 0x3f) as usize] as char);
    }
    s
}

pub fn expand_guid(s: &str) -> Option<uuid::Uuid> {
    if s.len() != 22 {
        return None;
    }
    let mut n: u128 = 0;
    for (i, c) in s.bytes().enumerate() {
        let v = B64.iter().position(|b| *b == c)? as u128;
        if i == 0 && v > 3 {
            return None;
        }
        n = (n << if i == 0 { 0 } else { 6 }) | v;
    }
    Some(uuid::Uuid::from_u128(n))
}

fn new_guid() -> String {
    compress_guid(&uuid::Uuid::new_v4())
}

fn element_guid(e: &Element) -> String {
    uuid::Uuid::parse_str(&e.uid).map(|u| compress_guid(&u)).unwrap_or_else(|_| new_guid())
}

// ---------------------------------------------------------------- STEP writing

fn step_str(s: &str) -> String {
    let mut out = String::from("'");
    for c in s.chars() {
        match c {
            '\'' => out.push_str("''"),
            '\\' => out.push_str("\\\\"),
            c if (' '..='~').contains(&c) => out.push(c),
            c => {
                let mut buf = [0u16; 2];
                out.push_str("\\X2\\");
                for u in c.encode_utf16(&mut buf) {
                    let _ = write!(out, "{:04X}", u);
                }
                out.push_str("\\X0\\");
            }
        }
    }
    out.push('\'');
    out
}

fn opt_str(s: &str) -> String {
    if s.is_empty() { "$".into() } else { step_str(s) }
}

fn real(x: f64) -> String {
    let x = if x.abs() < 1e-9 { 0.0 } else { x };
    let s = format!("{}", (x * 1e6).round() / 1e6);
    if s.contains('.') || s.contains('E') || s.contains('e') { s } else { format!("{s}.") }
}

fn refs(ids: &[u32]) -> String {
    format!("({})", ids.iter().map(|i| format!("#{i}")).collect::<Vec<_>>().join(","))
}

struct Writer {
    out: String,
    next: u32,
    points: HashMap<(i64, i64, i64), u32>,
    dirs: HashMap<(i64, i64, i64), u32>,
    materials: HashMap<String, u32>,
    styles: HashMap<String, u32>,
}

impl Writer {
    fn material(&mut self, p: &Project, name: &str) -> u32 {
        if let Some(id) = self.materials.get(name) {
            return *id;
        }
        let class = p.material(name).map(|m| m.class.clone()).unwrap_or_default();
        let id = self.add(format!("IFCMATERIAL({},$,{})", step_str(name), opt_str(&class)));
        self.materials.insert(name.to_string(), id);
        id
    }

    fn style(&mut self, p: &Project, name: &str) -> u32 {
        if let Some(id) = self.styles.get(name) {
            return *id;
        }
        let m = p
            .material(name)
            .cloned()
            .unwrap_or(Material { name: name.into(), color: [200, 200, 200], opacity: 1.0, ..Default::default() });
        let c = self.add(format!(
            "IFCCOLOURRGB($,{},{},{})",
            real(m.color[0] as f64 / 255.0),
            real(m.color[1] as f64 / 255.0),
            real(m.color[2] as f64 / 255.0)
        ));
        let shading = self.add(format!("IFCSURFACESTYLESHADING(#{c},{})", real(1.0 - m.opacity)));
        let id = self.add(format!("IFCSURFACESTYLE({},.BOTH.,(#{shading}))", step_str(name)));
        self.styles.insert(name.to_string(), id);
        id
    }

    /// Triangulated face sets (one per material), relative to `origin`.
    fn tessellated(&mut self, p: &Project, meshes: &[(String, Mesh)], origin: DVec3) -> Vec<u32> {
        let mut items = Vec::new();
        for (mat, m) in meshes {
            if m.indices.is_empty() {
                continue;
            }
            let coords: Vec<String> = m
                .positions
                .iter()
                .map(|q| format!("({},{},{})", real(q.x - origin.x), real(q.y - origin.y), real(q.z - origin.z)))
                .collect();
            let list = self.add(format!("IFCCARTESIANPOINTLIST3D(({}))", coords.join(",")));
            let tris: Vec<String> = m.indices.chunks(3).map(|t| format!("({},{},{})", t[0] + 1, t[1] + 1, t[2] + 1)).collect();
            let set = self.add(format!("IFCTRIANGULATEDFACESET(#{list},$,$,({}),$)", tris.join(",")));
            let st = self.style(p, mat);
            self.add(format!("IFCSTYLEDITEM(#{set},(#{st}),$)"));
            items.push(set);
        }
        items
    }

    fn add(&mut self, entity: impl AsRef<str>) -> u32 {
        let id = self.next;
        self.next += 1;
        let _ = writeln!(self.out, "#{id}={};", entity.as_ref());
        id
    }

    fn point3(&mut self, p: DVec3) -> u32 {
        let key = ((p.x * 1000.0).round() as i64, (p.y * 1000.0).round() as i64, (p.z * 1000.0).round() as i64);
        if let Some(id) = self.points.get(&key) {
            return *id;
        }
        let id = self.add(format!("IFCCARTESIANPOINT(({},{},{}))", real(p.x), real(p.y), real(p.z)));
        self.points.insert(key, id);
        id
    }

    fn point2(&mut self, p: DVec2) -> u32 {
        self.add(format!("IFCCARTESIANPOINT(({},{}))", real(p.x), real(p.y)))
    }

    fn dir3(&mut self, d: DVec3) -> u32 {
        let key = ((d.x * 1e6).round() as i64, (d.y * 1e6).round() as i64, (d.z * 1e6).round() as i64);
        if let Some(id) = self.dirs.get(&key) {
            return *id;
        }
        let id = self.add(format!("IFCDIRECTION(({},{},{}))", real(d.x), real(d.y), real(d.z)));
        self.dirs.insert(key, id);
        id
    }

    fn axis3(&mut self, origin: DVec3, z: Option<DVec3>, x: Option<DVec3>) -> u32 {
        let o = self.point3(origin);
        let zs = z.map(|d| format!("#{}", self.dir3(d))).unwrap_or_else(|| "$".into());
        let xs = x.map(|d| format!("#{}", self.dir3(d))).unwrap_or_else(|| "$".into());
        self.add(format!("IFCAXIS2PLACEMENT3D(#{o},{zs},{xs})"))
    }

    fn placement(&mut self, parent: Option<u32>, origin: DVec3, x: Option<DVec3>) -> u32 {
        let ax = self.axis3(origin, x.map(|_| DVec3::Z), x);
        let parent = parent.map(|p| format!("#{p}")).unwrap_or_else(|| "$".into());
        self.add(format!("IFCLOCALPLACEMENT({parent},#{ax})"))
    }

    fn polyline2(&mut self, pts: &[DVec2], closed: bool) -> u32 {
        let mut ids: Vec<u32> = pts.iter().map(|p| self.point2(*p)).collect();
        if closed {
            ids.push(ids[0]);
        }
        self.add(format!("IFCPOLYLINE({})", refs(&ids)))
    }

    fn property_set(&mut self, object: u32, name: &str, props: &[(&str, String)]) {
        if props.is_empty() {
            return;
        }
        let ids: Vec<u32> = props
            .iter()
            .map(|(n, v)| self.add(format!("IFCPROPERTYSINGLEVALUE({},$,{v},$)", step_str(n))))
            .collect();
        let pset = self.add(format!("IFCPROPERTYSET('{}',$,{},$,{})", new_guid(), step_str(name), refs(&ids)));
        self.add(format!("IFCRELDEFINESBYPROPERTIES('{}',$,$,$,(#{object}),#{pset})", new_guid()));
    }
}

fn label(s: &str) -> String {
    format!("IFCLABEL({})", step_str(s))
}
fn length(x: f64) -> String {
    format!("IFCLENGTHMEASURE({})", real(x))
}
fn number(x: f64) -> String {
    format!("IFCREAL({})", real(x))
}
fn boolean(b: bool) -> String {
    format!("IFCBOOLEAN(.{}.)", if b { "T" } else { "F" })
}

fn points_text(pts: &[DVec2]) -> String {
    pts.iter().map(|p| format!("{:.3},{:.3}", p.x, p.y)).collect::<Vec<_>>().join(";")
}

fn parse_points(s: &str) -> Vec<DVec2> {
    s.split(';')
        .filter_map(|pair| {
            let mut it = pair.split(',');
            Some(DVec2::new(it.next()?.trim().parse().ok()?, it.next()?.trim().parse().ok()?))
        })
        .collect()
}

/// Writes the project as an IFC4 file.
pub fn export(p: &Project, file_name: &str, timestamp: &str) -> String {
    let mut w = Writer {
        out: String::new(),
        next: 1,
        points: HashMap::new(),
        dirs: HashMap::new(),
        materials: HashMap::new(),
        styles: HashMap::new(),
    };

    // Units, contexts, project.
    let len_u = w.add("IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.)");
    let area_u = w.add("IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.)");
    let vol_u = w.add("IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.)");
    let ang_u = w.add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)");
    let units = w.add(format!("IFCUNITASSIGNMENT({})", refs(&[len_u, area_u, vol_u, ang_u])));
    let world = w.axis3(DVec3::ZERO, None, None);
    let ctx = w.add(format!("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#{world},$)"));
    let body_ctx = w.add(format!("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#{ctx},$,.MODEL_VIEW.,$)"));
    let axis_ctx = w.add(format!("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Axis','Model',*,*,*,*,#{ctx},$,.GRAPH_VIEW.,$)"));
    let project = w.add(format!(
        "IFCPROJECT('{}',$,{},$,$,{},{},(#{ctx}),#{units})",
        new_guid(),
        step_str(&p.info.name),
        opt_str(&p.info.number),
        opt_str(&p.info.status)
    ));
    let site_pl = w.placement(None, DVec3::ZERO, None);
    let site = w.add(format!("IFCSITE('{}',$,'Default Site',$,$,#{site_pl},$,$,.ELEMENT.,$,$,$,$,$)", new_guid()));
    let bldg_pl = w.placement(Some(site_pl), DVec3::ZERO, None);
    let building = w.add(format!("IFCBUILDING('{}',$,{},$,$,#{bldg_pl},$,$,.ELEMENT.,$,$,$)", new_guid(), step_str(&p.info.name)));
    w.add(format!("IFCRELAGGREGATES('{}',$,$,$,#{project},(#{site}))", new_guid()));
    w.add(format!("IFCRELAGGREGATES('{}',$,$,$,#{site},(#{building}))", new_guid()));

    let mut storeys: BTreeMap<Id, (u32, u32, f64)> = BTreeMap::new();
    let mut storey_ids = Vec::new();
    for (id, l) in p.levels() {
        let pl = w.placement(Some(bldg_pl), DVec3::new(0.0, 0.0, l.elevation), None);
        let s = w.add(format!(
            "IFCBUILDINGSTOREY('{}',$,{},$,$,#{pl},$,$,.ELEMENT.,{})",
            element_guid(p.element(id).unwrap()),
            step_str(&l.name),
            real(l.elevation)
        ));
        storeys.insert(id, (s, pl, l.elevation));
        storey_ids.push(s);
    }
    w.add(format!("IFCRELAGGREGATES('{}',$,$,$,#{building},{})", new_guid(), refs(&storey_ids)));

    let footprints = analysis::wall_footprints(p);
    let mut contained: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    let mut spaces: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    let mut layer_sets: HashMap<Id, u32> = HashMap::new();
    let mut ifc_of: HashMap<Id, (u32, u32)> = HashMap::new(); // element -> (entity, placement)

    for e in &p.elements {
        let guid = element_guid(e);
        let name = step_str(&p.display_name(e));
        let tag = opt_str(&e.mark);
        let desc = opt_str(&e.comments);
        match &e.kind {
            ElementKind::Wall(wall) => {
                let Some(&(storey, spl, elev)) = storeys.get(&wall.base_level) else { continue };
                let Some(fp) = footprints.get(&e.id) else { continue };
                let height = analysis::wall_height(p, wall);
                if height <= 0.0 {
                    continue;
                }
                let dir = wall.direction();
                let n = wall.normal();
                let base = analysis::wall_base_z(p, wall) - elev;
                let pl = w.placement(Some(spl), geom::at(wall.start, base), Some(geom::at(dir, 0.0)));
                let ty = p.sys_type(wall.type_id);
                let curtain = analysis::is_curtain(p, wall);
                // Simple extrusions where possible; everything else (curtain, stacked, attached,
                // curved or with free openings) as a tessellated body.
                let simple = !curtain
                    && wall.arc_mid.is_none()
                    && wall.attach_top.is_none()
                    && wall.attach_base.is_none()
                    && wall.openings.is_empty()
                    && ty.is_none_or(|t| t.wall_kind == WallKind::Basic);
                let body = if simple {
                    let local: Vec<DVec2> = fp
                        .polygon()
                        .iter()
                        .map(|q| DVec2::new((*q - wall.start).dot(dir), (*q - wall.start).dot(n)))
                        .collect();
                    let outline = w.polyline2(&local, true);
                    let profile = w.add(format!("IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#{outline})"));
                    let pos = w.axis3(DVec3::ZERO, None, None);
                    let up = w.dir3(DVec3::Z);
                    let solid = w.add(format!("IFCEXTRUDEDAREASOLID(#{profile},#{pos},#{up},{})", real(height)));
                    let primary = ty.map(|t| t.primary_material()).unwrap_or_else(|| "Default".into());
                    let st = w.style(p, &primary);
                    w.add(format!("IFCSTYLEDITEM(#{solid},(#{st}),$)"));
                    w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','SweptSolid',(#{solid}))"))
                } else {
                    // Tessellated items are in storey coordinates; place them under a storey-aligned
                    // placement and keep the wall placement for hosted openings.
                    let set = build3d::element_mesh(p, e, &footprints);
                    let meshes: Vec<(String, Mesh)> = set.by_material.into_iter().collect();
                    let to_local = |v: DVec3| {
                        let d = DVec2::new(v.x, v.y) - wall.start;
                        DVec3::new(d.dot(dir), d.dot(n), v.z - elev - base)
                    };
                    let local: Vec<(String, Mesh)> = meshes
                        .into_iter()
                        .map(|(k, mut m)| {
                            for v in m.positions.iter_mut() {
                                *v = to_local(*v);
                            }
                            (k, m)
                        })
                        .collect();
                    let items = w.tessellated(p, &local, DVec3::ZERO);
                    w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','Tessellation',{})", refs(&items)))
                };
                let axis_line = w.polyline2(&[DVec2::ZERO, DVec2::new(wall.chord(), 0.0)], false);
                let axis_rep = w.add(format!("IFCSHAPEREPRESENTATION(#{axis_ctx},'Axis','Curve2D',(#{axis_line}))"));
                let shape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{axis_rep},#{body}))"));
                let object_type = opt_str(&ty.map(|t| t.name.clone()).unwrap_or_default());
                let ent = if curtain {
                    w.add(format!("IFCCURTAINWALL('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.NOTDEFINED.)"))
                } else {
                    w.add(format!("IFCWALL('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.STANDARD.)"))
                };
                contained.entry(storey).or_default().push(ent);
                ifc_of.insert(e.id, (ent, pl));

                // Material layer set (exterior side is +Y, layers run towards −Y).
                if let Some(t) = ty {
                    let ls = match layer_sets.get(&t.id) {
                        Some(id) => *id,
                        None => {
                            let layers: Vec<u32> = t
                                .layers
                                .iter()
                                .map(|l| {
                                    let m = w.material(p, &l.material);
                                    w.add(format!("IFCMATERIALLAYER(#{m},{},$,{},$,$,$)", real(l.thickness), step_str(l.function.label())))
                                })
                                .collect();
                            let id = w.add(format!("IFCMATERIALLAYERSET({},{},$)", refs(&layers), step_str(&t.name)));
                            layer_sets.insert(t.id, id);
                            id
                        }
                    };
                    let usage = w.add(format!("IFCMATERIALLAYERSETUSAGE(#{ls},.AXIS2.,.NEGATIVE.,{},$)", real(t.thickness() / 2.0)));
                    w.add(format!("IFCRELASSOCIATESMATERIAL('{}',$,$,$,(#{ent}),#{usage})", new_guid()));
                }
                w.property_set(ent, "Pset_WallCommon", &[
                    ("IsExternal", boolean(ty.is_some_and(|t| t.function == WallFunction::Exterior))),
                    ("LoadBearing", boolean(wall.structural)),
                ]);
                let mut props = vec![
                    ("Type", label(&ty.map(|t| t.name.clone()).unwrap_or_default())),
                    ("RoomBounding", boolean(wall.room_bounding)),
                    ("BaseOffset", length(wall.base_offset)),
                    ("Location", label(&points_text(&[wall.start, wall.end]))),
                    ("LocationLine", label(wall.location_line.label())),
                    ("UnconnectedHeight", length(height)),
                ];
                if let Some(m) = wall.arc_mid {
                    props.push(("ArcMid", label(&points_text(&[m]))));
                }
                if let Some(c) = &wall.curtain {
                    props.push(("CurtainGrid", label(&serde_json::to_string(c).unwrap_or_default())));
                }
                if let Some(top) = wall.top_level {
                    props.push(("TopLevel", label(&p.level_name(top))));
                    props.push(("TopOffset", length(wall.top_offset)));
                }
                w.property_set(ent, PSET, &props);
            }
            ElementKind::Floor(f) => {
                let Some(&(storey, spl, elev)) = storeys.get(&f.level) else { continue };
                let thick = analysis::floor_thickness(p, f);
                let top = analysis::floor_top_z(p, f) - elev;
                let pl = w.placement(Some(spl), DVec3::new(0.0, 0.0, top - thick), None);
                let outline = w.polyline2(&f.boundary, true);
                let profile = w.add(format!("IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#{outline})"));
                let pos = w.axis3(DVec3::ZERO, None, None);
                let up = w.dir3(DVec3::Z);
                let solid = w.add(format!("IFCEXTRUDEDAREASOLID(#{profile},#{pos},#{up},{})", real(thick)));
                let ty = p.sys_type(f.type_id);
                let st = w.style(p, &ty.and_then(|t| t.layers.first()).map(|l| l.material.clone()).unwrap_or_else(|| "Default".into()));
                w.add(format!("IFCSTYLEDITEM(#{solid},(#{st}),$)"));
                let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','SweptSolid',(#{solid}))"));
                let shape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))"));
                let object_type = opt_str(&ty.map(|t| t.name.clone()).unwrap_or_default());
                let ent = w.add(format!("IFCSLAB('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.FLOOR.)"));
                contained.entry(storey).or_default().push(ent);
                w.property_set(ent, PSET, &[("Type", label(&ty.map(|t| t.name.clone()).unwrap_or_default())), ("HeightOffset", length(f.height_offset))]);
            }
            ElementKind::Roof(r) => {
                let Some(&(storey, spl, elev)) = storeys.get(&r.level) else { continue };
                let set = build3d::element_mesh(p, e, &footprints);
                let meshes: Vec<(String, Mesh)> = set.by_material.into_iter().collect();
                let pl = w.placement(Some(spl), DVec3::ZERO, None);
                let items = w.tessellated(p, &meshes, DVec3::new(0.0, 0.0, elev));
                if items.is_empty() {
                    continue;
                }
                let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','Tessellation',{})", refs(&items)));
                let shape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))"));
                let predefined = match r.shape {
                    RoofShape::Flat => ".FLAT_ROOF.",
                    RoofShape::Gable => ".GABLE_ROOF.",
                    RoofShape::Hip => ".HIP_ROOF.",
                    RoofShape::Shed => ".SHED_ROOF.",
                };
                let ty = p.sys_type(r.type_id);
                let object_type = opt_str(&ty.map(|t| t.name.clone()).unwrap_or_default());
                let ent = w.add(format!("IFCROOF('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},{predefined})"));
                contained.entry(storey).or_default().push(ent);
                w.property_set(ent, PSET, &[
                    ("Type", label(&ty.map(|t| t.name.clone()).unwrap_or_default())),
                    ("Shape", label(r.shape.label())),
                    ("Slope", number(r.slope_deg)),
                    ("Overhang", length(r.overhang)),
                    ("BaseOffset", length(r.base_offset)),
                    ("Footprint", label(&points_text(&r.footprint))),
                ]);
            }
            ElementKind::Room(room) => {
                let Some(&(storey, spl, _)) = storeys.get(&room.level) else { continue };
                let Some(b) = analysis::room_boundary(p, room) else { continue };
                let pl = w.placement(Some(spl), DVec3::ZERO, None);
                let outline = w.polyline2(&b.interior, true);
                let profile = w.add(format!("IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#{outline})"));
                let pos = w.axis3(DVec3::ZERO, None, None);
                let up = w.dir3(DVec3::Z);
                let solid = w.add(format!("IFCEXTRUDEDAREASOLID(#{profile},#{pos},#{up},{})", real(analysis::room_height(p, room))));
                let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','SweptSolid',(#{solid}))"));
                let shape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))"));
                let ent = w.add(format!(
                    "IFCSPACE('{guid}',$,{},{desc},$,#{pl},#{shape},{},.ELEMENT.,.INTERNAL.,$)",
                    step_str(&room.number),
                    step_str(&room.name)
                ));
                spaces.entry(storey).or_default().push(ent);
                w.property_set(ent, PSET, &[
                    ("Location", label(&points_text(&[room.location]))),
                    ("Department", label(&room.department)),
                    ("FloorFinish", label(&room.floor_finish)),
                    ("WallFinish", label(&room.wall_finish)),
                    ("CeilingFinish", label(&room.ceiling_finish)),
                    ("Occupancy", label(&room.occupancy)),
                ]);
            }
            ElementKind::Ceiling(_) | ElementKind::Stair(_) | ElementKind::Ramp(_) | ElementKind::Railing(_) | ElementKind::WallFoundation(_) => {
                let level = match &e.kind {
                    ElementKind::WallFoundation(f) => p.wall(f.wall).map(|w| w.base_level),
                    _ => e.level(),
                };
                let Some(&(storey, spl, elev)) = level.and_then(|l| storeys.get(&l)) else { continue };
                let set = build3d::element_mesh(p, e, &footprints);
                let meshes: Vec<(String, Mesh)> = set.by_material.into_iter().collect();
                let pl = w.placement(Some(spl), DVec3::ZERO, None);
                let items = w.tessellated(p, &meshes, DVec3::new(0.0, 0.0, elev));
                if items.is_empty() {
                    continue;
                }
                let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','Tessellation',{})", refs(&items)));
                let shape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))"));
                let type_id = match &e.kind {
                    ElementKind::Ceiling(c) => c.type_id,
                    ElementKind::Stair(s) => s.type_id,
                    ElementKind::Ramp(r) => r.type_id,
                    ElementKind::Railing(r) => r.type_id,
                    ElementKind::WallFoundation(f) => f.type_id,
                    _ => unreachable!(),
                };
                let ty_name = p.sys_type(type_id).map(|t| t.name.clone()).unwrap_or_default();
                let object_type = opt_str(&ty_name);
                let mut props: Vec<(&str, String)> = vec![("Type", label(&ty_name))];
                let ent = match &e.kind {
                    ElementKind::Ceiling(c) => {
                        props.push(("Boundary", label(&points_text(&c.boundary))));
                        props.push(("HeightOffset", length(c.height_offset)));
                        w.add(format!("IFCCOVERING('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.CEILING.)"))
                    }
                    ElementKind::Stair(s) => {
                        let runs: Vec<String> =
                            s.runs.iter().map(|r| format!("{};{:.3}", points_text(&[r.start, r.end]), r.width)).collect();
                        props.push(("Runs", label(&runs.join("|"))));
                        props.push(("BaseOffset", length(s.base_offset)));
                        props.push(("UnconnectedHeight", length(analysis::stair_numbers(p, s).3)));
                        if let Some(t) = s.top_level {
                            props.push(("TopLevel", label(&p.level_name(t))));
                            props.push(("TopOffset", length(s.top_offset)));
                        }
                        props.push(("DesiredRisers", number(s.desired_risers as f64)));
                        w.add(format!("IFCSTAIR('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.NOTDEFINED.)"))
                    }
                    ElementKind::Ramp(r) => {
                        let runs: Vec<String> = r.runs.iter().map(|q| format!("{};{:.3}", points_text(&[q.start, q.end]), q.width)).collect();
                        props.push(("Runs", label(&runs.join("|"))));
                        props.push(("BaseOffset", length(r.base_offset)));
                        w.add(format!("IFCRAMP('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.NOTDEFINED.)"))
                    }
                    ElementKind::Railing(r) => {
                        props.push(("Path", label(&points_text(&r.path))));
                        props.push(("BaseOffset", length(r.base_offset)));
                        w.add(format!("IFCRAILING('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.GUARDRAIL.)"))
                    }
                    ElementKind::WallFoundation(f) => {
                        if let Some(host) = p.element(f.wall) {
                            props.push(("Wall", label(&host.uid)));
                        }
                        w.add(format!("IFCFOOTING('{guid}',$,{name},{desc},{object_type},#{pl},#{shape},{tag},.STRIP_FOOTING.)"))
                    }
                    _ => unreachable!(),
                };
                contained.entry(storey).or_default().push(ent);
                w.property_set(ent, PSET, &props);
            }
            _ => {}
        }
    }

    // Family instances (after walls, so hosts exist).
    for e in &p.elements {
        let ElementKind::Instance(i) = &e.kind else { continue };
        let Some(&(storey, spl, elev)) = storeys.get(&i.level) else { continue };
        let Some((family, ftype)) = p.family_type(i.type_id) else { continue };
        let guid = element_guid(e);
        let name = step_str(&p.display_name(e));
        let tag = opt_str(&e.mark);
        let desc = opt_str(&e.comments);
        let set = build3d::element_mesh(p, e, &footprints);
        let meshes: Vec<(String, Mesh)> = set.by_material.into_iter().collect();
        let pl = w.placement(Some(spl), DVec3::ZERO, None);
        let items = w.tessellated(p, &meshes, DVec3::new(0.0, 0.0, elev));
        let shape = if items.is_empty() {
            "$".to_string()
        } else {
            let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','Tessellation',{})", refs(&items)));
            format!("#{}", w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))")))
        };
        let object_type = step_str(&ftype.name);
        let (ow, oh) = analysis::opening_size(p, i);
        let ent = match family.category {
            Category::Doors => {
                let op = if family.template == FamilyTemplate::DoubleDoor { ".DOUBLE_DOOR_SINGLE_SWING." } else { ".SINGLE_SWING_LEFT." };
                w.add(format!("IFCDOOR('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},{},{},.DOOR.,{op},$)", real(oh), real(ow)))
            }
            Category::Windows => {
                let panels = crate::family_params::Resolver::for_instance(p, i).map(|r| r.num("Panels", 1.0)).unwrap_or(1.0);
                let part = if panels >= 2.0 { ".DOUBLE_PANEL_VERTICAL." } else { ".SINGLE_PANEL." };
                w.add(format!("IFCWINDOW('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},{},{},.WINDOW.,{part},$)", real(oh), real(ow)))
            }
            Category::Furniture | Category::Casework => w.add(format!("IFCFURNITURE('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},.NOTDEFINED.)")),
            Category::Columns | Category::StructuralColumns => {
                w.add(format!("IFCCOLUMN('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},.COLUMN.)"))
            }
            Category::StructuralFraming => w.add(format!("IFCBEAM('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},.BEAM.)")),
            Category::StructuralFoundations => {
                w.add(format!("IFCFOOTING('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},.PAD_FOOTING.)"))
            }
            _ => w.add(format!("IFCBUILDINGELEMENTPROXY('{guid}',$,{name},{desc},{object_type},#{pl},{shape},{tag},.NOTDEFINED.)")),
        };
        contained.entry(storey).or_default().push(ent);

        // Openings for hosted elements.
        if let (Some(host), Some(wall)) = (i.host, i.host.and_then(|h| p.wall(h))) {
            if let Some(&(wall_ent, wall_pl)) = ifc_of.get(&host) {
                let t = analysis::wall_thickness(p, wall);
                let base = analysis::wall_base_z(p, wall);
                let z0 = p.level_elevation(i.level) + i.elevation - base;
                let opl = w.placement(Some(wall_pl), DVec3::new(i.offset_along_host, 0.0, z0), Some(DVec3::X));
                let p0 = w.point2(DVec2::ZERO);
                let center = w.add(format!("IFCAXIS2PLACEMENT2D(#{p0},$)"));
                let rect = w.add(format!("IFCRECTANGLEPROFILEDEF(.AREA.,$,#{center},{},{})", real(ow), real(t + 20.0)));
                let pos = w.axis3(DVec3::ZERO, None, None);
                let up = w.dir3(DVec3::Z);
                let solid = w.add(format!("IFCEXTRUDEDAREASOLID(#{rect},#{pos},#{up},{})", real(oh)));
                let body = w.add(format!("IFCSHAPEREPRESENTATION(#{body_ctx},'Body','SweptSolid',(#{solid}))"));
                let oshape = w.add(format!("IFCPRODUCTDEFINITIONSHAPE($,$,(#{body}))"));
                let opening = w.add(format!("IFCOPENINGELEMENT('{}',$,'Opening',$,$,#{opl},#{oshape},$,.OPENING.)", new_guid()));
                w.add(format!("IFCRELVOIDSELEMENT('{}',$,$,$,#{wall_ent},#{opening})", new_guid()));
                w.add(format!("IFCRELFILLSELEMENT('{}',$,$,$,#{opening},#{ent})", new_guid()));
            }
        }
        let mut props = vec![
            ("Family", label(&family.name)),
            ("Template", label(&format!("{:?}", family.template))),
            ("Type", label(&ftype.name)),
            ("Elevation", length(i.elevation)),
            ("FlipFacing", boolean(i.flip_facing)),
            ("FlipHand", boolean(i.flip_hand)),
        ];
        if i.host.is_some() {
            props.push(("OffsetAlongHost", length(i.offset_along_host)));
        } else {
            props.push(("Location", label(&points_text(&[i.location]))));
            props.push(("Rotation", number(i.rotation_deg)));
        }
        props.push(("Category", label(family.category.label())));
        if let Some(t) = i.top_level {
            props.push(("TopLevel", label(&p.level_name(t))));
            props.push(("TopOffset", length(i.top_offset)));
        }
        if let Some(end) = i.end {
            props.push(("End", label(&points_text(&[end]))));
            props.push(("EndElevation", length(i.end_elevation)));
        }
        for (k, v) in &i.values {
            props.push((k.as_str(), label(v)));
        }
        // Type values let another RevitCraft project recreate a missing type exactly.
        let type_values: Vec<(String, String)> = ftype.values.iter().map(|(k, v)| (format!("Type:{k}"), label(v))).collect();
        let mut all: Vec<(&str, String)> = props;
        all.extend(type_values.iter().map(|(k, v)| (k.as_str(), v.clone())));
        w.property_set(ent, PSET, &all);
        if family.category == Category::Doors {
            let fire = crate::family_params::Resolver::for_instance(p, i).map(|r| r.text("Fire Rating", "")).unwrap_or_default();
            if !fire.is_empty() {
                w.property_set(ent, "Pset_DoorCommon", &[("FireRating", label(&fire))]);
            }
        }
    }

    // Grids: one IfcGrid holding every grid line (U = mostly north-south, V = the rest).
    let grids: Vec<(&Element, &Grid)> = p
        .elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::Grid(g) => Some((e, g)),
            _ => None,
        })
        .collect();
    if let Some(&(first_storey, spl, _)) = p.levels().first().and_then(|(id, _)| storeys.get(id)) {
        if !grids.is_empty() {
            let mut u = Vec::new();
            let mut v = Vec::new();
            for (_, g) in &grids {
                let line = w.polyline2(&[g.start, g.end], false);
                let axis = w.add(format!("IFCGRIDAXIS({},#{line},.T.)", step_str(&g.name)));
                let d = g.end - g.start;
                if d.y.abs() >= d.x.abs() { u.push(axis) } else { v.push(axis) }
            }
            if v.is_empty() {
                v.push(u.pop().unwrap());
            } else if u.is_empty() {
                u.push(v.pop().unwrap());
            }
            let pl = w.placement(Some(spl), DVec3::ZERO, None);
            let grid = w.add(format!("IFCGRID('{}',$,'Grid',$,$,#{pl},$,{},{},$,.RECTANGULAR.)", new_guid(), refs(&u), refs(&v)));
            contained.entry(first_storey).or_default().push(grid);
        }
    }

    for (storey, elements) in &contained {
        w.add(format!("IFCRELCONTAINEDINSPATIALSTRUCTURE('{}',$,$,$,{},#{storey})", new_guid(), refs(elements)));
    }
    for (storey, sp) in &spaces {
        w.add(format!("IFCRELAGGREGATES('{}',$,$,$,#{storey},{})", new_guid(), refs(sp)));
    }

    let mut out = String::new();
    out.push_str("ISO-10303-21;\nHEADER;\n");
    out.push_str("FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');\n");
    let _ = writeln!(
        out,
        "FILE_NAME({},{},({}),(''),'RevitCraft','RevitCraft {}','');",
        step_str(file_name),
        step_str(timestamp),
        step_str(&p.info.author),
        env!("CARGO_PKG_VERSION")
    );
    out.push_str("FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n");
    out.push_str(&w.out);
    out.push_str("ENDSEC;\nEND-ISO-10303-21;\n");
    out
}

// ---------------------------------------------------------------- STEP reading

#[derive(Clone, Debug, PartialEq)]
pub enum Arg {
    Ref(u32),
    Str(String),
    Num(f64),
    Enum(String),
    List(Vec<Arg>),
    Typed(String, Box<Arg>),
    Null,
    Derived,
}

impl Arg {
    fn as_ref(&self) -> Option<u32> {
        match self {
            Arg::Ref(r) => Some(*r),
            _ => None,
        }
    }
    fn as_num(&self) -> Option<f64> {
        match self {
            Arg::Num(n) => Some(*n),
            Arg::Typed(_, a) => a.as_num(),
            _ => None,
        }
    }
    fn as_str(&self) -> Option<&str> {
        match self {
            Arg::Str(s) => Some(s),
            Arg::Typed(_, a) => a.as_str(),
            _ => None,
        }
    }
    fn as_list(&self) -> &[Arg] {
        match self {
            Arg::List(l) => l,
            _ => &[],
        }
    }
    fn as_enum(&self) -> Option<&str> {
        match self {
            Arg::Enum(e) => Some(e),
            Arg::Typed(_, a) => a.as_enum(),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Entity {
    pub ty: String,
    pub args: Vec<Arg>,
}

fn decode_step_string(raw: &str) -> String {
    let mut out = String::new();
    let mut rest = raw;
    while let Some(pos) = rest.find('\\') {
        out.push_str(&rest[..pos]);
        rest = &rest[pos..];
        if let Some(r) = rest.strip_prefix("\\X2\\") {
            let end = r.find("\\X0\\").unwrap_or(r.len());
            let hex = &r[..end];
            let units: Vec<u16> = (0..hex.len() / 4).filter_map(|k| u16::from_str_radix(&hex[k * 4..k * 4 + 4], 16).ok()).collect();
            out.push_str(&String::from_utf16_lossy(&units));
            rest = r.get(end + 4..).unwrap_or("");
        } else if let Some(r) = rest.strip_prefix("\\X\\") {
            if let Some(b) = r.get(..2).and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(b as char);
            }
            rest = r.get(2..).unwrap_or("");
        } else if let Some(r) = rest.strip_prefix("\\\\") {
            out.push('\\');
            rest = r;
        } else if rest.starts_with("\\S\\") && rest.len() >= 4 {
            let c = rest.as_bytes()[3];
            out.push((c + 128) as char);
            rest = &rest[4..];
        } else {
            out.push('\\');
            rest = &rest[1..];
        }
    }
    out.push_str(rest);
    out
}

struct ArgParser<'a> {
    s: &'a [u8],
    i: usize,
}

impl ArgParser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && (self.s[self.i] as char).is_whitespace() {
            self.i += 1;
        }
    }

    fn list(&mut self) -> Result<Vec<Arg>, String> {
        self.ws();
        if self.s.get(self.i) != Some(&b'(') {
            return Err("expected '('".into());
        }
        self.i += 1;
        let mut out = Vec::new();
        loop {
            self.ws();
            match self.s.get(self.i) {
                Some(b')') => {
                    self.i += 1;
                    return Ok(out);
                }
                Some(b',') => self.i += 1,
                None => return Err("unterminated list".into()),
                _ => out.push(self.arg()?),
            }
        }
    }

    fn arg(&mut self) -> Result<Arg, String> {
        self.ws();
        let c = *self.s.get(self.i).ok_or("unexpected end")?;
        match c {
            b'#' => {
                self.i += 1;
                let start = self.i;
                while self.i < self.s.len() && self.s[self.i].is_ascii_digit() {
                    self.i += 1;
                }
                let n = std::str::from_utf8(&self.s[start..self.i]).unwrap().parse().map_err(|_| "bad reference")?;
                Ok(Arg::Ref(n))
            }
            b'\'' => {
                self.i += 1;
                let mut bytes = Vec::new();
                loop {
                    match self.s.get(self.i) {
                        None => return Err("unterminated string".into()),
                        Some(b'\'') if self.s.get(self.i + 1) == Some(&b'\'') => {
                            bytes.push(b'\'');
                            self.i += 2;
                        }
                        Some(b'\'') => {
                            self.i += 1;
                            break;
                        }
                        Some(b) => {
                            bytes.push(*b);
                            self.i += 1;
                        }
                    }
                }
                Ok(Arg::Str(decode_step_string(&String::from_utf8_lossy(&bytes))))
            }
            b'.' if self.s.get(self.i + 1).is_some_and(|b| b.is_ascii_alphabetic()) => {
                self.i += 1;
                let start = self.i;
                while self.i < self.s.len() && self.s[self.i] != b'.' {
                    self.i += 1;
                }
                let e = String::from_utf8_lossy(&self.s[start..self.i]).to_string();
                self.i += 1;
                Ok(Arg::Enum(e))
            }
            b'$' => {
                self.i += 1;
                Ok(Arg::Null)
            }
            b'*' => {
                self.i += 1;
                Ok(Arg::Derived)
            }
            b'(' => Ok(Arg::List(self.list()?)),
            b'"' => {
                // Binary literal: keep as text.
                self.i += 1;
                let start = self.i;
                while self.i < self.s.len() && self.s[self.i] != b'"' {
                    self.i += 1;
                }
                let v = String::from_utf8_lossy(&self.s[start..self.i]).to_string();
                self.i += 1;
                Ok(Arg::Str(v))
            }
            c if c.is_ascii_alphabetic() => {
                let start = self.i;
                while self.i < self.s.len() && (self.s[self.i].is_ascii_alphanumeric() || self.s[self.i] == b'_') {
                    self.i += 1;
                }
                let name = String::from_utf8_lossy(&self.s[start..self.i]).to_uppercase();
                let inner = self.list()?;
                Ok(Arg::Typed(name, Box::new(inner.into_iter().next().unwrap_or(Arg::Null))))
            }
            _ => {
                let start = self.i;
                while self.i < self.s.len() && (self.s[self.i].is_ascii_digit() || matches!(self.s[self.i], b'.' | b'-' | b'+' | b'E' | b'e')) {
                    self.i += 1;
                }
                let t = std::str::from_utf8(&self.s[start..self.i]).unwrap_or("");
                t.parse::<f64>().map(Arg::Num).map_err(|_| format!("bad value '{t}'"))
            }
        }
    }
}

/// Parses the DATA section of a STEP file.
pub fn parse_step(text: &str) -> Result<HashMap<u32, Entity>, String> {
    let data_start = text.find("DATA;").ok_or("Not an IFC file: no DATA section.")? + 5;
    let body = &text[data_start..];
    let mut map = HashMap::new();
    let bytes = body.as_bytes();
    let mut i = 0;
    let mut stmt_start = 0;
    let mut in_str = false;
    while i < bytes.len() {
        let b = bytes[i];
        if in_str {
            if b == b'\'' {
                if bytes.get(i + 1) == Some(&b'\'') {
                    i += 1;
                } else {
                    in_str = false;
                }
            }
        } else if b == b'\'' {
            in_str = true;
        } else if b == b'/' && bytes.get(i + 1) == Some(&b'*') {
            let end = body[i + 2..].find("*/").map(|e| i + 2 + e + 2).unwrap_or(bytes.len());
            i = end;
            continue;
        } else if b == b';' {
            let stmt = body[stmt_start..i].trim();
            stmt_start = i + 1;
            if stmt.starts_with("ENDSEC") {
                break;
            }
            if let Some(rest) = stmt.strip_prefix('#') {
                if let Some(eq) = rest.find('=') {
                    let id: u32 = rest[..eq].trim().parse().map_err(|_| format!("Bad entity id in '{stmt}'"))?;
                    let def = rest[eq + 1..].trim();
                    if let Some(paren) = def.find('(') {
                        let ty = def[..paren].trim().to_uppercase();
                        let mut p = ArgParser { s: def[paren..].as_bytes(), i: 0 };
                        let args = p.list().map_err(|e| format!("#{id}: {e}"))?;
                        map.insert(id, Entity { ty, args });
                    }
                }
            }
        }
        i += 1;
    }
    Ok(map)
}

// ---------------------------------------------------------------- import

struct Model {
    ents: HashMap<u32, Entity>,
    scale: f64,
}

impl Model {
    fn get(&self, id: u32) -> Option<&Entity> {
        self.ents.get(&id)
    }

    fn of_type<'a>(&'a self, ty: &'a str) -> impl Iterator<Item = (u32, &'a Entity)> + 'a {
        let mut v: Vec<(u32, &Entity)> = self.ents.iter().filter(|(_, e)| e.ty == ty).map(|(k, e)| (*k, e)).collect();
        v.sort_by_key(|x| x.0);
        v.into_iter()
    }

    fn point(&self, id: Option<u32>) -> Option<DVec3> {
        let e = self.get(id?)?;
        let c = e.args.first()?.as_list();
        let x = c.first().and_then(Arg::as_num).unwrap_or(0.0);
        let y = c.get(1).and_then(Arg::as_num).unwrap_or(0.0);
        let z = c.get(2).and_then(Arg::as_num).unwrap_or(0.0);
        Some(DVec3::new(x, y, z) * self.scale)
    }

    fn direction(&self, id: Option<u32>) -> Option<DVec3> {
        let e = self.get(id?)?;
        let c = e.args.first()?.as_list();
        Some(DVec3::new(
            c.first().and_then(Arg::as_num).unwrap_or(0.0),
            c.get(1).and_then(Arg::as_num).unwrap_or(0.0),
            c.get(2).and_then(Arg::as_num).unwrap_or(0.0),
        ))
    }

    fn axis_placement(&self, id: Option<u32>) -> Frame3 {
        let Some(e) = id.and_then(|i| self.get(i)) else { return Frame3::IDENTITY };
        let origin = self.point(e.args.first().and_then(Arg::as_ref)).unwrap_or(DVec3::ZERO);
        match e.ty.as_str() {
            "IFCAXIS2PLACEMENT2D" => {
                let x = self.direction(e.args.get(1).and_then(Arg::as_ref));
                Frame3::from_axes(origin, None, x)
            }
            _ => {
                let z = self.direction(e.args.get(1).and_then(Arg::as_ref));
                let x = self.direction(e.args.get(2).and_then(Arg::as_ref));
                Frame3::from_axes(origin, z, x)
            }
        }
    }

    fn placement(&self, id: Option<u32>, depth: u32) -> Frame3 {
        let Some(e) = id.and_then(|i| self.get(i)) else { return Frame3::IDENTITY };
        if e.ty != "IFCLOCALPLACEMENT" || depth > 64 {
            return Frame3::IDENTITY;
        }
        let parent = self.placement(e.args.first().and_then(Arg::as_ref), depth + 1);
        let local = self.axis_placement(e.args.get(1).and_then(Arg::as_ref));
        parent.then(&local)
    }

    fn object_placement(&self, ent: &Entity) -> Frame3 {
        self.placement(ent.args.get(5).and_then(Arg::as_ref), 0)
    }

    /// Representation items of a product, by representation identifier.
    fn items(&self, ent: &Entity, identifier: &str) -> Vec<u32> {
        let Some(shape) = ent.args.get(6).and_then(Arg::as_ref).and_then(|i| self.get(i)) else { return vec![] };
        let mut out = Vec::new();
        for r in shape.args.get(2).map(Arg::as_list).unwrap_or(&[]) {
            let Some(rep) = r.as_ref().and_then(|i| self.get(i)) else { continue };
            if rep.args.get(1).and_then(Arg::as_str).is_some_and(|s| s.eq_ignore_ascii_case(identifier)) {
                out.extend(rep.args.get(3).map(Arg::as_list).unwrap_or(&[]).iter().filter_map(Arg::as_ref));
            }
        }
        out
    }

    /// 2D points of a polyline (local coordinates).
    fn polyline(&self, id: u32) -> Vec<DVec2> {
        let Some(e) = self.get(id) else { return vec![] };
        if e.ty != "IFCPOLYLINE" {
            return vec![];
        }
        let mut pts: Vec<DVec2> = e.args[0]
            .as_list()
            .iter()
            .filter_map(|a| self.point(a.as_ref()))
            .map(|p| DVec2::new(p.x, p.y))
            .collect();
        if pts.len() > 1 && pts[0].distance(pts[pts.len() - 1]) < 1e-6 {
            pts.pop();
        }
        pts
    }

    /// Outline of a profile definition in its own 2D frame.
    fn profile(&self, id: u32) -> Vec<DVec2> {
        let Some(e) = self.get(id) else { return vec![] };
        match e.ty.as_str() {
            "IFCARBITRARYCLOSEDPROFILEDEF" => e.args.get(2).and_then(Arg::as_ref).map(|c| self.polyline(c)).unwrap_or_default(),
            "IFCRECTANGLEPROFILEDEF" => {
                let f = self.axis_placement(e.args.get(2).and_then(Arg::as_ref));
                let x = e.args.get(3).and_then(Arg::as_num).unwrap_or(0.0) * self.scale / 2.0;
                let y = e.args.get(4).and_then(Arg::as_num).unwrap_or(0.0) * self.scale / 2.0;
                [(-x, -y), (x, -y), (x, y), (-x, y)]
                    .iter()
                    .map(|(a, b)| {
                        let q = f.point(DVec3::new(*a, *b, 0.0));
                        DVec2::new(q.x, q.y)
                    })
                    .collect()
            }
            _ => vec![],
        }
    }

    /// An extruded area solid: world-space profile, base z and depth (assumes vertical extrusion).
    fn extrusion(&self, id: u32, frame: &Frame3) -> Option<(Vec<DVec2>, f64, f64)> {
        let e = self.get(id)?;
        if e.ty != "IFCEXTRUDEDAREASOLID" {
            return None;
        }
        let profile = self.profile(e.args[0].as_ref()?);
        if profile.len() < 3 {
            return None;
        }
        let pos = frame.then(&self.axis_placement(e.args.get(1).and_then(Arg::as_ref)));
        let depth = e.args.get(3).and_then(Arg::as_num)? * self.scale;
        let pts: Vec<DVec2> = profile.iter().map(|q| pos.point(geom::at(*q, 0.0))).map(|q| DVec2::new(q.x, q.y)).collect();
        Some((pts, pos.origin.z, depth))
    }

    /// World bounding box of tessellated or extruded body geometry.
    fn body_bounds(&self, ent: &Entity) -> Option<(DVec3, DVec3)> {
        let frame = self.object_placement(ent);
        let mut pts = Vec::new();
        for item in self.items(ent, "Body") {
            let Some(e) = self.get(item) else { continue };
            match e.ty.as_str() {
                "IFCTRIANGULATEDFACESET" | "IFCPOLYGONALFACESET" => {
                    if let Some(list) = e.args.first().and_then(Arg::as_ref).and_then(|i| self.get(i)) {
                        for c in list.args[0].as_list() {
                            let l = c.as_list();
                            let p = DVec3::new(
                                l.first().and_then(Arg::as_num).unwrap_or(0.0),
                                l.get(1).and_then(Arg::as_num).unwrap_or(0.0),
                                l.get(2).and_then(Arg::as_num).unwrap_or(0.0),
                            ) * self.scale;
                            pts.push(frame.point(p));
                        }
                    }
                }
                "IFCEXTRUDEDAREASOLID" => {
                    if let Some((outline, z, d)) = self.extrusion(item, &frame) {
                        for q in outline {
                            pts.push(geom::at(q, z));
                            pts.push(geom::at(q, z + d));
                        }
                    }
                }
                _ => {}
            }
        }
        let first = *pts.first()?;
        Some(pts.iter().fold((first, first), |(a, b), p| (a.min(*p), b.max(*p))))
    }

    fn psets(&self, object: u32) -> HashMap<String, Arg> {
        let mut out = HashMap::new();
        for (_, rel) in self.of_type("IFCRELDEFINESBYPROPERTIES") {
            if !rel.args.get(4).map(Arg::as_list).unwrap_or(&[]).iter().any(|a| a.as_ref() == Some(object)) {
                continue;
            }
            let Some(pset) = rel.args.get(5).and_then(Arg::as_ref).and_then(|i| self.get(i)) else { continue };
            for prop in pset.args.get(4).map(Arg::as_list).unwrap_or(&[]) {
                let Some(pe) = prop.as_ref().and_then(|i| self.get(i)) else { continue };
                if let (Some(name), Some(value)) = (pe.args.first().and_then(Arg::as_str), pe.args.get(2)) {
                    out.insert(name.to_string(), value.clone());
                }
            }
        }
        out
    }
}

fn text_of(props: &HashMap<String, Arg>, key: &str) -> Option<String> {
    props.get(key).and_then(|a| a.as_str()).map(String::from)
}

fn num_of(props: &HashMap<String, Arg>, key: &str, scale: f64) -> Option<f64> {
    props.get(key).and_then(|a| match a {
        Arg::Typed(t, inner) if t.contains("LENGTH") => inner.as_num().map(|v| v * scale),
        other => other.as_num(),
    })
}

fn bool_of(props: &HashMap<String, Arg>, key: &str) -> Option<bool> {
    props.get(key).and_then(|a| a.as_enum()).map(|e| e == "T")
}

fn length_scale(m: &HashMap<u32, Entity>) -> f64 {
    for e in m.values() {
        if e.ty == "IFCSIUNIT" && e.args.get(1).and_then(Arg::as_enum) == Some("LENGTHUNIT") {
            let prefix = e.args.get(2).and_then(Arg::as_enum);
            return match prefix {
                Some("MILLI") => 1.0,
                Some("CENTI") => 10.0,
                Some("DECI") => 100.0,
                _ => 1000.0,
            };
        }
        if e.ty == "IFCCONVERSIONBASEDUNIT" && e.args.get(1).and_then(Arg::as_enum) == Some("LENGTHUNIT") {
            let name = e.args.get(2).and_then(Arg::as_str).unwrap_or("").to_lowercase();
            if name.contains("foot") || name.contains("feet") {
                return 304.8;
            }
            if name.contains("inch") {
                return 25.4;
            }
        }
    }
    1000.0
}

/// Result of an import: the new project and any warnings.
pub struct ImportResult {
    pub project: Project,
    pub warnings: Vec<String>,
}

fn find_or_make_wall_type(p: &mut Project, name: Option<&str>, layers: Vec<Layer>, thickness: f64) -> Id {
    if let Some(n) = name {
        if let Some(t) = p.types_of(Category::Walls).find(|t| t.name == n && (t.thickness() - thickness).abs() < 1.0) {
            return t.id;
        }
    }
    if name.is_none() {
        if let Some(t) = p.types_of(Category::Walls).find(|t| (t.thickness() - thickness).abs() < 0.5) {
            return t.id;
        }
    }
    let layers = if layers.is_empty() { vec![Layer { function: LayerFunction::Structure, material: "Default".into(), thickness, core: true }] } else { layers };
    for l in &layers {
        if p.material(&l.material).is_none() {
            p.materials.push(Material { name: l.material.clone(), color: [200, 200, 200], opacity: 1.0, class: "Imported".into(), ..Default::default() });
        }
    }
    let base = name.map(String::from).unwrap_or_else(|| format!("Imported - {}mm", thickness.round()));
    let name = edit::unique_name(p.types.iter().map(|t| t.name.clone()), &base);
    let id = p.new_id();
    p.types.push(SystemType {
        id,
        category: Category::Walls,
        name,
        type_mark: String::new(),
        description: "Imported from IFC".into(),
        cost: 0.0,
        function: WallFunction::Exterior,
        layers,
        ..Default::default()
    });
    id
}

fn find_or_make_sys_type(p: &mut Project, category: Category, name: Option<&str>, thickness: f64) -> Id {
    if let Some(n) = name {
        if let Some(t) = p.types_of(category).find(|t| t.name == n) {
            return t.id;
        }
    }
    if let Some(t) = p.types_of(category).find(|t| (t.thickness() - thickness).abs() < 0.5) {
        return t.id;
    }
    let base = name.map(String::from).unwrap_or_else(|| format!("Imported - {}mm", thickness.round()));
    let name = edit::unique_name(p.types.iter().map(|t| t.name.clone()), &base);
    let id = p.new_id();
    p.types.push(SystemType {
        id,
        category,
        name,
        type_mark: String::new(),
        description: "Imported from IFC".into(),
        cost: 0.0,
        function: WallFunction::Exterior,
        layers: vec![Layer { function: LayerFunction::Structure, material: "Concrete".into(), thickness, core: true }],
        ..Default::default()
    });
    id
}

/// Finds a family type by family/type name, or creates one from the given template and values.
fn find_or_make_family_type(
    p: &mut Project,
    family_name: &str,
    template: FamilyTemplate,
    type_name: &str,
    values: &[(String, String)],
) -> Id {
    if let Some(f) = p.families.iter().find(|f| f.name == family_name) {
        if let Some(t) = f.types.iter().find(|t| t.name == type_name) {
            return t.id;
        }
        let fid = f.id;
        let id = p.new_id();
        let f = p.family_mut(fid).unwrap();
        f.types.push(FamilyType { id, name: type_name.into(), values: values.iter().cloned().collect() });
        return id;
    }
    let fid = defaults::add_family(p, family_name, template, &[]);
    let id = p.new_id();
    p.family_mut(fid).unwrap().types.push(FamilyType { id, name: type_name.into(), values: values.iter().cloned().collect() });
    id
}

fn template_from_name(s: &str) -> Option<FamilyTemplate> {
    FamilyTemplate::ALL.into_iter().find(|t| format!("{t:?}") == s)
}

/// Imports an IFC file into a new project based on the default template.
pub fn import(text: &str) -> Result<ImportResult, String> {
    let ents = parse_step(text)?;
    let scale = length_scale(&ents);
    let m = Model { ents, scale };
    let mut warnings = Vec::new();

    let system = if scale > 100.0 && scale < 1000.0 || scale < 30.0 && scale > 20.0 { crate::units::UnitSystem::Imperial } else { crate::units::UnitSystem::Metric };
    let mut p = defaults::new_project(system);
    // Start from the template's types and families but none of its levels, views or elements.
    p.elements.clear();
    p.views.retain(|v| !matches!(v.kind, ViewKind::FloorPlan { .. }));
    if let Some(proj) = m.of_type("IFCPROJECT").next() {
        if let Some(n) = proj.1.args.get(2).and_then(Arg::as_str) {
            p.info.name = n.to_string();
        }
        if let Some(n) = proj.1.args.get(5).and_then(Arg::as_str) {
            p.info.number = n.to_string();
        }
    }

    // Storeys → levels.
    let mut storey_level: HashMap<u32, Id> = HashMap::new();
    let mut storeys: Vec<(u32, String, f64)> = m
        .of_type("IFCBUILDINGSTOREY")
        .map(|(id, e)| {
            let name = e.args.get(2).and_then(Arg::as_str).unwrap_or("Level").to_string();
            let z = m.object_placement(e).origin.z;
            (id, name, z)
        })
        .collect();
    storeys.sort_by(|a, b| a.2.total_cmp(&b.2));
    for (sid, name, z) in &storeys {
        let name = edit::unique_name(p.levels().iter().map(|(_, l)| l.name.clone()), name);
        let id = defaults::add_level(&mut p, &name, *z, true);
        if let Some(e) = m.get(*sid) {
            if let Some(u) = e.args.first().and_then(Arg::as_str).and_then(expand_guid) {
                p.element_mut(id).unwrap().uid = u.to_string();
            }
        }
        storey_level.insert(*sid, id);
    }
    if storey_level.is_empty() {
        defaults::add_level(&mut p, "Level 1", 0.0, true);
        warnings.push("The file has no building storeys; everything was placed on Level 1.".into());
    }
    let default_level = p.levels()[0].0;

    // Element → storey.
    let mut container: HashMap<u32, u32> = HashMap::new();
    for (_, rel) in m.of_type("IFCRELCONTAINEDINSPATIALSTRUCTURE") {
        let Some(s) = rel.args.get(5).and_then(Arg::as_ref) else { continue };
        for a in rel.args.get(4).map(Arg::as_list).unwrap_or(&[]) {
            if let Some(r) = a.as_ref() {
                container.insert(r, s);
            }
        }
    }
    for (_, rel) in m.of_type("IFCRELAGGREGATES") {
        let Some(s) = rel.args.get(4).and_then(Arg::as_ref) else { continue };
        if m.get(s).is_none_or(|e| e.ty != "IFCBUILDINGSTOREY") {
            continue;
        }
        for a in rel.args.get(5).map(Arg::as_list).unwrap_or(&[]) {
            if let Some(r) = a.as_ref() {
                container.insert(r, s);
            }
        }
    }
    let level_for = |p: &Project, ent_id: u32, z: f64| -> Id {
        if let Some(l) = container.get(&ent_id).and_then(|s| storey_level.get(s)) {
            return *l;
        }
        // Not contained: use the highest level at or below z.
        p.levels().iter().rev().find(|(_, l)| l.elevation <= z + 1.0).map(|(id, _)| *id).unwrap_or(default_level)
    };

    // Material layer sets per element.
    let mut layer_sets: HashMap<u32, (Option<String>, Vec<Layer>)> = HashMap::new();
    for (_, rel) in m.of_type("IFCRELASSOCIATESMATERIAL") {
        let Some(mut mat) = rel.args.get(5).and_then(Arg::as_ref).and_then(|i| m.get(i)) else { continue };
        if mat.ty == "IFCMATERIALLAYERSETUSAGE" {
            let Some(ls) = mat.args.first().and_then(Arg::as_ref).and_then(|i| m.get(i)) else { continue };
            mat = ls;
        }
        if mat.ty != "IFCMATERIALLAYERSET" {
            continue;
        }
        let name = mat.args.get(1).and_then(Arg::as_str).map(String::from);
        let layers: Vec<Layer> = mat.args[0]
            .as_list()
            .iter()
            .filter_map(|a| m.get(a.as_ref()?))
            .map(|l| {
                let material = l.args.first().and_then(Arg::as_ref).and_then(|i| m.get(i)).and_then(|me| me.args.first()?.as_str()).unwrap_or("Default").to_string();
                let thickness = l.args.get(1).and_then(Arg::as_num).unwrap_or(0.0) * scale;
                let function = l
                    .args
                    .get(3)
                    .and_then(Arg::as_str)
                    .and_then(|n| LayerFunction::ALL.into_iter().find(|f| f.label() == n))
                    .unwrap_or(LayerFunction::Structure);
                Layer { function, material, thickness, core: function == LayerFunction::Structure }
            })
            .collect();
        for a in rel.args.get(4).map(Arg::as_list).unwrap_or(&[]) {
            if let Some(r) = a.as_ref() {
                layer_sets.insert(r, (name.clone(), layers.clone()));
            }
        }
    }

    let set_identity = |p: &mut Project, id: Id, ent: &Entity| {
        if let Some(e) = p.element_mut(id) {
            if let Some(u) = ent.args.first().and_then(Arg::as_str).and_then(expand_guid) {
                e.uid = u.to_string();
            }
            if let Some(d) = ent.args.get(3).and_then(Arg::as_str) {
                e.comments = d.to_string();
            }
            if let Some(t) = ent.args.get(7).and_then(Arg::as_str) {
                if !matches!(e.kind, ElementKind::Room(_)) {
                    e.mark = t.to_string();
                }
            }
        }
    };

    // Walls.
    let mut wall_of: HashMap<u32, Id> = HashMap::new();
    for ty in ["IFCWALL", "IFCWALLSTANDARDCASE", "IFCCURTAINWALL"] {
        for (eid, ent) in m.of_type(ty) {
            let frame = m.object_placement(ent);
            let props = m.psets(eid);
            // RevitCraft files carry the exact location line; prefer it to reverse-engineering the body.
            if let Some(loc) = text_of(&props, "Location").map(|s| parse_points(&s)).filter(|v| v.len() >= 2) {
                let type_name = text_of(&props, "Type");
                let existing = type_name.as_deref().and_then(|n| p.types_of(Category::Walls).find(|t| t.name == n).map(|t| t.id));
                let type_id = match existing {
                    Some(t) => t,
                    None if ty == "IFCCURTAINWALL" => match p.types_of(Category::Walls).find(|t| t.wall_kind == WallKind::Curtain) {
                        Some(t) => t.id,
                        None => {
                            warnings.push(format!("Curtain wall #{eid} has no matching curtain wall type and was skipped."));
                            continue;
                        }
                    },
                    None => {
                        let (ls_name, layers) = layer_sets.get(&eid).cloned().unwrap_or((None, vec![]));
                        let th: f64 = layers.iter().map(|l| l.thickness).sum();
                        find_or_make_wall_type(&mut p, type_name.as_deref().or(ls_name.as_deref()), layers, if th > 0.0 { th } else { 200.0 })
                    }
                };
                let level = level_for(&p, eid, frame.origin.z);
                let height = num_of(&props, "UnconnectedHeight", scale).unwrap_or(3000.0);
                let Ok(id) = edit::add_wall(&mut p, level, type_id, loc[0], loc[1], height) else { continue };
                let top_level = text_of(&props, "TopLevel").and_then(|n| p.levels().iter().find(|(_, l)| l.name == n).map(|(id, _)| *id));
                if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
                    w.base_offset = num_of(&props, "BaseOffset", scale).unwrap_or(0.0);
                    w.unconnected_height = height;
                    w.top_level = top_level;
                    if top_level.is_some() {
                        w.top_offset = num_of(&props, "TopOffset", scale).unwrap_or(0.0);
                    }
                    if let Some(ll) = text_of(&props, "LocationLine").and_then(|s| LocationLine::ALL.into_iter().find(|l| l.label() == s)) {
                        w.location_line = ll;
                    }
                    w.arc_mid = text_of(&props, "ArcMid").and_then(|s| parse_points(&s).first().copied());
                    w.curtain = text_of(&props, "CurtainGrid").and_then(|s| serde_json::from_str(&s).ok());
                    w.room_bounding = bool_of(&props, "RoomBounding").unwrap_or(true);
                    w.structural = bool_of(&props, "LoadBearing").unwrap_or(false);
                }
                set_identity(&mut p, id, ent);
                wall_of.insert(eid, id);
                continue;
            }
            let body = m.items(ent, "Body").into_iter().find_map(|i| m.extrusion(i, &frame));
            let Some((outline, z, depth)) = body else {
                warnings.push(format!("Wall #{eid} has no supported body geometry and was skipped."));
                continue;
            };
            let axis = m.items(ent, "Axis").into_iter().map(|i| m.polyline(i)).find(|pl| pl.len() >= 2);
            let (start, end, thickness) = match axis {
                Some(pl) => {
                    let a = frame.point(geom::at(pl[0], 0.0));
                    let b = frame.point(geom::at(pl[pl.len() - 1], 0.0));
                    let (a, b) = (DVec2::new(a.x, a.y), DVec2::new(b.x, b.y));
                    let d = (b - a).normalize_or_zero();
                    let n = geom::perp(d);
                    let offs: Vec<f64> = outline.iter().map(|q| (*q - a).dot(n)).collect();
                    let t = offs.iter().cloned().fold(f64::MIN, f64::max) - offs.iter().cloned().fold(f64::MAX, f64::min);
                    // Re-centre on the wall's middle line if the axis is on a face.
                    let mid = (offs.iter().cloned().fold(f64::MIN, f64::max) + offs.iter().cloned().fold(f64::MAX, f64::min)) / 2.0;
                    (a + n * mid, b + n * mid, t)
                }
                None => match geom::as_rectangle(&outline) {
                    Some(r) => (r.point(-r.half_length, 0.0), r.point(r.half_length, 0.0), 2.0 * r.half_width),
                    None => {
                        warnings.push(format!("Wall #{eid} has an irregular footprint and was skipped."));
                        continue;
                    }
                },
            };
            if start.distance(end) < 10.0 || thickness < 1.0 {
                continue;
            }
            let (ls_name, layers) = layer_sets.get(&eid).cloned().unwrap_or((None, vec![]));
            let type_name = text_of(&props, "Type").or(ls_name).or_else(|| ent.args.get(4).and_then(Arg::as_str).map(String::from));
            let layers_ok = (layers.iter().map(|l| l.thickness).sum::<f64>() - thickness).abs() < 1.0;
            let type_id = find_or_make_wall_type(&mut p, type_name.as_deref(), if layers_ok { layers } else { vec![] }, thickness);
            let level = level_for(&p, eid, z);
            let base_offset = z - p.level_elevation(level);
            let Ok(id) = edit::add_wall(&mut p, level, type_id, start, end, depth) else { continue };
            let top_level = text_of(&props, "TopLevel").and_then(|n| p.levels().iter().find(|(_, l)| l.name == n).map(|(id, _)| *id));
            if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
                w.base_offset = base_offset;
                w.unconnected_height = depth;
                w.top_level = None;
                if let Some(t) = top_level {
                    w.top_level = Some(t);
                    w.top_offset = num_of(&props, "TopOffset", scale).unwrap_or(0.0);
                }
                w.room_bounding = bool_of(&props, "RoomBounding").unwrap_or(true);
                w.structural = bool_of(&props, "LoadBearing").unwrap_or(false);
            }
            set_identity(&mut p, id, ent);
            wall_of.insert(eid, id);
        }
    }

    // Slabs and roofs.
    for (eid, ent) in m.of_type("IFCSLAB") {
        let frame = m.object_placement(ent);
        let props = m.psets(eid);
        let Some((outline, z, depth)) = m.items(ent, "Body").into_iter().find_map(|i| m.extrusion(i, &frame)) else {
            warnings.push(format!("Slab #{eid} has no supported body geometry and was skipped."));
            continue;
        };
        let predefined = ent.args.get(8).and_then(Arg::as_enum).unwrap_or("FLOOR");
        let level = level_for(&p, eid, z);
        let type_name = text_of(&props, "Type").or_else(|| ent.args.get(4).and_then(Arg::as_str).map(String::from));
        if predefined == "ROOF" {
            let ty = find_or_make_sys_type(&mut p, Category::Roofs, type_name.as_deref(), depth);
            let off = z - p.level_elevation(level);
            if let Ok(id) = edit::add_roof(&mut p, level, ty, outline, RoofShape::Flat, off) {
                if let Some(Element { kind: ElementKind::Roof(r), .. }) = p.element_mut(id) {
                    r.overhang = 0.0;
                }
                set_identity(&mut p, id, ent);
            }
            continue;
        }
        let ty = find_or_make_sys_type(&mut p, Category::Floors, type_name.as_deref(), depth);
        if let Ok(id) = edit::add_floor(&mut p, level, ty, outline) {
            let top = z + depth;
            let off = top - p.level_elevation(level);
            if let Some(Element { kind: ElementKind::Floor(f), .. }) = p.element_mut(id) {
                f.height_offset = off;
            }
            set_identity(&mut p, id, ent);
        }
    }
    for (eid, ent) in m.of_type("IFCROOF") {
        let props = m.psets(eid);
        let footprint = text_of(&props, "Footprint").map(|s| parse_points(&s));
        let frame = m.object_placement(ent);
        let level = level_for(&p, eid, frame.origin.z);
        let type_name = text_of(&props, "Type").or_else(|| ent.args.get(4).and_then(Arg::as_str).map(String::from));
        match footprint {
            Some(fp) if fp.len() >= 3 => {
                let ty = find_or_make_sys_type(&mut p, Category::Roofs, type_name.as_deref(), 250.0);
                let shape = text_of(&props, "Shape").and_then(|s| RoofShape::ALL.into_iter().find(|r| r.label() == s)).unwrap_or(RoofShape::Flat);
                let off = num_of(&props, "BaseOffset", scale).unwrap_or(0.0);
                if let Ok(id) = edit::add_roof(&mut p, level, ty, fp, shape, off) {
                    if let Some(Element { kind: ElementKind::Roof(r), .. }) = p.element_mut(id) {
                        r.slope_deg = num_of(&props, "Slope", 1.0).unwrap_or(30.0);
                        r.overhang = num_of(&props, "Overhang", scale).unwrap_or(0.0);
                    }
                    set_identity(&mut p, id, ent);
                }
            }
            _ => {
                if let Some((mn, mx)) = m.body_bounds(ent) {
                    let ty = find_or_make_sys_type(&mut p, Category::Roofs, type_name.as_deref(), 250.0);
                    let fp = vec![DVec2::new(mn.x, mn.y), DVec2::new(mx.x, mn.y), DVec2::new(mx.x, mx.y), DVec2::new(mn.x, mx.y)];
                    let off = mn.z - p.level_elevation(level);
                    if let Ok(id) = edit::add_roof(&mut p, level, ty, fp, RoofShape::Flat, off) {
                        if let Some(Element { kind: ElementKind::Roof(r), .. }) = p.element_mut(id) {
                            r.overhang = 0.0;
                        }
                        set_identity(&mut p, id, ent);
                    }
                    warnings.push(format!("Roof #{eid} was imported as a flat roof over its bounding box."));
                } else {
                    warnings.push(format!("Roof #{eid} has no supported geometry and was skipped."));
                }
            }
        }
    }

    // Openings: opening entity → (host wall, box).
    let mut opening_host: HashMap<u32, u32> = HashMap::new();
    for (_, rel) in m.of_type("IFCRELVOIDSELEMENT") {
        if let (Some(w), Some(o)) = (rel.args.get(4).and_then(Arg::as_ref), rel.args.get(5).and_then(Arg::as_ref)) {
            opening_host.insert(o, w);
        }
    }
    let mut filled_by: HashMap<u32, u32> = HashMap::new();
    for (_, rel) in m.of_type("IFCRELFILLSELEMENT") {
        if let (Some(o), Some(f)) = (rel.args.get(4).and_then(Arg::as_ref), rel.args.get(5).and_then(Arg::as_ref)) {
            filled_by.insert(f, o);
        }
    }

    // Doors, windows, furniture and proxies.
    for (ty, category) in [
        ("IFCDOOR", Category::Doors),
        ("IFCWINDOW", Category::Windows),
        ("IFCFURNITURE", Category::Furniture),
        ("IFCFURNISHINGELEMENT", Category::Furniture),
        ("IFCBUILDINGELEMENTPROXY", Category::GenericModels),
        ("IFCCOLUMN", Category::StructuralColumns),
        ("IFCBEAM", Category::StructuralFraming),
        ("IFCFOOTING", Category::StructuralFoundations),
    ] {
        for (eid, ent) in m.of_type(ty) {
            if ty == "IFCFOOTING" && ent.args.get(8).and_then(Arg::as_enum) == Some("STRIP_FOOTING") {
                continue;
            }
            let props = m.psets(eid);
            let type_name = text_of(&props, "Type")
                .or_else(|| ent.args.get(4).and_then(Arg::as_str).map(String::from))
                .unwrap_or_else(|| "Imported".into());
            let mut values: Vec<(String, String)> = props
                .iter()
                .filter_map(|(k, v)| Some((k.strip_prefix("Type:")?.to_string(), v.as_str()?.to_string())))
                .collect();
            values.sort();
            let template = text_of(&props, "Template").and_then(|s| template_from_name(&s));
            let bounds = m.body_bounds(ent);

            if category == Category::Doors || category == Category::Windows {
                let opening = filled_by.get(&eid).copied();
                let host_ifc = opening.and_then(|o| opening_host.get(&o)).copied();
                let Some(host) = host_ifc.and_then(|h| wall_of.get(&h)).copied() else {
                    warnings.push(format!("{} #{eid} has no host wall and was skipped.", category.singular()));
                    continue;
                };
                let wall = p.wall(host).unwrap().clone();
                let ow = ent.args.get(9).and_then(Arg::as_num).map(|v| v * scale);
                let oh = ent.args.get(8).and_then(Arg::as_num).map(|v| v * scale);
                // Opening box gives the position for files from other tools.
                let obox = opening.and_then(|o| m.get(o)).and_then(|o| m.body_bounds(o)).or(bounds);
                let (center, bottom) = match obox {
                    Some((mn, mx)) => (DVec2::new((mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0), mn.z),
                    None => {
                        let f = m.object_placement(ent);
                        (DVec2::new(f.origin.x, f.origin.y), f.origin.z)
                    }
                };
                let along = num_of(&props, "OffsetAlongHost", scale).unwrap_or_else(|| (center - wall.start).dot(wall.direction()));
                let (family_name, tmpl) = match (text_of(&props, "Family"), template) {
                    (Some(f), Some(t)) => (f, t),
                    _ if category == Category::Doors => ("Imported Door".to_string(), FamilyTemplate::SingleDoor),
                    _ => ("Imported Window".to_string(), FamilyTemplate::FixedWindow),
                };
                if values.is_empty() {
                    let (w, h) = (ow.unwrap_or(900.0), oh.unwrap_or(2100.0));
                    values = if category == Category::Doors {
                        vec![("Width".into(), units_str(w - 100.0)), ("Height".into(), units_str(h - 50.0))]
                    } else {
                        vec![("Width".into(), units_str(w)), ("Height".into(), units_str(h))]
                    };
                }
                let type_id = find_or_make_family_type(&mut p, &family_name, tmpl, &type_name, &values);
                let level = wall.base_level;
                let sill = num_of(&props, "Elevation", scale).unwrap_or(bottom - p.level_elevation(level));
                let fam = p.family_type(type_id).map(|(f, _)| (f.id, f.category)).unwrap();
                let id = p.new_id();
                p.elements.push(Element::new(
                    id,
                    ElementKind::Instance(FamilyInstance {
                        family_id: fam.0,
                        type_id,
                        category: fam.1,
                        level,
                        host: Some(host),
                        offset_along_host: along,
                        location: DVec2::ZERO,
                        elevation: sill,
                        rotation_deg: 0.0,
                        flip_facing: bool_of(&props, "FlipFacing").unwrap_or(false),
                        flip_hand: bool_of(&props, "FlipHand").unwrap_or(false),
                        values: Default::default(),
                        ..Default::default()
                    }),
                ));
                set_identity(&mut p, id, ent);
                continue;
            }

            // Free-standing.
            let location = text_of(&props, "Location").and_then(|s| parse_points(&s).first().copied());
            let (family_name, tmpl) = match (text_of(&props, "Family"), template) {
                (Some(f), Some(t)) => (f, t),
                _ => ("Imported Object".to_string(), FamilyTemplate::Box),
            };
            let (loc, z) = match (location, bounds) {
                (Some(l), Some((mn, _))) => (l, mn.z),
                (Some(l), None) => (l, m.object_placement(ent).origin.z),
                (None, Some((mn, mx))) => {
                    if values.is_empty() {
                        values = vec![
                            ("Width".into(), units_str(mx.x - mn.x)),
                            ("Depth".into(), units_str(mx.y - mn.y)),
                            ("Height".into(), units_str(mx.z - mn.z)),
                        ];
                    }
                    (DVec2::new((mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0), mn.z)
                }
                (None, None) => {
                    warnings.push(format!("{} #{eid} has no supported geometry and was skipped.", category.singular()));
                    continue;
                }
            };
            let type_id = find_or_make_family_type(&mut p, &family_name, tmpl, &type_name, &values);
            let level = level_for(&p, eid, z);
            let Ok(id) = edit::place_free(&mut p, type_id, level, loc, num_of(&props, "Rotation", 1.0).unwrap_or(0.0)) else { continue };
            let elevation = num_of(&props, "Elevation", scale).unwrap_or(z - p.level_elevation(level));
            let top_level = text_of(&props, "TopLevel").and_then(|n| p.levels().iter().find(|(_, l)| l.name == n).map(|(id, _)| *id));
            if let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) {
                i.elevation = elevation;
                i.top_level = top_level;
                i.top_offset = num_of(&props, "TopOffset", scale).unwrap_or(0.0);
                i.end = text_of(&props, "End").and_then(|s| parse_points(&s).first().copied());
                i.end_elevation = num_of(&props, "EndElevation", scale).unwrap_or(elevation);
            }
            set_identity(&mut p, id, ent);
        }
    }

    // Ceilings, stairs, railings and strip footings written by RevitCraft (recreated from their psets).
    let find_type = |p: &Project, category: Category, name: Option<String>| -> Option<Id> {
        name.and_then(|n| p.types_of(category).find(|t| t.name == n).map(|t| t.id)).or_else(|| p.types_of(category).next().map(|t| t.id))
    };
    for (eid, ent) in m.of_type("IFCCOVERING") {
        if ent.args.get(8).and_then(Arg::as_enum) != Some("CEILING") {
            continue;
        }
        let props = m.psets(eid);
        let Some(boundary) = text_of(&props, "Boundary").map(|s| parse_points(&s)).filter(|b| b.len() >= 3) else {
            warnings.push(format!("Ceiling #{eid} has no boundary data and was skipped."));
            continue;
        };
        let level = level_for(&p, eid, m.object_placement(ent).origin.z);
        let Some(ty) = find_type(&p, Category::Ceilings, text_of(&props, "Type")) else { continue };
        let h = num_of(&props, "HeightOffset", scale).unwrap_or(2600.0);
        if let Ok(id) = edit::add_ceiling(&mut p, level, ty, boundary, h) {
            set_identity(&mut p, id, ent);
        }
    }
    for (eid, ent) in m.of_type("IFCSTAIR") {
        let props = m.psets(eid);
        let runs: Vec<StairRun> = text_of(&props, "Runs")
            .unwrap_or_default()
            .split('|')
            .filter_map(|r| {
                let parts: Vec<&str> = r.split(';').collect();
                if parts.len() < 3 {
                    return None;
                }
                let a = parse_points(parts[0]).first().copied()?;
                let b = parse_points(parts[1]).first().copied()?;
                Some(StairRun { start: a, end: b, width: parts[2].trim().parse().ok()? })
            })
            .collect();
        if runs.is_empty() {
            warnings.push(format!("Stair #{eid} has no run data and was skipped."));
            continue;
        }
        let level = level_for(&p, eid, m.object_placement(ent).origin.z);
        let Some(ty) = find_type(&p, Category::Stairs, text_of(&props, "Type")) else { continue };
        let top_level = text_of(&props, "TopLevel").and_then(|n| p.levels().iter().find(|(_, l)| l.name == n).map(|(id, _)| *id));
        // Railings are imported as their own elements below.
        let Ok(id) = edit::add_stair(&mut p, level, ty, runs, None) else { continue };
        if let Some(Element { kind: ElementKind::Stair(s), .. }) = p.element_mut(id) {
            s.base_offset = num_of(&props, "BaseOffset", scale).unwrap_or(0.0);
            s.top_level = top_level;
            s.top_offset = num_of(&props, "TopOffset", scale).unwrap_or(0.0);
            s.unconnected_height = num_of(&props, "UnconnectedHeight", scale).unwrap_or(s.unconnected_height);
            s.desired_risers = num_of(&props, "DesiredRisers", 1.0).unwrap_or(0.0) as u32;
            s.railings = false;
        }
        set_identity(&mut p, id, ent);
    }
    for (eid, ent) in m.of_type("IFCRAILING") {
        let props = m.psets(eid);
        let Some(path) = text_of(&props, "Path").map(|s| parse_points(&s)).filter(|b| b.len() >= 2) else {
            warnings.push(format!("Railing #{eid} has no path data and was skipped."));
            continue;
        };
        let level = level_for(&p, eid, m.object_placement(ent).origin.z);
        let Some(ty) = find_type(&p, Category::Railings, text_of(&props, "Type")) else { continue };
        if let Ok(id) = edit::add_railing(&mut p, level, ty, path) {
            if let Some(Element { kind: ElementKind::Railing(r), .. }) = p.element_mut(id) {
                r.base_offset = num_of(&props, "BaseOffset", scale).unwrap_or(0.0);
            }
            set_identity(&mut p, id, ent);
        }
    }
    for (eid, ent) in m.of_type("IFCFOOTING") {
        if ent.args.get(8).and_then(Arg::as_enum) != Some("STRIP_FOOTING") {
            continue;
        }
        let props = m.psets(eid);
        let host = text_of(&props, "Wall").and_then(|uid| p.elements.iter().find(|e| e.uid == uid).map(|e| e.id));
        let Some(host) = host else {
            warnings.push(format!("Wall foundation #{eid} has no host wall and was skipped."));
            continue;
        };
        let Some(ty) = find_type(&p, Category::StructuralFoundations, text_of(&props, "Type")) else { continue };
        if let Ok(id) = edit::add_wall_foundation(&mut p, host, ty) {
            set_identity(&mut p, id, ent);
        }
    }

    // Grid axes.
    for (_, ent) in m.of_type("IFCGRID") {
        let frame = m.object_placement(ent);
        for axes in [ent.args.get(7), ent.args.get(8), ent.args.get(9)].into_iter().flatten() {
            for a in axes.as_list() {
                let Some(axis) = a.as_ref().and_then(|i| m.get(i)) else { continue };
                let name = axis.args.first().and_then(Arg::as_str).unwrap_or("?").to_string();
                let pts = axis.args.get(1).and_then(Arg::as_ref).map(|c| m.polyline(c)).unwrap_or_default();
                if pts.len() < 2 {
                    continue;
                }
                let to_world = |q: DVec2| {
                    let w = frame.point(geom::at(q, 0.0));
                    DVec2::new(w.x, w.y)
                };
                if let Ok(id) = edit::add_grid(&mut p, to_world(pts[0]), to_world(pts[pts.len() - 1])) {
                    if let Some(Element { kind: ElementKind::Grid(g), .. }) = p.element_mut(id) {
                        g.name = name;
                    }
                }
            }
        }
    }

    // Spaces → rooms (boundaries are re-detected from walls).
    for (eid, ent) in m.of_type("IFCSPACE") {
        let props = m.psets(eid);
        let frame = m.object_placement(ent);
        let body = m.items(ent, "Body").into_iter().find_map(|i| m.extrusion(i, &frame));
        let location = text_of(&props, "Location").and_then(|s| parse_points(&s).first().copied()).or_else(|| body.as_ref().map(|b| geom::centroid(&b.0)));
        let Some(loc) = location else {
            warnings.push(format!("Space #{eid} has no position and was skipped."));
            continue;
        };
        let z = body.as_ref().map(|b| b.1).unwrap_or(frame.origin.z);
        let level = level_for(&p, eid, z);
        let id = p.new_id();
        let number = ent.args.get(2).and_then(Arg::as_str).unwrap_or("").to_string();
        let name = ent.args.get(7).and_then(Arg::as_str).unwrap_or("Room").to_string();
        p.elements.push(Element::new(
            id,
            ElementKind::Room(Room {
                name,
                number,
                level,
                location: loc,
                upper_offset: body.as_ref().map(|b| b.2).unwrap_or(2700.0),
                upper_level: None,
                base_offset: 0.0,
                department: text_of(&props, "Department").unwrap_or_default(),
                floor_finish: text_of(&props, "FloorFinish").unwrap_or_default(),
                wall_finish: text_of(&props, "WallFinish").unwrap_or_default(),
                ceiling_finish: text_of(&props, "CeilingFinish").unwrap_or_default(),
                occupancy: text_of(&props, "Occupancy").unwrap_or_default(),
            }),
        ));
        set_identity(&mut p, id, ent);
    }

    if p.elements.iter().all(|e| matches!(e.kind, ElementKind::Level(_))) {
        warnings.push("No supported building elements were found in the file.".into());
    }
    Ok(ImportResult { project: p, warnings })
}

fn units_str(v: f64) -> String {
    crate::units::to_stored((v * 10.0).round() / 10.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::params;

    #[test]
    fn guid_round_trip() {
        for _ in 0..50 {
            let u = uuid::Uuid::new_v4();
            let s = compress_guid(&u);
            assert_eq!(s.len(), 22);
            assert_eq!(expand_guid(&s), Some(u));
        }
    }

    #[test]
    fn strings_escape_and_decode() {
        let s = step_str("O'Brien café \\ test");
        let wrapped = format!("({s})");
        let mut ap = ArgParser { s: wrapped.as_bytes(), i: 0 };
        let parsed = ap.list().unwrap();
        assert_eq!(parsed[0], Arg::Str("O'Brien café \\ test".into()));
    }

    fn sample() -> Project {
        let mut p = defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let brick = p.types_of(Category::Walls).find(|t| t.name == "Exterior - Brick on Block").unwrap().id;
        let pts = [(0.0, 0.0), (8000.0, 0.0), (8000.0, 6000.0), (0.0, 6000.0)];
        let mut walls = Vec::new();
        for k in 0..4 {
            let a = DVec2::new(pts[k].0, pts[k].1);
            let b = DVec2::new(pts[(k + 1) % 4].0, pts[(k + 1) % 4].1);
            walls.push(edit::add_wall(&mut p, lvl, brick, a, b, 3000.0).unwrap());
        }
        let door = p.families.iter().find(|f| f.name == "Single-Flush").unwrap().types[1].id;
        let window = p.families.iter().find(|f| f.name == "Fixed").unwrap().types[1].id;
        let d = edit::place_hosted(&mut p, door, walls[0], 2000.0, false).unwrap();
        p.element_mut(d).unwrap().mark = "D1".into();
        edit::place_hosted(&mut p, window, walls[1], 3000.0, false).unwrap();
        let floor_t = p.types_of(Category::Floors).next().unwrap().id;
        edit::add_floor(&mut p, lvl, floor_t, pts.iter().map(|(x, y)| DVec2::new(*x, *y)).collect()).unwrap();
        let roof_t = p.types_of(Category::Roofs).next().unwrap().id;
        let l2 = p.levels()[1].0;
        edit::add_roof(&mut p, l2, roof_t, pts.iter().map(|(x, y)| DVec2::new(*x, *y)).collect(), RoofShape::Hip, 0.0).unwrap();
        let r = edit::add_room(&mut p, lvl, DVec2::new(4000.0, 3000.0)).unwrap();
        if let Some(Element { kind: ElementKind::Room(room), .. }) = p.element_mut(r) {
            room.name = "Living".into();
        }
        let table = p.families.iter().find(|f| f.name == "Table-Dining").unwrap().types[0].id;
        edit::place_free(&mut p, table, lvl, DVec2::new(3000.0, 3000.0), 90.0).unwrap();
        p
    }

    #[test]
    fn export_import_round_trip() {
        let p = sample();
        let text = export(&p, "test.ifc", "2026-01-01T00:00:00");
        assert!(text.starts_with("ISO-10303-21;"));
        let ents = parse_step(&text).unwrap();
        assert_eq!(ents.values().filter(|e| e.ty == "IFCWALL").count(), 4);
        assert_eq!(ents.values().filter(|e| e.ty == "IFCOPENINGELEMENT").count(), 2);

        let r = import(&text).unwrap();
        assert!(r.warnings.is_empty(), "{:?}", r.warnings);
        let q = r.project;
        let count = |c: Category| q.elements.iter().filter(|e| e.category() == c).count();
        assert_eq!(count(Category::Levels), 2);
        assert_eq!(count(Category::Walls), 4);
        assert_eq!(count(Category::Doors), 1);
        assert_eq!(count(Category::Windows), 1);
        assert_eq!(count(Category::Floors), 1);
        assert_eq!(count(Category::Roofs), 1);
        assert_eq!(count(Category::Rooms), 1);
        assert_eq!(count(Category::Furniture), 1);

        // Geometry and parameters survive.
        let orig_wall = p.walls().next().unwrap().1.clone();
        let wall = q.walls().find(|(_, w)| w.start.distance(orig_wall.start) < 1.0).unwrap().1;
        assert!(wall.end.distance(orig_wall.end) < 1.0);
        assert_eq!(q.sys_type(wall.type_id).unwrap().name, "Exterior - Brick on Block");
        assert!(wall.top_level.is_some());
        let door = q.elements.iter().find(|e| e.category() == Category::Doors).unwrap();
        assert_eq!(door.mark, "D1");
        assert!((door.as_instance().unwrap().offset_along_host - 2000.0).abs() < 1e-6);
        let room = q.elements.iter().find(|e| e.category() == Category::Rooms).unwrap();
        assert_eq!(params::get(&q, room, "Name"), Some(params::Value::Text("Living".into())));
        let area = params::get(&q, room, "Area").unwrap().as_num().unwrap();
        let orig_room = p.elements.iter().find(|e| e.category() == Category::Rooms).unwrap();
        assert!((area - params::get(&p, orig_room, "Area").unwrap().as_num().unwrap()).abs() < 1.0);
        let roof = q.elements.iter().find_map(|e| match &e.kind {
            ElementKind::Roof(r) => Some(r),
            _ => None,
        });
        assert_eq!(roof.unwrap().shape, RoofShape::Hip);
        assert_eq!(q.elements.iter().find(|e| e.category() == Category::Doors).unwrap().uid,
                   p.elements.iter().find(|e| e.category() == Category::Doors).unwrap().uid);
    }

    #[test]
    fn imports_foreign_metre_file_without_axis() {
        let text = "ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\n\
#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n\
#2=IFCCARTESIANPOINT((0.,0.,0.));\n\
#3=IFCAXIS2PLACEMENT3D(#2,$,$);\n\
#4=IFCLOCALPLACEMENT($,#3);\n\
#5=IFCBUILDINGSTOREY('0HqrGZbeL0Rf0gWmBBuF7Y',$,'Ground',$,$,#4,$,$,.ELEMENT.,0.);\n\
#6=IFCCARTESIANPOINT((2.5,0.1));\n\
#7=IFCAXIS2PLACEMENT2D(#6,$);\n\
#8=IFCRECTANGLEPROFILEDEF(.AREA.,$,#7,5.,0.2);\n\
#9=IFCDIRECTION((0.,0.,1.));\n\
#10=IFCEXTRUDEDAREASOLID(#8,#3,#9,2.8);\n\
#11=IFCSHAPEREPRESENTATION($,'Body','SweptSolid',(#10));\n\
#12=IFCPRODUCTDEFINITIONSHAPE($,$,(#11));\n\
#13=IFCWALL('2HqrGZbeL0Rf0gWmBBuF7Y',$,'W',$,$,#4,#12,$,$);\n\
#14=IFCRELCONTAINEDINSPATIALSTRUCTURE('3HqrGZbeL0Rf0gWmBBuF7Y',$,$,$,(#13),#5);\n\
ENDSEC;\nEND-ISO-10303-21;\n";
        let r = import(text).unwrap();
        let (_, w) = r.project.walls().next().expect("wall");
        assert!((w.length() - 5000.0).abs() < 1e-6);
        assert!((analysis::wall_height(&r.project, w) - 2800.0).abs() < 1e-6);
        assert!((analysis::wall_thickness(&r.project, w) - 200.0).abs() < 1e-6);
        assert_eq!(r.project.level_name(w.base_level), "Ground");
    }
}
