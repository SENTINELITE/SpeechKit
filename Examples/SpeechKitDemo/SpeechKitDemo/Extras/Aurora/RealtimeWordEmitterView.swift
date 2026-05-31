import SwiftUI

/// An optional transcript flourish that emits new realtime words around the microphone orb.
struct RealtimeWordEmitterView: View {
    let transcript: String
    let isActive: Bool
    let level: Double
    let resetID: UUID

    @State private var emittedWords: [EmittedWord] = []
    @State private var emittedTokenCount = 0

    private let fonts: [Font] = [
        .title2.weight(.semibold),
        .title3.weight(.semibold),
        .headline,
        .body.weight(.semibold),
        .callout.weight(.semibold)
    ]

    private let accents: [Color] = [
        .cyan,
        .mint,
        .blue,
        .purple,
        .pink
    ]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.52)
            let maxDistance = max(180, min(proxy.size.width, proxy.size.height) * 0.43)

            ZStack {
                ForEach(emittedWords) { word in
                    let distance = word.progress * maxDistance * word.distanceScale
                    let x = center.x + cos(word.angle) * distance
                    let y = center.y + sin(word.angle) * distance
                    let opacity = opacity(for: word.progress)
                    let scale = scale(for: word.progress)
                    let rotation = word.initialRotation + Double(word.progress) * 4

                    RealtimeWordBubble(text: word.text, font: word.font, accent: word.accent)
                        .opacity(opacity)
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(rotation))
                        .position(x: x, y: y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            emittedTokenCount = tokens(from: transcript).count
        }
        .onChange(of: transcript) { _, newTranscript in
            emitNewWords(from: newTranscript)
        }
        .onChange(of: isActive) { _, active in
            if !active {
                emittedTokenCount = tokens(from: transcript).count
            }
        }
        .onChange(of: resetID) { _, _ in
            emittedWords.removeAll()
            emittedTokenCount = tokens(from: transcript).count
        }
    }

    /// Emits only the new words appended since the last transcript update.
    private func emitNewWords(from newTranscript: String) {
        let currentTokens = tokens(from: newTranscript)

        guard isActive else {
            emittedTokenCount = currentTokens.count
            return
        }

        guard currentTokens.count >= emittedTokenCount else {
            emittedTokenCount = currentTokens.count
            return
        }

        let newTokens = Array(currentTokens.dropFirst(emittedTokenCount))
        emittedTokenCount = currentTokens.count

        guard !newTokens.isEmpty else { return }

        for token in newTokens.suffix(8) {
            emit(token)
        }
    }

    /// Adds a single animated word bubble and removes it after its lifetime ends.
    private func emit(_ token: String) {
        let clampedLevel = min(max(level, 0), 1)
        let word = EmittedWord(
            text: token,
            angle: Double.random(in: 0...(2 * .pi)),
            distanceScale: CGFloat(Double.random(in: 0.72...1.06) + clampedLevel * 0.12),
            font: fonts.randomElement() ?? .body.weight(.semibold),
            accent: accents.randomElement() ?? .cyan,
            initialRotation: Double.random(in: -4...4),
            lifetimeScale: Double.random(in: 0.92...1.24)
        )

        emittedWords.append(word)

        withAnimation(.spring(response: 3.8 * word.lifetimeScale, dampingFraction: 0.9)) {
            if let index = emittedWords.firstIndex(where: { $0.id == word.id }) {
                emittedWords[index].progress = 1.12
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.8 * word.lifetimeScale))
            emittedWords.removeAll { $0.id == word.id }
        }
    }

    /// Maps animation progress to fade-out opacity.
    private func opacity(for progress: CGFloat) -> Double {
        let fadeStart: CGFloat = 0.58
        if progress < fadeStart {
            return 0.92
        }
        return Double(max(0, 0.92 * (1 - ((progress - fadeStart) / (1 - fadeStart)))))
    }

    /// Maps animation progress to a slight emerge-and-taper scale curve.
    private func scale(for progress: CGFloat) -> CGFloat {
        let emerge = min(1, progress * 4)
        let taper = max(0.72, 1 - progress * 0.24)
        return (0.72 + emerge * 0.28) * taper
    }

    /// Splits transcript text into stable display tokens.
    private func tokens(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { token in
                token.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}

/// The transient bubble used by the realtime word-emitter extra.
private struct RealtimeWordBubble: View {
    let text: String
    let font: Font
    let accent: Color

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, accent.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(.black.opacity(0.34))

                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.72),
                                .white.opacity(0.24),
                                accent.opacity(0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: accent.opacity(0.28), radius: 12, x: 0, y: 0)
            .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 4)
    }
}

/// A single animated word produced from realtime transcript deltas.
private struct EmittedWord: Identifiable {
    let id = UUID()
    let text: String
    let angle: Double
    let distanceScale: CGFloat
    let font: Font
    let accent: Color
    let initialRotation: Double
    let lifetimeScale: Double
    var progress: CGFloat = 0
}
