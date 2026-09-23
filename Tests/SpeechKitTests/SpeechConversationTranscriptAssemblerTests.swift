import Foundation
import Testing
@testable import SpeechKit

/// One captured GPT-Live transcript fragment.
private struct ConversationFragment {
    let role: SpeechConversationRole
    let delta: String
    let start: Int
    let end: Int
}

/// The fragment sequence captured from gpt-live-1 on 2026-09-15, where the model
/// began answering before the user finished the question.
private let capturedFragments: [ConversationFragment] = [
    ConversationFragment(role: .user, delta: "Hello", start: 600, end: 800),
    ConversationFragment(role: .user, delta: " there", start: 1000, end: 1200),
    ConversationFragment(role: .user, delta: ". What is", start: 1400, end: 1600),
    ConversationFragment(role: .user, delta: " the", start: 1600, end: 1800),
    ConversationFragment(role: .user, delta: " capital", start: 2000, end: 2200),
    ConversationFragment(role: .user, delta: " of", start: 2200, end: 2400),
    ConversationFragment(role: .assistant, delta: "Paris.", start: 2600, end: 2800),
    ConversationFragment(role: .user, delta: " France", start: 2800, end: 3000),
    ConversationFragment(role: .user, delta: "?", start: 3000, end: 3200)
]

private func replayCapturedFragments(
    into assembler: inout SpeechConversationTranscriptAssembler
) -> [SpeechConversationTranscriptEntry] {
    var entries: [SpeechConversationTranscriptEntry] = []
    for fragment in capturedFragments {
        entries = assembler.append(
            role: fragment.role,
            delta: fragment.delta,
            startMilliseconds: fragment.start,
            endMilliseconds: fragment.end
        )
    }
    return entries
}

@Suite("Conversation transcript assembler")
struct SpeechConversationTranscriptAssemblerTests {
    @Test("A captured overlapping exchange groups into one entry per speaker")
    func capturedExchangeGroupsIntoOneEntryPerSpeaker() {
        var assembler = SpeechConversationTranscriptAssembler()
        let entries = replayCapturedFragments(into: &assembler)

        #expect(entries.count == 2)
        #expect(entries[0].role == .user)
        #expect(entries[0].text == "Hello there. What is the capital of France?")
        #expect(entries[0].startMilliseconds == 600)
        #expect(entries[0].endMilliseconds == 3200)
        #expect(entries[1].role == .assistant)
        #expect(entries[1].text == "Paris.")
        #expect(entries[1].startMilliseconds == 2600)
        #expect(entries[1].endMilliseconds == 2800)
        #expect(entries.map(\.provider) == [.openAI, .openAI])
        #expect(assembler.entries == entries)
    }

    @Test("An interruption leaves both rows open and growing")
    func interruptionLeavesBothRowsOpen() {
        var assembler = SpeechConversationTranscriptAssembler()
        let entries = replayCapturedFragments(into: &assembler)

        #expect(entries[0].isOpen)
        #expect(entries[1].isOpen)
        #expect(entries[0].text.hasSuffix(" France?"))
        #expect(entries[0].endMilliseconds > entries[1].startMilliseconds)
    }

    @Test("A silence longer than the turn gap opens a new entry")
    func silenceLongerThanTurnGapOpensNewEntry() {
        var assembler = SpeechConversationTranscriptAssembler()
        _ = replayCapturedFragments(into: &assembler)

        let entries = assembler.append(
            role: .user,
            delta: "Thanks",
            startMilliseconds: 3200 + 1201,
            endMilliseconds: 4600
        )

        #expect(entries.count == 3)
        #expect(entries[0].isOpen == false)
        #expect(entries[2].role == .user)
        #expect(entries[2].text == "Thanks")
        #expect(entries[2].startMilliseconds == 4401)
        #expect(entries[2].isOpen)
    }

    @Test("A silence exactly at the turn gap continues the same entry")
    func silenceAtTurnGapContinuesSameEntry() {
        var assembler = SpeechConversationTranscriptAssembler()
        _ = assembler.append(role: .user, delta: "Hello", startMilliseconds: 600, endMilliseconds: 800)

        let entries = assembler.append(
            role: .user,
            delta: " again",
            startMilliseconds: 2000,
            endMilliseconds: 2200
        )

        #expect(entries.count == 1)
        #expect(entries[0].text == "Hello again")
        #expect(entries[0].endMilliseconds == 2200)
    }

    @Test("A custom turn gap changes the grouping")
    func customTurnGapChangesGrouping() {
        var assembler = SpeechConversationTranscriptAssembler(turnGapMilliseconds: 100)
        _ = assembler.append(role: .assistant, delta: "Paris.", startMilliseconds: 2600, endMilliseconds: 2800)

        let entries = assembler.append(
            role: .assistant,
            delta: " The capital of France.",
            startMilliseconds: 3000,
            endMilliseconds: 3400
        )

        #expect(entries.count == 2)
        #expect(entries[0].text == "Paris.")
        #expect(entries[0].isOpen == false)
        #expect(entries[1].text == " The capital of France.")
    }

    @Test("Partial text reports the newest open entry per role")
    func partialTextReportsNewestOpenEntryPerRole() {
        var assembler = SpeechConversationTranscriptAssembler()
        #expect(assembler.partialText(for: .user).isEmpty)
        #expect(assembler.partialText(for: .assistant).isEmpty)

        _ = replayCapturedFragments(into: &assembler)
        #expect(assembler.partialText(for: .user) == "Hello there. What is the capital of France?")
        #expect(assembler.partialText(for: .assistant) == "Paris.")

        _ = assembler.append(role: .user, delta: " Thanks", startMilliseconds: 10_000, endMilliseconds: 10_400)
        #expect(assembler.partialText(for: .user) == "Thanks")
    }

    @Test("Closing open entries stops later fragments from extending them")
    func closingOpenEntriesStartsFreshEntries() {
        var assembler = SpeechConversationTranscriptAssembler()
        _ = replayCapturedFragments(into: &assembler)

        assembler.closeOpenEntries()
        #expect(assembler.entries.allSatisfy { $0.isOpen == false })
        #expect(assembler.partialText(for: .user).isEmpty)

        let entries = assembler.append(role: .user, delta: "Again", startMilliseconds: 3300, endMilliseconds: 3400)
        #expect(entries.count == 3)
        #expect(entries[2].text == "Again")
    }

    @Test("Reset clears every entry")
    func resetClearsEveryEntry() {
        var assembler = SpeechConversationTranscriptAssembler()
        _ = replayCapturedFragments(into: &assembler)

        assembler.reset()

        #expect(assembler.entries.isEmpty)
        #expect(assembler.partialText(for: .user).isEmpty)
        #expect(assembler.partialText(for: .assistant).isEmpty)

        let entries = assembler.append(role: .assistant, delta: "Hi", startMilliseconds: 0, endMilliseconds: 200)
        #expect(entries.count == 1)
        #expect(entries[0].text == "Hi")
    }

    @Test("Raw deltas concatenate without a separator and display text is trimmed")
    func rawDeltasConcatenateWithoutSeparator() {
        var assembler = SpeechConversationTranscriptAssembler()
        _ = assembler.append(role: .assistant, delta: " Paris", startMilliseconds: 0, endMilliseconds: 200)
        let entries = assembler.append(role: .assistant, delta: ". ", startMilliseconds: 200, endMilliseconds: 400)

        #expect(entries[0].text == " Paris. ")
        #expect(entries[0].displayText == "Paris.")
    }
}
