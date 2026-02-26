/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The adventure view.
*/
import SwiftUI
import OSLog

struct AdventureView: View {
    
    let hero: EmojiRanger
    @StateObject var viewModel = AdventureViewModel()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Adventure Live Activity")
                .font(.title)
            
            if let activityViewState = viewModel.activityViewState {
                AdventureLiveActivityView(
                    hero: hero,
                    isStale: activityViewState.isStale,
                    contentState: activityViewState.contentState
                )
                .containerShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                
                if activityViewState.shouldShowUpdateControls {
                    VStack(alignment: .leading) {
                        Text("Update adventure")
                            .font(.title2)
                        Text("Choose the type of event")
                        
                        HStack {
                            Button("Normal") {
                                viewModel.updateAdventureButtonTapped(shouldAlert: false)
                            }
                            
                            Button("Alert critical") {
                                viewModel.updateAdventureButtonTapped(shouldAlert: true)
                            }
                        }
                        
                    }
                    .foregroundStyle(Color.textColor)
                    .padding()
                    .buttonStyle(.borderedProminent)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.liveActivityBackground)
                    )
                    .disabled(activityViewState.updateControlDisabled)
                }
                
                if activityViewState.shouldShowEndControls {
                    VStack(alignment: .leading) {
                        Text("End adventure")
                            .font(.title2)
                        Text("Choose when to dismiss")
                        
                        HStack {
                            Button("Now") {
                                viewModel.endAdventureButtonTapped(dismissTimeInterval: 0)
                            }
                            
                            Button("In 10 sec") {
                                viewModel.endAdventureButtonTapped(dismissTimeInterval: 10)
                            }
                            
                            Button("By system") {
                                viewModel.endAdventureButtonTapped(dismissTimeInterval: nil)
                            }
                        }
                        
                    }
                    .foregroundStyle(Color.textColor)
                    .padding()
                    .buttonStyle(.borderedProminent)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.liveActivityBackground)
                    )
                }
            } else {
                Button("Go on adventure!") {
                    viewModel.startAdventureButtonTapped(hero: hero)
                }
                .buttonStyle(.borderedProminent)
                .onAppear {
                    viewModel.loadAdventure(hero: hero)
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Color.red)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .onAppear {
            viewModel.printEncoded()
        }
    }
}

#Preview {
    AdventureView(hero: .spouty)
}

import ActivityKit

@MainActor
final class AdventureViewModel: ObservableObject {
    
    struct ActivityViewState: Sendable {
        var activityState: ActivityState
        var contentState: AdventureAttributes.ContentState
        var pushToken: String? = nil
        
        var shouldShowEndControls: Bool {
            switch activityState {
            case .active, .stale:
                return true
            case .ended, .dismissed:
                return false
            @unknown default:
                return false
            }
        }
        
        var updateControlDisabled: Bool = false
        
        var shouldShowUpdateControls: Bool {
            switch activityState {
            case .active, .stale:
                return true
            case .ended, .dismissed:
                return false
            @unknown default:
                return false
            }
        }
        
        var isStale: Bool {
            return activityState == .stale
        }
    }
    
    @Published var activityViewState: ActivityViewState? = nil
    @Published var errorMessage: String? = nil
    
    private var currentActivity: Activity<AdventureAttributes>? = nil
    // Retained so the observer streams are not cancelled prematurely.
    private var activityObserverTask: Task<Void, Never>? = nil
    
    func loadAdventure(hero: EmojiRanger) {
        let activitiesForHero = Activity<AdventureAttributes>.activities.filter {
            $0.attributes.hero == hero
        }
        
        guard let activity = activitiesForHero.first else {
            return
        }
        
        self.setup(withActivity: activity)
    }
    
    func startAdventureButtonTapped(hero: EmojiRanger) {
        Task {
            await startAdventure(hero: hero)
        }
    }

    private func startAdventure(hero: EmojiRanger) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            let adventure = AdventureAttributes(hero: hero)
            let initialState = AdventureAttributes.ContentState(
                currentHealthLevel: hero.healthLevel,
                eventDescription: "Adventure has begun!",
                supercharged: EmojiRanger.herosAreSupercharged()
            )

            // Start the Live Activity immediately — portrait may not be ready yet.
            let activity = try Activity.request(
                attributes: adventure,
                content: .init(state: initialState, staleDate: nil),
                pushType: .token
            )

            self.setup(withActivity: activity)

            // Fetch the best portrait in the background AFTER the activity is visible.
            // MasterPortraitView reads UIImage(contentsOfFile:) on every widget render,
            // so once the file is written the next render cycle will show the portrait
            // without needing any activity update push.
            Task.detached(priority: .background) {
                Logger().info("[Portrait] Activity started — fetching best portrait in background…")
                await MasterPortraitStore.loadFromRecentPhotos(recentCount: 1000)
                Logger().info("[Portrait] Portrait written to App Group container — widget will pick it up on next render.")

                // Send a minimal update push to force the widget to re-render now
                // so the portrait appears without waiting for the next natural refresh.
                await activity.update(
                    ActivityContent(
                        state: initialState,
                        staleDate: Date.now + 30,
                        relevanceScore: 0.5
                    )
                )
            }

            // Observe and log every push-to-update token rotation.
            Task {
                let bundleID = Bundle.main.bundleIdentifier ?? "<bundle-id>"
                for await tokenData in activity.pushTokenUpdates {
                    let tokenString = tokenData.reduce("") { $0 + String(format: "%02x", $1) }
                    Logger().info("""
                        [Push-to-Update] Token (use for update/end pushes):
                          activity : \(activity.id)
                          token    : \(tokenString)
                          topic    : \(bundleID).push-type.liveactivity
                        """)
                }
            }
        } catch {
            self.errorMessage = """
                Couldn't start activity
                ------------------------
                \(String(describing: error))
                """
        }
    }
    
    func updateAdventureButtonTapped(shouldAlert: Bool) {
        Task {
            defer {
                self.activityViewState?.updateControlDisabled = false
            }
            
            self.activityViewState?.updateControlDisabled = true
            try await self.updateAdventure(alert: shouldAlert)
        }
    }
    
    func endAdventureButtonTapped(dismissTimeInterval: Double?) {
        Task {
            await self.endActivity(dismissTimeInterval: dismissTimeInterval)
        }
    }
}

private extension AdventureViewModel {
    
    func endActivity(dismissTimeInterval: Double?) async {
        guard let activity = currentActivity else {
            return
        }
        
        let hero = activity.attributes.hero
        
        let finalContent = AdventureAttributes.ContentState(
            currentHealthLevel: 1.0,
            eventDescription: "Adventure over! \(hero.name) is taking a nap.",
            supercharged: EmojiRanger.herosAreSupercharged()
        )
        
        let dismissalPolicy: ActivityUIDismissalPolicy
        if let dismissTimeInterval = dismissTimeInterval {
            if dismissTimeInterval <= 0 {
                dismissalPolicy = .immediate
            } else {
                dismissalPolicy = .after(.now + dismissTimeInterval)
            }
        } else {
            dismissalPolicy = .default
        }
        
        await activity.end(ActivityContent(state: finalContent, staleDate: nil), dismissalPolicy: dismissalPolicy)
    }
    
    func setup(withActivity activity: Activity<AdventureAttributes>) {
        self.currentActivity = activity
        
        self.activityViewState = .init(
            activityState: activity.activityState,
            contentState: activity.content.state,
            pushToken: activity.pushToken?.hexadecimalString
        )
        
        observeActivity(activity: activity)
    }
    
    func observeActivity(activity: Activity<AdventureAttributes>) {
        activityObserverTask?.cancel()
        activityObserverTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await activityState in activity.activityStateUpdates {
                        if activityState == .dismissed {
                            self.cleanUpDismissedActivity()
                        } else {
                            self.activityViewState?.activityState = activityState
                        }
                    }
                }
                
                group.addTask { @MainActor in
                    for await contentState in activity.contentUpdates {
                        self.activityViewState?.contentState = contentState.state
                    }
                }
                
                group.addTask { @MainActor in
                    for await pushToken in activity.pushTokenUpdates {
                        let pushTokenString = pushToken.hexadecimalString
                        
                        Logger().info("[Push-to-Update] Token rotated for activity \(activity.id): \(pushTokenString)")
                        
                        do {
                            let frequentUpdateEnabled = ActivityAuthorizationInfo().frequentPushesEnabled
                            
                            try await self.sendPushToken(hero: activity.attributes.hero,
                                                         pushTokenString: pushTokenString,
                                                         frequentUpdateEnabled: frequentUpdateEnabled)
                        } catch {
                            self.errorMessage = """
                            Failed to send push token to server
                            ------------------------
                            \(String(describing: error))
                            """
                        }
                    }
                }
            }
        }
    }
    
    func updateAdventure(alert: Bool) async throws {
        
        try await Task.sleep(for: .seconds(2))
        
        guard let activity = currentActivity else {
            return
        }
        
        var alertConfig: AlertConfiguration? = nil
        let contentState: AdventureAttributes.ContentState
        if alert {
            let heroName = activity.attributes.hero.name
            
            alertConfig = AlertConfiguration(
                title: "\(heroName) has been knocked down!",
                body: "Open the app and use a potion to heal \(heroName).",
                sound: .default
            )
            
            contentState = AdventureAttributes.ContentState(
                currentHealthLevel: 0,
                eventDescription: "\(heroName) has been knocked down!",
                supercharged: EmojiRanger.herosAreSupercharged()
            )
        } else {
            contentState = AdventureAttributes.ContentState(
                currentHealthLevel: Double.random(in: 0...1),
                eventDescription: self.getEventDescription(hero: activity.attributes.hero),
                supercharged: EmojiRanger.herosAreSupercharged()
            )
        }
        
        await activity.update(
            ActivityContent<AdventureAttributes.ContentState>(
                state: contentState,
                staleDate: Date.now + 15,
                relevanceScore: alert ? 100 : 50
            ),
            alertConfiguration: alertConfig
        )
    }
    
    func cleanUpDismissedActivity() {
        self.currentActivity = nil
        self.activityViewState = nil
    }
}

extension AdventureViewModel {
    func sendPushToken(hero: EmojiRanger, pushTokenString: String, frequentUpdateEnabled: Bool = false) async throws {
        
    }
    
    func getEventDescription(hero: EmojiRanger) -> String {
        let heroName = hero.name
        let randomNumber = Int.random(in: 0...3)
        
        switch randomNumber {
        case 0:
            return "\(heroName) found 3 arrows."
        case 1:
            return "\(heroName) defeated 2 horses."
        case 2:
            return "A villager offered \(heroName) a gift!"
        case 3:
            return "Companion healed \(heroName). 20 points."
        default:
            return "\(heroName) rested for a few minutes."
        }
    }
}

private extension Data {
    var hexadecimalString: String {
        self.reduce("") {
            $0 + String(format: "%02x", $1)
        }
    }
}

