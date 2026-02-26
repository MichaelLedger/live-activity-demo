/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The app.
*/

import SwiftUI
import UserNotifications
import ActivityKit
import OSLog

@main
struct EmojiRangersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EmojiRangers", category: "Push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestPushPermissions() }
        observePushToStartToken()
        return true
    }

    // MARK: - Push Permission

    private func requestPushPermissions() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                logger.info("[Push] Permission granted, registering for remote notifications.")
            } else {
                logger.warning("[Push] Permission denied by user.")
            }
        } catch {
            logger.error("[Push] Permission request error: \(error)")
        }
    }

    // MARK: - APNs Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.reduce("") { $0 + String(format: "%02x", $1) }
        // This token is for regular push notifications only.
        // Do NOT use this token for Live Activity push-to-start or push-to-update.
        logger.info("[Push] APNs device token (regular notifications only): \(tokenString)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("[Push] Failed to register for remote notifications: \(error)")
    }

    // MARK: - Foreground Notification Handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    // MARK: - Push-to-Start Token (iOS 17.2+ / iOS 18 input-push-token)

    /// Observes the push-to-start token so a server can remotely start a Live Activity.
    /// On iOS 18+, include `"input-push-token": 1` in the APNs payload to receive a
    /// refreshed token that can be used to start a new Live Activity via push.
    private func observePushToStartToken() {
        Task {
            if #available(iOS 17.2, *) {
                for await tokenData in Activity<AdventureAttributes>.pushToStartTokenUpdates {
                    let tokenString = tokenData.reduce("") { $0 + String(format: "%02x", $1) }
                    let bundleID = Bundle.main.bundleIdentifier ?? "<bundle-id>"
                    // Use THIS token (not the APNs device token) to start a Live Activity via push.
                    // APNs topic must be: <bundle-id>.push-type.liveactivity
                    logger.info("""
                        [Push-to-Start] Token (use for Live Activity start push):
                          token : \(tokenString)
                          topic : \(bundleID).push-type.liveactivity
                        """)
                    // TODO: Send tokenString + topic to your server.
                }
            }
        }
    }
}
