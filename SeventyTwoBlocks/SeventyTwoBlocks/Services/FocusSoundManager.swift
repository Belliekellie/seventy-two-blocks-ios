import AVFoundation
import Combine

/// Manages ambient focus sounds that can play anytime (not tied to timer)
@MainActor
final class FocusSoundManager: ObservableObject {
    static let shared = FocusSoundManager()

    @Published var isPlaying = false
    @Published var currentSound: String = "rain"
    @Published var volume: Float = 0.5

    private var audioPlayer: AVAudioPlayer?
    private var audioPlayer2: AVAudioPlayer?  // For crossfade looping
    private var crossfadeTimer: Timer?
    private var audioEngine: AVAudioEngine?
    private var noiseNode: AVAudioSourceNode?

    // Available sounds with their display info
    // Note: Some sounds are generated, others are from bundled files
    static let availableSounds: [(id: String, name: String, icon: String, isGenerated: Bool)] = [
        ("rain", "Rain", "cloud.rain.fill", false),
        ("ocean", "Ocean Waves", "water.waves", false),
        ("fireplace", "Fireplace", "flame.fill", false),
        ("binaural", "Binaural Focus", "brain.head.profile", true),  // Generated - stereo beats
        ("brownnoise", "Brown Noise", "waveform.circle", true),  // Generated
        ("pinknoise", "Pink Noise", "waveform.badge.plus", true),  // Generated
    ]

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            // Allow mixing with other audio and play in background
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error)")
        }
    }

    // MARK: - Playback Control

    func play(sound: String? = nil) {
        if let sound = sound {
            currentSound = sound
        }

        // Stop any existing playback
        stop()

        // Check if this is a generated sound (noise)
        let soundInfo = Self.availableSounds.first { $0.id == currentSound }

        if soundInfo?.isGenerated == true {
            playGeneratedNoise(type: currentSound)
        } else {
            playBundledSound()
        }
    }

    private func playBundledSound() {
        // Try to load bundled sound file
        guard let soundURL = Bundle.main.url(forResource: currentSound, withExtension: "mp3") else {
            print("⚠️ Sound file not found: \(currentSound).mp3")
            isPlaying = false
            return
        }

        do {
            // Set up primary player
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.numberOfLoops = 0  // No built-in loop, we handle it
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()

            // Set up secondary player for crossfade
            audioPlayer2 = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer2?.numberOfLoops = 0
            audioPlayer2?.volume = 0  // Start silent
            audioPlayer2?.prepareToPlay()

            audioPlayer?.play()
            isPlaying = true
            print("▶️ Playing bundled sound with crossfade: \(currentSound)")

            // Start crossfade monitoring
            startCrossfadeMonitoring()
        } catch {
            print("❌ Could not play sound: \(error)")
            isPlaying = false
        }

        AudioManager.shared.triggerHapticFeedback(.light)
    }

    private func startCrossfadeMonitoring() {
        crossfadeTimer?.invalidate()

        // Check every 0.1 seconds if we need to start crossfade
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.checkAndCrossfade()
            }
        }
    }

    private func checkAndCrossfade() {
        guard let player = audioPlayer, player.isPlaying else { return }

        let crossfadeDuration: TimeInterval = 2.0
        let timeRemaining = player.duration - player.currentTime

        // Start crossfade when 2 seconds remain
        if timeRemaining <= crossfadeDuration && timeRemaining > 0 {
            performCrossfade(duration: timeRemaining)
        }
    }

    private func performCrossfade(duration: TimeInterval) {
        guard let player1 = audioPlayer, let player2 = audioPlayer2 else { return }

        // Only crossfade if player2 isn't already playing
        guard !player2.isPlaying else { return }

        // Start player2 and fade it in
        player2.currentTime = 0
        player2.volume = 0
        player2.play()

        // Animate the crossfade
        let steps = 20
        let stepDuration = duration / Double(steps)

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak self] in
                guard let self = self else { return }
                let progress = Float(i) / Float(steps)
                player1.volume = self.volume * (1 - progress)
                player2.volume = self.volume * progress
            }
        }

        // After crossfade, swap players
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
            guard let self = self else { return }
            player1.stop()
            player1.currentTime = 0
            player1.volume = 0
            player1.prepareToPlay()

            // Swap
            let temp = self.audioPlayer
            self.audioPlayer = self.audioPlayer2
            self.audioPlayer2 = temp
        }
    }

    private func playGeneratedNoise(type: String) {
        // Binaural beats require stereo for the beat effect
        if type == "binaural" {
            playBinauralBeats()
            return
        }

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        // Create noise generator based on type
        var lastOutput: Float = 0 // For brown noise
        var pinkState: [Float] = [0, 0, 0, 0, 0, 0, 0] // For pink noise

        noiseNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                var sample: Float

                switch type {
                case "brownnoise":
                    // Brown noise (random walk)
                    let white = Float.random(in: -1...1)
                    lastOutput = (lastOutput + (0.02 * white)) / 1.02
                    sample = lastOutput * 3.5

                case "pinknoise":
                    // Pink noise using Paul Kellet's algorithm
                    let white = Float.random(in: -1...1)
                    pinkState[0] = 0.99886 * pinkState[0] + white * 0.0555179
                    pinkState[1] = 0.99332 * pinkState[1] + white * 0.0750759
                    pinkState[2] = 0.96900 * pinkState[2] + white * 0.1538520
                    pinkState[3] = 0.86650 * pinkState[3] + white * 0.3104856
                    pinkState[4] = 0.55000 * pinkState[4] + white * 0.5329522
                    pinkState[5] = -0.7616 * pinkState[5] - white * 0.0168980
                    sample = (pinkState[0] + pinkState[1] + pinkState[2] + pinkState[3] + pinkState[4] + pinkState[5] + pinkState[6] + white * 0.5362) * 0.11
                    pinkState[6] = white * 0.115926

                default:
                    sample = Float.random(in: -1...1)
                }

                // Apply volume
                sample *= self.volume

                // Clamp
                sample = max(-1, min(1, sample))

                for buffer in ablPointer {
                    let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                    buf?[frame] = sample
                }
            }

            return noErr
        }

        guard let sourceNode = noiseNode else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: format)

        do {
            try engine.start()
            isPlaying = true
            print("▶️ Playing generated noise: \(type)")
        } catch {
            print("❌ Could not start audio engine: \(error)")
            isPlaying = false
        }

        AudioManager.shared.triggerHapticFeedback(.light)
    }

    /// Binaural beats: Two slightly different frequencies in each ear
    /// Creates a perceived "beat" at the difference frequency (40 Hz = gamma waves for focus)
    private func playBinauralBeats() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = Float(outputFormat.sampleRate)

        // Binaural beat frequencies
        let baseFreq: Float = 200.0     // Left ear: 200 Hz
        let beatFreq: Float = 40.0      // Beat frequency (gamma waves for focus)
        let rightFreq = baseFreq + beatFreq  // Right ear: 240 Hz
        let amplitude: Float = 0.15     // Keep amplitude low for pure tones

        // Phase accumulators
        var leftPhase: Float = 0
        var rightPhase: Float = 0
        let leftIncrement = (2.0 * Float.pi * baseFreq) / sampleRate
        let rightIncrement = (2.0 * Float.pi * rightFreq) / sampleRate

        // Stereo source node for binaural beats
        noiseNode = AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // For stereo interleaved format
            guard let buffer = ablPointer.first,
                  let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            for frame in 0..<Int(frameCount) {
                // Generate sine waves for each ear
                let leftSample = sin(leftPhase) * amplitude * self.volume
                let rightSample = sin(rightPhase) * amplitude * self.volume

                // Update phases
                leftPhase += leftIncrement
                rightPhase += rightIncrement

                // Keep phases in range to prevent overflow
                if leftPhase > 2.0 * Float.pi { leftPhase -= 2.0 * Float.pi }
                if rightPhase > 2.0 * Float.pi { rightPhase -= 2.0 * Float.pi }

                // Interleaved stereo: L, R, L, R, ...
                data[frame * 2] = leftSample      // Left channel
                data[frame * 2 + 1] = rightSample // Right channel
            }

            return noErr
        }

        guard let sourceNode = noiseNode else { return }

        // Use stereo format for binaural
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: stereoFormat)

        do {
            try engine.start()
            isPlaying = true
            print("▶️ Playing binaural beats: \(baseFreq)Hz (L) / \(rightFreq)Hz (R) = \(beatFreq)Hz beat")
        } catch {
            print("❌ Could not start audio engine for binaural: \(error)")
            isPlaying = false
        }

        AudioManager.shared.triggerHapticFeedback(.light)
    }

    func stop() {
        // Stop crossfade timer
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        // Stop audio players
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayer2?.stop()
        audioPlayer2 = nil

        // Stop audio engine
        audioEngine?.stop()
        if let node = noiseNode {
            audioEngine?.detach(node)
        }
        noiseNode = nil
        audioEngine = nil

        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        // Set volume on whichever player is currently the "main" one
        // During crossfade, both have proportional volumes, so just update the target
        if let player = audioPlayer, player.isPlaying, audioPlayer2?.isPlaying != true {
            player.volume = newVolume
        }
        if let player2 = audioPlayer2, player2.isPlaying, audioPlayer?.isPlaying != true {
            player2.volume = newVolume
        }
        // For generated noise, volume is applied in the render callback
    }

    func changeSound(_ soundId: String) {
        let wasPlaying = isPlaying
        currentSound = soundId
        if wasPlaying {
            play() // Restart with new sound
        }
    }

    // MARK: - Sound Info

    func soundName(for id: String) -> String {
        Self.availableSounds.first { $0.id == id }?.name ?? "Sound"
    }

    /// Shorter name for compact display (e.g. bottom bar)
    func shortSoundName(for id: String) -> String {
        switch id {
        case "ocean": return "Ocean"
        case "binaural": return "Binaural"
        default: return soundName(for: id)
        }
    }

    func soundIcon(for id: String) -> String {
        Self.availableSounds.first { $0.id == id }?.icon ?? "speaker.wave.2.fill"
    }
}
