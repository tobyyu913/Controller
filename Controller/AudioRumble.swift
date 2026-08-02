//
//  AudioRumble.swift
//  Controller
//
//  Taps the Mac's system audio and turns low-frequency energy into a rumble
//  level, so the phone buzzes with the bass of whatever is playing — no game
//  support required (unlike controller rumble, which the game has to send).
//
//  Uses ScreenCaptureKit audio capture, so it needs Screen Recording permission.
//

#if os(macOS)
import Foundation
import ScreenCaptureKit
import AVFoundation

@Observable
final class AudioRumble: NSObject, SCStreamDelegate, SCStreamOutput {
    /// Current bass level, 0...1. Read by the server and pushed to phones.
    private(set) var level: Double = 0
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    /// How strongly bass maps to rumble.
    var gain: Double = 1.0
    /// Level below which nothing is sent, so quiet passages stay still.
    var threshold: Double = 0.06

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "controller.audio", qos: .userInitiated)

    // One-pole low-pass state (keeps only the bass) and an envelope follower
    private var lpState: Double = 0
    private var envelope: Double = 0

    func start() {
        guard !isRunning else { return }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false
                )
                guard let display = content.displays.first else {
                    errorMessage = "No display to capture audio from"
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
                // Video is unavoidable in a stream; keep it tiny and slow.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

                let s = SCStream(filter: filter, configuration: config, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                try await s.startCapture()
                stream = s
                isRunning = true
                errorMessage = nil
            } catch {
                errorMessage = "Needs Screen Recording permission"
                isRunning = false
            }
        }
    }

    func stop() {
        let s = stream
        stream = nil
        isRunning = false
        level = 0
        Task { try? await s?.stopCapture() }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let samples = Self.monoSamples(from: sampleBuffer), !samples.isEmpty else { return }

        // One-pole low-pass ~120 Hz at 48 kHz, then RMS of what's left.
        // alpha = dt / (RC + dt); RC = 1 / (2*pi*fc)
        let alpha = 0.0155
        var sumSquares = 0.0
        for sample in samples {
            lpState += alpha * (Double(sample) - lpState)
            sumSquares += lpState * lpState
        }
        let rms = (sumSquares / Double(samples.count)).squareRoot()

        // Envelope follower: snap up on a hit, ease back down so each bass note
        // reads as a distinct thump instead of a constant buzz.
        let target = min(1.0, rms * 6.0 * gain)
        envelope = target > envelope ? target : envelope * 0.82 + target * 0.18

        let out = envelope < threshold ? 0 : min(1.0, (envelope - threshold) / (1 - threshold))
        DispatchQueue.main.async { [weak self] in self?.level = out }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.errorMessage = error.localizedDescription
        }
    }

    /// Flatten an audio sample buffer to mono floats.
    private static func monoSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let description = sampleBuffer.formatDescription,
              let asbd = description.audioStreamBasicDescription else { return nil }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard let first = buffers.first, let data = first.mData else { return nil }
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }

        let pointer = data.bindMemory(to: Float.self, capacity: count)
        // Sub-sample: we only need the envelope, not every frame
        var out: [Float] = []
        out.reserveCapacity(count / 4 + 1)
        var i = 0
        while i < count {
            out.append(pointer[i])
            i += 4
        }
        return out
    }
}
#endif
