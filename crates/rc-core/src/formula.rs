//! Revit-style parameter formulas, e.g. `Width - 2 * Frame Width` or `if(Width > 1000, 2, 1)`.
//!
//! Parameter names may contain spaces, or be written in square brackets. Supported: `+ - * / ^`,
//! comparisons `< > = <= >= <>`, `and`, `or`, `not(x)`, and the functions `if, min, max, abs, round,
//! roundup, rounddown, sqrt, sin, cos, tan` (degrees) and the constant `pi`.

use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq)]
pub struct FormulaError(pub String);

impl std::fmt::Display for FormulaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for FormulaError {}

fn err<T>(msg: impl Into<String>) -> Result<T, FormulaError> {
    Err(FormulaError(msg.into()))
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Num(f64),
    Ident(String),
    Op(&'static str),
    LParen,
    RParen,
    Comma,
    End,
}

const FUNCTIONS: [&str; 12] =
    ["if", "min", "max", "abs", "round", "roundup", "rounddown", "sqrt", "sin", "cos", "tan", "not"];

fn is_function(s: &str) -> bool {
    FUNCTIONS.iter().any(|f| f.eq_ignore_ascii_case(s))
}

fn tokenize(s: &str) -> Result<Vec<Tok>, FormulaError> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        if c.is_ascii_digit() || (c == '.' && chars.get(i + 1).is_some_and(|d| d.is_ascii_digit())) {
            let start = i;
            while i < chars.len() && (chars[i].is_ascii_digit() || chars[i] == '.') {
                i += 1;
            }
            if i < chars.len()
                && (chars[i] == 'e' || chars[i] == 'E')
                && chars.get(i + 1).is_some_and(|d| d.is_ascii_digit() || *d == '-' || *d == '+')
            {
                i += 2;
                while i < chars.len() && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            let text: String = chars[start..i].iter().collect();
            match text.parse::<f64>() {
                Ok(v) => out.push(Tok::Num(v)),
                Err(_) => return err(format!("Invalid number '{text}'.")),
            }
            continue;
        }
        if c == '[' {
            let Some(end) = chars[i + 1..].iter().position(|&c| c == ']') else {
                return err("Missing ']'.");
            };
            let name: String = chars[i + 1..i + 1 + end].iter().collect();
            out.push(Tok::Ident(name.trim().to_string()));
            i += end + 2;
            continue;
        }
        if c.is_alphabetic() || c == '_' {
            let start = i;
            while i < chars.len() && (chars[i].is_alphanumeric() || chars[i] == '_' || chars[i] == ' ') {
                i += 1;
            }
            let text: String = chars[start..i].iter().collect();
            // Split out the keyword operators "and"/"or" from multi-word names.
            let mut current: Vec<&str> = Vec::new();
            for w in text.split_whitespace() {
                if w.eq_ignore_ascii_case("and") || w.eq_ignore_ascii_case("or") {
                    if !current.is_empty() {
                        out.push(Tok::Ident(current.join(" ")));
                        current.clear();
                    }
                    out.push(Tok::Op(if w.eq_ignore_ascii_case("and") { "and" } else { "or" }));
                } else {
                    current.push(w);
                }
            }
            if !current.is_empty() {
                out.push(Tok::Ident(current.join(" ")));
            }
            continue;
        }
        let next = chars.get(i + 1).copied();
        let tok = match (c, next) {
            ('(', _) => Tok::LParen,
            (')', _) => Tok::RParen,
            (',', _) => Tok::Comma,
            ('<', Some('=')) => {
                i += 1;
                Tok::Op("<=")
            }
            ('>', Some('=')) => {
                i += 1;
                Tok::Op(">=")
            }
            ('<', Some('>')) => {
                i += 1;
                Tok::Op("<>")
            }
            ('+', _) => Tok::Op("+"),
            ('-', _) => Tok::Op("-"),
            ('*', _) => Tok::Op("*"),
            ('/', _) => Tok::Op("/"),
            ('^', _) => Tok::Op("^"),
            ('<', _) => Tok::Op("<"),
            ('>', _) => Tok::Op(">"),
            ('=', _) => Tok::Op("="),
            _ => return err(format!("Unexpected character '{c}'.")),
        };
        out.push(tok);
        i += 1;
    }
    out.push(Tok::End);
    Ok(out)
}

/// Evaluates a formula, resolving parameter names through `resolve`.
pub fn evaluate(formula: &str, resolve: &mut dyn FnMut(&str) -> Result<f64, FormulaError>) -> Result<f64, FormulaError> {
    let tokens = tokenize(formula)?;
    let mut p = Parser { t: &tokens, pos: 0, resolve };
    let v = p.expr()?;
    if p.peek() != &Tok::End {
        return err(format!("Unexpected '{}'.", describe(p.peek())));
    }
    Ok(v)
}

/// Names of parameters referenced by a formula.
pub fn references(formula: &str) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    if let Ok(tokens) = tokenize(formula) {
        for (i, t) in tokens.iter().enumerate() {
            if let Tok::Ident(name) = t {
                let call = matches!(tokens.get(i + 1), Some(Tok::LParen)) && is_function(name);
                let constant = ["pi", "true", "false"].iter().any(|k| k.eq_ignore_ascii_case(name));
                if !call && !constant {
                    names.insert(name.clone());
                }
            }
        }
    }
    names
}

fn describe(t: &Tok) -> String {
    match t {
        Tok::Num(v) => v.to_string(),
        Tok::Ident(s) => s.clone(),
        Tok::Op(o) => o.to_string(),
        Tok::LParen => "(".into(),
        Tok::RParen => ")".into(),
        Tok::Comma => ",".into(),
        Tok::End => "end of formula".into(),
    }
}

struct Parser<'a> {
    t: &'a [Tok],
    pos: usize,
    resolve: &'a mut dyn FnMut(&str) -> Result<f64, FormulaError>,
}

impl Parser<'_> {
    fn peek(&self) -> &Tok {
        &self.t[self.pos]
    }

    fn next(&mut self) -> Tok {
        let t = self.t[self.pos].clone();
        if self.pos < self.t.len() - 1 {
            self.pos += 1;
        }
        t
    }

    fn is_op(&self, op: &str) -> bool {
        matches!(self.peek(), Tok::Op(o) if *o == op)
    }

    fn expect(&mut self, t: Tok) -> Result<(), FormulaError> {
        if *self.peek() != t {
            return err(format!("Expected '{}'.", describe(&t)));
        }
        self.next();
        Ok(())
    }

    fn expr(&mut self) -> Result<f64, FormulaError> {
        let mut l = self.and()?;
        while self.is_op("or") {
            self.next();
            let r = self.and()?;
            l = bool_f(l != 0.0 || r != 0.0);
        }
        Ok(l)
    }

    fn and(&mut self) -> Result<f64, FormulaError> {
        let mut l = self.cmp()?;
        while self.is_op("and") {
            self.next();
            let r = self.cmp()?;
            l = bool_f(l != 0.0 && r != 0.0);
        }
        Ok(l)
    }

    fn cmp(&mut self) -> Result<f64, FormulaError> {
        let mut l = self.add()?;
        loop {
            let op = match self.peek() {
                Tok::Op(o) if matches!(*o, "<" | ">" | "=" | "<=" | ">=" | "<>") => *o,
                _ => break,
            };
            self.next();
            let r = self.add()?;
            let eps = 1e-9;
            l = bool_f(match op {
                "<" => l < r - eps,
                ">" => l > r + eps,
                "<=" => l <= r + eps,
                ">=" => l >= r - eps,
                "=" => (l - r).abs() <= eps,
                _ => (l - r).abs() > eps,
            });
        }
        Ok(l)
    }

    fn add(&mut self) -> Result<f64, FormulaError> {
        let mut l = self.mul()?;
        while self.is_op("+") || self.is_op("-") {
            let plus = self.is_op("+");
            self.next();
            let r = self.mul()?;
            l = if plus { l + r } else { l - r };
        }
        Ok(l)
    }

    fn mul(&mut self) -> Result<f64, FormulaError> {
        let mut l = self.unary()?;
        while self.is_op("*") || self.is_op("/") {
            let times = self.is_op("*");
            self.next();
            let r = self.unary()?;
            if times {
                l *= r;
            } else {
                if r.abs() < 1e-12 {
                    return err("Division by zero.");
                }
                l /= r;
            }
        }
        Ok(l)
    }

    fn unary(&mut self) -> Result<f64, FormulaError> {
        if self.is_op("-") {
            self.next();
            return Ok(-self.unary()?);
        }
        if self.is_op("+") {
            self.next();
            return self.unary();
        }
        self.power()
    }

    fn power(&mut self) -> Result<f64, FormulaError> {
        let b = self.primary()?;
        if self.is_op("^") {
            self.next();
            let e = self.unary()?;
            return Ok(b.powf(e));
        }
        Ok(b)
    }

    fn primary(&mut self) -> Result<f64, FormulaError> {
        match self.next() {
            Tok::Num(v) => Ok(v),
            Tok::LParen => {
                let v = self.expr()?;
                self.expect(Tok::RParen)?;
                Ok(v)
            }
            Tok::Ident(name) => {
                if *self.peek() == Tok::LParen && is_function(&name) {
                    return self.call(&name.to_ascii_lowercase());
                }
                match name.to_ascii_lowercase().as_str() {
                    "pi" => Ok(std::f64::consts::PI),
                    "true" => Ok(1.0),
                    "false" => Ok(0.0),
                    _ => (self.resolve)(&name),
                }
            }
            Tok::End => err("Formula ends unexpectedly."),
            t => err(format!("Unexpected '{}'.", describe(&t))),
        }
    }

    fn call(&mut self, name: &str) -> Result<f64, FormulaError> {
        self.expect(Tok::LParen)?;
        if name == "if" {
            // Only the chosen branch is evaluated so the other branch cannot fail.
            let cond = self.expr()?;
            self.expect(Tok::Comma)?;
            let result = if cond != 0.0 {
                let v = self.expr()?;
                self.expect(Tok::Comma)?;
                self.skip_expr();
                v
            } else {
                self.skip_expr();
                self.expect(Tok::Comma)?;
                self.expr()?
            };
            self.expect(Tok::RParen)?;
            return Ok(result);
        }
        let mut args = Vec::new();
        if *self.peek() != Tok::RParen {
            args.push(self.expr()?);
            while *self.peek() == Tok::Comma {
                self.next();
                args.push(self.expr()?);
            }
        }
        self.expect(Tok::RParen)?;
        let arg = |i: usize| args.get(i).copied().ok_or_else(|| FormulaError(format!("{name}() needs more arguments.")));
        let deg = std::f64::consts::PI / 180.0;
        Ok(match name {
            "min" => args.iter().copied().reduce(f64::min).ok_or_else(|| FormulaError("min() needs arguments.".into()))?,
            "max" => args.iter().copied().reduce(f64::max).ok_or_else(|| FormulaError("max() needs arguments.".into()))?,
            "abs" => arg(0)?.abs(),
            "round" => match args.len() {
                1 => arg(0)?.round(),
                _ => (arg(0)? / arg(1)?).round() * arg(1)?,
            },
            "roundup" => match args.len() {
                1 => arg(0)?.ceil(),
                _ => (arg(0)? / arg(1)?).ceil() * arg(1)?,
            },
            "rounddown" => match args.len() {
                1 => arg(0)?.floor(),
                _ => (arg(0)? / arg(1)?).floor() * arg(1)?,
            },
            "sqrt" => {
                let a = arg(0)?;
                if a < 0.0 {
                    return err("sqrt() of a negative number.");
                }
                a.sqrt()
            }
            "sin" => (arg(0)? * deg).sin(),
            "cos" => (arg(0)? * deg).cos(),
            "tan" => (arg(0)? * deg).tan(),
            "not" => bool_f(arg(0)? == 0.0),
            _ => return err(format!("Unknown function '{name}'.")),
        })
    }

    /// Skips one expression without evaluating it, balanced on parentheses.
    fn skip_expr(&mut self) {
        let mut depth = 0;
        loop {
            match self.peek() {
                Tok::End => return,
                Tok::LParen => depth += 1,
                Tok::RParen => {
                    if depth == 0 {
                        return;
                    }
                    depth -= 1;
                }
                Tok::Comma if depth == 0 => return,
                _ => {}
            }
            self.next();
        }
    }
}

fn bool_f(b: bool) -> f64 {
    if b { 1.0 } else { 0.0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(f: &str) -> Result<f64, FormulaError> {
        evaluate(f, &mut |n| match n.to_ascii_lowercase().as_str() {
            "width" => Ok(900.0),
            "frame width" => Ok(50.0),
            "height" => Ok(2100.0),
            _ => err(format!("Unknown parameter '{n}'.")),
        })
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3").unwrap(), 7.0);
        assert_eq!(eval("(1 + 2) * 3").unwrap(), 9.0);
        assert_eq!(eval("2 ^ 3 ^ 2").unwrap(), 512.0);
        assert_eq!(eval("-2 ^ 2").unwrap(), -4.0);
        assert_eq!(eval("10 / 4").unwrap(), 2.5);
    }

    #[test]
    fn multi_word_parameters() {
        assert_eq!(eval("Width + 2 * Frame Width").unwrap(), 1000.0);
        assert_eq!(eval("[Frame Width] * 2").unwrap(), 100.0);
    }

    #[test]
    fn conditionals_and_logic() {
        assert_eq!(eval("if(Width > 800, 2, 1)").unwrap(), 2.0);
        assert_eq!(eval("if(Width > 1000, 1 / 0, 7)").unwrap(), 7.0);
        assert_eq!(eval("if(Width > 800 and Height < 2000, 1, 0)").unwrap(), 0.0);
        assert_eq!(eval("if(Width > 800 or Height < 2000, 1, 0)").unwrap(), 1.0);
        assert_eq!(eval("not(Width = 900)").unwrap(), 0.0);
    }

    #[test]
    fn functions() {
        assert_eq!(eval("round(1234, 100)").unwrap(), 1200.0);
        assert_eq!(eval("roundup(1201, 100)").unwrap(), 1300.0);
        assert_eq!(eval("max(1, Width, 3)").unwrap(), 900.0);
        assert!((eval("sin(30)").unwrap() - 0.5).abs() < 1e-12);
    }

    #[test]
    fn errors() {
        assert!(eval("Width +").is_err());
        assert!(eval("Depth * 2").is_err());
        assert!(eval("1 / 0").is_err());
        assert!(eval("(1").is_err());
    }

    #[test]
    fn finds_references() {
        let r = references("if(Width > 800, Frame Width, round(Height, 10))");
        assert_eq!(r.into_iter().collect::<Vec<_>>(), vec!["Frame Width", "Height", "Width"]);
    }
}
