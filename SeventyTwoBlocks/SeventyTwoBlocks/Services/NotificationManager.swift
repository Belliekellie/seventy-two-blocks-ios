import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    /// Stores the notification action ID until the foreground handler reads it.
    /// Checked synchronously after restoreFromBackground() to avoid race conditions.
    var pendingAction: String?

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

    func scheduleTimerComplete(at date: Date, blockIndex: Int, isBreak: Bool) {
        let content = UNMutableNotificationContent()

        if isBreak {
            content.title = "Break Complete"
            content.body = "Your 5-minute break is over. Ready to get back to work?"
        } else {
            content.title = "Block Complete!"
            content.body = "Great work! Block \(blockIndex + 1) is done. Keep the momentum going!"
        }

        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "TIMER_COMPLETE"

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

        let stopAction = UNNotificationAction(
            identifier: "STOP",
            title: "Stop",
            options: [.destructive]
        )

        let timerCompleteCategory = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [continueAction, takeBreakAction, stopAction],
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
        switch response.actionIdentifier {
        case "CONTINUE":
            pendingAction = "continue"
        case "TAKE_BREAK":
            pendingAction = "takeBreak"
        case "STOP":
            pendingAction = "stop"
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body — app opens, no specific action
            break
        default:
            break
        }
        completionHandler()
    }

    /// Called when a notification arrives while the app is in the foreground.
    /// Suppress it — the in-app completion dialog handles this case.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
