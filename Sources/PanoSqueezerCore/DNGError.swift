import Foundation

/// All errors the core can produce. Every error has a short, user-facing description.
public enum DNGError: Error, Equatable, CustomStringConvertible, Sendable {
    // Reading / structure
    case cannotOpen(String)
    case notTIFF
    case bigTIFF
    case fileTooLarge
    case truncated(String)
    case offsetOutOfBounds(String)
    case cycle
    case tooManyIFDs
    case tooManyEntries(Int)
    case noRawIFD
    case multipleRawIFDs(Int)
    // Desqueeze decisions
    case alreadyDesqueezed(String)
    case unexpectedDefaultScale
    case destinationExists
    // Writing
    case verificationFailed(String)
    case cancelled
    case io(String)

    public var description: String {
        switch self {
        case .cannotOpen(let s): return "cannot open file (\(s))"
        case .notTIFF: return "not a valid DNG/TIFF file"
        case .bigTIFF: return "BigTIFF is not supported"
        case .fileTooLarge: return "file is larger than 4 GB"
        case .truncated(let s): return "file is damaged or truncated (\(s))"
        case .offsetOutOfBounds(let s): return "file is damaged (offset out of bounds: \(s))"
        case .cycle: return "file is damaged (IFD cycle)"
        case .tooManyIFDs: return "file is damaged (too many IFDs)"
        case .tooManyEntries(let n): return "file is damaged (IFD with \(n) entries)"
        case .noRawIFD: return "no raw image found"
        case .multipleRawIFDs(let n): return "\(n) raw images found, expected exactly one"
        case .alreadyDesqueezed(let s): return "already desqueezed (\(s))"
        case .unexpectedDefaultScale: return "existing DefaultScale tag has an unexpected format"
        case .destinationExists: return "output file already exists"
        case .verificationFailed(let s): return "verification failed: \(s)"
        case .cancelled: return "cancelled"
        case .io(let s): return "write error: \(s)"
        }
    }

    /// Errors that mean "this file was deliberately not converted" (as opposed to a failure while writing).
    public var isSkip: Bool {
        switch self {
        case .verificationFailed, .cancelled, .io: return false
        default: return true
        }
    }
}
