import AVFoundation
import UIKit

final class AudioManager {
    static let shared = AudioManager()

    private var audioPlayer: AVAudioPlayer?

    private init() {
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
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
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
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
