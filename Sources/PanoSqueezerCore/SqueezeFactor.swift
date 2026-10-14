import Foundation

public enum FactorError: Error, Equatable, CustomStringConvertible, Sendable {
    case empty
    case invalidFormat
    case tooManyDecimals
    case outOfRange

    public var description: String {
        switch self {
        case .empty: return "Enter a squeeze factor."
        case .invalidFormat: return "Use a number like 1.33 or 1,5."
        case .tooManyDecimals: return "Use at most 2 decimal places."
        case .outOfRange: return "Allowed range is 1.01 to 4.00."
        }
    }
}

/// A squeeze factor with at most two decimals, stored exactly as hundredths (1.33 → 133).
/// Stored as a reduced fraction in the DNG: 1.33 → 133/100, 1.5 → 3/2, 2.0 → 2/1.
public struct SqueezeFactor: Hashable, Sendable, Codable {
    public let hundredths: Int

    public static let minHundredths = 101
    public static let maxHundredths = 400
    public static let presets: [SqueezeFactor] = [125, 133, 150, 160, 180, 200].map { SqueezeFactor(uncheckedHundredths: $0) }
    public static let standard = SqueezeFactor(uncheckedHundredths: 133)

    private init(uncheckedHundredths: Int) { hundredths = uncheckedHundredths }

    public init(hundredths: Int) throws {
        guard (Self.minHundredths...Self.maxHundredths).contains(hundredths) else { throw FactorError.outOfRange }
        self.hundredths = hundredths
    }

    /// Parses strings like "1.33", "1,5", "2", "1.5x". Never goes through floating point.
    public init(parsing input: String) throws {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("x") || s.hasSuffix("×") || s.hasSuffix("X") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw FactorError.empty }
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              let intPart = parts.first, !intPart.isEmpty, intPart.count <= 3,
              intPart.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw FactorError.invalidFormat }
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw FactorError.invalidFormat }
        if parts.count == 2 && fraction.isEmpty { throw FactorError.invalidFormat }
        guard fraction.count <= 2 else { throw FactorError.tooManyDecimals }
        while fraction.count < 2 { fraction += "0" }
        try self.init(hundredths: Int(intPart)! * 100 + Int(fraction)!)
    }

    /// Reduced fraction (numerator, denominator).
    public var fraction: (numerator: UInt32, denominator: UInt32) {
        let g = gcd(hundredths, 100)
        return (UInt32(hundredths / g), UInt32(100 / g))
    }

    public var rational: Rational { Rational(fraction.numerator, fraction.denominator) }

    public var value: Double { Double(hundredths) / 100 }

    /// "1.33", "1.5", "2.0" — used in labels and folder names.
    public var label: String {
        let whole = hundredths / 100, rest = hundredths % 100
        if rest == 0 { return "\(whole).0" }
        if rest % 10 == 0 { return "\(whole).\(rest / 10)" }
        return "\(whole).\(rest < 10 ? "0" : "")\(rest)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

public enum SqueezeDirection: String, Sendable, Codable, CaseIterable {
    case horizontal
    case vertical
}

public struct DesqueezeSettings: Sendable, Equatable {
    public var factor: SqueezeFactor
    public var direction: SqueezeDirection

    public init(factor: SqueezeFactor, direction: SqueezeDirection) {
        self.factor = factor
        self.direction = direction
    }

    /// DefaultScale value [horizontal, vertical]: horizontal (f, 1), vertical (1, f).
    public var defaultScale: [Rational] {
        switch direction {
        case .horizontal: return [factor.rational, Rational(1, 1)]
        case .vertical: return [Rational(1, 1), factor.rational]
        }
    }

    /// "Desqueezed 1.33x" or "Desqueezed 1.33x vertical".
    public var outputFolderName: String {
        "Desqueezed \(factor.label)x" + (direction == .vertical ? " vertical" : "")
    }

    public static let outputFolderPrefix = "Desqueezed "
}
