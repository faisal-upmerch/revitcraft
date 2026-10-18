import Foundation

/// Grid names in sequence (BL-SCHED, ARCUS-089): the next grid continues the most recently created name — numbers
/// count up ("9" → "10"), letters run A–Z skipping I and O and then AA, AB… ("Z" → "AA"), and a trailing number
/// after a prefix counts up ("A1" → "A2", "G-09" → "G-10"). The result never repeats an existing name.
public enum GridNaming {
    public static func next(after names: [String]) -> String {
        let taken = Set(names)
        guard let last = names.last(where: { !$0.isEmpty }) else { return "1" }
        var candidate = increment(last)
        var guardCount = 0
        while taken.contains(candidate) && guardCount < 10_000 { candidate = increment(candidate); guardCount += 1 }
        return candidate
    }

    /// The name after `name` (see the type's description); names with no letters or digits at the end get "1" appended.
    public static func increment(_ name: String) -> String {
        if let n = Int(name) { return String(n + 1) }
        if !name.isEmpty, name.allSatisfy({ $0.isASCII && $0.isUppercase }) { return nextLetters(name) }
        if !name.isEmpty, name.allSatisfy({ $0.isASCII && $0.isLowercase }) { return nextLetters(name.uppercased()).lowercased() }
        // Prefix + trailing digits: keep zero padding.
        let digits = String(name.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        if !digits.isEmpty, let n = Int(digits) {
            let next = String(n + 1)
            let padded = next.count < digits.count ? String(repeating: "0", count: digits.count - next.count) + next : next
            return String(name.dropLast(digits.count)) + padded
        }
        // Prefix + trailing capital letter ("1A" → "1B").
        if let ch = name.last, ch.isASCII, ch.isUppercase { return String(name.dropLast()) + nextLetters(String(ch)) }
        return name + "1"
    }

    /// Spreadsheet-style uppercase sequence without I and O: A, B, … H, J, … N, P, … Z, AA, AB, …
    static func nextLetters(_ s: String) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        var chars = Array(s)
        var i = chars.count - 1
        while i >= 0 {
            let c = chars[i]
            // Letters outside the sequence (I, O) step to the following letter.
            let idx = alphabet.firstIndex(of: c) ?? alphabet.firstIndex { $0 > c }.map { $0 - 1 } ?? alphabet.count - 1
            if idx + 1 < alphabet.count { chars[i] = alphabet[idx + 1]; return String(chars) }
            chars[i] = alphabet[0]
            i -= 1
        }
        return String(alphabet[0]) + String(chars)
    }
}
