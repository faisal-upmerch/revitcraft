//! Constraints re-applied after every transaction: locked and EQ dimensions, dependent
//! annotation (tags lose their host, dimensions keep fallback points), hosted openings.

use crate::annotation;
use crate::edit;
use crate::formula;
use crate::params;
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

    apply_globals(p)?;

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

/// Global parameters: evaluates their formulas, then pushes their values into associated
/// element parameters and labelled dimensions.
fn apply_globals(p: &mut Project) -> Result<(), String> {
    if p.global_params.is_empty() {
        return Ok(());
    }
    for _ in 0..p.global_params.len().max(1) {
        let mut changed = false;
        for k in 0..p.global_params.len() {
            let g = &p.global_params[k];
            if g.formula.trim().is_empty() || g.is_text() {
                continue;
            }
            let vals: std::collections::HashMap<String, f64> = p.global_params.iter().filter(|x| !x.is_text()).map(|x| (x.name.clone(), x.value)).collect();
            let me = g.name.clone();
            let mut resolve = |n: &str| {
                if n == me {
                    return Err(formula::FormulaError(format!("'{me}' cannot refer to itself.")));
                }
                vals.get(n).copied().ok_or_else(|| formula::FormulaError(format!("Unknown global parameter '{n}'.")))
            };
            let v = formula::evaluate(&g.formula, &mut resolve).map_err(|e| format!("Global parameter '{me}': {}", e.0))?;
            if (v - p.global_params[k].value).abs() > 1e-9 {
                p.global_params[k].value = v;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    // Element parameters associated with a global.
    let links: Vec<(Id, String, String)> = p.elements.iter().flat_map(|e| e.global_links.iter().map(move |(k, v)| (e.id, k.clone(), v.clone()))).collect();
    for (id, param, gname) in links {
        let Some(g) = p.global(&gname).cloned() else {
            if let Some(e) = p.element_mut(id) {
                e.global_links.remove(&param);
            }
            continue;
        };
        let Some(e) = p.element(id) else { continue };
        let want = if g.is_text() { params::Value::Text(g.text.clone()) } else { params::Value::Num(g.value) };
        let same = match (params::get(p, e, &param), &want) {
            (Some(params::Value::Num(a)), params::Value::Num(b)) => (a - b).abs() < 1e-6,
            (Some(params::Value::Text(a)), params::Value::Text(b)) => a == *b,
            _ => false,
        };
        if !same {
            params::set_value(p, id, &param, want).map_err(|e| format!("Global parameter '{gname}': {e}"))?;
        }
    }
    // Dimensions labelled with a global drive their geometry. As in Revit, a label applies to
    // a single-segment linear dimension, a radial/diameter dimension or an angular dimension.
    let dims: Vec<(Id, Dimension)> = p
        .elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::Dimension(d) if !d.label.is_empty() => Some((e.id, d.clone())),
            _ => None,
        })
        .collect();
    for (_, d) in dims {
        let Some(g) = p.global(&d.label).filter(|g| !g.is_text()).cloned() else { continue };
        match d.kind {
            DimKind::Radial | DimKind::Diameter => {
                let Some(id) = d.refs.iter().find_map(|r| r.element) else { continue };
                let Some(e) = p.element(id) else { continue };
                let Some(arc) = annotation::element_arc(e).and_then(|(a, m, b)| crate::geom::Arc2::through(a, m, b)) else { continue };
                let want = if d.kind == DimKind::Radial { g.value } else { g.value / 2.0 };
                if want <= 0.0 {
                    return Err(format!("Global parameter '{}' must be greater than zero.", g.name));
                }
                if (want - arc.radius).abs() > 0.01 {
                    if p.element(id).is_some_and(|e| e.pinned) {
                        return Err(format!("The dimension labelled '{}' cannot change: its arc is pinned.", g.name));
                    }
                    edit::scale_elements(p, &[id], arc.center, want / arc.radius)?;
                }
                continue;
            }
            DimKind::Angular => {
                let (Some((a, v, b)), Some(id)) = (annotation::angular_points(p, &d), d.refs.get(2).and_then(|r| r.element)) else { continue };
                let (da, db) = ((a - v).normalize_or_zero(), (b - v).normalize_or_zero());
                let signed = da.angle_to(db).to_degrees();
                let delta = (g.value - signed.abs()) * signed.signum();
                if delta.abs() > 1e-6 {
                    if p.element(id).is_some_and(|e| e.pinned) {
                        return Err(format!("The dimension labelled '{}' cannot change: its line is pinned.", g.name));
                    }
                    edit::rotate_elements(p, &[id], v, delta);
                }
                continue;
            }
            _ if d.refs.len() != 2 => continue,
            _ => {}
        }
        let now = annotation::coordinates(p, &d);
        let have = now[1] - now[0];
        let want = if have < 0.0 { -g.value } else { g.value };
        let delta = want - have;
        if delta.abs() < 0.01 {
            continue;
        }
        if !move_ref(p, &d.refs[1], d.direction * delta) && !move_ref(p, &d.refs[0], -d.direction * delta) {
            return Err(format!("The dimension labelled '{}' cannot change: its references are pinned.", g.name));
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
