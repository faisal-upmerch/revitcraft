//! Resolves family parameter values (with formulas) for a family type or a placed instance.
//!
//! Resolution order: formula → instance value (instance parameters) → type value → default.

use crate::formula::{self, FormulaError};
use crate::model::{Family, FamilyInstance, FamilyParameter, FamilyType, ParamKind, Project};
use crate::units;
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};

/// Reserved name a hosted family's formulas can use to read the host wall thickness.
pub const WALL_THICKNESS: &str = "Wall Thickness";

pub struct Resolver<'a> {
    family: &'a Family,
    ftype: &'a FamilyType,
    instance: Option<&'a FamilyInstance>,
    host_thickness: Option<f64>,
    cache: RefCell<BTreeMap<String, f64>>,
}

impl<'a> Resolver<'a> {
    pub fn for_type(family: &'a Family, ftype: &'a FamilyType) -> Resolver<'a> {
        Resolver { family, ftype, instance: None, host_thickness: None, cache: RefCell::default() }
    }

    pub fn for_instance(p: &'a Project, inst: &'a FamilyInstance) -> Option<Resolver<'a>> {
        let (family, ftype) = p.family_type(inst.type_id)?;
        let host_thickness = inst
            .host
            .and_then(|h| p.wall(h))
            .and_then(|w| p.sys_type(w.type_id))
            .map(|t| t.thickness());
        Some(Resolver { family, ftype, instance: Some(inst), host_thickness, cache: RefCell::default() })
    }

    pub fn family(&self) -> &Family {
        self.family
    }

    /// Numeric value or `fallback` if the parameter is missing or its formula fails.
    pub fn num(&self, name: &str, fallback: f64) -> f64 {
        if self.family.param(name).is_none() && !name.eq_ignore_ascii_case(WALL_THICKNESS) {
            return fallback;
        }
        self.number(name).unwrap_or(fallback)
    }

    pub fn text(&self, name: &str, fallback: &str) -> String {
        match self.family.param(name) {
            None => fallback.to_string(),
            Some(p) if !p.kind.is_numeric() => self.raw(p).to_string(),
            Some(p) => match self.number(&p.name) {
                Ok(v) => units::format(v, p.kind),
                Err(_) => fallback.to_string(),
            },
        }
    }

    pub fn yes_no(&self, name: &str, fallback: bool) -> bool {
        match self.family.param(name) {
            Some(_) => self.number(name).map(|v| v != 0.0).unwrap_or(fallback),
            None => fallback,
        }
    }

    /// The stored (non-formula) value.
    pub fn raw<'s>(&'s self, p: &'s FamilyParameter) -> &'s str {
        if p.instance {
            if let Some(v) = self.instance.and_then(|i| i.values.get(&p.name)) {
                return v;
            }
        }
        self.ftype.values.get(&p.name).map(String::as_str).unwrap_or(&p.default)
    }

    /// Numeric value; errors on formula problems and circular references.
    pub fn number(&self, name: &str) -> Result<f64, FormulaError> {
        self.number_inner(name, &mut BTreeSet::new())
    }

    fn number_inner(&self, name: &str, visiting: &mut BTreeSet<String>) -> Result<f64, FormulaError> {
        if name.eq_ignore_ascii_case(WALL_THICKNESS) {
            return Ok(self.host_thickness.unwrap_or(200.0));
        }
        let key = name.to_ascii_lowercase();
        if let Some(v) = self.cache.borrow().get(&key) {
            return Ok(*v);
        }
        let Some(p) = self.family.param(name) else {
            return Err(FormulaError(format!("Unknown parameter '{name}'.")));
        };
        if !p.kind.is_numeric() {
            return Err(FormulaError(format!("'{}' is not a number.", p.name)));
        }
        let value = if p.formula.trim().is_empty() {
            units::parse_stored(self.raw(p), p.kind)
        } else {
            if !visiting.insert(key.clone()) {
                return Err(FormulaError(format!("Circular reference involving '{}'.", p.name)));
            }
            let mut resolve = |n: &str| self.number_inner(n, visiting);
            let r = formula::evaluate(&p.formula, &mut resolve);
            visiting.remove(&key);
            let v = r?;
            if p.kind == ParamKind::Integer { v.round() } else { v }
        };
        self.cache.borrow_mut().insert(key, value);
        Ok(value)
    }

    /// Formula error message for a parameter, if any.
    pub fn formula_error(&self, p: &FamilyParameter) -> Option<String> {
        if p.formula.trim().is_empty() {
            return None;
        }
        self.cache.borrow_mut().clear();
        self.number(&p.name).err().map(|e| e.0)
    }

    /// Display string of any parameter.
    pub fn display(&self, p: &FamilyParameter) -> String {
        if !p.kind.is_numeric() {
            return self.raw(p).to_string();
        }
        match self.number(&p.name) {
            Ok(v) => units::format(v, p.kind),
            Err(e) => format!("⚠ {e}"),
        }
    }
}

/// Checks a formula before it is stored: syntax, unknown names, cycles, and the
/// Revit rule that type parameters cannot depend on instance parameters.
pub fn validate_formula(family: &Family, param_name: &str, formula: &str) -> Result<(), String> {
    if formula.trim().is_empty() {
        return Ok(());
    }
    let Some(p) = family.param(param_name) else {
        return Err(format!("Unknown parameter '{param_name}'."));
    };
    if !p.kind.is_numeric() {
        return Err("Formulas are only supported for numeric parameters.".into());
    }
    for r in formula::references(formula) {
        if r.eq_ignore_ascii_case(WALL_THICKNESS) {
            if !p.instance {
                return Err(format!("Type parameters cannot use '{WALL_THICKNESS}'."));
            }
            continue;
        }
        let Some(target) = family.param(&r) else {
            return Err(format!("Unknown parameter '{r}'."));
        };
        if !p.instance && target.instance {
            return Err(format!("Type parameter '{}' cannot depend on instance parameter '{}'.", p.name, target.name));
        }
    }
    let mut trial = family.clone();
    if let Some(tp) = trial.params.iter_mut().find(|x| x.name.eq_ignore_ascii_case(param_name)) {
        tp.formula = formula.to_string();
    }
    let ftype = trial.types.first().cloned().unwrap_or(FamilyType { id: 0, name: String::new(), values: BTreeMap::new() });
    let r = Resolver::for_type(&trial, &ftype);
    r.number(param_name).map(|_| ()).map_err(|e| e.0)
}
