import AVFoundation
import Testing
@testable import Loop_Sense

struct ClipGainTests {
    @Test func quietClipIsBoostedUpToTheMaximum() {
        // A clip at -60 dBFS RMS, well above a -80 dBFS background, with a -45 dBFS peak.
        #expect(ClipGain.boost(rms: -60, peak: -45, background: -80) == 30)
    }

    @Test func moderateClipIsBroughtToTheTarget() {
        #expect(ClipGain.boost(rms: -35, peak: -25, background: -70) == 15)
    }

    @Test func loudClipIsNotTurnedDown() {
        #expect(ClipGain.boost(rms: -12, peak: -2, background: -60) == 0)
    }

    @Test func clipCloseToBackgroundIsCappedToAvoidHiss() {
        // Only 3 dB above the background: mostly room noise, so at most 12 dB.
        #expect(ClipGain.boost(rms: -63, peak: -50, background: -66) == ClipGain.hissBoost)
    }

    @Test func loudPeakLimitsTheBoost() {
        // A quiet clip with one sharp bang at -6 dBFS: boost stops where the limiter would squash it.
        #expect(ClipGain.boost(rms: -50, peak: -6, background: -80) == 15)
    }

    @Test func noBackgroundStillBoosts() {
        #expect(ClipGain.boost(rms: -45, peak: -35, background: nil) == 25)
    }

    @Test func limiterLeavesQuietSamplesAlone() {
        for x: Float in [0, 0.3, -0.5, 0.7] {
            #expect(ClipGain.limit(x) == x)
        }
    }

    @Test func limiterNeverLetsPeaksPastFullScale() {
        // Huge inputs round to exactly 1.0 in Float, which is full scale, not clipping.
        for x: Float in [0.71, 0.9, 1.0, 2.0, 10.0, -3.0] {
            let y = ClipGain.limit(x)
            #expect(abs(y) <= 1.0, "\(x) became \(y)")
            #expect(abs(y) >= ClipGain.limiterThreshold)
            #expect((y < 0) == (x < 0))
        }
    }

    @Test func limiterIsSmoothAndRising() {
        let xs = stride(from: Float(0), through: 5, by: 0.01).map { $0 }
        let ys = xs.map(ClipGain.limit)
        #expect(zip(ys, ys.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func applyBoostsAndLimitsABuffer() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let data = try #require(buffer.floatChannelData?[0])
        data[0] = 0.001; data[1] = -0.01; data[2] = 0.05; data[3] = 0.5
        ClipGain.apply(gainDB: 30, to: buffer)
        #expect(abs(data[0] - 0.0316) < 0.001)                // ×31.6
        #expect(abs(data[1] + 0.316) < 0.001)
        #expect(data[2] > 0.7 && data[2] < 1)                 // 1.58 eased by the limiter
        #expect(data[3] > 0.99 && data[3] <= 1)               // 15.8 held at full scale, not beyond
    }
}
