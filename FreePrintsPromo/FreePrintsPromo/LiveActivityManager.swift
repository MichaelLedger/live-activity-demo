import ActivityKit
import Foundation

// MARK: - Data helper

extension Data {
    var hexString: String {
        map { String(format: "%02.2hhx", $0) }.joined()
    }
}

// MARK: - LiveActivityManager

@MainActor
class LiveActivityManager: ObservableObject {

    // Activity state tracking (keyed by PromoType.rawValue)
    @Published var activeActivities: [String: String] = [:]
    @Published var activityStates: [String: ActivityState] = [:]

    // Push tokens for server integration
    /// Send this token to your server so it can POST to APNs to *start*
    /// a new Live Activity even when the app is not running (iOS 17.2+).
    @Published var pushToStartToken: String?

    /// Per-activity push tokens. Send these to your server so it can POST to
    /// APNs to *update* or *end* an existing Live Activity at any time.
    @Published var activityPushTokens: [String: String] = [:]

    @Published var errorMessage: String?

    private var observationTasks: [String: Task<Void, Never>] = [:]
    private var autoEndTasks: [String: Task<Void, Never>] = [:]
    private var pushToStartObserverTask: Task<Void, Never>?

    // MARK: - Push-to-Start Token (iOS 17.2+)

    /// Call once on app launch. The system emits a new token whenever it rotates.
    /// Send every fresh token to your server — the old one becomes invalid.
    ///
    /// APNs payload to **start** an activity when the app is NOT running:
    /// ```json
    /// {
    ///   "aps": {
    ///     "timestamp": <Unix seconds>,
    ///     "event": "start",
    ///     "content-state": { <FreePrintsPromoAttributes.ContentState fields> },
    ///     "attributes-type": "FreePrintsPromoAttributes",
    ///     "attributes": { "promoId": "abc", "productType": "4x6 Prints" },
    ///     "alert": { "title": "New Offer!", "body": "10 FREE prints waiting" }
    ///   }
    /// }
    /// ```
    /// APNs headers: `apns-push-type: liveactivity`, `apns-topic: <bundleId>.push-type.liveactivity`
    func observePushToStartToken() {
        pushToStartObserverTask?.cancel()
        pushToStartObserverTask = Task {
            if #available(iOS 17.2, *) {
                for await tokenData in Activity<FreePrintsPromoAttributes>.pushToStartTokenUpdates {
                    guard !Task.isCancelled else { return }
                    pushToStartToken = tokenData.hexString
                    print("[Push-to-Start] Token: \(tokenData.hexString)")
                    // TODO: POST token to your server
                }
            }
        }
    }

    // MARK: - Restore on Launch

    func syncWithRunningActivities() {
        let running = Activity<FreePrintsPromoAttributes>.activities
        var restored: [String: String] = [:]
        var states: [String: ActivityState] = [:]

        for activity in running {
            let promoType = activity.content.state.promoType
            let endTime = activity.content.state.endTime

            // If endTime already passed while app was killed, end immediately.
            if endTime <= .now {
                Task { await autoEnd(activity) }
                continue
            }

            restored[promoType.rawValue] = activity.id
            states[promoType.rawValue] = activity.activityState
            observeActivity(activity) // also reschedules auto-end at endTime
        }

        activeActivities = restored
        activityStates = states
    }

    // MARK: - Observe Activity (state + push token)

    private func observeActivity(_ activity: Activity<FreePrintsPromoAttributes>) {
        let promoKey = activity.content.state.promoType.rawValue
        let activityId = activity.id

        // Cancel any existing observer for this activity ID
        observationTasks[activityId]?.cancel()

        // Schedule auto-end exactly at endTime (primary mechanism)
        scheduleAutoEnd(for: activity, at: activity.content.state.endTime)

        // Watch activity lifecycle state
        observationTasks[activityId] = Task {
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                activityStates[promoKey] = state

                switch state {
                case .dismissed, .ended:
                    // Clean up after system or manual end
                    cleanUp(promoKey: promoKey, activityId: activityId)
                    return
                case .stale:
                    // Fallback: app was suspended and the scheduled task fired late.
                    // Cancel the scheduled task to avoid a double-end, push the
                    // ended content state, wait 5s, then dismiss.
                    autoEndTasks[promoKey]?.cancel()
                    let dismissAt = Date.now.addingTimeInterval(5)
                    await pushEndedUpdate(activity, dismissAt: dismissAt)
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await autoEnd(activity)
                    return
                default:
                    break
                }
            }
        }

        // Watch push token rotation
        // The token changes whenever iOS rotates it — always send the latest to your server.
        //
        // APNs payload to **update** an existing activity:
        // { "aps": { "timestamp": <Unix seconds>, "event": "update",
        //            "content-state": { <ContentState fields> } } }
        //
        // APNs payload to **end** an existing activity:
        // { "aps": { "timestamp": <Unix seconds>, "event": "end",
        //            "content-state": { <final ContentState> },
        //            "dismissal-date": <Unix seconds> } }
        //
        // APNs headers: `apns-push-type: liveactivity`
        //               `apns-topic: <bundleId>.push-type.liveactivity`
        Task {
            for await tokenData in activity.pushTokenUpdates {
                activityPushTokens[promoKey] = tokenData.hexString
                print("[Push-to-Update] \(promoKey) token: \(tokenData.hexString)")
                // TODO: POST token to your server
            }
        }
    }

    // MARK: - Auto-End Helpers

    /// Two-step auto-end sequence:
    ///
    ///   endTime      → activity.update("ended" state)  → widget switches to ended UI via content state
    ///   endTime + 5s → activity.end(.immediate)        → banner fully dismissed
    private func scheduleAutoEnd(
        for activity: Activity<FreePrintsPromoAttributes>,
        at endTime: Date
    ) {
        let promoKey = activity.content.state.promoType.rawValue
        autoEndTasks[promoKey]?.cancel()
        autoEndTasks[promoKey] = Task {
            // ── Step 1: push "ended" content state at endTime ──────────────────
            let delayToEnd = endTime.timeIntervalSinceNow
            if delayToEnd > 0 {
                try? await Task.sleep(for: .seconds(delayToEnd))
            }
            guard !Task.isCancelled else { return }
            await pushEndedUpdate(activity, dismissAt: endTime.addingTimeInterval(5))

            // ── Step 2: dismiss 5 seconds later ────────────────────────────────
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await autoEnd(activity)
        }
    }

    /// Pushes an `activity.update()` with the "ended" content state.
    /// The widget switches to the ended UI immediately via content state change.
    /// `staleDate` is set to `dismissAt` so `context.isStale` also fires then.
    private func pushEndedUpdate(
        _ activity: Activity<FreePrintsPromoAttributes>,
        dismissAt: Date
    ) async {
        let promoType = activity.content.state.promoType
        let endedState = endedContentState(for: activity)
        await activity.update(
            ActivityContent(state: endedState, staleDate: dismissAt)
        )
    }

    /// Dismisses the banner after the 5-second display window has elapsed.
    private func autoEnd(_ activity: Activity<FreePrintsPromoAttributes>) async {
        let endedState = endedContentState(for: activity)
        await activity.end(
            ActivityContent(state: endedState, staleDate: .now),
            dismissalPolicy: .immediate
        )
        cleanUp(promoKey: activity.content.state.promoType.rawValue, activityId: activity.id)
    }

    /// Builds the final "ended" ContentState for any promo type.
    /// `isExpired: true` tells the widget to hide countdowns immediately
    /// on the content state change, before `context.isStale` fires.
    private func endedContentState(
        for activity: Activity<FreePrintsPromoAttributes>
    ) -> FreePrintsPromoAttributes.ContentState {
        let promoType = activity.content.state.promoType
        return FreePrintsPromoAttributes.ContentState(
            promoTitle: promoType == .freePrints ? "Offer has ended"
                      : promoType == .flashSale  ? "Sale has ended"
                      : "Delivery complete",
            promoSubtitle: promoType == .freePrints ? "Thanks for your interest!"
                         : promoType == .flashSale  ? "This offer has expired"
                         : "Your prints have arrived!",
            discount: "",
            endTime: activity.content.state.endTime,
            promoType: promoType,
            progress: promoType == .orderTracking ? activity.content.state.progress : 1.0,
            currentStep: promoType == .orderTracking ? activity.content.state.currentStep : "Complete",
            itemCount: activity.content.state.itemCount,
            isExpired: true
        )
    }

    private func cleanUp(promoKey: String, activityId: String) {
        activeActivities.removeValue(forKey: promoKey)
        activityStates.removeValue(forKey: promoKey)
        activityPushTokens.removeValue(forKey: promoKey)
        autoEndTasks[promoKey]?.cancel()
        autoEndTasks.removeValue(forKey: promoKey)
        observationTasks[activityId]?.cancel()
        observationTasks.removeValue(forKey: activityId)
    }

    // MARK: - Start: Free Prints Promo

    func startFreePrintsPromo() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "Live Activities are not enabled. Please enable them in Settings."
            return
        }

        let endTime = Calendar.current.date(byAdding: .second, value: 10, to: .now)!
        let attributes = FreePrintsPromoAttributes(promoId: UUID().uuidString, productType: "4x6 Prints")
        let state = FreePrintsPromoAttributes.ContentState(
            promoTitle: "10 FREE Prints!",
            promoSubtitle: "Just pay shipping • Limited time",
            discount: "FREE",
            endTime: endTime,
            promoType: .freePrints,
            progress: 0,
            currentStep: "",
            itemCount: 10
        )

        request(attributes: attributes, state: state, promoType: .freePrints, endTime: endTime,
                errorPrefix: "Failed to start Free Prints promo")
    }

    // MARK: - Start: Flash Sale

    func startFlashSale() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "Live Activities are not enabled. Please enable them in Settings."
            return
        }

        let endTime = Calendar.current.date(byAdding: .second, value: 10, to: .now)!
        let attributes = FreePrintsPromoAttributes(promoId: UUID().uuidString, productType: "Photo Books")
        let state = FreePrintsPromoAttributes.ContentState(
            promoTitle: "50% OFF Photo Books",
            promoSubtitle: "Flash sale ends soon!",
            discount: "50%",
            endTime: endTime,
            promoType: .flashSale,
            progress: 0,
            currentStep: "",
            itemCount: 0
        )

        request(attributes: attributes, state: state, promoType: .flashSale, endTime: endTime,
                errorPrefix: "Failed to start Flash Sale")
    }

    // MARK: - Start: Order Tracking

    func startOrderTracking() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "Live Activities are not enabled. Please enable them in Settings."
            return
        }

        let endTime = Calendar.current.date(byAdding: .second, value: 10, to: .now)!
        let attributes = FreePrintsPromoAttributes(promoId: UUID().uuidString, productType: "Photo Prints")
        let state = FreePrintsPromoAttributes.ContentState(
            promoTitle: "Your Prints Are On The Way!",
            promoSubtitle: "Estimated delivery: 2-3 days",
            discount: "",
            endTime: endTime,
            promoType: .orderTracking,
            progress: 0.35,
            currentStep: "Shipped",
            itemCount: 25
        )

        request(attributes: attributes, state: state, promoType: .orderTracking, endTime: endTime,
                errorPrefix: "Failed to start Order Tracking")
    }

    // MARK: - Generic Request

    private func request(
        attributes: FreePrintsPromoAttributes,
        state: FreePrintsPromoAttributes.ContentState,
        promoType: PromoType,
        endTime: Date,
        errorPrefix: String
    ) {
        let content = ActivityContent(state: state, staleDate: endTime)
        do {
            // pushType: .token enables push-to-update AND push-to-start token delivery
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                //pushType: .token
                pushType: nil
            )
            activeActivities[promoType.rawValue] = activity.id
            activityStates[promoType.rawValue] = activity.activityState
            observeActivity(activity)
            errorMessage = nil
        } catch {
            errorMessage = "\(errorPrefix): \(error.localizedDescription)"
        }
    }

    // MARK: - Update Order Progress

    func updateOrderProgress(to progress: Double, step: String) async {
        guard let activityId = activeActivities[PromoType.orderTracking.rawValue] else { return }
        guard let activity = Activity<FreePrintsPromoAttributes>.activities.first(where: { $0.id == activityId }) else { return }

        let endTime = Calendar.current.date(byAdding: .second, value: 10, to: .now)!
        let updatedState = FreePrintsPromoAttributes.ContentState(
            promoTitle: "Your Prints Are On The Way!",
            promoSubtitle: step == "Delivered" ? "Your prints have arrived!" : "Estimated delivery: 2-3 days",
            discount: "",
            endTime: endTime,
            promoType: .orderTracking,
            progress: progress,
            currentStep: step,
            itemCount: 25
        )
        await activity.update(ActivityContent(state: updatedState, staleDate: endTime))
    }

    // MARK: - End Activity

    func endActivity(for promoType: PromoType) async {
        guard let activityId = activeActivities[promoType.rawValue] else { return }
        guard let activity = Activity<FreePrintsPromoAttributes>.activities.first(where: { $0.id == activityId }) else { return }

        let finalState = FreePrintsPromoAttributes.ContentState(
            promoTitle: "Promo Ended",
            promoSubtitle: "Thanks for checking out our deals!",
            discount: "",
            endTime: .now,
            promoType: promoType,
            progress: 1.0,
            currentStep: "Complete",
            itemCount: 0
        )
        let dismissAt = Date.now.addingTimeInterval(5)
        await activity.end(
            ActivityContent(state: finalState, staleDate: dismissAt),
            dismissalPolicy: .after(dismissAt)
        )
        cleanUp(promoKey: promoType.rawValue, activityId: activityId)
    }

    func endAllActivities() async {
        for activity in Activity<FreePrintsPromoAttributes>.activities {
            let promoType = activity.content.state.promoType
            let finalState = FreePrintsPromoAttributes.ContentState(
                promoTitle: "Promo Ended",
                promoSubtitle: "Thanks for visiting!",
                discount: "",
                endTime: .now,
                promoType: promoType,
                progress: 1.0,
                currentStep: "Complete",
                itemCount: 0
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: .now),
                dismissalPolicy: .immediate
            )
            cleanUp(promoKey: promoType.rawValue, activityId: activity.id)
        }
    }
}
