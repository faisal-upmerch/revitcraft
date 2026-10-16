//! Project files (.rcx, JSON) and family files (.rcfa).

use crate::model::{Family, Project};
use std::path::Path;

pub const EXTENSION: &str = "rcx";
pub const FAMILY_EXTENSION: &str = "rcfa";
pub const FORMAT_VERSION: u32 = 4;

pub fn to_json(p: &Project) -> String {
    serde_json::to_string_pretty(p).expect("project serialises")
}

pub fn from_json(s: &str) -> Result<Project, String> {
    let mut p: Project = serde_json::from_str(s).map_err(|e| format!("Not a valid RevitCraft project: {e}"))?;
    if p.format > FORMAT_VERSION {
        return Err(format!(
            "This project was saved by a newer version of RevitCraft (format {}); this version reads format {FORMAT_VERSION}.",
            p.format
        ));
    }
    migrate(&mut p);
    Ok(p)
}

/// Upgrades older projects in place.
fn migrate(p: &mut Project) {
    if p.format < 2 {
        // Format 1 had no phases, ceiling plans or annotation styles.
        if p.phases.is_empty() {
            let id = p.new_id();
            p.phases.push(crate::model::Phase { id, name: "New Construction".into() });
        }
        if p.dim_styles.is_empty() {
            let id = p.new_id();
            p.dim_styles.push(crate::model::DimensionStyle { id, name: "Linear - 2.5mm Arial".into(), text_size: 2.5, tick: true, gap: 1.5 });
        }
        if p.area_schemes.is_empty() {
            let id = p.new_id();
            p.area_schemes.push(crate::model::AreaScheme { id, name: "Gross Building".into() });
        }
        p.format = 2;
    }
    if p.format < 3 {
        // Format 2 used "Solid fill" on materials to mean no cut pattern.
        for m in &mut p.materials {
            if m.cut_pattern == crate::model::FillPattern::Solid {
                m.cut_pattern = crate::model::FillPattern::None;
            }
        }
        p.format = 3;
    }
    if p.format < 4 {
        // Format 3 sections looked to the right of their line; they now look to the left.
        // Swapping the ends keeps each saved section looking the same way.
        for v in &mut p.views {
            if let crate::model::ViewKind::Section { start, end, .. } = &mut v.kind {
                std::mem::swap(start, end);
            }
        }
        p.format = 4;
    }
}

pub fn save(p: &Project, path: &Path) -> Result<(), String> {
    // Write to a temporary file first so a failed save never destroys the previous file.
    let tmp = path.with_extension("rcx.tmp");
    std::fs::write(&tmp, to_json(p)).map_err(|e| format!("Could not write {}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("Could not save {}: {e}", path.display()))
}

pub fn load(path: &Path) -> Result<Project, String> {
    let s = std::fs::read_to_string(path).map_err(|e| format!("Could not read {}: {e}", path.display()))?;
    let mut p = from_json(&s)?;
    // Linked models come from their files (a missing file leaves the link unloaded).
    for l in p.links.iter_mut() {
        l.data = load_link(Path::new(&l.path)).ok();
    }
    Ok(p)
}

/// Reads a linked project file (its own links are not followed).
pub fn load_link(path: &Path) -> Result<std::sync::Arc<Project>, String> {
    let s = std::fs::read_to_string(path).map_err(|e| format!("Could not read {}: {e}", path.display()))?;
    from_json(&s).map(std::sync::Arc::new)
}

/// Family files carry the family and the materials it references.
#[derive(serde::Serialize, serde::Deserialize)]
pub struct FamilyFile {
    pub format: u32,
    pub family: Family,
    pub materials: Vec<crate::model::Material>,
}

pub fn save_family(p: &Project, family: &Family, path: &Path) -> Result<(), String> {
    let used: std::collections::BTreeSet<String> = family
        .types
        .iter()
        .flat_map(|t| t.values.values().cloned())
        .chain(family.params.iter().map(|p| p.default.clone()))
        .collect();
    let materials = p.materials.iter().filter(|m| used.contains(&m.name)).cloned().collect();
    let f = FamilyFile { format: FORMAT_VERSION, family: family.clone(), materials };
    let json = serde_json::to_string_pretty(&f).map_err(|e| e.to_string())?;
    std::fs::write(path, json).map_err(|e| format!("Could not write {}: {e}", path.display()))
}

pub fn load_family(path: &Path) -> Result<FamilyFile, String> {
    let s = std::fs::read_to_string(path).map_err(|e| format!("Could not read {}: {e}", path.display()))?;
    serde_json::from_str(&s).map_err(|e| format!("Not a valid RevitCraft family: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{defaults, edit, geom::DVec2, model::*, units::UnitSystem};

    #[test]
    fn round_trip_preserves_model() {
        let mut p = defaults::new_project(UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let wt = p.types_of(Category::Walls).next().unwrap().id;
        edit::add_wall(&mut p, lvl, wt, DVec2::ZERO, DVec2::new(5000.0, 0.0), 3000.0).unwrap();
        let json = to_json(&p);
        let q = from_json(&json).unwrap();
        assert_eq!(q.elements.len(), p.elements.len());
        assert_eq!(q.next_id, p.next_id);
        assert_eq!(to_json(&q), json);
    }

    #[test]
    fn rejects_garbage_and_future_versions() {
        assert!(from_json("{ nope").is_err());
        let mut p = defaults::new_project(UnitSystem::Metric);
        p.format = 99;
        assert!(from_json(&to_json(&p)).unwrap_err().contains("newer version"));
    }
}
