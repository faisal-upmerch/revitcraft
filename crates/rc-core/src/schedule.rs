//! Schedules: element schedules, material takeoffs and sheet lists, with sorting, grouping,
//! headers/footers, filters, calculated values and totals.

use crate::analysis;
use crate::formula;
use crate::model::*;
use crate::params::{self, PKind, ParamDef, Value};
use std::cmp::Ordering;

#[derive(Clone, Debug, PartialEq)]
pub enum RowKind {
    Item,
    /// A collapsed group (itemize off) or a group footer.
    Group,
    /// Group header (group headers on).
    Header,
    Total,
    /// Sorting/Grouping "Blank line" after a group.
    Blank,
}

#[derive(Clone, Debug)]
pub struct Row {
    pub kind: RowKind,
    pub cells: Vec<String>,
    /// Elements represented by the row.
    pub ids: Vec<Id>,
}

#[derive(Clone, Debug)]
pub struct Column {
    pub def: ParamDef,
    /// Formatting: the heading shown and the alignment (0 left, 1 center, 2 right).
    pub heading: String,
    pub align: u8,
}

#[derive(Clone, Debug)]
pub struct Table {
    pub columns: Vec<Column>,
    pub rows: Vec<Row>,
}

/// One schedule record: an element, an element/material pair, or a sheet.
#[derive(Clone, Debug)]
enum Rec {
    Element(Id),
    Material(Id, String, f64),
    Sheet(Id),
    /// A keynote legend row: the key.
    Keynote(String),
}

impl Rec {
    fn id(&self) -> Id {
        match self {
            Rec::Element(id) | Rec::Material(id, ..) | Rec::Sheet(id) => *id,
            Rec::Keynote(_) => 0,
        }
    }
}

fn text_def(name: &str, kind: ParamKind) -> ParamDef {
    ParamDef { name: name.into(), group: String::new(), kind: PKind::Value(kind), read_only: true, type_param: false }
}

/// All fields offered for a schedule definition.
pub fn available_fields(p: &Project, def: &ScheduleDef) -> Vec<ParamDef> {
    if def.keynote_legend {
        return ["Key Value", "Keynote Text"].iter().map(|n| text_def(n, ParamKind::Text)).collect();
    }
    if def.sheet_list {
        return ["Sheet Number", "Sheet Name", "Drawn By", "Checked By", "Approved By", "Issue Date", "Current Revision", "Sheet Size"].iter().map(|n| text_def(n, ParamKind::Text)).collect();
    }
    let mut v = params::category_fields(p, def.category);
    if def.material_takeoff {
        v.push(text_def("Material: Name", ParamKind::Text));
        v.push(text_def("Material: Class", ParamKind::Text));
        v.push(text_def("Material: Thickness", ParamKind::Length));
        v.push(text_def("Material: Area", ParamKind::Area));
        v.push(text_def("Material: Volume", ParamKind::Volume));
    }
    for c in &def.calculated {
        v.push(text_def(&c.name, c.kind));
    }
    v
}

fn field_def(available: &[ParamDef], name: &str) -> ParamDef {
    available.iter().find(|d| d.name == name).cloned().unwrap_or_else(|| text_def(name, ParamKind::Text))
}

fn format_value(p: &Project, v: &Option<Value>, def: &ParamDef) -> String {
    match v {
        None => String::new(),
        Some(Value::Text(s)) => s.clone(),
        Some(Value::Num(x)) => match def.kind {
            PKind::Value(k) => p.units.format(*x, k),
            _ => p.units.format(*x, ParamKind::Number),
        },
    }
}

/// Compares values naturally: numbers numerically, text case-insensitively with numeric awareness.
pub fn compare(a: &Option<Value>, b: &Option<Value>) -> Ordering {
    match (a, b) {
        (Some(Value::Num(x)), Some(Value::Num(y))) => x.total_cmp(y),
        (Some(Value::Text(x)), Some(Value::Text(y))) => match (x.trim().parse::<f64>(), y.trim().parse::<f64>()) {
            (Ok(nx), Ok(ny)) => nx.total_cmp(&ny),
            _ => x.to_lowercase().cmp(&y.to_lowercase()),
        },
        (None, None) => Ordering::Equal,
        (None, _) => Ordering::Less,
        (_, None) => Ordering::Greater,
        (Some(Value::Num(_)), _) => Ordering::Less,
        _ => Ordering::Greater,
    }
}

fn layer_area(p: &Project, e: &Element) -> f64 {
    match &e.kind {
        ElementKind::Wall(w) => analysis::wall_net_area(p, e.id, w),
        ElementKind::Floor(f) => analysis::floor_area(f),
        ElementKind::Roof(r) => analysis::roof_area(r),
        ElementKind::Ceiling(c) => crate::geom::area(&c.boundary),
        _ => 0.0,
    }
}

fn records(p: &Project, def: &ScheduleDef) -> Vec<Rec> {
    if def.sheet_list {
        return p.views.iter().filter(|v| matches!(v.kind, ViewKind::Sheet(_))).map(|v| Rec::Sheet(v.id)).collect();
    }
    if def.keynote_legend {
        // Every key shown by a keynote tag in the project.
        let mut keys: Vec<String> = p
            .elements
            .iter()
            .filter_map(|e| match &e.kind {
                ElementKind::Tag(t) => {
                    let host = p.element(t.host)?;
                    let k = match t.parameter.as_str() {
                        "Keynote" => crate::keynote::element_keynote(p, host),
                        "Material Keynote" => crate::keynote::material_keynote(p, host),
                        "User Keynote" => t.key.clone(),
                        _ => return None,
                    };
                    (!k.is_empty()).then_some(k)
                }
                _ => None,
            })
            .collect();
        keys.sort();
        keys.dedup();
        return keys.into_iter().map(Rec::Keynote).collect();
    }
    let mut out = Vec::new();
    for e in p.elements.iter().filter(|e| e.category() == def.category && e.view.is_none()) {
        if def.material_takeoff {
            if let Some(t) = p.type_of(e).and_then(|t| p.sys_type(t)) {
                for l in &t.layers {
                    out.push(Rec::Material(e.id, l.material.clone(), l.thickness));
                }
                continue;
            }
            if let ElementKind::Instance(i) = &e.kind {
                if let Some(r) = crate::family_params::Resolver::for_instance(p, i) {
                    for fp in r.family().params.iter().filter(|fp| fp.kind == ParamKind::Material) {
                        out.push(Rec::Material(e.id, r.raw(fp).to_string(), 0.0));
                    }
                    continue;
                }
            }
        }
        out.push(Rec::Element(e.id));
    }
    out
}

fn raw_get(p: &Project, def: &ScheduleDef, r: &Rec, field: &str) -> Option<Value> {
    match r {
        Rec::Keynote(k) => match field {
            "Key Value" => Some(Value::Text(k.clone())),
            "Keynote Text" => Some(Value::Text(crate::keynote::text_of(p, k).unwrap_or_default())),
            _ => None,
        },
        Rec::Sheet(id) => {
            let v = p.view(*id)?;
            let ViewKind::Sheet(s) = &v.kind else { return None };
            let rev = s.revisions.iter().filter_map(|rid| p.revisions.iter().find(|x| x.id == *rid)).max_by_key(|x| x.sequence).map(|x| x.sequence.to_string()).unwrap_or_default();
            Some(Value::Text(match field {
                "Sheet Number" => s.number.clone(),
                "Sheet Name" => v.name.clone(),
                "Drawn By" => s.drawn_by.clone(),
                "Checked By" => s.checked_by.clone(),
                "Approved By" => s.approved_by.clone(),
                "Issue Date" => s.issue_date.clone(),
                "Current Revision" => rev,
                "Sheet Size" => s.size.label().into(),
                _ => return None,
            }))
        }
        Rec::Material(id, mat, thick) => {
            let e = p.element(*id)?;
            match field {
                "Material: Name" => Some(Value::Text(mat.clone())),
                "Material: Class" => Some(Value::Text(p.material(mat).map(|m| m.class.clone()).unwrap_or_default())),
                "Material: Thickness" => Some(Value::Num(*thick)),
                "Material: Area" => Some(Value::Num(layer_area(p, e))),
                "Material: Volume" => Some(Value::Num(layer_area(p, e) * thick)),
                _ => get_field(p, def, e, field),
            }
        }
        Rec::Element(id) => get_field(p, def, p.element(*id)?, field),
    }
}

fn get_field(p: &Project, def: &ScheduleDef, e: &Element, field: &str) -> Option<Value> {
    if let Some(c) = def.calculated.iter().find(|c| c.name == field) {
        let mut resolve = |n: &str| -> Result<f64, formula::FormulaError> {
            if n == field {
                return Err(formula::FormulaError("A calculated value cannot refer to itself.".into()));
            }
            match params::get(p, e, n) {
                Some(Value::Num(x)) => Ok(x),
                _ => Err(formula::FormulaError(format!("'{n}' is not a numeric field."))),
            }
        };
        return formula::evaluate(&c.formula, &mut resolve).ok().map(Value::Num);
    }
    params::get(p, e, field)
}

fn passes(p: &Project, filter: &ScheduleFilter, value: &Option<Value>, def: &ParamDef) -> bool {
    rule_passes(p, filter.op, &filter.value, value, def)
}

/// One filter rule (schedule filters and view filters) against a parameter value.
pub fn rule_passes(p: &Project, op: FilterOp, target: &str, value: &Option<Value>, def: &ParamDef) -> bool {
    let text = format_value(p, value, def).to_lowercase();
    let numeric = match (value, &def.kind) {
        (Some(Value::Num(x)), PKind::Value(k)) => p.units.parse(target, *k).map(|t| (*x, t)),
        _ => None,
    };
    op.test(text.trim(), &target.trim().to_lowercase(), numeric)
}

pub fn build(p: &Project, def: &ScheduleDef) -> Table {
    let available = available_fields(p, def);
    // Hidden fields still sort and filter, but are not shown.
    let columns: Vec<Column> = def
        .fields
        .iter()
        .filter(|f| !def.format(f).hidden)
        .map(|f| {
            let fm = def.format(f);
            Column { def: field_def(&available, f), heading: if fm.heading.is_empty() { f.clone() } else { fm.heading }, align: fm.align }
        })
        .collect();

    // (sort keys, record, values)
    let mut items: Vec<(Vec<Option<Value>>, Rec, Vec<Option<Value>>)> = Vec::new();
    'records: for r in records(p, def) {
        for f in &def.filters {
            let fd = field_def(&available, &f.field);
            if !passes(p, f, &raw_get(p, def, &r, &f.field), &fd) {
                continue 'records;
            }
        }
        let values = columns.iter().map(|c| raw_get(p, def, &r, &c.def.name)).collect();
        let keys = def.sort_by.iter().map(|f| raw_get(p, def, &r, f)).collect();
        items.push((keys, r, values));
    }
    let levels: Vec<SortLevel> = (0..def.sort_by.len()).map(|k| def.level(k)).collect();
    items.sort_by(|a, b| {
        for (k, (x, y)) in a.0.iter().zip(&b.0).enumerate() {
            let ord = compare(x, y);
            if ord != Ordering::Equal {
                return if levels[k].descending { ord.reverse() } else { ord };
            }
        }
        a.1.id().cmp(&b.1.id())
    });
    let first = levels.first().cloned().unwrap_or_default();
    let grouped = !def.sort_by.is_empty() && (first.header || first.footer || first.blank_line);
    // A footer or grand total's first cell: title and/or count, by its mode.
    let title_cell = |mode: u8, title: &str, count: usize| -> String {
        match mode {
            0 => format!("{title}: {count}"),
            1 => title.to_string(),
            2 => count.to_string(),
            _ => String::new(),
        }
    };

    let summable = |c: &Column| c.def.name == "Count" || def.total_fields.contains(&c.def.name);
    let aggregate = |group: &[&(Vec<Option<Value>>, Rec, Vec<Option<Value>>)]| -> Vec<String> {
        columns
            .iter()
            .enumerate()
            .map(|(ci, c)| {
                let first = &group[0].2[ci];
                if c.def.name == "Count" {
                    return group.len().to_string();
                }
                if summable(c) {
                    let sum: f64 = group.iter().filter_map(|g| g.2[ci].as_ref().and_then(Value::as_num)).sum();
                    return format_value(p, &Some(Value::Num(sum)), &c.def);
                }
                if group.iter().all(|g| compare(&g.2[ci], first) == Ordering::Equal) {
                    format_value(p, first, &c.def)
                } else {
                    String::new()
                }
            })
            .collect()
    };
    let item_row = |it: &(Vec<Option<Value>>, Rec, Vec<Option<Value>>)| Row {
        kind: RowKind::Item,
        cells: columns.iter().zip(&it.2).map(|(c, v)| if c.def.name == "Count" { "1".into() } else { format_value(p, v, &c.def) }).collect(),
        ids: vec![it.1.id()],
    };

    let mut rows = Vec::new();
    let same_key = |a: &[Option<Value>], b: &[Option<Value>], n: usize| a.iter().zip(b).take(n).all(|(x, y)| compare(x, y) == Ordering::Equal);
    if def.itemize && !grouped {
        rows.extend(items.iter().map(item_row));
    } else {
        let key_len = if def.sort_by.is_empty() { 0 } else if def.itemize { 1 } else { def.sort_by.len() };
        let mut i = 0;
        while i < items.len() {
            let mut j = i + 1;
            while j < items.len() && (key_len == 0 && !def.itemize && same_key(&[raw_get(p, def, &items[j].1, "Family and Type")], &[raw_get(p, def, &items[i].1, "Family and Type")], 1) || key_len > 0 && same_key(&items[j].0, &items[i].0, key_len)) {
                j += 1;
            }
            let group: Vec<_> = items[i..j].iter().collect();
            if def.itemize {
                let label = items[i].0.first().map(|v| format_value(p, v, &field_def(&available, &def.sort_by[0]))).unwrap_or_default();
                if first.header {
                    let mut header = vec![String::new(); columns.len()];
                    if let Some(h) = header.first_mut() {
                        *h = label.clone();
                    }
                    rows.push(Row { kind: RowKind::Header, cells: header, ids: vec![] });
                }
                rows.extend(group.iter().map(|g| item_row(g)));
                if first.footer {
                    let mut footer: Vec<String> = aggregate(&group).into_iter().zip(&columns).map(|(s, c)| if summable(c) { s } else { String::new() }).collect();
                    if let Some(f) = footer.first_mut() {
                        if f.is_empty() {
                            *f = title_cell(first.footer_mode, &label, group.len());
                        }
                    }
                    rows.push(Row { kind: RowKind::Group, cells: footer, ids: group.iter().map(|g| g.1.id()).collect() });
                }
                if first.blank_line {
                    rows.push(Row { kind: RowKind::Blank, cells: vec![String::new(); columns.len()], ids: vec![] });
                }
            } else {
                rows.push(Row { kind: RowKind::Group, cells: aggregate(&group), ids: group.iter().map(|g| g.1.id()).collect() });
            }
            i = j;
        }
    }

    if def.grand_total && !items.is_empty() {
        let all: Vec<_> = items.iter().collect();
        let mut cells: Vec<String> = aggregate(&all).into_iter().zip(&columns).map(|(s, c)| if summable(c) { s } else { String::new() }).collect();
        if let Some(first) = cells.first_mut() {
            if first.is_empty() {
                let title = if def.grand_title.is_empty() { "Grand total" } else { def.grand_title.as_str() };
                *first = title_cell(def.grand_mode, title, items.len());
            }
        }
        rows.push(Row { kind: RowKind::Total, cells, ids: vec![] });
    }
    Table { columns, rows }
}

/// CSV export (Revit's "Export > Reports > Schedule").
pub fn to_csv(view_name: &str, t: &Table) -> String {
    let esc = |s: &str| {
        if s.contains([',', '"', '\n']) {
            format!("\"{}\"", s.replace('"', "\"\""))
        } else {
            s.to_string()
        }
    };
    let mut out = format!("{}\n", esc(view_name));
    out.push_str(&t.columns.iter().map(|c| esc(&c.heading)).collect::<Vec<_>>().join(","));
    out.push('\n');
    for r in &t.rows {
        out.push_str(&r.cells.iter().map(|c| esc(c)).collect::<Vec<_>>().join(","));
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{defaults, edit, geom::DVec2, units::UnitSystem};

    fn project_with_doors() -> Project {
        let mut p = defaults::new_project(UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let wt = p.types_of(Category::Walls).next().unwrap().id;
        let wall = edit::add_wall(&mut p, lvl, wt, DVec2::ZERO, DVec2::new(10000.0, 0.0), 3000.0).unwrap();
        let fam = p.families.iter().find(|f| f.name == "Single-Flush").unwrap();
        let (t800, t900) = (fam.types[0].id, fam.types[1].id);
        for (i, (t, x)) in [(t900, 1000.0), (t800, 3000.0), (t900, 5000.0)].into_iter().enumerate() {
            let id = edit::place_hosted(&mut p, t, wall, x, false).unwrap();
            p.element_mut(id).unwrap().mark = format!("{}", 10 - i);
        }
        p
    }

    fn door_def() -> ScheduleDef {
        ScheduleDef {
            category: Category::Doors,
            fields: vec!["Mark".into(), "Type".into(), "Width".into(), "Cost".into(), "Count".into()],
            sort_by: vec!["Mark".into()],
            itemize: true,
            grand_total: true,
            total_fields: vec!["Cost".into()],
            ..Default::default()
        }
    }

    #[test]
    fn sorting_grouping_and_formatting() {
        let p = project_with_doors();
        let mut d = door_def();
        d.sort_by = vec!["Type".into(), "Mark".into()];
        d.levels = vec![SortLevel { header: true, footer: true, footer_mode: 0, blank_line: true, ..Default::default() }, SortLevel { descending: true, ..Default::default() }];
        d.formats.insert("Cost".into(), FieldFormat { hidden: true, ..Default::default() });
        d.formats.insert("Mark".into(), FieldFormat { heading: "No.".into(), align: 1, ..Default::default() });
        d.grand_title = "All doors".into();
        let t = build(&p, &d);
        assert!(t.columns.iter().all(|c| c.def.name != "Cost"));
        assert_eq!(t.columns[0].heading, "No.");
        assert_eq!(t.rows[0].kind, RowKind::Header);
        assert!(t.rows.iter().any(|r| r.kind == RowKind::Blank));
        let footer = t.rows.iter().find(|r| r.kind == RowKind::Group).unwrap();
        assert!(footer.cells[0].contains(": "), "{:?}", footer.cells);
        let total = t.rows.last().unwrap();
        assert!(total.cells[0].starts_with("All doors: "), "{:?}", total.cells);
        // Marks run downward within a type.
        let marks: Vec<&String> = t.rows.iter().take_while(|r| r.kind != RowKind::Group).filter(|r| r.kind == RowKind::Item).map(|r| &r.cells[0]).collect();
        let mut sorted = marks.clone();
        sorted.sort();
        sorted.reverse();
        assert_eq!(marks, sorted);
    }

    #[test]
    fn itemized_sorted_with_totals() {
        let p = project_with_doors();
        let t = build(&p, &door_def());
        let marks: Vec<&str> = t.rows.iter().take(3).map(|r| r.cells[0].as_str()).collect();
        assert_eq!(marks, vec!["8", "9", "10"]);
        let total = t.rows.last().unwrap();
        assert_eq!(total.kind, RowKind::Total);
        assert_eq!(total.cells[3], "1320.00");
        assert_eq!(total.cells[4], "3");
    }

    #[test]
    fn grouped_filtered_calculated_and_takeoff() {
        let p = project_with_doors();
        let mut d = door_def();
        d.itemize = false;
        d.sort_by = vec!["Type".into()];
        let t = build(&p, &d);
        assert_eq!(t.rows.len(), 3);
        let g900 = t.rows.iter().find(|r| r.cells[1] == "900 x 2100").unwrap();
        assert_eq!(g900.cells[4], "2");
        d.filters.push(ScheduleFilter { field: "Width".into(), op: FilterOp::Greater, value: "850".into() });
        assert_eq!(build(&p, &d).rows.len(), 2);

        let mut c = door_def();
        c.calculated.push(CalculatedField { name: "Leaf Area".into(), formula: "Width * Height".into(), kind: ParamKind::Area });
        c.fields.push("Leaf Area".into());
        let t = build(&p, &c);
        assert_eq!(t.rows[0].cells[5], "1.89 m²");

        let walls = ScheduleDef { category: Category::Walls, fields: vec!["Material: Name".into(), "Material: Volume".into()], material_takeoff: true, ..Default::default() };
        let t = build(&p, &walls);
        assert!(!t.rows.is_empty());
    }
}
