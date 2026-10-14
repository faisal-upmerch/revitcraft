//! Keynotes: a keynote table (built in, or loaded from a tab-delimited file of
//! `key <tab> text <tab> parent`) and the lookups keynote tags use.

use crate::annotation;
use crate::model::*;

fn k(key: &str, text: &str, parent: &str) -> Keynote {
    Keynote { key: key.into(), text: text.into(), parent: parent.into() }
}

/// The built-in table: divisions with a few common items each.
pub fn builtin() -> Vec<Keynote> {
    vec![
        k("03", "Concrete", ""),
        k("03 30 00", "Cast-in-place concrete", "03"),
        k("03 30 00.A1", "Concrete slab on grade", "03 30 00"),
        k("03 30 00.A2", "Concrete spread footing", "03 30 00"),
        k("03 30 00.A3", "Concrete foundation wall", "03 30 00"),
        k("04", "Masonry", ""),
        k("04 21 13", "Brick masonry", "04"),
        k("04 21 13.A1", "Face brick veneer", "04 21 13"),
        k("04 22 00", "Concrete unit masonry", "04"),
        k("04 22 00.A1", "8\" concrete masonry unit wall", "04 22 00"),
        k("05", "Metals", ""),
        k("05 12 00", "Structural steel framing", "05"),
        k("05 12 00.A1", "Steel column", "05 12 00"),
        k("05 12 00.A2", "Steel beam", "05 12 00"),
        k("05 52 00", "Metal railings", "05"),
        k("06", "Wood, Plastics, and Composites", ""),
        k("06 11 00", "Wood framing", "06"),
        k("06 11 00.A1", "2x4 wood studs at 16\" o.c.", "06 11 00"),
        k("06 11 00.A2", "2x6 wood studs at 16\" o.c.", "06 11 00"),
        k("06 16 00", "Sheathing", "06"),
        k("06 16 00.A1", "Plywood sheathing", "06 16 00"),
        k("07", "Thermal and Moisture Protection", ""),
        k("07 21 00", "Thermal insulation", "07"),
        k("07 21 00.A1", "Batt insulation", "07 21 00"),
        k("07 21 00.A2", "Rigid board insulation", "07 21 00"),
        k("07 27 00", "Air barrier membrane", "07"),
        k("07 31 13", "Asphalt shingles", "07"),
        k("07 54 00", "Thermoplastic membrane roofing", "07"),
        k("07 62 00", "Sheet metal flashing", "07"),
        k("07 92 00", "Joint sealant", "07"),
        k("08", "Openings", ""),
        k("08 11 13", "Hollow metal door and frame", "08"),
        k("08 14 16", "Flush wood door", "08"),
        k("08 51 13", "Aluminum window", "08"),
        k("08 71 00", "Door hardware", "08"),
        k("08 80 00", "Glazing", "08"),
        k("09", "Finishes", ""),
        k("09 21 16", "Gypsum board assembly", "09"),
        k("09 21 16.A1", "5/8\" gypsum board", "09 21 16"),
        k("09 30 00", "Tile", "09"),
        k("09 51 00", "Acoustical ceiling", "09"),
        k("09 65 00", "Resilient flooring", "09"),
        k("09 68 00", "Carpet", "09"),
        k("09 91 00", "Paint", "09"),
        k("10", "Specialties", ""),
        k("10 14 00", "Signage", "10"),
        k("10 28 00", "Toilet accessories", "10"),
        k("12", "Furnishings", ""),
        k("12 32 00", "Wood casework", "12"),
        k("12 36 00", "Countertop", "12"),
        k("31", "Earthwork", ""),
        k("31 23 00", "Excavation and fill", "31"),
        k("32", "Exterior Improvements", ""),
        k("32 12 16", "Asphalt paving", "32"),
        k("32 13 13", "Concrete paving", "32"),
        k("32 93 00", "Plants", "32"),
    ]
}

/// The project's keynote table.
pub fn table(p: &Project) -> Vec<Keynote> {
    if p.keynotes.is_empty() { builtin() } else { p.keynotes.clone() }
}

pub fn text_of(p: &Project, key: &str) -> Option<String> {
    table(p).into_iter().find(|k| k.key == key).map(|k| k.text)
}

/// Reads a keynote file: one `key<TAB>text<TAB>parent` per line (parent optional).
pub fn parse(s: &str) -> Result<Vec<Keynote>, String> {
    let mut out = Vec::new();
    for (n, line) in s.lines().enumerate() {
        let line = line.trim_end_matches('\r');
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let mut cols = line.split('\t');
        let key = cols.next().unwrap_or("").trim();
        let text = cols.next().map(str::trim).ok_or_else(|| format!("Line {}: expected key<TAB>text<TAB>parent.", n + 1))?;
        let parent = cols.next().unwrap_or("").trim();
        if key.is_empty() {
            return Err(format!("Line {}: the key is empty.", n + 1));
        }
        out.push(k(key, text, parent));
    }
    if out.is_empty() {
        return Err("The file has no keynotes.".into());
    }
    Ok(out)
}

/// Keynote of an element's type.
pub fn element_keynote(p: &Project, e: &Element) -> String {
    let Some(t) = p.type_of(e) else { return String::new() };
    match p.sys_type(t) {
        Some(st) => st.texts.get("Keynote").cloned().unwrap_or_default(),
        None => p.family_type(t).and_then(|(_, ft)| ft.values.get("Keynote").cloned()).unwrap_or_default(),
    }
}

/// Keynote of an element's main material.
pub fn material_keynote(p: &Project, e: &Element) -> String {
    let m = annotation::element_material(p, e);
    p.material(&m).map(|m| m.keynote.clone()).unwrap_or_default()
}

/// What a keynote tag shows, following Keynoting Settings.
pub fn display(p: &Project, key: &str) -> String {
    if key.is_empty() {
        return "?".into();
    }
    match p.keynote_display {
        1 => text_of(p, key).unwrap_or_else(|| key.to_string()),
        2 => format!("{key}  {}", text_of(p, key).unwrap_or_default()),
        _ => key.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keynote_file_and_tags() {
        let file = "# test\nA\tGeneral\t\nA.1\tPaint finish\tA\n";
        let t = parse(file).unwrap();
        assert_eq!(t.len(), 2);
        assert_eq!(t[1].parent, "A");
        assert!(parse("no tabs here").is_err());

        let mut p = crate::defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let ty = p.types_of(Category::Walls).next().unwrap().id;
        let wall = crate::edit::add_wall(&mut p, lvl, ty, crate::geom::DVec2::ZERO, crate::geom::DVec2::new(3000.0, 0.0), 3000.0).unwrap();
        crate::params::set(&mut p, wall, "Keynote", "09 21 16").unwrap();
        assert_eq!(element_keynote(&p, p.element(wall).unwrap()), "09 21 16");
        let view = p.views.iter().find(|v| v.plan_level().is_some()).unwrap().id;
        let tag = crate::edit::add_tag(&mut p, view, wall, crate::geom::DVec2::new(1500.0, 500.0), false).unwrap();
        if let Some(ElementKind::Tag(t)) = p.element_mut(tag).map(|e| &mut e.kind) {
            t.parameter = "Keynote".into();
        }
        let ElementKind::Tag(t) = p.element(tag).unwrap().kind.clone() else { panic!() };
        assert_eq!(annotation::tag_text(&p, &t), "09 21 16");
        p.keynote_display = 1;
        assert_eq!(annotation::tag_text(&p, &t), "Gypsum board assembly");
        // Loaded tables replace the built-in one.
        p.keynotes = parse(file).unwrap();
        assert_eq!(text_of(&p, "A.1").as_deref(), Some("Paint finish"));
        assert_eq!(text_of(&p, "09 21 16"), None);
        // The keynote legend lists the keys tags show.
        p.keynotes.clear();
        let lg = crate::edit::new_keynote_legend(&mut p);
        let ViewKind::Schedule(def) = &p.view(lg).unwrap().kind else { panic!() };
        let table = crate::schedule::build(&p, def);
        assert_eq!(table.rows.iter().filter(|r| r.cells.first().map(String::as_str) == Some("09 21 16")).count(), 1);
    }
}
