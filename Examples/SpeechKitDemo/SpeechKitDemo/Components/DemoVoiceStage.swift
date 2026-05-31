import SwiftUI

/// The centered title and microphone orb shared by the realtime and recorded-upload samples.
struct DemoVoiceStage: View {
    let title: String
    let providerTitle: String
    let iconName: String
    let voiceLevel: Double
    let voiceState: DemoVoiceState

    private var orbTint: Color {
        switch voiceState {
        case .active:
            return .cyan.opacity(0.18)
        case .preview:
            return .mint.opacity(0.14 + min(voiceLevel, 1) * 0.10)
        case .idle:
            return .white.opacity(0.10)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            Spacer(minLength: 0)
            voiceOrb
            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .padding(.horizontal, 20)
        .padding(.bottom, 138)
    }

    /// Displays the active workflow and provider without changing the unified screen structure.
    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(providerTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }

    /// Shows the current microphone action and passive/active input state.
    private var voiceOrb: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(voiceState == .active ? 0.16 : voiceState == .preview ? 0.12 : 0.08))
                .frame(width: 112, height: 112)

            Image(systemName: iconName)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .speed(0.45), value: voiceState != .idle && voiceLevel > 0.24)
        }
        .scaleEffect(voiceState == .preview ? 1 + min(voiceLevel, 0.7) * 0.035 : 1)
        .glassButtonProminence(tint: orbTint, cornerRadius: 56)
        .animation(.smooth(duration: 0.28), value: voiceLevel)
        .animation(.smooth(duration: 0.22), value: voiceState)
        .accessibilityHidden(true)
    }
}
