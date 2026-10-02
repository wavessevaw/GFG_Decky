import SwiftUI

struct AboutView: View {
    @EnvironmentObject var loc: Localizer
    @AppStorage("ssmt.showSplash") private var showSplash = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandMark(variant: .full, height: 64)
            Text("SSMT · SoundSolution Multi Tool").font(Theme.heading(16))
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"))")
                .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            Text(loc.t("about.text")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(loc.t("about.splash"), isOn: $showSplash)
        }
        .padding(18)
        .frame(width: 340)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
