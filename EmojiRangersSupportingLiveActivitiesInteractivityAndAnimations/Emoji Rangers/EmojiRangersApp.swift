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

    // Retained so the async streams are not cancelled prematurely.
    private var pushPermissionTask: Task<Void, Never>?
    private var pushToStartObserverTask: Task<Void, Never>?
    private var activityUpdatesTask: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        pushPermissionTask = Task { await requestPushPermissions() }
        observePushToStartToken()
        observeNewActivities()
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

    // MARK: - New Activity Observer (TEST: portrait fetch for push-started activities)

    /// Observes all newly created AdventureAttributes activities — including those
    /// started remotely via a push-to-start APNs payload.
    ///
    /// When a new activity is detected, this fetches the best portrait from the
    /// photo library using Vision scoring (iOS 18+) and writes it to the App Group
    /// container, then triggers an in-app activity.update() so the widget re-renders
    /// and shows the portrait immediately.
    ///
    /// TEST ONLY — remove the portrait fetch block when done testing.
    private func observeNewActivities() {
        activityUpdatesTask?.cancel()
        activityUpdatesTask = Task {
            for await activity in Activity<AdventureAttributes>.activityUpdates {
                // Only handle newly active activities
                guard activity.activityState == .active else { continue }

                logger.info("[Portrait] New activity detected: \(activity.id) — fetching best portrait…")

                Task.detached(priority: .background) {
                    // TEST: fetch Vision-scored best portrait from the last 1000 photos.
                    await MasterPortraitStore.loadFromRecentPhotos(recentCount: 1000)
                    self.logger.info("[Portrait] Portrait written — triggering widget re-render for activity \(activity.id).")

                    // Force a widget re-render by updating the activity with the same
                    // content state. The widget reads UIImage(contentsOfFile:) on every
                    // render, so it will now find and display the new portrait.
                    let currentState = activity.content.state
                    await activity.update(
                        ActivityContent(
                            state: currentState,
                            staleDate: Date.now + 30,
                            relevanceScore: 0.5
                        )
                    )
                    self.logger.info("[Portrait] Activity \(activity.id) re-rendered with portrait.")
                }
            }
        }
    }

    // MARK: - Push-to-Start Token (iOS 17.2+ / iOS 18 input-push-token)

    /// Observes the push-to-start token so a server can remotely start a Live Activity.
    /// On iOS 18+, include `"input-push-token": 1` in the APNs payload to receive a
    /// refreshed token that can be used to start a new Live Activity via push.
    private func observePushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        // Retained on self — keeps the stream alive for the entire app session.
        // The stream only emits when the token is first issued or rotated by APNs,
        // NOT on every app launch, so this is safe and cheap to observe continuously.
        pushToStartObserverTask = Task {
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
                // IMPORTANT: Always replace the previously stored token — the old one
                // is immediately invalid once a new token is issued. In the sandbox
                // (development) environment APNs rotates this token on every launch;
                // in production it rotates far less frequently (days/weeks).
            }
        }
    }
}
