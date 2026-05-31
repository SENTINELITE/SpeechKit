import SwiftUI

/// The bottom command dock shared by the demo workflows.
struct DemoControlDock: View {
    let primaryTitle: String
    let primaryIcon: String
    let transcript: String
    let hasExportableRecording: Bool
    let isRealtimeMode: Bool
    let isAudioActive: Bool
    let errorMessage: String?
    let isPrimaryDisabled: Bool
    let primaryAction: () -> Void
    let showTranscript: () -> Void
    let saveRecording: () -> Void

    private var canShowTranscript: Bool {
        !transcript.isEmpty
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassSurface(cornerRadius: 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 16) {
                    transcriptButton

                    if hasExportableRecording {
                        iconButton(
                            systemImage: primaryIcon,
                            accessibilityLabel: primaryTitle,
                            tint: isAudioActive ? .cyan.opacity(0.20) : .white.opacity(0.10),
                            isDisabled: isPrimaryDisabled,
                            action: primaryAction
                        )
                        .transition(.scale.combined(with: .opacity))

                        iconButton(
                            systemImage: "square.and.arrow.down",
                            accessibilityLabel: "Save recording",
                            tint: .white.opacity(0.10),
                            isDisabled: false,
                            action: saveRecording
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.86)))
                    } else {
                        primaryButton
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hasExportableRecording)
            .animation(.smooth(duration: 0.22), value: errorMessage)
        }
    }

    /// Opens the transcript sheet and marks realtime sessions with a live indicator.
    private var transcriptButton: some View {
        Button(action: showTranscript) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(canShowTranscript ? .cyan : .secondary)
                    .frame(width: 62, height: 62)

                if isRealtimeMode && isAudioActive {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.65), lineWidth: 1)
                        }
                        .offset(x: -10, y: 11)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassButtonProminence(
            tint: canShowTranscript ? .cyan.opacity(0.18) : .white.opacity(0.10),
            cornerRadius: 31
        )
        .disabled(!canShowTranscript)
        .accessibilityLabel("Show transcript")
    }

    /// The expanded primary workflow command used before a recording is available to export.
    private var primaryButton: some View {
        Button(action: primaryAction) {
            Label(primaryTitle, systemImage: primaryIcon)
                .font(.headline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 190)
                .frame(height: 62)
                .padding(.horizontal, 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassButtonProminence(
            tint: isAudioActive ? .cyan.opacity(0.20) : .white.opacity(0.10),
            cornerRadius: 31
        )
        .disabled(isPrimaryDisabled)
        .accessibilityLabel(primaryTitle)
        .transition(.scale.combined(with: .opacity))
    }

    /// Creates the compact circular buttons used once the dock has multiple actions.
    private func iconButton(
        systemImage: String,
        accessibilityLabel: String,
        tint: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassButtonProminence(tint: tint, cornerRadius: 31)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
