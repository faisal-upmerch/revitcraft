//! The built-in family library: parameters per template and the default type catalogue.

use crate::model::*;
use crate::units::UnitSystem;

fn param(name: &str, kind: ParamKind, group: &str, default: &str) -> FamilyParameter {
    FamilyParameter { name: name.into(), kind, instance: false, formula: String::new(), group: group.into(), built_in: true, default: default.into(), reporting: false }
}

fn formula(name: &str, group: &str, f: &str) -> FamilyParameter {
    FamilyParameter { formula: f.into(), ..param(name, ParamKind::Length, group, "0") }
}

fn inst(mut p: FamilyParameter) -> FamilyParameter {
    p.instance = true;
    p
}

const DIM: &str = "Dimensions";
const MAT: &str = "Materials and Finishes";
const CON: &str = "Construction";
const IDENT: &str = "Identity Data";
const CONS: &str = "Constraints";
const STRUCT: &str = "Structural";

/// Parameters a template's geometry needs, with sensible metric defaults.
pub fn template_params(t: FamilyTemplate) -> Vec<FamilyParameter> {
    use FamilyTemplate::*;
    use ParamKind::*;
    let mut v = match t {
        SingleDoor | DoubleDoor | GlazedDoor | SlidingDoor | BifoldDoor | GarageDoor => {
            let width = match t {
                DoubleDoor => "1800",
                SlidingDoor => "1800",
                BifoldDoor => "1600",
                GarageDoor => "2400",
                _ => "900",
            };
            let mut v = vec![
                param("Width", Length, DIM, width),
                param("Height", Length, DIM, if t == GarageDoor { "2100" } else { "2100" }),
                param("Frame Width", Length, DIM, "50"),
                param("Panel Thickness", Length, DIM, "40"),
                formula("Rough Width", DIM, "Width + 2 * Frame Width"),
                formula("Rough Height", DIM, "Height + Frame Width"),
                param("Frame Material", Material, MAT, "Wood"),
                param("Panel Material", Material, MAT, if t == GarageDoor { "Aluminum" } else { "Wood - Painted White" }),
                param("Fire Rating", Text, IDENT, ""),
            ];
            if matches!(t, GlazedDoor | SlidingDoor) {
                v.push(param("Glass Material", Material, MAT, "Glass"));
            }
            if t == GarageDoor {
                v.push(param("Sections", Integer, CON, "5"));
            }
            if t == BifoldDoor {
                v.push(param("Leaves", Integer, CON, "4"));
            }
            v
        }
        FixedWindow | CasementWindow | AwningWindow | DoubleHungWindow | SlidingWindow | RoundWindow => {
            let mut v = vec![
                param("Width", Length, DIM, "1200"),
                param("Height", Length, DIM, "1200"),
                param("Default Sill Height", Length, CONS, "900"),
                param("Frame Width", Length, DIM, "60"),
                param("Frame Depth", Length, DIM, "100"),
                formula("Rough Width", DIM, "Width"),
                formula("Rough Height", DIM, "Height"),
                param("Frame Material", Material, MAT, "Aluminum"),
                param("Glass Material", Material, MAT, "Glass"),
            ];
            match t {
                FixedWindow | CasementWindow => {
                    v.push(param("Panels", Integer, CON, if t == CasementWindow { "2" } else { "1" }));
                    v.push(param("Transoms", Integer, CON, "0"));
                    v.push(formula("Mullion Width", DIM, "Frame Width"));
                    if t == CasementWindow {
                        v.push(param("Sash Width", Length, DIM, "45"));
                    }
                }
                AwningWindow | DoubleHungWindow | SlidingWindow => v.push(param("Sash Width", Length, DIM, "45")),
                RoundWindow => {
                    v.retain(|p| p.name != "Width" && p.name != "Height");
                    v.insert(0, param("Diameter", Length, DIM, "900"));
                    v.insert(1, formula("Width", DIM, "Diameter"));
                    v.insert(2, formula("Height", DIM, "Diameter"));
                }
                _ => {}
            }
            v
        }
        Tree => vec![
            param("Width", Length, DIM, "4000"),
            param("Depth", Length, DIM, "4000"),
            param("Height", Length, DIM, "6000"),
            param("Trunk Diameter", Length, DIM, "300"),
            param("Canopy Material", Material, MAT, "Foliage"),
            param("Trunk Material", Material, MAT, "Wood"),
        ],
        ParkingSpace => vec![
            param("Width", Length, DIM, "2500"),
            param("Depth", Length, DIM, "5000"),
            param("Line Width", Length, DIM, "100"),
            param("Paint Material", Material, MAT, "Paint - White"),
        ],
        Bench => vec![
            param("Width", Length, DIM, "1800"),
            param("Depth", Length, DIM, "600"),
            param("Seat Height", Length, DIM, "450"),
            param("Material", Material, MAT, "Wood"),
        ],
        Table => vec![
            param("Width", Length, DIM, "1600"),
            param("Depth", Length, DIM, "800"),
            param("Height", Length, DIM, "750"),
            param("Top Thickness", Length, DIM, "40"),
            param("Leg Size", Length, DIM, "60"),
            param("Top Material", Material, MAT, "Wood"),
            param("Leg Material", Material, MAT, "Steel"),
        ],
        Chair => vec![
            param("Width", Length, DIM, "450"),
            param("Depth", Length, DIM, "500"),
            param("Seat Height", Length, DIM, "450"),
            param("Height", Length, DIM, "850"),
            param("Material", Material, MAT, "Wood"),
        ],
        Sofa => vec![
            param("Width", Length, DIM, "2000"),
            param("Depth", Length, DIM, "900"),
            param("Height", Length, DIM, "800"),
            param("Seat Height", Length, DIM, "420"),
            param("Arm Width", Length, DIM, "200"),
            param("Material", Material, MAT, "Fabric"),
        ],
        Bed => vec![
            param("Width", Length, DIM, "1600"),
            param("Depth", Length, DIM, "2000"),
            param("Height", Length, DIM, "500"),
            param("Headboard Height", Length, DIM, "1000"),
            param("Frame Material", Material, MAT, "Wood"),
            param("Mattress Material", Material, MAT, "Fabric"),
        ],
        Desk => vec![
            param("Width", Length, DIM, "1400"),
            param("Depth", Length, DIM, "700"),
            param("Height", Length, DIM, "740"),
            param("Drawer Width", Length, DIM, "400"),
            param("Material", Material, MAT, "Wood"),
        ],
        Wardrobe => vec![
            param("Width", Length, DIM, "1200"),
            param("Depth", Length, DIM, "600"),
            param("Height", Length, DIM, "2100"),
            param("Doors", Integer, CON, "2"),
            param("Material", Material, MAT, "Wood - Painted White"),
        ],
        KitchenCabinet => vec![
            param("Width", Length, DIM, "600"),
            param("Depth", Length, DIM, "600"),
            param("Height", Length, DIM, "900"),
            param("Countertop Thickness", Length, DIM, "40"),
            param("Plinth Height", Length, DIM, "100"),
            param("Cabinet Material", Material, MAT, "Wood - Painted White"),
            param("Countertop Material", Material, MAT, "Stone"),
        ],
        Toilet => vec![
            param("Width", Length, DIM, "380"),
            param("Depth", Length, DIM, "700"),
            param("Height", Length, DIM, "400"),
            param("Material", Material, MAT, "Porcelain"),
        ],
        Sink => vec![
            param("Width", Length, DIM, "600"),
            param("Depth", Length, DIM, "450"),
            param("Height", Length, DIM, "850"),
            param("Material", Material, MAT, "Porcelain"),
        ],
        Bathtub => vec![
            param("Width", Length, DIM, "1700"),
            param("Depth", Length, DIM, "750"),
            param("Height", Length, DIM, "550"),
            param("Material", Material, MAT, "Porcelain"),
        ],
        Shower => vec![
            param("Width", Length, DIM, "900"),
            param("Depth", Length, DIM, "900"),
            param("Height", Length, DIM, "60"),
            param("Screen Height", Length, DIM, "1900"),
            param("Material", Material, MAT, "Porcelain"),
            param("Glass Material", Material, MAT, "Glass"),
        ],
        Refrigerator => vec![
            param("Width", Length, DIM, "700"),
            param("Depth", Length, DIM, "700"),
            param("Height", Length, DIM, "1800"),
            param("Material", Material, MAT, "Steel - Stainless"),
        ],
        RectColumn => vec![
            param("Width", Length, DIM, "400"),
            param("Depth", Length, DIM, "400"),
            param("Height", Length, DIM, "3000"),
            param("Material", Material, MAT, "Concrete"),
        ],
        RoundColumn => vec![
            param("Diameter", Length, DIM, "400"),
            formula("Width", DIM, "Diameter"),
            formula("Depth", DIM, "Diameter"),
            param("Height", Length, DIM, "3000"),
            param("Material", Material, MAT, "Concrete"),
        ],
        SteelColumn => vec![
            param("Section Depth", Length, STRUCT, "300"),
            param("Flange Width", Length, STRUCT, "300"),
            param("Web Thickness", Length, STRUCT, "11"),
            param("Flange Thickness", Length, STRUCT, "19"),
            formula("Width", DIM, "Flange Width"),
            formula("Depth", DIM, "Section Depth"),
            param("Height", Length, DIM, "3000"),
            param("Material", Material, MAT, "Steel"),
        ],
        RectBeam => vec![
            param("Width", Length, STRUCT, "300"),
            param("Section Depth", Length, STRUCT, "600"),
            param("Material", Material, MAT, "Concrete"),
        ],
        SteelBeam => vec![
            param("Section Depth", Length, STRUCT, "450"),
            param("Flange Width", Length, STRUCT, "190"),
            param("Web Thickness", Length, STRUCT, "9"),
            param("Flange Thickness", Length, STRUCT, "15"),
            formula("Width", STRUCT, "Flange Width"),
            param("Material", Material, MAT, "Steel"),
        ],
        Footing => vec![
            param("Width", Length, DIM, "1500"),
            param("Depth", Length, DIM, "1500"),
            param("Thickness", Length, DIM, "500"),
            param("Material", Material, MAT, "Concrete"),
        ],
        Box | Custom => vec![
            param("Width", Length, DIM, "1000"),
            param("Depth", Length, DIM, "1000"),
            param("Height", Length, DIM, "1000"),
            param("Material", Material, MAT, "Default"),
        ],
    };
    if matches!(t, RectColumn | RoundColumn | SteelColumn) {
        // Columns span between levels; the height is used when unconnected.
        let _ = inst; // instance parameters are set on the element (top level, offsets)
    }
    v.push(param("Type Mark", Text, IDENT, ""));
    v.push(param("Description", Text, IDENT, ""));
    v.push(param("Manufacturer", Text, IDENT, ""));
    v.push(param("Model", Text, IDENT, ""));
    v.push(param("Cost", Currency, IDENT, "0"));
    v
}

pub type Catalog = Vec<(&'static str, FamilyTemplate, Vec<(String, Vec<(&'static str, String)>)>)>;

fn mm(v: f64) -> String {
    crate::units::to_stored(v)
}

fn inch(v: f64) -> String {
    crate::units::to_stored(v * 25.4)
}

/// The default family catalogue: (family name, template, types).
pub fn catalog(units: UnitSystem) -> Catalog {
    use FamilyTemplate::*;
    let imp = units == UnitSystem::Imperial;
    // Helper: a type named "W x H" from sizes in mm (metric) or inches (imperial).
    let wh = |w: f64, h: f64, extra: Vec<(&'static str, String)>| -> (String, Vec<(&'static str, String)>) {
        let (name, wv, hv) = if imp {
            (format!("{}\" x {}\"", w, h), inch(w), inch(h))
        } else {
            (format!("{} x {}", w, h), mm(w), mm(h))
        };
        let mut v = vec![("Width", wv), ("Height", hv)];
        v.extend(extra);
        (name, v)
    };
    let cost = |c: f64| ("Cost", crate::units::to_stored(c));
    let sill = |v: f64| ("Default Sill Height", if imp { inch(v) } else { mm(v) });
    let (d_s, d_l) = if imp { ((30.0, 80.0), (36.0, 84.0)) } else { ((800.0, 2100.0), (900.0, 2100.0)) };
    vec![
        ("Single-Flush", SingleDoor, vec![wh(d_s.0, d_s.1, vec![cost(420.0)]), wh(d_l.0, d_l.1, vec![cost(450.0)]), wh(if imp { 40.0 } else { 1000.0 }, d_l.1, vec![cost(480.0)])]),
        ("Single-Glass", GlazedDoor, vec![wh(d_l.0, d_l.1, vec![cost(690.0)])]),
        ("Double-Flush", DoubleDoor, vec![wh(if imp { 60.0 } else { 1600.0 }, d_l.1, vec![cost(820.0)]), wh(if imp { 72.0 } else { 1800.0 }, d_l.1, vec![cost(880.0)])]),
        ("Sliding-2 Panel", SlidingDoor, vec![wh(if imp { 72.0 } else { 1800.0 }, d_l.1, vec![cost(1200.0)]), wh(if imp { 96.0 } else { 2400.0 }, d_l.1, vec![cost(1450.0)])]),
        ("Bifold-4 Panel", BifoldDoor, vec![wh(if imp { 48.0 } else { 1200.0 }, d_l.1, vec![cost(520.0)]), wh(if imp { 72.0 } else { 1800.0 }, d_l.1, vec![cost(640.0)])]),
        ("Overhead-Sectional", GarageDoor, vec![wh(if imp { 96.0 } else { 2400.0 }, if imp { 84.0 } else { 2100.0 }, vec![cost(1900.0)]), wh(if imp { 192.0 } else { 4800.0 }, if imp { 84.0 } else { 2100.0 }, vec![cost(3100.0)])]),
        ("Fixed", FixedWindow, vec![
            wh(if imp { 24.0 } else { 600.0 }, if imp { 48.0 } else { 1200.0 }, vec![cost(300.0)]),
            wh(if imp { 48.0 } else { 1200.0 }, if imp { 48.0 } else { 1200.0 }, vec![cost(420.0)]),
            wh(if imp { 72.0 } else { 1800.0 }, if imp { 60.0 } else { 1500.0 }, vec![sill(if imp { 30.0 } else { 750.0 }), ("Panels", "3".into()), cost(610.0)]),
        ]),
        ("Casement 2 Lite", CasementWindow, vec![
            wh(if imp { 48.0 } else { 1200.0 }, if imp { 48.0 } else { 1200.0 }, vec![cost(520.0)]),
            wh(if imp { 60.0 } else { 1500.0 }, if imp { 60.0 } else { 1500.0 }, vec![sill(if imp { 30.0 } else { 750.0 }), cost(640.0)]),
        ]),
        ("Awning", AwningWindow, vec![wh(if imp { 36.0 } else { 900.0 }, if imp { 24.0 } else { 600.0 }, vec![sill(if imp { 48.0 } else { 1200.0 }), cost(380.0)])]),
        ("Double Hung", DoubleHungWindow, vec![wh(if imp { 36.0 } else { 900.0 }, if imp { 60.0 } else { 1500.0 }, vec![sill(if imp { 30.0 } else { 750.0 }), cost(560.0)])]),
        ("Sliding", SlidingWindow, vec![wh(if imp { 60.0 } else { 1500.0 }, if imp { 36.0 } else { 900.0 }, vec![sill(if imp { 42.0 } else { 1050.0 }), cost(470.0)])]),
        ("Round", RoundWindow, vec![(if imp { "36\" Diameter".into() } else { "900 Diameter".into() }, vec![("Diameter", if imp { inch(36.0) } else { mm(900.0) }), sill(if imp { 48.0 } else { 1200.0 }), cost(450.0)])]),
        ("Tree - Deciduous", Tree, vec![
            (if imp { "13' Canopy".into() } else { "4m Canopy".into() }, vec![("Width", if imp { inch(156.0) } else { mm(4000.0) }), ("Depth", if imp { inch(156.0) } else { mm(4000.0) }), ("Height", if imp { inch(240.0) } else { mm(6000.0) })]),
            (if imp { "20' Canopy".into() } else { "6m Canopy".into() }, vec![("Width", if imp { inch(240.0) } else { mm(6000.0) }), ("Depth", if imp { inch(240.0) } else { mm(6000.0) }), ("Height", if imp { inch(360.0) } else { mm(9000.0) })]),
        ]),
        ("Parking Space", ParkingSpace, vec![
            (if imp { "9' x 18'".into() } else { "2500 x 5000".into() }, vec![("Width", if imp { inch(108.0) } else { mm(2500.0) }), ("Depth", if imp { inch(216.0) } else { mm(5000.0) })]),
        ]),
        ("Bench", Bench, vec![(if imp { "6'".into() } else { "1800".into() }, vec![("Width", if imp { inch(72.0) } else { mm(1800.0) })])]),
        ("Table-Dining", Table, vec![("1600 x 800".into(), vec![("Width", mm(1600.0)), ("Depth", mm(800.0))]), ("2000 x 1000".into(), vec![("Width", mm(2000.0)), ("Depth", mm(1000.0))])]),
        ("Chair-Dining", Chair, vec![("Standard".into(), vec![])]),
        ("Sofa", Sofa, vec![("2000 x 900".into(), vec![]), ("2400 x 950".into(), vec![("Width", mm(2400.0)), ("Depth", mm(950.0))])]),
        ("Bed-Double", Bed, vec![("1600 x 2000".into(), vec![]), ("1400 x 2000".into(), vec![("Width", mm(1400.0))]), ("1800 x 2000".into(), vec![("Width", mm(1800.0))])]),
        ("Desk", Desk, vec![("1400 x 700".into(), vec![])]),
        ("Wardrobe", Wardrobe, vec![("1200 Wide".into(), vec![]), ("1800 Wide".into(), vec![("Width", mm(1800.0)), ("Doors", "3".into())])]),
        ("Base Cabinet", KitchenCabinet, vec![("600 Wide".into(), vec![]), ("900 Wide".into(), vec![("Width", mm(900.0))]), ("1200 Wide".into(), vec![("Width", mm(1200.0))])]),
        ("Toilet-Domestic", Toilet, vec![("Standard".into(), vec![])]),
        ("Sink-Vanity", Sink, vec![("600 Wide".into(), vec![])]),
        ("Bathtub", Bathtub, vec![("1700 x 750".into(), vec![])]),
        ("Shower", Shower, vec![("900 x 900".into(), vec![]), ("1200 x 900".into(), vec![("Width", mm(1200.0))])]),
        ("Refrigerator", Refrigerator, vec![("700 Wide".into(), vec![])]),
        ("Concrete-Rectangular-Column", RectColumn, vec![("400 x 400".into(), vec![]), ("300 x 600".into(), vec![("Width", mm(300.0)), ("Depth", mm(600.0))])]),
        ("Concrete-Round-Column", RoundColumn, vec![("400 Diameter".into(), vec![]), ("600 Diameter".into(), vec![("Diameter", mm(600.0))])]),
        ("Steel-I-Column", SteelColumn, vec![("HE300B".into(), vec![]), ("HE200B".into(), vec![("Section Depth", mm(200.0)), ("Flange Width", mm(200.0)), ("Web Thickness", mm(9.0)), ("Flange Thickness", mm(15.0))])]),
        ("Concrete-Rectangular-Beam", RectBeam, vec![("300 x 600".into(), vec![]), ("400 x 800".into(), vec![("Width", mm(400.0)), ("Section Depth", mm(800.0))])]),
        ("Steel-I-Beam", SteelBeam, vec![("IPE450".into(), vec![]), ("IPE300".into(), vec![("Section Depth", mm(300.0)), ("Flange Width", mm(150.0)), ("Web Thickness", mm(7.1)), ("Flange Thickness", mm(10.7))])]),
        ("Footing-Rectangular", Footing, vec![("1500 x 1500 x 500".into(), vec![]), ("2000 x 2000 x 600".into(), vec![("Width", mm(2000.0)), ("Depth", mm(2000.0)), ("Thickness", mm(600.0))])]),
        ("Generic Box", Box, vec![("1000 x 1000 x 1000".into(), vec![])]),
    ]
}

/// The wider family library (Insert > Load Autodesk Family): families beyond the template's,
/// loaded on demand.
pub fn library_catalog(units: UnitSystem) -> Catalog {
    use FamilyTemplate::*;
    let imp = units == UnitSystem::Imperial;
    let len = |m: f64, i: f64| if imp { inch(i) } else { mm(m) };
    let name = |m: &str, i: &str| -> String { if imp { i.to_string() } else { m.to_string() } };
    let wh = |m: (f64, f64), i: (f64, f64)| -> (String, Vec<(&'static str, String)>) {
        (
            name(
                &format!("{} x {}", m.0, m.1),
                &format!("{}\" x {}\"", i.0, i.1),
            ),
            vec![("Width", len(m.0, i.0)), ("Height", len(m.1, i.1))],
        )
    };
    let wd = |m: (f64, f64), i: (f64, f64)| -> (String, Vec<(&'static str, String)>) {
        (
            name(
                &format!("{} x {}", m.0, m.1),
                &format!("{}\" x {}\"", i.0, i.1),
            ),
            vec![("Width", len(m.0, i.0)), ("Depth", len(m.1, i.1))],
        )
    };
    vec![
        (
            "Single-Flush Vision",
            GlazedDoor,
            vec![
                wh((900.0, 2100.0), (36.0, 84.0)),
                wh((1000.0, 2100.0), (40.0, 84.0)),
            ],
        ),
        (
            "Single-Panel 4",
            SingleDoor,
            vec![
                wh((820.0, 2040.0), (32.0, 80.0)),
                wh((920.0, 2040.0), (36.0, 80.0)),
            ],
        ),
        (
            "Double-Glass 2",
            DoubleDoor,
            vec![
                wh((1500.0, 2100.0), (60.0, 84.0)),
                wh((1800.0, 2400.0), (72.0, 96.0)),
            ],
        ),
        (
            "Sliding-4 Panel",
            SlidingDoor,
            vec![
                wh((3000.0, 2100.0), (120.0, 84.0)),
                wh((3600.0, 2400.0), (144.0, 96.0)),
            ],
        ),
        (
            "Bifold-2 Panel",
            BifoldDoor,
            vec![wh((800.0, 2100.0), (30.0, 84.0))],
        ),
        (
            "Overhead-Rolling",
            GarageDoor,
            vec![
                wh((3000.0, 3000.0), (120.0, 120.0)),
                wh((4000.0, 4200.0), (160.0, 168.0)),
            ],
        ),
        (
            "Fixed - Clerestory",
            FixedWindow,
            vec![
                wh((1800.0, 450.0), (72.0, 18.0)),
                wh((2400.0, 600.0), (96.0, 24.0)),
            ],
        ),
        (
            "Casement 3x3",
            CasementWindow,
            vec![wh((1800.0, 1500.0), (72.0, 60.0))],
        ),
        (
            "Awning - Hopper",
            AwningWindow,
            vec![
                wh((600.0, 450.0), (24.0, 18.0)),
                wh((1200.0, 600.0), (48.0, 24.0)),
            ],
        ),
        (
            "Double Hung - Tall",
            DoubleHungWindow,
            vec![wh((900.0, 2100.0), (36.0, 84.0))],
        ),
        (
            "Sliding - Horizontal 3 Lite",
            SlidingWindow,
            vec![wh((2400.0, 1200.0), (96.0, 48.0))],
        ),
        (
            "Round - Porthole",
            RoundWindow,
            vec![(
                name("600 Diameter", "24\" Diameter"),
                vec![("Diameter", len(600.0, 24.0))],
            )],
        ),
        (
            "Table-Coffee",
            Table,
            vec![wd((1200.0, 600.0), (48.0, 24.0))],
        ),
        (
            "Table-Conference",
            Table,
            vec![
                wd((3600.0, 1200.0), (144.0, 48.0)),
                wd((4800.0, 1400.0), (192.0, 56.0)),
            ],
        ),
        ("Chair-Office", Chair, vec![("Standard".into(), vec![])]),
        (
            "Sofa-Corner",
            Sofa,
            vec![wd((2800.0, 1000.0), (110.0, 40.0))],
        ),
        (
            "Bed-Single",
            Bed,
            vec![(
                name("900 x 2000", "39\" x 75\""),
                vec![("Width", len(900.0, 39.0))],
            )],
        ),
        (
            "Desk-Workstation",
            Desk,
            vec![
                wd((1600.0, 800.0), (63.0, 31.0)),
                wd((1800.0, 800.0), (71.0, 31.0)),
            ],
        ),
        (
            "Wall Cabinet",
            KitchenCabinet,
            vec![
                (
                    name("600 Wide", "24\" Wide"),
                    vec![("Width", len(600.0, 24.0))],
                ),
                (
                    name("900 Wide", "36\" Wide"),
                    vec![("Width", len(900.0, 36.0))],
                ),
            ],
        ),
        (
            "Toilet-Commercial",
            Toilet,
            vec![("Wall Hung".into(), vec![])],
        ),
        (
            "Sink-Kitchen Double",
            Sink,
            vec![(
                name("900 Wide", "36\" Wide"),
                vec![("Width", len(900.0, 36.0))],
            )],
        ),
        (
            "Shower-Walk In",
            Shower,
            vec![wd((1400.0, 900.0), (56.0, 36.0))],
        ),
        (
            "Tree - Conifer",
            Tree,
            vec![(
                name("3m Canopy", "10' Canopy"),
                vec![
                    ("Width", len(3000.0, 120.0)),
                    ("Depth", len(3000.0, 120.0)),
                    ("Height", len(8000.0, 312.0)),
                ],
            )],
        ),
        (
            "Parking Space - Accessible",
            ParkingSpace,
            vec![wd((3600.0, 5000.0), (144.0, 216.0))],
        ),
        (
            "Concrete-Square-Column",
            RectColumn,
            vec![
                (
                    name("500 x 500", "20\" x 20\""),
                    vec![("Width", len(500.0, 20.0)), ("Depth", len(500.0, 20.0))],
                ),
                (
                    name("600 x 600", "24\" x 24\""),
                    vec![("Width", len(600.0, 24.0)), ("Depth", len(600.0, 24.0))],
                ),
            ],
        ),
        (
            "Steel-UC-Column",
            SteelColumn,
            vec![(
                "254x254x73".into(),
                vec![
                    ("Section Depth", mm(254.1)),
                    ("Flange Width", mm(254.6)),
                    ("Web Thickness", mm(8.6)),
                    ("Flange Thickness", mm(14.2)),
                ],
            )],
        ),
        (
            "Steel-UB-Beam",
            SteelBeam,
            vec![
                (
                    "406x178x60".into(),
                    vec![
                        ("Section Depth", mm(406.4)),
                        ("Flange Width", mm(177.9)),
                        ("Web Thickness", mm(7.9)),
                        ("Flange Thickness", mm(12.8)),
                    ],
                ),
                (
                    "305x165x40".into(),
                    vec![
                        ("Section Depth", mm(303.4)),
                        ("Flange Width", mm(165.0)),
                        ("Web Thickness", mm(6.0)),
                        ("Flange Thickness", mm(10.2)),
                    ],
                ),
            ],
        ),
        (
            "Precast-Rectangular-Beam",
            RectBeam,
            vec![(
                name("250 x 500", "10\" x 20\""),
                vec![
                    ("Width", len(250.0, 10.0)),
                    ("Section Depth", len(500.0, 20.0)),
                ],
            )],
        ),
        (
            "Footing-Pile Cap",
            Footing,
            vec![(
                name("1200 x 1200 x 900", "48\" x 48\" x 36\""),
                vec![
                    ("Width", len(1200.0, 48.0)),
                    ("Depth", len(1200.0, 48.0)),
                    ("Thickness", len(900.0, 36.0)),
                ],
            )],
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_families_are_new_and_load() {
        for units in [UnitSystem::Metric, UnitSystem::Imperial] {
            let mut p = crate::defaults::new_project(units);
            let n = p.families.len();
            for (name, template, types) in library_catalog(units) {
                assert!(
                    p.families.iter().all(|f| f.name != name),
                    "{name} is already in the template"
                );
                crate::defaults::add_catalog_family(&mut p, name, template, types);
            }
            assert_eq!(p.families.len(), n + library_catalog(units).len());
            assert!(p.families.iter().all(|f| !f.types.is_empty()));
        }
    }
}
