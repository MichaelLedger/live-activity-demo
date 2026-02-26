import ActivityKit
import SwiftUI

// MARK: - Promo Types

enum PromoType: String, Codable, Hashable, CaseIterable {
    case freePrints
    case flashSale
    case orderTracking

    var displayName: String {
        switch self {
        case .freePrints: return "Free Prints"
        case .flashSale: return "Flash Sale"
        case .orderTracking: return "Order Tracking"
        }
    }

    var iconName: String {
        switch self {
        case .freePrints: return "photo.on.rectangle.angled"
        case .flashSale: return "bolt.fill"
        case .orderTracking: return "shippingbox.fill"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .freePrints:
            return [Color(hex: "667EEA"), Color(hex: "764BA2")]
        case .flashSale:
            return [Color(hex: "F857A6"), Color(hex: "FF5858")]
        case .orderTracking:
            return [Color(hex: "11998E"), Color(hex: "38EF7D")]
        }
    }
}

// MARK: - Activity Attributes

struct FreePrintsPromoAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var promoTitle: String
        var promoSubtitle: String
        var discount: String
        var endTime: Date
        var promoType: PromoType
        var progress: Double
        var currentStep: String
        var itemCount: Int
        /// Set to `true` when `pushEndedUpdate` is called at endTime.
        /// The widget uses this to hide countdowns immediately on the content
        /// state change, before `context.isStale` fires 5 seconds later.
        var isExpired: Bool = false
    }

    var promoId: String
    var productType: String
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
