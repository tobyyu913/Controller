//
//  SoundManager.swift
//  Controller
//
//  Handles background music (from file) and procedural sound effects.
//  Drop a music file named "bgm.mp3" (or .m4a/.wav) into the app bundle to play it.
//

#if os(macOS)
import AVFoundation
import Foundation

class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private let musicPlayer = AVAudioPlayerNode()
    private let sfxPlayer = AVAudioPlayerNode()
    private let sfxPlayer2 = AVAudioPlayerNode() // second channel for overlapping SFX
    private let mixer: AVAudioMixerNode

    private var musicBuffer: AVAudioPCMBuffer?
    private var footstepBuffer: AVAudioPCMBuffer?
    private var jumpBuffer: AVAudioPCMBuffer?
    private var landBuffer: AVAudioPCMBuffer?

    private var isWalking = false
    private var walkTimer: DispatchSourceTimer?
    private var isSprinting = false

    private init() {
        mixer = engine.mainMixerNode

        engine.attach(musicPlayer)
        engine.attach(sfxPlayer)
        engine.attach(sfxPlayer2)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(musicPlayer, to: mixer, format: format)
        engine.connect(sfxPlayer, to: mixer, format: format)
        engine.connect(sfxPlayer2, to: mixer, format: format)

        musicPlayer.volume = 0.3
        sfxPlayer.volume = 0.5
        sfxPlayer2.volume = 0.5

        generateSFXBuffers(format: format)

        do {
            try engine.start()
        } catch {
            print("Audio engine failed: \(error)")
        }
    }

    // MARK: - Background Music

    func playMusic() {
        // Try loading a file first, fall back to procedural
        if loadMusicFile() { return }

        // Generate procedural parkour music
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = generateParkourMusic(format: format) else { return }

        engine.disconnectNodeOutput(musicPlayer)
        engine.connect(musicPlayer, to: mixer, format: format)

        musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        musicPlayer.play()
    }

    private func loadMusicFile() -> Bool {
        let extensions = ["mp3", "m4a", "wav", "aac"]
        var url: URL?
        for ext in extensions {
            if let found = Bundle.main.url(forResource: "bgm", withExtension: ext) {
                url = found
                break
            }
        }
        guard let musicURL = url else { return false }
        do {
            let file = try AVAudioFile(forReading: musicURL)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return false }
            try file.read(into: buffer)
            engine.disconnectNodeOutput(musicPlayer)
            engine.connect(musicPlayer, to: mixer, format: format)
            musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            musicPlayer.play()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Procedural Parkour Music

    private func generateParkourMusic(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = Float(format.sampleRate)
        let bpm: Float = 140
        let beatLen = 60.0 / bpm // seconds per beat
        let bars = 8
        let beatsPerBar = 4
        let totalBeats = bars * beatsPerBar
        let totalSamples = Int(Float(totalBeats) * beatLen * sr)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        guard let data = buffer.floatChannelData?[0] else { return nil }

        // Note frequencies
        func noteFreq(_ midi: Int) -> Float {
            440.0 * pow(2.0, Float(midi - 69) / 12.0)
        }

        // Bass line pattern (E minor pentatonic feel) — MIDI notes
        // 8 bars, each bar has a root note
        let bassRoots: [Int] = [40, 40, 43, 43, 45, 47, 43, 40] // E2, E2, G2, G2, A2, B2, G2, E2
        // Bass plays 8th notes with a driving pattern
        let bassPattern: [Bool] = [true, false, true, true, false, true, true, false] // per 8th note

        // Melody notes per bar (quarter notes) — higher octave
        let melodyBars: [[Int]] = [
            [64, 67, 69, 67],   // E4 G4 A4 G4
            [71, 69, 67, 64],   // B4 A4 G4 E4
            [67, 69, 71, 72],   // G4 A4 B4 C5
            [71, 69, 67, 69],   // B4 A4 G4 A4
            [69, 71, 72, 74],   // A4 B4 C5 D5
            [76, 74, 72, 71],   // E5 D5 C5 B4
            [67, 69, 71, 67],   // G4 A4 B4 G4
            [64, 67, 64, 62],   // E4 G4 E4 D4
        ]

        // Arpeggio notes per bar (16th notes)
        let arpBars: [[Int]] = [
            [52, 55, 59, 64],   // E3 G3 B3 E4
            [52, 55, 59, 64],
            [55, 59, 62, 67],   // G3 B3 D4 G4
            [55, 59, 62, 67],
            [57, 60, 64, 69],   // A3 C4 E4 A4
            [59, 62, 67, 71],   // B3 D4 G4 B4
            [55, 59, 62, 67],
            [52, 55, 59, 64],
        ]

        let samplesPerBeat = Int(beatLen * sr)
        let samplesPerBar = samplesPerBeat * beatsPerBar

        for i in 0..<totalSamples {
            let t = Float(i) / sr
            let bar = min(i / samplesPerBar, bars - 1)
            let posInBar = i % samplesPerBar

            var sample: Float = 0

            // -- Kick drum on beats 1 and 3 --
            let beatInBar = posInBar / samplesPerBeat
            let posInBeat = posInBar % samplesPerBeat
            let beatT = Float(posInBeat) / sr
            if (beatInBar == 0 || beatInBar == 2) && beatT < 0.1 {
                let kickFreq: Float = 60 - beatT * 400
                let kickEnv = max(0, 1 - beatT * 10)
                sample += sin(2 * .pi * kickFreq * beatT) * kickEnv * 0.35
            }

            // -- Hi-hat on every 8th note --
            let eighthLen = samplesPerBeat / 2
            let posIn8th = posInBar % eighthLen
            let eighthT = Float(posIn8th) / sr
            if eighthT < 0.03 {
                let hhEnv = max(0, 1 - eighthT * 33)
                sample += Float.random(in: -1...1) * hhEnv * 0.08
            }

            // -- Snare on beats 2 and 4 --
            if (beatInBar == 1 || beatInBar == 3) && beatT < 0.08 {
                let snareEnv = max(0, 1 - beatT * 12)
                let noise = Float.random(in: -1...1)
                let tone = sin(2 * .pi * 200 * beatT)
                sample += (noise * 0.5 + tone * 0.5) * snareEnv * 0.2
            }

            // -- Bass synth (square-ish wave) --
            let eighth = posInBar / eighthLen
            let bassIdx = eighth % bassPattern.count
            if bassPattern[bassIdx] {
                let bassFreq = noteFreq(bassRoots[bar])
                let bassT = Float(posInBar % eighthLen) / sr
                let bassEnv = max(0, 1 - bassT / (beatLen * 0.4))
                // Square-ish wave (fundamental + odd harmonics)
                let bassWave = sin(2 * .pi * bassFreq * t) * 0.7
                    + sin(2 * .pi * bassFreq * 3 * t) * 0.2
                    + sin(2 * .pi * bassFreq * 5 * t) * 0.1
                sample += bassWave * bassEnv * 0.18
            }

            // -- Melody (saw-like synth, quarter notes) --
            let melodyNote = melodyBars[bar][beatInBar]
            let melodyFreq = noteFreq(melodyNote)
            let melodyT = Float(posInBeat) / sr
            let melodyEnv = max(0, 1 - melodyT / (beatLen * 0.8))
            // Saw approximation
            let phase = (melodyFreq * t).truncatingRemainder(dividingBy: 1.0)
            let sawWave = 2.0 * phase - 1.0
            sample += sawWave * melodyEnv * 0.1

            // -- Arpeggio (16th notes, triangle wave) --
            let sixteenthLen = samplesPerBeat / 4
            let sixteenthIdx = (posInBar / sixteenthLen) % 4
            let arpNote = arpBars[bar][sixteenthIdx]
            let arpFreq = noteFreq(arpNote)
            let arpT = Float(posInBar % sixteenthLen) / sr
            let arpEnv = max(0, 1 - arpT / (beatLen * 0.2))
            // Triangle wave
            let arpPhase = (arpFreq * t).truncatingRemainder(dividingBy: 1.0)
            let triWave = 4.0 * abs(arpPhase - 0.5) - 1.0
            sample += triWave * arpEnv * 0.06

            // Soft clip to prevent harsh distortion
            sample = tanh(sample * 1.2)

            data[i] = sample * 0.7
        }

        return buffer
    }

    func stopMusic() {
        musicPlayer.stop()
    }

    func setMusicVolume(_ volume: Float) {
        musicPlayer.volume = volume
    }

    // MARK: - Walking Sound

    func startWalking(sprinting: Bool) {
        guard !isWalking else {
            // Update sprint pace
            if sprinting != isSprinting {
                isSprinting = sprinting
                restartWalkTimer()
            }
            return
        }
        isWalking = true
        isSprinting = sprinting
        restartWalkTimer()
    }

    func stopWalking() {
        guard isWalking else { return }
        isWalking = false
        walkTimer?.cancel()
        walkTimer = nil
    }

    private func restartWalkTimer() {
        walkTimer?.cancel()
        let interval = isSprinting ? 250 : 400 // ms between footsteps
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval))
        timer.setEventHandler { [weak self] in
            self?.playFootstep()
        }
        timer.resume()
        walkTimer = timer
    }

    private func playFootstep() {
        guard let buffer = footstepBuffer else { return }
        // Alternate pitch slightly for natural feel
        let pitch = Float.random(in: 0.85...1.15)
        sfxPlayer.stop()
        sfxPlayer.rate = pitch
        sfxPlayer.scheduleBuffer(buffer, at: nil, options: [])
        sfxPlayer.play()
    }

    // MARK: - Jump Sound

    func playJump() {
        guard let buffer = jumpBuffer else { return }
        sfxPlayer2.stop()
        sfxPlayer2.scheduleBuffer(buffer, at: nil, options: [])
        sfxPlayer2.play()
    }

    // MARK: - Land Sound

    func playLand() {
        guard let buffer = landBuffer else { return }
        sfxPlayer2.stop()
        sfxPlayer2.scheduleBuffer(buffer, at: nil, options: [])
        sfxPlayer2.play()
    }

    // MARK: - Procedural SFX Generation

    private func generateSFXBuffers(format: AVAudioFormat) {
        let sampleRate = Float(format.sampleRate)

        // Footstep: short filtered noise burst (50ms)
        footstepBuffer = generateBuffer(format: format, duration: 0.05) { i in
            let t = Float(i) / sampleRate
            let noise = Float.random(in: -1...1)
            let env = max(0, 1 - t * 20) // fast decay
            // Low-pass feel: average with previous samples
            return noise * env * 0.4
        }

        // Jump: rising sine sweep (150ms)
        jumpBuffer = generateBuffer(format: format, duration: 0.15) { i in
            let t = Float(i) / sampleRate
            let freq: Float = 200 + t * 2000 // sweep 200→500 Hz
            let env = max(0, 1 - t * 6.5)
            return sin(2 * .pi * freq * t) * env * 0.3
        }

        // Land: thump (80ms)
        landBuffer = generateBuffer(format: format, duration: 0.08) { i in
            let t = Float(i) / sampleRate
            let freq: Float = 80 - t * 400 // descending thump
            let env = max(0, 1 - t * 12)
            return sin(2 * .pi * freq * t) * env * 0.5
        }
    }

    private func generateBuffer(format: AVAudioFormat, duration: Float, generator: (Int) -> Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * Float(format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }
        for i in 0..<Int(frameCount) {
            data[i] = generator(i)
        }
        return buffer
    }
}
#endif
