import SwiftUI

/// Shared Liquid Glass helpers used by the demo's optional visual chrome.
extension View {
    /// Applies a panel surface that uses Liquid Glass on iOS 26 and material fallback elsewhere.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(.white.opacity(0.12)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Applies the interactive glass treatment used by primary demo controls.
    @ViewBuilder
    func glassButtonProminence(tint: Color, cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Applies a platform-appropriate prominent button style for action rows.
    @ViewBuilder
    func glassActionStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Applies a platform-appropriate toolbar button style.
    @ViewBuilder
    func glassToolbarButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
