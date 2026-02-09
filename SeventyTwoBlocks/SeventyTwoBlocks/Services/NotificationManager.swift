import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    /// Stores the notification action ID until the foreground handler reads it.
    /// Checked synchronously after restoreFromBackground() to avoid race conditions.
    var pendingAction: String?

    /// Block index from the notification that triggered the action.
    /// Used to detect stale notifications (e.g., user tapped an old notification).
    var pendingActionBlockIndex: Int?

    private override init() {
        super.init()
        notificationCenter.delegate = self
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            print("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }

    func checkPermission() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule Notifications

    func scheduleTimerComplete(at date: Date, blockIndex: Int, isBreak: Bool, isCheckIn: Bool = false) {
        let content = UNMutableNotificationContent()

        if isCheckIn {
            content.title = "Still working?"
            content.body = "Tap to check in, or hold for options."
        } else if isBreak {
            content.title = "Break Complete"
            content.body = "Ready to get back to work? Hold for options."
        } else {
            content.title = "Block Complete!"
            content.body = "Hold for options: Continue, Break, or Stop"
        }

        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "TIMER_COMPLETE"
        // Make it time-sensitive so it can break through some Focus modes
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "timer_complete_\(blockIndex)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            } else {
                print("Scheduled notification for block \(blockIndex) at \(date)")
            }
        }
    }

    func scheduleBreakReminder(at date: Date, blockIndex: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Break Time?"
        content.body = "You've been working for a while. Consider taking a short break."
        content.sound = .default
        content.categoryIdentifier = "BREAK_REMINDER"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "break_reminder_\(blockIndex)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule break reminder: \(error)")
            }
        }
    }

    // MARK: - Cancel Notifications

    func cancelTimerNotification(for blockIndex: Int) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["timer_complete_\(blockIndex)"]
        )
    }

    func cancelBreakReminder(for blockIndex: Int) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["break_reminder_\(blockIndex)"]
        )
    }

    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    // MARK: - Badge Management

    func clearBadge() {
        Task {
            do {
                try await notificationCenter.setBadgeCount(0)
            } catch {
                print("Failed to clear badge: \(error)")
            }
        }
    }

    // MARK: - Setup Categories

    func setupNotificationCategories() {
        // Timer complete actions
        let continueAction = UNNotificationAction(
            identifier: "CONTINUE",
            title: "Continue",
            options: [.foreground]
        )

        let takeBreakAction = UNNotificationAction(
            identifier: "TAKE_BREAK",
            title: "Take Break",
            options: [.foreground]
        )

        let newBlockAction = UNNotificationAction(
            identifier: "NEW_BLOCK",
            title: "New Block",
            options: [.foreground]
        )

        let stopAction = UNNotificationAction(
            identifier: "STOP",
            title: "Stop",
            options: [.destructive, .foreground]  // Must bring app to foreground to actually stop timer
        )

        let timerCompleteCategory = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [continueAction, takeBreakAction, newBlockAction, stopAction],
            intentIdentifiers: [],
            options: []
        )

        // Break reminder actions
        let startBreakAction = UNNotificationAction(
            identifier: "START_BREAK",
            title: "Start Break",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let breakReminderCategory = UNNotificationCategory(
            identifier: "BREAK_REMINDER",
            actions: [startBreakAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            timerCompleteCategory,
            breakReminderCategory
        ])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when the user taps a notification or an action button while the app is in the background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract block index from notification identifier (format: "timer_complete_\(blockIndex)")
        let identifier = response.notification.request.identifier
        if identifier.hasPrefix("timer_complete_") {
            let blockIndexStr = identifier.replacingOccurrences(of: "timer_complete_", with: "")
            pendingActionBlockIndex = Int(blockIndexStr)
            print("📲 Notification for block: \(pendingActionBlockIndex ?? -1)")
        } else if identifier.hasPrefix("break_reminder_") {
            let blockIndexStr = identifier.replacingOccurrences(of: "break_reminder_", with: "")
            pendingActionBlockIndex = Int(blockIndexStr)
            print("📲 Break reminder for block: \(pendingActionBlockIndex ?? -1)")
        }

        switch response.actionIdentifier {
        case "CONTINUE":
            pendingAction = "continue"
            print("📲 Notification action received: CONTINUE")
        case "TAKE_BREAK":
            pendingAction = "takeBreak"
            print("📲 Notification action received: TAKE_BREAK")
        case "STOP":
            pendingAction = "stop"
            print("📲 Notification action received: STOP")
        case "NEW_BLOCK":
            pendingAction = "newBlock"
            print("📲 Notification action received: NEW_BLOCK")
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body — app opens, no specific action
            print("📲 Notification body tapped (default action)")
            break
        default:
            print("📲 Unknown notification action: \(response.actionIdentifier)")
            break
        }
        completionHandler()
    }

    /// Called when a notification arrives while the app is in the foreground.
    /// Play the sound so user hears it even when looking at the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Play sound even in foreground - the in-app dialog handles the visual
        completionHandler([.sound])
    }
}
