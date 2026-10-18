import Foundation

/// Text decoding for DXF strings: `\U+XXXX` escapes, `%%` control codes and MTEXT inline formatting.
public enum CADTextDecoder {
    /// Decodes `\U+XXXX` (and `\u+XXXX`) Unicode escapes used by DXF files before R2007 and by some writers after.
    public static func decodeUnicodeEscapes(_ s: String) -> String {
        guard s.contains("\\U+") || s.contains("\\u+") else { return s }
        var out = String.UnicodeScalarView()
        let u = Array(s.unicodeScalars)
        var i = 0
        while i < u.count {
            if u[i] == "\\", i + 2 < u.count, (u[i + 1] == "U" || u[i + 1] == "u"), u[i + 2] == "+",
               let scalar = hexScalar(u, from: i + 3, count: 4) {
                out.append(scalar)
                i += 7
                continue
            }
            out.append(u[i])
            i += 1
        }
        return String(out)
    }

    static func hexScalar(_ u: [Unicode.Scalar], from: Int, count: Int) -> Unicode.Scalar? {
        guard from + count <= u.count else { return nil }
        var v: UInt32 = 0
        for k in 0..<count {
            guard let d = hexValue(u[from + k]) else { return nil }
            v = v * 16 + d
        }
        return Unicode.Scalar(v)
    }

    static func hexValue(_ c: Unicode.Scalar) -> UInt32? {
        switch c.value {
        case 48...57: c.value - 48
        case 65...70: c.value - 55
        case 97...102: c.value - 87
        default: nil
        }
    }

    /// Translates `%%` control codes of TEXT/ATTRIB strings: %%d °, %%p ±, %%c ⌀, %%%, %%nnn, and removes %%u/%%o toggles.
    public static func decodeControlCodes(_ s: String) -> String {
        guard s.contains("%%") else { return s }
        var out = String.UnicodeScalarView()
        let u = Array(s.unicodeScalars)
        var i = 0
        while i < u.count {
            if u[i] == "%", i + 2 < u.count, u[i + 1] == "%" {
                let c = u[i + 2]
                switch c {
                case "d", "D": out.append("°"); i += 3; continue
                case "p", "P": out.append("±"); i += 3; continue
                case "c", "C": out.append("⌀"); i += 3; continue
                case "%": out.append("%"); i += 3; continue
                case "u", "U", "o", "O", "k", "K": i += 3; continue
                default:
                    // %%nnn: decimal character code.
                    var j = i + 2, v: UInt32 = 0, n = 0
                    while j < u.count, n < 3, u[j].value >= 48, u[j].value <= 57 { v = v * 10 + (u[j].value - 48); j += 1; n += 1 }
                    if n == 3, let sc = Unicode.Scalar(v) { out.append(sc); i = j; continue }
                }
            }
            out.append(u[i])
            i += 1
        }
        return String(out)
    }

    /// Decodes a TEXT/ATTRIB value.
    public static func decodeText(_ s: String) -> String { decodeControlCodes(decodeUnicodeEscapes(s)) }

    /// Strips MTEXT inline formatting and returns plain text; paragraphs (`\P`) become "\n",
    /// stacked fractions (`\S1/2;`) become "1/2". Single pass, linear in the input length.
    public static func plainMText(_ raw: String) -> String {
        let u = Array(raw.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(u.count)
        var i = 0
        let n = u.count
        func skipToSemicolon(_ from: Int) -> Int {
            var j = from
            while j < n && u[j] != ";" { j += 1 }
            return min(n, j + 1)
        }
        while i < n {
            let c = u[i]
            switch c {
            case "\\":
                guard i + 1 < n else { i += 1; continue }
                let k = u[i + 1]
                switch k {
                case "P", "N", "X": out.append("\n"); i += 2
                case "~": out.append("\u{00A0}"); i += 2
                case "\\", "{", "}": out.append(k); i += 2
                case "L", "l", "O", "o", "K", "k": i += 2
                case "U", "u":
                    if i + 2 < n, u[i + 2] == "+", let sc = hexScalar(u, from: i + 3, count: 4) { out.append(sc); i += 7 } else { i += 2 }
                case "M", "m":
                    // \M+nXXXX multibyte (codepage-specific): not decodable without the codepage table; show a replacement mark.
                    if i + 2 < n, u[i + 2] == "+", i + 8 <= n { out.append("\u{FFFD}"); i += 8 } else { i += 2 }
                case "S":
                    // Stacked text \Snum/den; or \Snum^den; or \Snum#den;
                    let end = skipToSemicolon(i + 2)
                    var num = String.UnicodeScalarView(), den = String.UnicodeScalarView()
                    var sawSep = false
                    var j = i + 2
                    while j < end && u[j] != ";" {
                        var ch = u[j]
                        if ch == "\\" && j + 1 < end { j += 1; ch = u[j] } else if !sawSep && (ch == "/" || ch == "#" || ch == "^") { sawSep = true; j += 1; continue }
                        if sawSep { den.append(ch) } else { num.append(ch) }
                        j += 1
                    }
                    let a = String(num).trimmingCharacters(in: .whitespaces), b = String(den).trimmingCharacters(in: .whitespaces)
                    out.append(contentsOf: (b.isEmpty ? a : (a.isEmpty ? b : a + "/" + b)).unicodeScalars)
                    i = end
                case "f", "F", "H", "h", "W", "w", "Q", "q", "T", "t", "C", "c", "A", "a", "p":
                    i = skipToSemicolon(i + 2)
                default:
                    // Unknown escape: drop the backslash, keep the character.
                    out.append(k); i += 2
                }
            case "{", "}":
                i += 1
            case "^":
                if i + 1 < n {
                    let k = u[i + 1]
                    if k == "I" { out.append("\t"); i += 2; continue }
                    if k == "J" || k == "M" { out.append("\n"); i += 2; continue }
                    if k == " " { out.append("^"); i += 2; continue }
                }
                out.append(c); i += 1
            default:
                out.append(c); i += 1
            }
        }
        return decodeControlCodes(String(out))
    }
}
