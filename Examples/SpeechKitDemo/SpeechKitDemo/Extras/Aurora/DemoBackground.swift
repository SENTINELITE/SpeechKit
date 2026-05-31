import Aurora
import SwiftUI

/// The optional Aurora-backed visual layer that reacts to the active microphone workflow.
struct DemoBackground: View {
    let level: Double
    let state: DemoVoiceState

    private var visualLevel: Double {
        pow(min(max(level, 0), 1), 0.78) * 0.46
    }

    private var glowSize: CGFloat {
        CGFloat(38 + visualLevel * 76)
    }

    private var borderWidth: CGFloat {
        CGFloat(5 + visualLevel * 7)
    }

    private var speed: Double {
        switch state {
        case .active:
            return 0.045 + visualLevel * 0.18
        case .preview:
            return 0.034 + visualLevel * 0.08
        case .idle:
            return 0.03
        }
    }

    private var palette: AuroraGlow.Palette {
        switch state {
        case .active:
            let amount = Float(min(max(visualLevel / 0.46, 0), 1))
            return .interpolated(from: .ocean, to: .cyberpunk, amount: amount)
        case .preview:
            let amount = Float(min(max(visualLevel / 0.46, 0), 1))
            return .interpolated(from: .ocean, to: .auroraPreview, amount: amount * 0.72)
        case .idle:
            return .ocean
        }
    }

    private var saturation: Double {
        switch state {
        case .active:
            return 1.05 + visualLevel * 0.55
        case .preview:
            return 0.96 + visualLevel * 0.28
        case .idle:
            return 0.9
        }
    }

    private var radialAccent: Color {
        switch state {
        case .active:
            return .cyan
        case .preview:
            return .mint
        case .idle:
            return .cyan
        }
    }

    private var radialPrimaryOpacity: Double {
        switch state {
        case .active:
            return 0.055 + visualLevel * 0.16
        case .preview:
            return 0.035 + visualLevel * 0.10
        case .idle:
            return 0.025
        }
    }

    private var radialSecondaryOpacity: Double {
        switch state {
        case .active:
            return 0.045 + visualLevel * 0.10
        case .preview:
            return 0.028 + visualLevel * 0.06
        case .idle:
            return 0.018
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.025, blue: 0.04),
                    Color(red: 0.035, green: 0.045, blue: 0.07),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                let cornerRadius = bezelCornerRadius(for: proxy.size)

                AuroraGlow(.standard)
                    .mood(.listening)
                    .palette(palette)
                    .glowSize(glowSize)
                    .borderWidth(borderWidth)
                    .speed(speed)
                    .cornerRadius(cornerRadius)
                    .ignoresSafeArea()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .saturation(saturation)
                    .animation(.smooth(duration: 1.25), value: level)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    radialAccent.opacity(radialPrimaryOpacity),
                    Color.white.opacity(radialSecondaryOpacity),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Keeps the Aurora bezel proportional across phone and iPad sizes.
    private func bezelCornerRadius(for size: CGSize) -> CGFloat {
        let shortestSide = min(size.width, size.height)
        let radius = shortestSide * 0.145
        return min(max(radius, 58), shortestSide > 600 ? 86 : 72)
    }
}

/// The small state model used by the visual extras to distinguish idle, preview, and active capture.
enum DemoVoiceState {
    case idle
    case preview
    case active
}

/// Demo-only palette helpers for interpolating Aurora colors as microphone input changes.
extension AuroraGlow.Palette {
    static let auroraPreview = Self(
        base: SIMD3<Float>(0.28, 0.92, 0.78),
        anchors: [
            SIMD3<Float>(0.20, 0.80, 0.68),
            SIMD3<Float>(0.45, 0.72, 1.00),
            SIMD3<Float>(0.64, 0.54, 1.00),
            SIMD3<Float>(0.24, 0.95, 0.58)
        ]
    )

    /// Blends two Aurora palettes by linearly interpolating their base and anchor colors.
    static func interpolated(from start: Self, to end: Self, amount: Float) -> Self {
        let clampedAmount = max(0, min(1, amount))
        let startAnchors = normalizedAnchors(start.anchors, fallback: Self.ocean.anchors)
        let endAnchors = normalizedAnchors(end.anchors, fallback: Self.ocean.anchors)

        return Self(
            base: interpolate(start.base, end.base, amount: clampedAmount),
            anchors: zip(startAnchors, endAnchors).map {
                interpolate($0, $1, amount: clampedAmount)
            }
        )
    }

    /// Aurora validates this at runtime, so keep interpolated palettes valid even if an upstream palette changes.
    private static func normalizedAnchors(_ anchors: [SIMD3<Float>], fallback: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let source = anchors.isEmpty ? fallback : anchors
        return (0..<4).map { index in
            source[index % source.count]
        }
    }

    /// Interpolates two SIMD colors for Aurora palette construction.
    private static func interpolate(_ start: SIMD3<Float>, _ end: SIMD3<Float>, amount: Float) -> SIMD3<Float> {
        start + (end - start) * amount
    }
}
