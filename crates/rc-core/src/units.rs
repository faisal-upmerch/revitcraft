//! Project units: formatting and parsing of lengths, areas, volumes, angles and currency.
//! Internally every length is millimetres; projects choose metric or imperial display.

use crate::model::ParamKind;
use serde::{Deserialize, Serialize};

pub const MM_PER_INCH: f64 = 25.4;
pub const MM_PER_FOOT: f64 = 304.8;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum UnitSystem {
    Metric,
    Imperial,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LengthUnit {
    Millimeters,
    Centimeters,
    Meters,
    FeetFractionalInches,
    FractionalInches,
    DecimalFeet,
    DecimalInches,
}

impl LengthUnit {
    pub const ALL: [LengthUnit; 7] = [
        LengthUnit::Millimeters,
        LengthUnit::Centimeters,
        LengthUnit::Meters,
        LengthUnit::FeetFractionalInches,
        LengthUnit::FractionalInches,
        LengthUnit::DecimalFeet,
        LengthUnit::DecimalInches,
    ];
    pub fn label(self) -> &'static str {
        match self {
            LengthUnit::Millimeters => "Millimeters",
            LengthUnit::Centimeters => "Centimeters",
            LengthUnit::Meters => "Meters",
            LengthUnit::FeetFractionalInches => "Feet and fractional inches",
            LengthUnit::FractionalInches => "Fractional inches",
            LengthUnit::DecimalFeet => "Decimal feet",
            LengthUnit::DecimalInches => "Decimal inches",
        }
    }
    pub fn is_imperial(self) -> bool {
        !matches!(self, LengthUnit::Millimeters | LengthUnit::Centimeters | LengthUnit::Meters)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum AreaUnit {
    SquareMeters,
    SquareFeet,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum VolumeUnit {
    CubicMeters,
    CubicFeet,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Units {
    pub system: UnitSystem,
    pub length: LengthUnit,
    /// Decimal places for decimal length units.
    pub length_decimals: u8,
    /// Rounding denominator for fractional inches (2, 4, 8, 16, 32, 64, 128, 256).
    pub fraction: u32,
    pub area: AreaUnit,
    pub volume: VolumeUnit,
    pub area_decimals: u8,
    pub angle_decimals: u8,
    pub currency: String,
}

impl Default for Units {
    fn default() -> Self {
        Units::metric()
    }
}

impl Units {
    pub fn metric() -> Units {
        Units {
            system: UnitSystem::Metric,
            length: LengthUnit::Millimeters,
            length_decimals: 0,
            fraction: 256,
            area: AreaUnit::SquareMeters,
            volume: VolumeUnit::CubicMeters,
            area_decimals: 2,
            angle_decimals: 2,
            currency: String::new(),
        }
    }

    pub fn imperial() -> Units {
        Units {
            system: UnitSystem::Imperial,
            length: LengthUnit::FeetFractionalInches,
            length_decimals: 2,
            fraction: 256,
            area: AreaUnit::SquareFeet,
            volume: VolumeUnit::CubicFeet,
            area_decimals: 0,
            angle_decimals: 2,
            currency: String::new(),
        }
    }

    pub fn length(&self, mm: f64) -> String {
        let d = self.length_decimals as usize;
        match self.length {
            LengthUnit::Millimeters => trim(format!("{mm:.d$}")),
            LengthUnit::Centimeters => trim(format!("{:.d$}", mm / 10.0)),
            LengthUnit::Meters => format!("{:.*}", d.max(3), mm / 1000.0),
            LengthUnit::DecimalFeet => format!("{:.d$}'", mm / MM_PER_FOOT),
            LengthUnit::DecimalInches => format!("{:.d$}\"", mm / MM_PER_INCH),
            LengthUnit::FractionalInches => {
                let (neg, whole, num, den) = fraction_parts(mm / MM_PER_INCH, self.fraction);
                format!("{}{}\"", if neg { "-" } else { "" }, frac_text(whole, num, den))
            }
            LengthUnit::FeetFractionalInches => {
                let inches_total = mm / MM_PER_INCH;
                let (neg, whole, num, den) = fraction_parts(inches_total, self.fraction);
                let feet = whole / 12;
                let inches = whole % 12;
                format!("{}{}' - {}\"", if neg { "-" } else { "" }, feet, frac_text(inches, num, den))
            }
        }
    }

    pub fn area(&self, mm2: f64) -> String {
        let d = self.area_decimals as usize;
        match self.area {
            AreaUnit::SquareMeters => format!("{:.d$} m²", mm2 / 1e6),
            AreaUnit::SquareFeet => format!("{:.d$} SF", mm2 / (MM_PER_FOOT * MM_PER_FOOT)),
        }
    }

    pub fn volume(&self, mm3: f64) -> String {
        match self.volume {
            VolumeUnit::CubicMeters => format!("{:.3} m³", mm3 / 1e9),
            VolumeUnit::CubicFeet => format!("{:.2} CF", mm3 / MM_PER_FOOT.powi(3)),
        }
    }

    pub fn format(&self, value: f64, kind: ParamKind) -> String {
        match kind {
            ParamKind::Length => self.length(value),
            ParamKind::Area => self.area(value),
            ParamKind::Volume => self.volume(value),
            ParamKind::Angle => format!("{}°", trim(format!("{value:.*}", self.angle_decimals as usize))),
            ParamKind::Integer => format!("{}", value.round() as i64),
            ParamKind::YesNo => if value != 0.0 { "Yes" } else { "No" }.into(),
            ParamKind::Currency => format!("{}{value:.2}", self.currency),
            _ => trim(format!("{value:.3}")),
        }
    }

    /// Parses user input. Bare numbers use the project length unit; any explicit unit is honoured.
    pub fn parse(&self, input: &str, kind: ParamKind) -> Option<f64> {
        match kind {
            ParamKind::Length => parse_length(input, self.length),
            ParamKind::Area => {
                let s = input.trim().replace(',', ".");
                let (num, factor) = if let Some(n) = strip_any(&s, &["m²", "m2", "sqm"]) {
                    (n, 1e6)
                } else if let Some(n) = strip_any(&s, &["SF", "sf", "ft²", "ft2", "sqft"]) {
                    (n, MM_PER_FOOT * MM_PER_FOOT)
                } else {
                    (s.as_str(), if self.area == AreaUnit::SquareFeet { MM_PER_FOOT * MM_PER_FOOT } else { 1e6 })
                };
                num.trim().parse::<f64>().ok().map(|v| v * factor)
            }
            ParamKind::Volume => {
                let s = input.trim().replace(',', ".");
                let (num, factor) = if let Some(n) = strip_any(&s, &["m³", "m3"]) {
                    (n, 1e9)
                } else if let Some(n) = strip_any(&s, &["CF", "cf", "ft³", "ft3"]) {
                    (n, MM_PER_FOOT.powi(3))
                } else {
                    (s.as_str(), if self.volume == VolumeUnit::CubicFeet { MM_PER_FOOT.powi(3) } else { 1e9 })
                };
                num.trim().parse::<f64>().ok().map(|v| v * factor)
            }
            ParamKind::Currency => input.trim().trim_start_matches(|c: char| !c.is_ascii_digit() && c != '-' && c != '.').replace(',', "").parse().ok(),
            _ => parse_input(input, kind),
        }
    }

    /// Length snapping increment appropriate for the unit system (10 mm or 1/2").
    pub fn snap_increment(&self) -> f64 {
        if self.length.is_imperial() { MM_PER_INCH / 2.0 } else { 10.0 }
    }
}

fn strip_any<'a>(s: &'a str, suffixes: &[&str]) -> Option<&'a str> {
    suffixes.iter().find_map(|x| s.strip_suffix(x))
}

fn fraction_parts(value: f64, denominator: u32) -> (bool, i64, i64, i64) {
    let neg = value < 0.0;
    let den = denominator.max(1) as i64;
    let total = (value.abs() * den as f64).round() as i64;
    let whole = total / den;
    let mut num = total % den;
    let mut d = den;
    while num != 0 && num % 2 == 0 && d % 2 == 0 {
        num /= 2;
        d /= 2;
    }
    (neg && total != 0, whole, num, d)
}

fn frac_text(whole: i64, num: i64, den: i64) -> String {
    if num == 0 { format!("{whole}") } else { format!("{whole} {num}/{den}") }
}

fn trim(s: String) -> String {
    if s.contains('.') {
        let t = s.trim_end_matches('0').trim_end_matches('.');
        if t == "-0" { "0".into() } else { t.to_string() }
    } else {
        s
    }
}

fn parse_number(s: &str) -> Option<f64> {
    let s = s.trim();
    if s.is_empty() {
        return None;
    }
    // Mixed numbers: "6 1/2", "1/2".
    let parts: Vec<&str> = s.split_whitespace().collect();
    let mut total = 0.0;
    for p in parts {
        if let Some((a, b)) = p.split_once('/') {
            let (a, b): (f64, f64) = (a.parse().ok()?, b.parse().ok()?);
            if b == 0.0 {
                return None;
            }
            total += a / b;
        } else {
            total += p.parse::<f64>().ok()?;
        }
    }
    Some(total)
}

/// Parses a length with optional units. Bare numbers use `default`.
/// Imperial: `10'`, `10' 6"`, `10'-6 1/2"`, `6"`, `6 1/2"`, `10 6` (feet then inches in feet-inch projects).
pub fn parse_length(input: &str, default: LengthUnit) -> Option<f64> {
    let s = input.trim().replace(',', ".").replace('′', "'").replace('″', "\"");
    if s.is_empty() {
        return None;
    }
    let neg = s.starts_with('-') && !s[1..].trim_start().is_empty();
    let body = if neg { s[1..].trim() } else { s.as_str() };
    let sign = if neg { -1.0 } else { 1.0 };
    let lower = body.to_ascii_lowercase();

    // Imperial with explicit marks.
    if body.contains('\'') || body.contains('"') {
        let (feet_part, rest) = match body.split_once('\'') {
            Some((f, r)) => (Some(f), r),
            None => (None, body),
        };
        let feet = match feet_part {
            Some(f) => parse_number(f)?,
            None => 0.0,
        };
        let rest = rest.trim().trim_start_matches('-').trim().trim_end_matches('"').trim();
        let inches = if rest.is_empty() { 0.0 } else { parse_number(rest)? };
        return Some(sign * (feet * MM_PER_FOOT + inches * MM_PER_INCH));
    }
    for (suffix, factor) in [("mm", 1.0), ("cm", 10.0), ("m", 1000.0), ("ft", MM_PER_FOOT), ("in", MM_PER_INCH)] {
        if let Some(n) = lower.strip_suffix(suffix) {
            return parse_number(n).map(|v| sign * v * factor);
        }
    }
    match default {
        LengthUnit::Millimeters => parse_number(body).map(|v| sign * v),
        LengthUnit::Centimeters => parse_number(body).map(|v| sign * v * 10.0),
        LengthUnit::Meters => parse_number(body).map(|v| sign * v * 1000.0),
        LengthUnit::DecimalInches | LengthUnit::FractionalInches => parse_number(body).map(|v| sign * v * MM_PER_INCH),
        LengthUnit::DecimalFeet => parse_number(body).map(|v| sign * v * MM_PER_FOOT),
        LengthUnit::FeetFractionalInches => {
            // "10 6" means 10'-6"; "10 6 1/2" means 10'-6 1/2"; a single number is feet.
            let parts: Vec<&str> = body.split_whitespace().collect();
            match parts.len() {
                0 => None,
                1 => parse_number(parts[0]).map(|v| sign * v * MM_PER_FOOT),
                _ => {
                    let feet: f64 = parts[0].parse().ok()?;
                    let inches = parse_number(&parts[1..].join(" "))?;
                    Some(sign * (feet * MM_PER_FOOT + inches * MM_PER_INCH))
                }
            }
        }
    }
}

// ---------------------------------------------------------------- metric defaults (storage, IFC, tests)

pub fn format(value: f64, kind: ParamKind) -> String {
    Units::metric().format(value, kind)
}

/// Invariant string used in parameter dictionaries.
pub fn to_stored(v: f64) -> String {
    format!("{v}")
}

pub fn parse_stored(s: &str, kind: ParamKind) -> f64 {
    let t = s.trim();
    if kind == ParamKind::YesNo {
        if t.eq_ignore_ascii_case("yes") || t.eq_ignore_ascii_case("true") {
            return 1.0;
        }
        if t.eq_ignore_ascii_case("no") || t.eq_ignore_ascii_case("false") {
            return 0.0;
        }
    }
    t.parse().unwrap_or(0.0)
}

/// Parses input with metric defaults ("1200", "1.2 m", "120 cm"); explicit imperial marks also work.
pub fn parse_input(input: &str, kind: ParamKind) -> Option<f64> {
    let s = input.trim().replace(',', ".");
    match kind {
        ParamKind::YesNo => match s.to_ascii_lowercase().as_str() {
            "yes" | "1" | "true" | "y" => Some(1.0),
            "no" | "0" | "false" | "n" => Some(0.0),
            _ => None,
        },
        ParamKind::Length => parse_length(&s, LengthUnit::Millimeters),
        ParamKind::Area => Units::metric().parse(&s, kind),
        ParamKind::Volume => Units::metric().parse(&s, kind),
        ParamKind::Angle => s.trim_end_matches('°').trim().parse().ok().filter(|v: &f64| v.is_finite()),
        ParamKind::Integer => s.parse::<f64>().ok().map(f64::round),
        _ => s.parse().ok().filter(|v: &f64| v.is_finite()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metric_lengths() {
        assert_eq!(parse_input("1.2 m", ParamKind::Length), Some(1200.0));
        assert_eq!(parse_input("120cm", ParamKind::Length), Some(1200.0));
        assert_eq!(parse_input("1200", ParamKind::Length), Some(1200.0));
        assert_eq!(parse_input("abc", ParamKind::Length), None);
        assert_eq!(format(1200.0, ParamKind::Length), "1200");
        assert_eq!(format(2.5e6, ParamKind::Area), "2.50 m²");
    }

    #[test]
    fn imperial_lengths() {
        let u = Units::imperial();
        assert_eq!(u.length(3048.0), "10' - 0\"");
        assert_eq!(u.length(3048.0 + 6.5 * 25.4), "10' - 6 1/2\"");
        assert_eq!(u.length(25.4 * 3.25), "0' - 3 1/4\"");
        let close = |a: Option<f64>, b: f64| (a.unwrap() - b).abs() < 1e-9;
        assert!(close(u.parse("10'", ParamKind::Length), 3048.0));
        assert!(close(u.parse("10' 6\"", ParamKind::Length), 3048.0 + 152.4));
        assert!(close(u.parse("10'-6 1/2\"", ParamKind::Length), 3048.0 + 165.1));
        assert!(close(u.parse("6\"", ParamKind::Length), 152.4));
        assert!(close(u.parse("10 6", ParamKind::Length), 3048.0 + 152.4));
        assert!(close(u.parse("10", ParamKind::Length), 3048.0));
        assert!(close(u.parse("2400mm", ParamKind::Length), 2400.0));
        assert_eq!(u.area(MM_PER_FOOT * MM_PER_FOOT * 120.0), "120 SF");
    }
}
