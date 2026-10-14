#if os(macOS)
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text(AppInfo.name).font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            Text("Lossless desqueeze for anamorphic DNG photos.\nSets the DNG DefaultScale tag – no pixels are changed.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("MIT License · Not affiliated with Adobe or Leica.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link(destination: AppInfo.gitHubURL) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                if let donation = AppInfo.donationURL {
                    Link(destination: donation) { Label("Support this project", systemImage: "cup.and.saucer") }
                }
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
    }
}
#endif
