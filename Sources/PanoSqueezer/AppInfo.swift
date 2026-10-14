#if os(macOS)
import Foundation

enum AppInfo {
    static let name = "pano-squeezer"
    static let gitHubURL = URL(string: "https://github.com/lucaspalmtrees/pano-squeezer")!
    /// Donation link (Ko-fi / Buy Me a Coffee / GitHub Sponsors). nil hides all donation UI.
    static let donationURL: URL? = nil

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }
}
#endif
