import SpeechKit
import SwiftUI

/// A focused sample for SpeechKit speech-to-speech conversations with OpenAI GPT-Live.
///
/// GPT-Live bills per second of streamed audio, so this view ends the session as
/// soon as it leaves the hierarchy or the app moves to the background.
struct ConversationView: View {
    @Environment(\.speechService) private var speech
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var configuration: DemoConfiguration
    let inputPreview: DemoInputPreviewMonitor
    @Binding var transcriptSheetText: String
    @Binding var isTranscriptPresented: Bool

    @State private var controlErrorMessage: String?

    private var isAudioActive: Bool {
        speech.conversationState.isWorking
    }

    private var voiceLevel: Double {
        isAudioActive ? speech.conversationInputLevel : inputPreview.currentLevel
    }

    private var voiceState: DemoVoiceState {
        if isAudioActive {
            return .active
        }
        if inputPreview.isPreviewing {
            return .preview
        }
        return .idle
    }

    private var hasConversationKey: Bool {
        configuration.hasConversationAPIKey
    }

    private var providerTitle: String {
        "OpenAI · \(OpenAILiveModelID.gptLive1.rawValue) · \(configuration.resolvedOpenAILiveVoice.rawValue)"
    }

    private var microphoneIconName: String {
        if speech.isConversationInputMuted {
            return "mic.slash.fill"
        }
        return isAudioActive ? "waveform.circle.fill" : "bubble.left.and.bubble.right.fill"
    }

    private var primaryControlTitle: String {
        if !hasConversationKey && !isAudioActive {
            return "API Key Required"
        }
        return isAudioActive ? "End Conversation" : "Start Conversation"
    }

    private var activeErrorMessage: String? {
        if !hasConversationKey && !isAudioActive {
            return configuration.missingConversationAPIKeyMessage
        }
        return controlErrorMessage ?? speech.conversationLastError?.localizedDescription
    }

    /// The newest in-progress text, which mirrors whichever transcript entry is still open.
    private var partialLine: String? {
        let assistant = speech.partialAssistantTranscriptText
        if !assistant.isEmpty {
            return "Assistant: \(assistant)"
        }
        let user = speech.partialUserTranscriptText
        return user.isEmpty ? nil : "You: \(user)"
    }

    private var usageText: String {
        let total = Int(speech.conversationUsageSeconds.rounded())
        let seconds = total % 60
        let padding = seconds < 10 ? "0" : ""
        return "\(total / 60):\(padding)\(seconds) billed"
    }

    private var expiryText: String? {
        guard let expiresAt = speech.conversationExpiresAt else { return nil }
        return "expires \(expiresAt.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        ZStack {
            DemoBackground(level: voiceLevel, state: voiceState)

            VStack(spacing: 14) {
                DemoVoiceStage(
                    title: "Speech-to-speech conversation",
                    providerTitle: providerTitle,
                    iconName: microphoneIconName,
                    voiceLevel: voiceLevel,
                    voiceState: voiceState
                )
                .padding(.bottom, -118)

                ConversationAssistantMeter(
                    level: speech.conversationOutputLevel,
                    isSpeaking: speech.assistantIsSpeaking
                )

                transcriptPanel

                statusPanel

                sessionControls
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 108)

            DemoControlDock(
                primaryTitle: primaryControlTitle,
                primaryIcon: isAudioActive ? "stop.circle.fill" : "mic.fill",
                transcript: fullTranscriptText,
                hasExportableRecording: false,
                isRealtimeMode: true,
                isAudioActive: isAudioActive,
                errorMessage: activeErrorMessage,
                isPrimaryDisabled: !isAudioActive && !hasConversationKey,
                primaryAction: {
                    Task {
                        await handleConversationTap()
                    }
                },
                showTranscript: showTranscript,
                saveRecording: {}
            )
        }
        .onDisappear {
            Task {
                await speech.endConversation()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .background else { return }
            Task {
                await speech.endConversation()
            }
        }
    }

    /// The interleaved user and assistant rows for the running session.
    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if speech.conversationTranscript.isEmpty {
                        Text("Start the conversation and talk. Transcript fragments from both speakers appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }

                    ForEach(speech.conversationTranscript) { entry in
                        ConversationTranscriptRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 250)
            .glassSurface(cornerRadius: 18)
            .onChange(of: speech.conversationTranscript.last?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }

    /// The live session status, billed seconds, expiry, and in-progress text.
    private var statusPanel: some View {
        VStack(spacing: 4) {
            Text(statusLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let partialLine {
                Text(partialLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: String {
        var parts = [speech.conversationState.title, usageText]
        if let expiryText {
            parts.append(expiryText)
        }
        return parts.joined(separator: " · ")
    }

    /// Mute and barge-in commands that only make sense while a session is open.
    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: muteBinding) {
                Label(
                    speech.isConversationInputMuted ? "Unmute" : "Mute",
                    systemImage: speech.isConversationInputMuted ? "mic.slash.fill" : "mic.fill"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(speech.isConversationInputMuted ? Color.orange : Color.white)
            .glassButtonProminence(
                tint: speech.isConversationInputMuted ? .orange.opacity(0.20) : .white.opacity(0.10),
                cornerRadius: 18
            )
            .disabled(!speech.conversationState.isActive)

            if speech.assistantIsSpeaking {
                Button {
                    speech.flushAssistantAudio()
                } label: {
                    Label("Flush", systemImage: "speaker.slash.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassButtonProminence(tint: .cyan.opacity(0.20), cornerRadius: 18)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Stop assistant audio")
            }
        }
        .animation(.smooth(duration: 0.22), value: speech.assistantIsSpeaking)
        .opacity(isAudioActive ? 1 : 0)
        .allowsHitTesting(isAudioActive)
    }

    /// Bridges the read-only mute state onto the asynchronous mute commands.
    private var muteBinding: Binding<Bool> {
        Binding(
            get: { speech.isConversationInputMuted },
            set: { newValue in
                Task {
                    await setInputMuted(newValue)
                }
            }
        )
    }

    /// The whole session rendered as speaker-prefixed lines for the shared transcript sheet.
    private var fullTranscriptText: String {
        speech.conversationTranscript
            .map { entry in
                let prefix = entry.role == .user ? "You:" : "Assistant:"
                return "\(prefix) \(entry.displayText)"
            }
            .joined(separator: "\n")
    }

    /// Starts or ends the GPT-Live session while keeping the passive meter out of the audio session.
    private func handleConversationTap() async {
        controlErrorMessage = nil

        if isAudioActive {
            await speech.endConversation()
            inputPreview.startIfAuthorized()
            return
        }

        guard hasConversationKey else { return }
        configuration.apply(to: speech)
        inputPreview.stop(deactivateAudioSession: false)
        speech.clearConversationTranscript()
        await speech.startConversation(provider: .openAI)
    }

    /// Applies a mute change and surfaces provider rejections in the dock error line.
    private func setInputMuted(_ isMuted: Bool) async {
        do {
            if isMuted {
                try await speech.muteConversationInput()
            } else {
                try await speech.unmuteConversationInput()
            }
            controlErrorMessage = nil
        } catch {
            controlErrorMessage = error.localizedDescription
        }
    }

    /// Presents the speaker-prefixed conversation in the shared transcript sheet.
    private func showTranscript() {
        transcriptSheetText = fullTranscriptText
        isTranscriptPresented = true
    }
}

/// A single interleaved conversation row, aligned by speaker.
private struct ConversationTranscriptRow: View {
    let entry: SpeechConversationTranscriptEntry

    private var isUser: Bool {
        entry.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 32)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isUser ? Color.cyan : Color.secondary)

                Text(entry.isOpen ? "\(entry.displayText)…" : entry.displayText)
                    .font(.callout)
                    .foregroundStyle(isUser ? Color.primary : Color.secondary)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isUser ? Color.cyan.opacity(0.16) : Color.white.opacity(0.08))
            )
            .opacity(entry.isOpen ? 0.78 : 1)

            if !isUser {
                Spacer(minLength: 32)
            }
        }
        .animation(.smooth(duration: 0.2), value: entry.isOpen)
    }
}

/// A compact ring that shows how loudly the assistant is speaking back.
private struct ConversationAssistantMeter: View {
    let level: Double
    let isSpeaking: Bool

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: max(clampedLevel, 0.02))
                    .stroke(
                        isSpeaking ? Color.cyan : Color.white.opacity(0.35),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSpeaking ? Color.cyan : Color.secondary)
            }
            .frame(width: 30, height: 30)

            Text(isSpeaking ? "Assistant speaking" : "Assistant idle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .animation(.smooth(duration: 0.22), value: clampedLevel)
        .animation(.smooth(duration: 0.22), value: isSpeaking)
        .accessibilityLabel("Assistant output level")
    }
}
