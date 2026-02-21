import Foundation

// Provides Bundle.module for LayoutConfigLoader.
// When running from an .app bundle, Bundle.main.url(forResource:) looks in
// Contents/Resources/ — which is where the build script copies Layouts.json.
// If the file is absent, LayoutConfigLoader.fallback() returns the full
// hardcoded EN↔RU mapping, so the app remains functional either way.
extension Bundle {
    static let module: Bundle = .main
}
