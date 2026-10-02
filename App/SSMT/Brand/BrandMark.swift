import AppKit
import SwiftUI

/// Brand logo slot. Uses ONLY the files supplied by the brand owner (Resources/Brand,
/// asset names "BrandLogoFull" and "BrandMark"). The logo is never redrawn in code:
/// until the files are added, a neutral text placeholder is shown instead.
struct BrandMark: View {
    enum Variant { case full, compact }
    var variant: Variant = .compact
    var height: CGFloat = 22

    var body: some View {
        if let image = NSImage(named: variant == .full ? "BrandLogoFull" : "BrandMark")
            ?? (variant == .compact ? NSImage(named: "BrandLogoFull") : nil) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            // Placeholder: plain product name, not an imitation of the logo.
            Text("SSMT")
                .font(Theme.heading(height * 0.8))

                .foregroundStyle(Color.white)
                .frame(height: height)
        }
    }
}
