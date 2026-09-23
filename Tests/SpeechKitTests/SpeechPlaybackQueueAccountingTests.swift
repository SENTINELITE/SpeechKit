import Foundation
import Testing
@testable import SpeechKit

@Suite("Duplex playback queue accounting")
struct SpeechPlaybackQueueAccountingTests {
    @Test("A fresh queue is empty")
    func freshQueueIsEmpty() {
        let accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000)

        #expect(accounting.pendingBytes == 0)
        #expect(accounting.pendingSeconds == 0)
        #expect(accounting.isPending == false)
        #expect(accounting.bytesPerSecond == 48000)
    }

    @Test("Scheduling and playing back balance out")
    func scheduleAndPlayBalance() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000)
        accounting.schedule(byteCount: 4800)
        accounting.schedule(byteCount: 2400)

        #expect(accounting.pendingBytes == 7200)
        #expect(accounting.isPending)

        accounting.didPlay(byteCount: 4800)
        #expect(accounting.pendingBytes == 2400)

        accounting.didPlay(byteCount: 2400)
        #expect(accounting.pendingBytes == 0)
        #expect(accounting.isPending == false)
    }

    @Test("Pending seconds convert bytes at the session sample rate")
    func pendingSecondsAt24kHz() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000)
        accounting.schedule(byteCount: 4800)

        #expect(abs(accounting.pendingSeconds - 0.1) < 0.000001)

        var lowRate = SpeechPlaybackQueueAccounting(sampleRate: 16000)
        lowRate.schedule(byteCount: 4800)

        #expect(abs(lowRate.pendingSeconds - 0.15) < 0.000001)
    }

    @Test("Playing back more than was scheduled clamps at zero")
    func didPlayClampsAtZero() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000)
        accounting.schedule(byteCount: 960)
        accounting.didPlay(byteCount: 4800)

        #expect(accounting.pendingBytes == 0)
        #expect(accounting.pendingSeconds == 0)
    }

    @Test("Non-positive counts are ignored")
    func nonPositiveCountsAreIgnored() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000, pendingBytes: 960)
        accounting.schedule(byteCount: 0)
        accounting.schedule(byteCount: -480)
        accounting.didPlay(byteCount: 0)
        accounting.didPlay(byteCount: -480)

        #expect(accounting.pendingBytes == 960)
    }

    @Test("A negative starting count is treated as empty")
    func negativeStartingCountIsEmpty() {
        let accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000, pendingBytes: -10)

        #expect(accounting.pendingBytes == 0)
    }

    @Test("Resetting drops everything that was queued")
    func resetDropsTheQueue() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 24000)
        accounting.schedule(byteCount: 48000)
        accounting.reset()

        #expect(accounting.pendingBytes == 0)
        #expect(accounting.pendingSeconds == 0)
        #expect(accounting.isPending == false)
    }

    @Test("Pending seconds are zero when the sample rate is unusable")
    func pendingSecondsWithoutASampleRate() {
        var accounting = SpeechPlaybackQueueAccounting(sampleRate: 0)
        accounting.schedule(byteCount: 4800)

        #expect(accounting.pendingBytes == 4800)
        #expect(accounting.pendingSeconds == 0)
    }

    @Test("Frame alignment drops a trailing odd byte")
    func frameAlignmentDropsOddByte() {
        #expect(SpeechPlaybackQueueAccounting.frameAlignedByteCount(4801) == 4800)
        #expect(SpeechPlaybackQueueAccounting.frameAlignedByteCount(4800) == 4800)
        #expect(SpeechPlaybackQueueAccounting.frameAlignedByteCount(1) == 0)
        #expect(SpeechPlaybackQueueAccounting.frameAlignedByteCount(0) == 0)
        #expect(SpeechPlaybackQueueAccounting.frameAlignedByteCount(-3) == 0)
    }
}
