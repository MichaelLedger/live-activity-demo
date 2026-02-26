import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct PromoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FreePrintsPromoAttributes.self) { context in
            LockScreenBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(context: context)
                }
            } compactLeading: {
                compactLeading(context: context)
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                minimalView(context: context)
            }
        }
    }

    // MARK: - Dynamic Island Compact

    @ViewBuilder
    private func compactLeading(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        Image(systemName: context.state.promoType.iconName)
            .font(.body.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: context.state.promoType.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        // context.isStale is true once staleDate (== endTime) is reached.
        // The system guarantees a re-render at that moment — no TimelineView needed.
        let expired = context.state.isExpired || context.isStale
        let orderComplete = context.state.progress >= 1.0

        Group {
            switch context.state.promoType {
            case .freePrints:
                if expired {
                    Text("ENDED")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                } else {
                    Text("FREE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color(hex: "667EEA"))
                }
            case .flashSale:
                if expired {
                    Text("ENDED")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                } else {
                    Text(context.state.endTime, style: .timer)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color(hex: "F857A6"))
                        .frame(minWidth: 40)
                }
            case .orderTracking:
                if orderComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "11998E"))
                } else {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "11998E"))
                        .scaleEffect(0.6)
                }
            }
        }
    }

    // MARK: - Dynamic Island Minimal

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        Image(systemName: context.state.promoType.iconName)
            .font(.body.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: context.state.promoType.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Dynamic Island Expanded

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        Image(systemName: context.state.promoType.iconName)
            .font(.title2.weight(.bold))
            .foregroundStyle(
                LinearGradient(
                    colors: context.state.promoType.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.leading, 4)
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        let expired = context.state.isExpired || context.isStale
        let orderComplete = context.state.promoType == .orderTracking && context.state.progress >= 1.0
        let showEnded = (expired && context.state.promoType != .orderTracking) || orderComplete

        if showEnded {
            Text("Ended")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
        } else if !context.state.discount.isEmpty {
            Text(context.state.discount)
                .font(.title3.weight(.black))
                .foregroundStyle(
                    LinearGradient(
                        colors: context.state.promoType.gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private func expandedCenter(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        let expired = context.state.isExpired || context.isStale
        let orderComplete = context.state.promoType == .orderTracking && context.state.progress >= 1.0
        let showEnded = (expired && context.state.promoType != .orderTracking) || orderComplete

        if showEnded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                Text("Ended")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.secondary)
        } else {
            Text(context.state.promoTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        switch context.state.promoType {
        case .freePrints:
            freePrintsExpandedBottom(context: context)
        case .flashSale:
            flashSaleExpandedBottom(context: context)
        case .orderTracking:
            orderTrackingExpandedBottom(context: context)
        }
    }

    // MARK: - Expanded Bottom: Free Prints

    private func freePrintsExpandedBottom(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        Group {
            if context.state.isExpired || context.isStale {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.body.weight(.semibold))
                    Text("Offer has ended")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    Text(context.state.promoSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: context.state.promoType.gradientColors,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 28, height: 34)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                )
                                .rotationEffect(.degrees(Double(i - 2) * 3))
                        }
                    }

                    HStack {
                        Text("Offer expires in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.endTime, style: .timer)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color(hex: "667EEA"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Expanded Bottom: Flash Sale

    private func flashSaleExpandedBottom(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        Group {
            if context.state.isExpired || context.isStale {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.body.weight(.semibold))
                    Text("Sale has ended")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    Text(context.state.promoSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: "F857A6"))
                        Text("Ends in")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(context.state.endTime, style: .timer)
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(Color(hex: "F857A6"))
                    }

                    Link(destination: URL(string: "freeprints://promo/flashsale")!) {
                        Text("Shop Now")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(hex: "F857A6"), Color(hex: "FF5858")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Expanded Bottom: Order Tracking

    private func orderTrackingExpandedBottom(context: ActivityViewContext<FreePrintsPromoAttributes>) -> some View {
        let complete = context.state.progress >= 1.0

        return Group {
            if complete {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(hex: "11998E"))
                    Text("Delivered")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    OrderProgressBar(progress: context.state.progress, currentStep: context.state.currentStep)

                    HStack {
                        Label("\(context.state.itemCount) prints", systemImage: "photo.stack")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(context.state.promoSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Lock Screen Banner

struct LockScreenBannerView: View {
    let context: ActivityViewContext<FreePrintsPromoAttributes>

    var body: some View {
        switch context.state.promoType {
        case .freePrints:
            freePrintsBanner
        case .flashSale:
            flashSaleBanner
        case .orderTracking:
            orderTrackingBanner
        }
    }

    // MARK: - Free Prints Banner

    private var freePrintsBanner: some View {
        let expired = context.state.isExpired || context.isStale

        return HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: expired ? "clock.badge.xmark" : "photo.on.rectangle.angled")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white.opacity(expired ? 0.7 : 1))
                if expired {
                    Text("ENDED")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(1)
                } else {
                    Text("10")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("FREE")
                        .font(.caption2.weight(.black))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(expired ? "Offer has ended" : context.state.promoTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(expired ? 0.85 : 1))

                if expired {
                    Text("Thanks for your interest")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text(context.state.promoSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(context.state.endTime, style: .timer)
                            .font(.caption.weight(.bold).monospacedDigit())
                        Text("remaining")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            if !expired {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(.clear)
    }

    // MARK: - Flash Sale Banner

    private var flashSaleBanner: some View {
        let expired = context.state.isExpired || context.isStale

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(expired ? 0.15 : 0.2))
                    .frame(width: 64, height: 64)
                if expired {
                    Image(systemName: "clock.badge.xmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    VStack(spacing: 0) {
                        Text(context.state.discount)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("OFF")
                            .font(.system(size: 10, weight: .black))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if expired {
                    Text("Sale has ended")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("This offer has expired")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                        Text("FLASH SALE")
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.yellow)

                    Text(context.state.promoTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                        Text(context.state.endTime, style: .timer)
                            .font(.caption.weight(.heavy).monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            if !expired {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "F857A6"), Color(hex: "FF5858")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .activityBackgroundTint(.clear)
    }

    // MARK: - Order Tracking Banner

    private var orderTrackingBanner: some View {
        let complete = context.state.progress >= 1.0

        return VStack(spacing: 12) {
            HStack {
                Image(systemName: complete ? "checkmark.circle.fill" : "shippingbox.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: "11998E"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(complete ? "Delivered" : context.state.promoTitle)
                        .font(.subheadline.weight(.bold))
                    Text(complete ? "Your prints have arrived!" : context.state.promoSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if complete {
                    Text("Complete")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "11998E")))
                } else {
                    Text("\(context.state.itemCount) prints")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "11998E").opacity(0.15)))
                        .foregroundStyle(Color(hex: "11998E"))
                }
            }

            OrderProgressBar(
                progress: context.state.progress,
                currentStep: context.state.currentStep,
                isComplete: complete
            )
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground))
    }
}

// MARK: - Order Progress Bar

struct OrderProgressBar: View {
    let progress: Double
    let currentStep: String
    var isComplete: Bool = false

    private let steps = ["Ordered", "Printed", "Shipped", "Delivered"]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "11998E"), Color(hex: "38EF7D")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            if isComplete {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "11998E"))
                    Text("All steps complete")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "11998E"))
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    ForEach(steps, id: \.self) { step in
                        Text(step)
                            .font(.system(size: 9, weight: step == currentStep ? .bold : .regular))
                            .foregroundStyle(step == currentStep ? Color(hex: "11998E") : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
