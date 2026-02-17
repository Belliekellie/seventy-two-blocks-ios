import AVFoundation
import UIKit

final class AudioManager {
    static let shared = AudioManager()

    private var audioPlayer: AVAudioPlayer?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Pre-created haptic generators for instant response
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // Setting for playing sounds in silent mode
    private var playSoundsInSilentMode: Bool {
        UserDefaults.standard.bool(forKey: "playSoundsInSilentMode")
    }

    private init() {
        // Prepare haptic generators for instant response
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// Fully warm up the haptic engine by triggering a minimal haptic
    /// Call this at app startup to prevent delay on first user interaction
    func warmupHaptics() {
        // Trigger selection feedback - it's the lightest and least noticeable
        // This forces the haptic engine to fully initialize
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Configure audio session - call this when needed for synthesized playback
    private func configureAudioSessionForPlayback() {
        do {
            // Use .playback category to ignore silent switch
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    // MARK: - Completion Bell

    func playCompletionBell() {
        print("🔔 playCompletionBell called, playSoundsInSilentMode=\(playSoundsInSilentMode)")

        if playSoundsInSilentMode {
            // Use synthesized sound that ignores silent switch
            playSynthesizedChime()
        } else {
            // Use system sound (respects silent switch)
            playSystemSound(.tripleBeep)
        }

        // Also trigger haptic feedback
        triggerHapticFeedback(.success)
    }

    // MARK: - Synthesized Chime (ignores silent mode)

    /// Generates a pleasant multi-tone bell chime similar to system sound 1005
    /// Uses AVAudioEngine with .playback category to ignore silent switch
    private func playSynthesizedChime() {
        configureAudioSessionForPlayback()

        // Create audio engine and player node
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let sampleRate: Double = 44100
        let duration: Double = 1.2  // Total duration of the chime

        // Bell-like chime: 3 ascending notes with harmonics
        // Frequencies based on a pleasant major chord (C5-E5-G5-C6)
        let notes: [(frequency: Double, startTime: Double, amplitude: Double)] = [
            (523.25, 0.0, 0.7),    // C5 - root note
            (659.25, 0.15, 0.6),   // E5 - major third
            (783.99, 0.30, 0.5),   // G5 - perfect fifth
            (1046.50, 0.45, 0.4),  // C6 - octave
        ]

        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            print("🔔 Failed to create audio buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData?[0] else {
            print("🔔 Failed to get channel data")
            return
        }

        // Initialize buffer to silence
        for i in 0..<frameCount {
            channelData[i] = 0
        }

        // Generate each note with bell-like harmonics and decay
        for note in notes {
            let startFrame = Int(note.startTime * sampleRate)
            let noteDuration = duration - note.startTime
            let noteFrames = Int(noteDuration * sampleRate)

            for i in 0..<noteFrames {
                let frameIndex = startFrame + i
                guard frameIndex < frameCount else { break }

                let t = Double(i) / sampleRate
                let decay = exp(-t * 3.5)  // Exponential decay for bell-like sound

                // Fundamental frequency
                var sample = sin(2.0 * .pi * note.frequency * t)

                // Add harmonics for richer bell tone
                sample += 0.5 * sin(2.0 * .pi * note.frequency * 2.0 * t)  // 2nd harmonic
                sample += 0.25 * sin(2.0 * .pi * note.frequency * 3.0 * t) // 3rd harmonic
                sample += 0.125 * sin(2.0 * .pi * note.frequency * 4.0 * t) // 4th harmonic

                // Apply amplitude, decay, and add to buffer
                channelData[frameIndex] += Float(sample * note.amplitude * decay * 0.3)
            }
        }

        // Connect player to output and play
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()

            // Keep references alive until playback completes
            self.audioEngine = engine
            self.playerNode = player

            // Stop engine after playback
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
                self?.playerNode?.stop()
                self?.audioEngine?.stop()
                self?.audioEngine = nil
                self?.playerNode = nil
            }
        } catch {
            print("🔔 Failed to play synthesized chime: \(error)")
        }
    }

    // MARK: - Break Reminder

    func playBreakReminder() {
        playSystemSound(.doubleBeep)
        triggerHapticFeedback(.warning)
    }

    // MARK: - Simple Alert

    func playAlertSound() {
        playSystemSound(.singleBeep)
        triggerHapticFeedback(.light)
    }

    // MARK: - Haptic Feedback

    func triggerHapticFeedback(_ type: HapticType) {
        switch type {
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()  // Re-prepare for next use
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        case .error:
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        case .light:
            lightImpactGenerator.impactOccurred()
            lightImpactGenerator.prepare()
        case .medium:
            mediumImpactGenerator.impactOccurred()
            mediumImpactGenerator.prepare()
        case .heavy:
            heavyImpactGenerator.impactOccurred()
            heavyImpactGenerator.prepare()
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }

    // MARK: - Private Methods

    private func playSystemSound(_ sound: SoundType) {
        let soundID: SystemSoundID

        switch sound {
        case .singleBeep:
            soundID = 1057  // SMS received
        case .doubleBeep:
            soundID = 1007  // Mail sent
        case .tripleBeep:
            soundID = 1005  // Alarm/bell sound
        }

        AudioServicesPlaySystemSound(soundID)
    }

    // MARK: - Types

    enum SoundType {
        case singleBeep
        case doubleBeep
        case tripleBeep
    }

    enum HapticType {
        case success
        case warning
        case error
        case light
        case medium
        case heavy
        case selection
    }
}
