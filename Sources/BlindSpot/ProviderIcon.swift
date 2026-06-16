import SwiftUI
import AppKit

/// Renders a provider logo from the asset catalog, falling back to SF Symbols.
struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 24
    var foregroundColor: Color = .primary

    var body: some View {
        if resourcesBundle.image(forResource: provider.logoImageName) != nil {
            Image(provider.logoImageName, bundle: resourcesBundle)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(foregroundColor)
        } else {
            Image(systemName: provider.fallbackIcon)
                .font(.system(size: size * 0.75, weight: .light))
                .frame(width: size, height: size)
                .foregroundStyle(foregroundColor)
        }
    }
}

/// Finds the SPM resource bundle whether running from a .app (Contents/Resources/)
/// or directly from the build directory (debug). Falls back to Bundle.module.
private var resourcesBundle: Bundle {
    let bundleName = "BlindSpot_BlindSpot.bundle"
    // Release .app: bundle lives in Contents/Resources/
    if let url = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
       let b = Bundle(url: url) {
        return b
    }
    // Debug: bundle lives next to the executable in the build output directory
    return Bundle.module
}
