//! Constraints re-applied after every transaction: locked and EQ dimensions, dependent
//! annotation (tags lose their host, dimensions keep fallback points), hosted openings.

use crate::annotation;
use crate::edit;
use crate::geom::DVec2;
use crate::model::*;

/// Restores constraints after a change; `before` is the model before the transaction.
pub fn apply(p: &mut Project, before: &Project) -> Result<(), String> {
    // Tags are deleted with their host, as in Revit.
    let live: std::collections::HashSet<Id> = p.elements.iter().map(|e| e.id).collect();
    p.elements.retain(|e| match &e.kind {
        ElementKind::Tag(t) => live.contains(&t.host),
        ElementKind::WallFoundation(f) => live.contains(&f.wall),
        _ => true,
    });
    // Dimension references to deleted elements fall back to their picked points.
    for e in &mut p.elements {
        if let ElementKind::Dimension(d) = &mut e.kind {
            for r in &mut d.refs {
                if r.element.is_some_and(|id| !live.contains(&id)) {
                    r.element = None;
                    r.part = RefPart::Point;
                }
            }
        }
    }

    // Locked and EQ dimensions: move dependent references back into place.
    for _pass in 0..4 {
        let dims: Vec<(Id, Dimension)> = p
            .elements
            .iter()
            .filter_map(|e| match &e.kind {
                ElementKind::Dimension(d) if d.equal || d.locks.iter().any(|l| *l) => Some((e.id, d.clone())),
                _ => None,
            })
            .collect();
        if dims.is_empty() {
            return Ok(());
        }
        let mut changed = false;
        for (id, d) in dims {
            let now = annotation::coordinates(p, &d);
            let prev = match before.element(id).map(|e| &e.kind) {
                Some(ElementKind::Dimension(old)) if old.refs.len() == d.refs.len() => annotation::coordinates(before, old),
                _ => now.clone(),
            };
            let moved: Vec<f64> = now.iter().zip(&prev).map(|(a, b)| a - b).collect();
            // Locked segments keep their previous length.
            for k in 0..d.refs.len().saturating_sub(1) {
                if !d.locks.get(k).copied().unwrap_or(false) {
                    continue;
                }
                let want = prev[k + 1] - prev[k];
                let have = now[k + 1] - now[k];
                if (want - have).abs() < 0.01 {
                    continue;
                }
                let (a_moved, b_moved) = (moved[k].abs() > 0.01, moved[k + 1].abs() > 0.01);
                if a_moved && b_moved {
                    return Err("Constraints are not satisfied: a locked dimension would change.".into());
                }
                // Move whichever side did not move to follow the one that did.
                let (target, delta) = if a_moved { (k + 1, moved[k]) } else { (k, moved[k + 1]) };
                if !move_ref(p, &d.refs[target], d.direction * delta) {
                    return Err("Constraints are not satisfied: a locked reference cannot move.".into());
                }
                changed = true;
            }
            // EQ: redistribute interior references evenly between the ends.
            if d.equal && d.refs.len() >= 3 {
                let now = annotation::coordinates(p, &d);
                let n = now.len() - 1;
                let (a, b) = (now[0], now[n]);
                for k in 1..n {
                    let want = a + (b - a) * k as f64 / n as f64;
                    if (want - now[k]).abs() > 0.01 {
                        if !move_ref(p, &d.refs[k], d.direction * (want - now[k])) {
                            return Err("Constraints are not satisfied: an EQ reference cannot move.".into());
                        }
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            return Ok(());
        }
    }
    Ok(())
}

/// Moves the element behind a reference (or the free point) by `delta`.
fn move_ref(p: &mut Project, r: &DimRef, delta: DVec2) -> bool {
    match r.element {
        Some(id) => {
            if p.element(id).is_some_and(|e| e.pinned) {
                return false;
            }
            edit::move_elements(p, &[id], delta);
            true
        }
        None => true,
    }
}
