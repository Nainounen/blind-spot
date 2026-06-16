import SwiftUI
import AppKit

/// Renders a provider logo from the asset catalog (Bundle.module).
/// Falls back to an SF Symbol if the SVG hasn't been added yet.
struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 24
    var foregroundColor: Color = .primary

    var body: some View {
        if Bundle.module.image(forResource: provider.logoImageName) != nil {
            Image(provider.logoImageName, bundle: Bundle.module)
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
