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
    /// Current level, 0...1. Read by the server and pushed to phones.
    private(set) var level: Double = 0
    /// 0 = pure bass (soft, rolling), 1 = bright/percussive (short, sharp).
    private(set) var sharpness: Double = 0
    /// What the user asked for — the toggle binds to this, not to isRunning,
    /// so a permission failure doesn't silently flip the switch back.
    var enabled = UserDefaults.standard.bool(forKey: "audioRumble")
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    /// How strongly the audio maps to rumble.
    var gain: Double = 1.0

    enum Mode: String, CaseIterable, Identifiable {
        /// Everything rumbles — for music, where constant response is the point.
        case music
        /// Only distinct hits rumble — for games, so dialogue, footsteps and
        /// ambience stay quiet and explosions still land.
        case game
        var id: String { rawValue }
        var label: String { self == .music ? "Music" : "Game" }
    }

    var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "audioRumbleMode") ?? "music") ?? .music {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "audioRumbleMode") }
    }

    /// Level below which nothing is sent. Game mode ignores far more.
    private var threshold: Double { mode == .music ? 0.05 : 0.20 }
    /// Extra drive in music mode so quiet passages still register.
    private var modeGain: Double { mode == .music ? 1.0 : 0.75 }

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "controller.audio", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "controller.audio.video", qos: .utility)

    // One-pole low-pass state (keeps only the bass) and an envelope follower
    private var lpState: Double = 0
    private var lpState2: Double = 0
    private var hpState: Double = 0
    private var hpState2: Double = 0
    private var hpPrevIn: Double = 0
    private var hpPrevMid: Double = 0
    private var sharpSmoothed: Double = 0
    private var runningAvg: Double = 0
    private var envelope: Double = 0
    private var highEnvelope: Double = 0
    private var frameCount = 0
    private var decodeFailures = 0

    private func log(_ text: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(text)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/controller_audio.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    func start() {
        enabled = true
        UserDefaults.standard.set(true, forKey: "audioRumble")
        guard !isRunning else { return }

        // Prompt for Screen Recording if we don't have it — otherwise the capture
        // just fails and the feature looks broken.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            errorMessage = "Allow Screen Recording, then relaunch"
            log("no screen recording permission")
            return
        }
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
                // A stream will not deliver audio unless a video output is also
                // attached, so we take the smallest, slowest video we can and
                // throw every frame away.
                config.width = 128
                config.height = 128
                config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                config.queueDepth = 3
                config.showsCursor = false

                let s = SCStream(filter: filter, configuration: config, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
                try await s.startCapture()
                stream = s
                isRunning = true
                errorMessage = nil
                log("capture started")
            } catch {
                errorMessage = "Capture failed: \(error.localizedDescription)"
                isRunning = false
                log("start failed: \(error)")
            }
        }
    }

    func stop() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "audioRumble")
        let s = stream
        stream = nil
        isRunning = false
        level = 0
        Task { try? await s?.stopCapture() }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }   // video frames discarded
        guard let samples = Self.monoSamples(from: sampleBuffer), !samples.isEmpty else {
            decodeFailures += 1
            if decodeFailures % 100 == 1 { log("audio buffer arrived but could not decode PCM") }
            return
        }

        // Split into a low band and everything above it. The low band drives a
        // soft rolling rumble; the rest makes the hit feel sharp.
        // Independent filters for each band. Deriving "high" by subtracting the
        // low-passed signal does NOT work: the filter shifts phase, so the
        // subtraction leaves a big residual and deep bass reads as bright.
        // Both are two cascaded one-poles (12 dB/oct) on the decimated stream.
        let lpAlpha = 0.06    // low-pass  ~115 Hz
        let hpAlpha = 0.884   // high-pass ~250 Hz
        var lowSquares = 0.0
        var highSquares = 0.0
        for sample in samples {
            let x = Double(sample)

            // Low band
            lpState += lpAlpha * (x - lpState)
            lpState2 += lpAlpha * (lpState - lpState2)
            lowSquares += lpState2 * lpState2

            // High band
            let h1 = hpAlpha * (hpState + x - hpPrevIn)
            hpPrevIn = x
            hpState = h1
            let h2 = hpAlpha * (hpState2 + h1 - hpPrevMid)
            hpPrevMid = h1
            hpState2 = h2
            highSquares += h2 * h2
        }
        let n = Double(samples.count)
        let lowRms = (lowSquares / n).squareRoot()
        let highRms = (highSquares / n).squareRoot()

        // Envelope followers: snap up on a hit, ease back down, so notes read as
        // distinct thumps instead of a constant buzz.
        let g = gain * modeGain
        let lowTarget = min(1.0, lowRms * 9.0 * g)
        let highTarget = min(1.0, highRms * 6.0 * g)
        envelope = lowTarget > envelope ? lowTarget : envelope * 0.80 + lowTarget * 0.20
        highEnvelope = highTarget > highEnvelope ? highTarget : highEnvelope * 0.70 + highTarget * 0.30

        let combined = max(envelope, highEnvelope)
        var out = combined < threshold ? 0 : min(1.0, (combined - threshold) / (1 - threshold))

        // Game mode: only react to a sudden jump above the recent average, so a
        // steady soundtrack or crowd noise does not buzz continuously — only
        // impacts, explosions and hits do.
        if mode == .game {
            runningAvg = runningAvg * 0.98 + combined * 0.02
            let onset = combined - runningAvg
            out = onset < 0.07 ? 0 : min(1.0, out * min(1.0, onset * 5.0))
        }

        // Sharpness comes from the RAW band energies. Using the envelopes was
        // wrong: both saturate at 1.0 on anything loud, which collapsed every
        // ratio to 0.5 and made deep bass report as bright.
        let total = lowRms + highRms
        if total > 0.0005 {
            let instant = min(1.0, (highRms / total) * 1.25)
            sharpSmoothed = sharpSmoothed * 0.7 + instant * 0.3
        }
        let sharp = sharpSmoothed

        DispatchQueue.main.async { [weak self] in
            self?.level = out
            self?.sharpness = sharp
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.errorMessage = error.localizedDescription
        }
    }

    /// Flatten an audio sample buffer to mono floats.
    ///
    /// The audio is stereo and non-interleaved, so the buffer list holds one
    /// buffer per channel. A bare AudioBufferList only has room for one, which
    /// makes the fetch fail outright — the list has to be sized from the buffer.
    private static func monoSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var listSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        ) == noErr, listSize > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let listPointer = raw.assumingMemoryBound(to: AudioBufferList.self)

        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: listPointer,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ) == noErr else { return nil }

        let list = UnsafeMutableAudioBufferListPointer(listPointer)
        guard let first = list.first, let firstData = first.mData else { return nil }

        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frames > 0 else { return nil }

        // Average the channels, sub-sampling since we only need the envelope
        let step = 4
        var out: [Float] = []
        out.reserveCapacity(frames / step + 1)
        let channels = list.count
        let pointers = list.compactMap { $0.mData?.bindMemory(to: Float.self, capacity: frames) }
        guard !pointers.isEmpty else {
            let single = firstData.bindMemory(to: Float.self, capacity: frames)
            var i = 0
            while i < frames { out.append(single[i]); i += step }
            return out
        }

        var i = 0
        while i < frames {
            var sum: Float = 0
            for p in pointers { sum += p[i] }
            out.append(sum / Float(channels))
            i += step
        }
        return out
    }
}
#endif
