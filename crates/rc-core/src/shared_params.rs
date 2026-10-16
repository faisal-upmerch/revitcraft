//! Shared parameter files (Manage > Shared Parameters), in the reference app's tab-separated
//! text format so the same file serves both applications.

use crate::model::ParamKind;

#[derive(Clone, Debug, PartialEq)]
pub struct SharedParam {
    pub guid: String,
    pub name: String,
    pub kind: ParamKind,
    pub group: u32,
    pub visible: bool,
    pub description: String,
    pub user_modifiable: bool,
    pub hide_when_no_value: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SharedParamFile {
    pub groups: Vec<(u32, String)>,
    pub params: Vec<SharedParam>,
}

/// The file's DATATYPE for a parameter kind.
pub fn datatype(k: ParamKind) -> &'static str {
    match k {
        ParamKind::Length => "LENGTH",
        ParamKind::Number => "NUMBER",
        ParamKind::Integer => "INTEGER",
        ParamKind::Angle => "ANGLE",
        ParamKind::Area => "AREA",
        ParamKind::Volume => "VOLUME",
        ParamKind::Text => "TEXT",
        ParamKind::YesNo => "YESNO",
        ParamKind::Material => "MATERIAL",
        ParamKind::Currency => "CURRENCY",
        ParamKind::Slope => "SLOPE",
    }
}

fn kind_of(t: &str) -> ParamKind {
    match t {
        "LENGTH" => ParamKind::Length,
        "INTEGER" => ParamKind::Integer,
        "ANGLE" => ParamKind::Angle,
        "AREA" => ParamKind::Area,
        "VOLUME" => ParamKind::Volume,
        "YESNO" => ParamKind::YesNo,
        "MATERIAL" => ParamKind::Material,
        "CURRENCY" => ParamKind::Currency,
        "SLOPE" => ParamKind::Slope,
        "NUMBER" => ParamKind::Number,
        _ => ParamKind::Text,
    }
}

impl SharedParamFile {
    pub fn parse(text: &str) -> Result<SharedParamFile, String> {
        let mut f = SharedParamFile::default();
        // Column order comes from the "*PARAM" header line.
        let mut cols: Vec<String> = Vec::new();
        for line in text.lines() {
            let parts: Vec<&str> = line.split('\t').collect();
            match parts.first().copied() {
                Some("GROUP") if parts.len() >= 3 => f.groups.push((parts[1].trim().parse().map_err(|_| format!("Bad group id: {}", parts[1]))?, parts[2].to_string())),
                Some("*PARAM") => cols = parts.iter().map(|s| s.trim().to_string()).collect(),
                Some("PARAM") => {
                    let get = |name: &str| cols.iter().position(|c| c == name).and_then(|k| parts.get(k)).map(|s| s.trim().to_string()).unwrap_or_default();
                    let flag = |name: &str, d: bool| match get(name).as_str() {
                        "1" => true,
                        "0" => false,
                        _ => d,
                    };
                    f.params.push(SharedParam {
                        guid: get("GUID"),
                        name: get("NAME"),
                        kind: kind_of(&get("DATATYPE")),
                        group: get("GROUP").parse().unwrap_or(1),
                        visible: flag("VISIBLE", true),
                        description: get("DESCRIPTION"),
                        user_modifiable: flag("USERMODIFIABLE", true),
                        hide_when_no_value: flag("HIDEWHENNOVALUE", false),
                    });
                }
                _ => {}
            }
        }
        if cols.is_empty() && !f.params.is_empty() {
            return Err("The file has parameters but no *PARAM header.".into());
        }
        Ok(f)
    }

    pub fn to_text(&self) -> String {
        let mut s = String::from("# This is a Revit shared parameter file.\r\n# Do not edit manually.\r\n*META\tVERSION\tMINVERSION\r\nMETA\t2\t1\r\n*GROUP\tID\tNAME\r\n");
        for (id, name) in &self.groups {
            s += &format!("GROUP\t{id}\t{name}\r\n");
        }
        s += "*PARAM\tGUID\tNAME\tDATATYPE\tDATACATEGORY\tGROUP\tVISIBLE\tDESCRIPTION\tUSERMODIFIABLE\tHIDEWHENNOVALUE\r\n";
        let b = |v: bool| if v { "1" } else { "0" };
        for p in &self.params {
            s += &format!("PARAM\t{}\t{}\t{}\t\t{}\t{}\t{}\t{}\t{}\r\n", p.guid, p.name, datatype(p.kind), p.group, b(p.visible), p.description, b(p.user_modifiable), b(p.hide_when_no_value));
        }
        s
    }

    pub fn new_guid() -> String {
        uuid::Uuid::new_v4().to_string()
    }

    pub fn next_group_id(&self) -> u32 {
        self.groups.iter().map(|g| g.0).max().unwrap_or(0) + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_the_text_format() {
        let mut f = SharedParamFile { groups: vec![(1, "Doors".into())], params: vec![] };
        f.params.push(SharedParam { guid: "b8c3e4a1-0000-4000-8000-000000000001".into(), name: "Fire Rating".into(), kind: ParamKind::Text, group: 1, visible: true, description: "Rating".into(), user_modifiable: true, hide_when_no_value: false });
        f.params.push(SharedParam { guid: "b8c3e4a1-0000-4000-8000-000000000002".into(), name: "Clear Width".into(), kind: ParamKind::Length, group: 1, visible: true, description: String::new(), user_modifiable: true, hide_when_no_value: true });
        let text = f.to_text();
        assert!(text.contains("PARAM\tb8c3e4a1-0000-4000-8000-000000000002\tClear Width\tLENGTH\t\t1\t1\t\t1\t1"));
        assert_eq!(SharedParamFile::parse(&text).unwrap(), f);
    }
}
