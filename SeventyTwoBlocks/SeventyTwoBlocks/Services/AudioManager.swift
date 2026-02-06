import AVFoundation
import UIKit

final class AudioManager {
    static let shared = AudioManager()

    private var audioPlayer: AVAudioPlayer?

    // Pre-created haptic generators for instant response
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }

        // Prepare haptic generators for instant response
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    // MARK: - Completion Bell

    func playCompletionBell() {
        // Try to play system sound first
        playSystemSound(.tripleBeep)

        // Also trigger haptic feedback
        triggerHapticFeedback(.success)
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
