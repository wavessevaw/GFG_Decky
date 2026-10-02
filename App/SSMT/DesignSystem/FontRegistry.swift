import CoreText
import Foundation

/// Registers the fonts bundled in Resources/Fonts for this process.
enum FontRegistry {
    static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        var ok = 0
        for url in urls {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { ok += 1 }
        }
        Theme.customFontsAvailable = ok >= 2
    }
}
