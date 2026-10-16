//! Moving content between projects: Insert > Load as Group and Manage > Transfer Project
//! Standards. Types, families and materials are matched by name; missing ones are copied in.

use crate::edit::unique_name;
use crate::model::*;
use std::collections::HashMap;

/// The kinds of standards Transfer Project Standards can copy.
pub const STANDARDS: [&str; 13] = [
    "Ceiling Types",
    "Dimension Types",
    "Floor Types",
    "Line Styles",
    "Materials",
    "Object Styles",
    "Project Parameters",
    "Railing Types",
    "Ramp Types",
    "Roof Types",
    "Stair Types",
    "Text Types",
    "Wall Types",
];

fn category_of_standard(s: &str) -> Option<Category> {
    Some(match s {
        "Ceiling Types" => Category::Ceilings,
        "Floor Types" => Category::Floors,
        "Railing Types" => Category::Railings,
        "Ramp Types" => Category::Ramps,
        "Roof Types" => Category::Roofs,
        "Stair Types" => Category::Stairs,
        "Wall Types" => Category::Walls,
        _ => return None,
    })
}

/// Copies a material from `src` unless `dst` has one of that name.
fn ensure_material(dst: &mut Project, src: &Project, name: &str) {
    if name.is_empty() || dst.materials.iter().any(|m| m.name == name) {
        return;
    }
    if let Some(m) = src.materials.iter().find(|m| m.name == name) {
        dst.materials.push(m.clone());
    }
}

/// The `dst` id of a system type of `src`: the same-named type of its category, or a copy.
fn ensure_type(dst: &mut Project, src: &Project, id: Id, overwrite: bool) -> Option<Id> {
    let t = src.sys_type(id)?.clone();
    for l in &t.layers {
        ensure_material(dst, src, &l.material);
    }
    for v in t.texts.values() {
        ensure_material(dst, src, v);
    }
    // Stacked walls refer to other wall types.
    let stack: Vec<(Id, f64)> = t.stack.iter().filter_map(|(sid, h)| ensure_type(dst, src, *sid, false).map(|n| (n, *h))).collect();
    if let Some(existing) = dst.types.iter_mut().find(|d| d.category == t.category && d.name == t.name) {
        if overwrite {
            let keep = existing.id;
            *existing = SystemType { id: keep, stack, ..t };
        }
        return Some(existing.id);
    }
    let nid = dst.new_id();
    dst.types.push(SystemType { id: nid, stack, ..t });
    Some(nid)
}

/// The `dst` (family, type) ids of a loadable family type of `src`.
fn ensure_family_type(dst: &mut Project, src: &Project, family: Id, ty: Id) -> Option<(Id, Id)> {
    let f = src.family(family)?.clone();
    let tname = f.types.iter().find(|t| t.id == ty)?.name.clone();
    if let Some(df) = dst.families.iter().find(|d| d.name == f.name && d.category == f.category) {
        let fid = df.id;
        if let Some(dt) = df.types.iter().find(|t| t.name == tname) {
            return Some((fid, dt.id));
        }
        // The family is here but not this type: add it.
        let st = f.types.iter().find(|t| t.id == ty)?.clone();
        let nid = dst.new_id();
        let df = dst.families.iter_mut().find(|d| d.id == fid)?;
        df.types.push(FamilyType { id: nid, ..st });
        return Some((fid, nid));
    }
    let mut nf = f.clone();
    nf.id = dst.new_id();
    let mut out = None;
    for t in nf.types.iter_mut() {
        let old = t.id;
        t.id = dst.new_id();
        if old == ty {
            out = Some(t.id);
        }
    }
    let fid = nf.id;
    dst.families.push(nf);
    out.map(|t| (fid, t))
}

/// The `dst` level matching a `src` level: same name, else the nearest elevation.
fn map_level(dst: &Project, src: &Project, id: Id) -> Id {
    let levels = dst.levels();
    let Some(l) = src.level(id) else { return levels.first().map(|l| l.0).unwrap_or(id) };
    if let Some((lid, _)) = levels.iter().find(|(_, d)| d.name == l.name) {
        return *lid;
    }
    levels
        .iter()
        .min_by(|a, b| (a.1.elevation - l.elevation).abs().total_cmp(&(b.1.elevation - l.elevation).abs()))
        .map(|l| l.0)
        .unwrap_or(id)
}

/// Rewrites an element's type, family and level references from `src` into `dst`.
fn remap(dst: &mut Project, src: &Project, e: &mut Element) {
    let lv = |dst: &Project, id: Id| map_level(dst, src, id);
    match &mut e.kind {
        ElementKind::Wall(w) => {
            w.type_id = ensure_type(dst, src, w.type_id, false).unwrap_or(w.type_id);
            w.base_level = lv(dst, w.base_level);
            w.top_level = w.top_level.map(|t| lv(dst, t));
        }
        ElementKind::Floor(f) => {
            f.type_id = ensure_type(dst, src, f.type_id, false).unwrap_or(f.type_id);
            f.level = lv(dst, f.level);
        }
        ElementKind::Roof(r) => {
            r.type_id = ensure_type(dst, src, r.type_id, false).unwrap_or(r.type_id);
            r.level = lv(dst, r.level);
        }
        ElementKind::Ceiling(c) => {
            c.type_id = ensure_type(dst, src, c.type_id, false).unwrap_or(c.type_id);
            c.level = lv(dst, c.level);
        }
        ElementKind::Stair(s) => {
            s.type_id = ensure_type(dst, src, s.type_id, false).unwrap_or(s.type_id);
            s.base_level = lv(dst, s.base_level);
            s.top_level = s.top_level.map(|t| lv(dst, t));
        }
        ElementKind::Ramp(r) => {
            r.type_id = ensure_type(dst, src, r.type_id, false).unwrap_or(r.type_id);
            r.base_level = lv(dst, r.base_level);
            r.top_level = r.top_level.map(|t| lv(dst, t));
        }
        ElementKind::Railing(r) => {
            r.type_id = ensure_type(dst, src, r.type_id, false).unwrap_or(r.type_id);
            r.level = lv(dst, r.level);
        }
        ElementKind::WallFoundation(f) => f.type_id = ensure_type(dst, src, f.type_id, false).unwrap_or(f.type_id),
        ElementKind::Instance(i) => {
            if let Some((fid, tid)) = ensure_family_type(dst, src, i.family_id, i.type_id) {
                i.family_id = fid;
                i.type_id = tid;
            }
            i.level = lv(dst, i.level);
            i.top_level = i.top_level.map(|t| lv(dst, t));
        }
        ElementKind::Room(r) => {
            r.level = lv(dst, r.level);
            r.upper_level = r.upper_level.map(|t| lv(dst, t));
        }
        ElementKind::ModelText(t) => t.level = lv(dst, t.level),
        ElementKind::Shaft(s) => {
            s.base_level = lv(dst, s.base_level);
            s.top_level = s.top_level.map(|t| lv(dst, t));
        }
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => s.level = lv(dst, s.level),
        _ => {}
    }
}

/// Insert > Load as Group: the model elements of `src` (not its levels, grids, views or
/// groups) become a model group type in `dst`, named `name`; its origin is `src`'s origin.
pub fn load_as_group(dst: &mut Project, src: &Project, name: &str) -> Result<Id, String> {
    let picked: Vec<Element> = src
        .elements
        .iter()
        .filter(|e| e.view.is_none() && !matches!(e.kind, ElementKind::Level(_) | ElementKind::Grid(_) | ElementKind::GroupInstance(_) | ElementKind::RefPlane(_)))
        .cloned()
        .collect();
    if picked.is_empty() {
        return Err("The file has no model elements to load.".into());
    }
    let mut members = Vec::new();
    for mut e in picked {
        remap(dst, src, &mut e);
        e.group = None;
        e.phase_created = None;
        e.phase_demolished = None;
        members.push(e);
    }
    let id = dst.new_id();
    let name = unique_name(dst.group_types.iter().map(|g| g.name.clone()), name);
    dst.group_types.push(GroupType { id, name, members, detail: false });
    Ok(id)
}

/// Names of `src` items of a standard that `dst` already has (the "Duplicate Types" list).
pub fn duplicates(dst: &Project, src: &Project, what: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    for w in what {
        match (*w, category_of_standard(w)) {
            (_, Some(c)) => out.extend(src.types.iter().filter(|t| t.category == c && dst.types.iter().any(|d| d.category == c && d.name == t.name)).map(|t| format!("{w}: {}", t.name))),
            ("Materials", _) => out.extend(src.materials.iter().filter(|m| dst.materials.iter().any(|d| d.name == m.name)).map(|m| format!("Materials: {}", m.name))),
            ("Text Types", _) => out.extend(src.text_types.iter().filter(|t| dst.text_types.iter().any(|d| d.name == t.name)).map(|t| format!("Text Types: {}", t.name))),
            ("Dimension Types", _) => out.extend(src.dim_styles.iter().filter(|t| dst.dim_styles.iter().any(|d| d.name == t.name)).map(|t| format!("Dimension Types: {}", t.name))),
            ("Line Styles", _) => out.extend(src.line_styles.iter().filter(|t| dst.line_styles.iter().any(|d| d.name == t.name)).map(|t| format!("Line Styles: {}", t.name))),
            ("Project Parameters", _) => out.extend(src.project_params.iter().filter(|t| dst.project_params.iter().any(|d| d.name == t.name)).map(|t| format!("Project Parameters: {}", t.name))),
            _ => {}
        }
    }
    out
}

/// Manage > Transfer Project Standards: copies the chosen kinds of standards from `src`.
/// Items `dst` already has are replaced when `overwrite` (else kept: "New Only"). Returns how
/// many items were copied or replaced.
pub fn transfer_standards(dst: &mut Project, src: &Project, what: &[&str], overwrite: bool) -> usize {
    let mut n = 0;
    for w in what {
        if let Some(c) = category_of_standard(w) {
            let ids: Vec<Id> = src.types.iter().filter(|t| t.category == c).map(|t| t.id).collect();
            for id in ids {
                let name = src.sys_type(id).map(|t| t.name.clone()).unwrap_or_default();
                let had = dst.types.iter().any(|d| d.category == c && d.name == name);
                if !had || overwrite {
                    ensure_type(dst, src, id, overwrite);
                    n += 1;
                }
            }
            continue;
        }
        match *w {
            "Materials" => {
                for m in &src.materials {
                    match dst.materials.iter_mut().find(|d| d.name == m.name) {
                        Some(d) if overwrite => {
                            *d = m.clone();
                            n += 1;
                        }
                        Some(_) => {}
                        None => {
                            dst.materials.push(m.clone());
                            n += 1;
                        }
                    }
                }
            }
            "Text Types" => n += merge_by_name(&mut dst.text_types, &src.text_types, |t| t.name.clone(), overwrite),
            "Dimension Types" => n += merge_by_name(&mut dst.dim_styles, &src.dim_styles, |t| t.name.clone(), overwrite),
            "Line Styles" => n += merge_by_name(&mut dst.line_styles, &src.line_styles, |t| t.name.clone(), overwrite),
            "Project Parameters" => n += merge_by_name(&mut dst.project_params, &src.project_params, |t| t.name.clone(), overwrite),
            "Object Styles" => {
                for (c, st) in &src.object_styles {
                    if overwrite || !dst.object_styles.contains_key(c) {
                        dst.object_styles.insert(*c, *st);
                        n += 1;
                    }
                }
            }
            _ => {}
        }
    }
    n
}

/// Copies named items, keeping `dst` ids where an item is replaced. Items with an `id` field get
/// new ids through `Clone` only when they are added; text and dimension types keep theirs.
fn merge_by_name<T: Clone>(dst: &mut Vec<T>, src: &[T], name: impl Fn(&T) -> String, overwrite: bool) -> usize {
    let mut n = 0;
    let have: HashMap<String, usize> = dst.iter().enumerate().map(|(k, t)| (name(t), k)).collect();
    for s in src {
        match have.get(&name(s)) {
            Some(k) if overwrite => {
                dst[*k] = s.clone();
                n += 1;
            }
            Some(_) => {}
            None => {
                dst.push(s.clone());
                n += 1;
            }
        }
    }
    n
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::units::UnitSystem;

    #[test]
    fn load_as_group_brings_types_and_transfer_copies_new_only() {
        let mut src = crate::defaults::new_project(UnitSystem::Metric);
        let l1 = src.levels()[0].0;
        let wt = src.types_of(Category::Walls).next().unwrap().id;
        // A wall of a type only the source has.
        let mut special = src.sys_type(wt).unwrap().clone();
        special.id = src.new_id();
        special.name = "Special Wall".into();
        let sid = special.id;
        src.types.push(special);
        crate::edit::add_wall(&mut src, l1, sid, glam::DVec2::ZERO, glam::DVec2::new(4000.0, 0.0), 3000.0).unwrap();
        let mut dst = crate::defaults::new_project(UnitSystem::Metric);
        let walls_before = dst.types_of(Category::Walls).count();
        let g = load_as_group(&mut dst, &src, "House").unwrap();
        let gt = dst.group_types.iter().find(|t| t.id == g).unwrap();
        let ElementKind::Wall(w) = &gt.members.iter().find(|m| matches!(m.kind, ElementKind::Wall(_))).unwrap().kind else { panic!() };
        assert_eq!(dst.sys_type(w.type_id).unwrap().name, "Special Wall");
        assert_eq!(dst.types_of(Category::Walls).count(), walls_before + 1);
        // Transferring wall types again copies nothing new (New Only), all with Overwrite.
        assert_eq!(transfer_standards(&mut dst, &src, &["Wall Types"], false), 0);
        assert!(transfer_standards(&mut dst, &src, &["Wall Types"], true) > 0);
        assert_eq!(dst.types_of(Category::Walls).count(), walls_before + 1);
    }
}
