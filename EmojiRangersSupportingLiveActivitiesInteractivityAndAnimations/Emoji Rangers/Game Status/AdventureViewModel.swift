/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The adventure view model.
*/
import ActivityKit
import Foundation
import os.log

extension AdventureViewModel {
    
    typealias ServerManager = AdventureViewModel
    
    func startActivity(hero: EmojiRanger) throws {
        let adventure = AdventureAttributes(hero: hero)
        let initialState = AdventureAttributes.ContentState(
            currentHealthLevel: hero.healthLevel,
            eventDescription: "Adventure has begun!",
            supercharged: EmojiRanger.herosAreSupercharged()
        )
        
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let activity = try Activity.request(
                attributes: adventure,
                content: .init(state: initialState, staleDate: nil),
                pushType: .token
            )
            
            //        let pushToken = activity.pushToken // Returns nil.
            
            Task {
                for await pushToken in activity.pushTokenUpdates {
                    let pushTokenString = pushToken.reduce("") {
                        $0 + String(format: "%02x", $1)
                    }
                    
                    Logger().log("New push token: \(pushTokenString)")
                    
                    try await self.sendPushToken(hero: hero, pushTokenString: pushTokenString)
                }
            }
        }
    }
    
    func printEncoded() {
        let contentState = AdventureAttributes.ContentState(
            currentHealthLevel: 0.941,
            eventDescription: "Power Panda found a sword!",
            supercharged: EmojiRanger.herosAreSupercharged()
        )
        
        // Use default (camelCase) key encoding — this matches what ActivityKit's
        // APNs decoder expects in the "content-state" payload field.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let json = try! encoder.encode(contentState)
        Logger().log("content-state (camelCase, use this in APNs payload):\n\(String(data: json, encoding: .utf8)!)")
    }
    
    func showWarningBadge(_ shouldShow: Bool) {
        
    }
    
    func observeFrequentUpdate() {
        Task {
            for await isEnabled in ActivityAuthorizationInfo().frequentPushEnablementUpdates {
                self.showWarningBadge(!isEnabled)
            }
        }
    }
    
    // Content updates from push notifications are handled by the
    // activityObserverTask in AdventureView.swift via activity.contentUpdates.
    // The widget extension (EmojiRangerWidgetExtension) handles Lock Screen /
    // Dynamic Island rendering independently — it is woken directly by APNs.
}
