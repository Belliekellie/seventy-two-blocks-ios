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

    /// Thread identifier for grouping block timer notifications together.
    /// iOS groups notifications with the same threadIdentifier so they don't
    /// clutter the notification centre as separate items.
    private let timerThreadId = "block_timer"

    func scheduleTimerComplete(at date: Date, blockIndex: Int, isBreak: Bool, isCheckIn: Bool = false) {
        // Remove any previously delivered block notifications so the new one
        // effectively replaces the old one in the notification centre.
        notificationCenter.removeDeliveredNotifications(withIdentifiers:
            (0..<72).map { "block_timer_\($0)" })

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
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = timerThreadId
        content.userInfo = ["blockIndex": blockIndex]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )

        // Each notification uses a block-specific identifier so they can all be
        // pending at the same time. When one fires, removeDeliveredNotifications
        // in the next scheduled notification's trigger clears the previous one.
        let request = UNNotificationRequest(
            identifier: "block_timer_\(blockIndex)",
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

    /// Schedule an immediate check-in notification with grace period info.
    /// Used when the check-in limit is reached during retroactive auto-continue processing.
    func scheduleCheckInNotification(blockIndex: Int, graceMinutesRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Still working?"
        content.body = "You have \(graceMinutesRemaining) minutes to continue or your session will end. Tap to check in."
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "TIMER_COMPLETE"
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = timerThreadId
        content.userInfo = ["blockIndex": blockIndex]

        // Fire immediately (1 second delay minimum required)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "block_timer_\(blockIndex)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule check-in notification: \(error)")
            } else {
                print("📲 Scheduled check-in notification for block \(blockIndex) with \(graceMinutesRemaining) min grace")
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
            withIdentifiers: ["block_timer_\(blockIndex)"]
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
        // Extract block index from notification userInfo
        let userInfo = response.notification.request.content.userInfo
        if let blockIndex = userInfo["blockIndex"] as? Int {
            pendingActionBlockIndex = blockIndex
            print("📲 Notification for block: \(blockIndex)")
        } else {
            // Fallback: try parsing from identifier for legacy notifications
            let identifier = response.notification.request.identifier
            if identifier.hasPrefix("break_reminder_") {
                let blockIndexStr = identifier.replacingOccurrences(of: "break_reminder_", with: "")
                pendingActionBlockIndex = Int(blockIndexStr)
                print("📲 Break reminder for block: \(pendingActionBlockIndex ?? -1)")
            }
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
    /// Suppress it — the in-app dialog/popup handles everything when the user is looking.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Don't show banner, badge, or play sound — the in-app UI is the notification
        completionHandler([])
    }
}
