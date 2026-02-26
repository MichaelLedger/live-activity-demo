import SwiftUI
import ActivityKit

struct ContentView: View {
    @StateObject private var manager = LiveActivityManager()
    @State private var showingEndAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    promoCards
                    activeActivitiesSection
                    endAllButton
                    pushTokensPanel
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FreePrints Promos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEndAlert = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("End All Activities?", isPresented: $showingEndAlert) {
                Button("Cancel", role: .cancel) {}
                Button("End All", role: .destructive) {
                    Task { await manager.endAllActivities() }
                }
            } message: {
                Text("This will dismiss all active Live Activity banners.")
            }
            .overlay {
                if let error = manager.errorMessage {
                    errorBanner(error)
                }
            }
            .onAppear {
                manager.syncWithRunningActivities()
                manager.observePushToStartToken()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 8)

            Text("Live Activity Demo")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Tap a card to launch a Live Activity promo banner on your Lock Screen and Dynamic Island.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Promo Cards

    private var promoCards: some View {
        VStack(spacing: 16) {
            PromoCard(
                promoType: .freePrints,
                title: "10 FREE Prints",
                subtitle: "Just pay shipping — no strings attached",
                badge: "FREE",
                isActive: manager.activeActivities[PromoType.freePrints.rawValue] != nil
            ) {
                manager.startFreePrintsPromo()
            } onEnd: {
                Task { await manager.endActivity(for: .freePrints) }
            }

            PromoCard(
                promoType: .flashSale,
                title: "50% OFF Photo Books",
                subtitle: "Lightning deal — only 30 minutes left",
                badge: "50% OFF",
                isActive: manager.activeActivities[PromoType.flashSale.rawValue] != nil
            ) {
                manager.startFlashSale()
            } onEnd: {
                Task { await manager.endActivity(for: .flashSale) }
            }

            PromoCard(
                promoType: .orderTracking,
                title: "Track Your Order",
                subtitle: "Follow your prints from production to doorstep",
                badge: "LIVE",
                isActive: manager.activeActivities[PromoType.orderTracking.rawValue] != nil
            ) {
                manager.startOrderTracking()
            } onEnd: {
                Task { await manager.endActivity(for: .orderTracking) }
            }
        }
    }

    // MARK: - Active Activities

    @ViewBuilder
    private var activeActivitiesSection: some View {
        if !manager.activeActivities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Active Live Activities", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .padding(.leading, 4)

                ForEach(Array(manager.activeActivities.keys), id: \.self) { key in
                    if let promoType = PromoType(rawValue: key) {
                        ActiveActivityRow(
                            promoType: promoType,
                            state: manager.activityStates[key]
                        )
                    }
                }

                if manager.activeActivities[PromoType.orderTracking.rawValue] != nil {
                    orderTrackingControls
                }
            }
            .padding(.top, 8)
        }
    }

    private var orderTrackingControls: some View {
        VStack(spacing: 10) {
            Text("Update Order Progress")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(
                    [("Printed", 0.5), ("Shipped", 0.7), ("Out for Delivery", 0.9), ("Delivered", 1.0)],
                    id: \.0
                ) { step, progress in
                    Button {
                        Task { await manager.updateOrderProgress(to: progress, step: step) }
                    } label: {
                        Text(step)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    Color(hex: "11998E").opacity(0.15)
                                )
                            )
                            .foregroundStyle(Color(hex: "11998E"))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - End All

    @ViewBuilder
    private var endAllButton: some View {
        if !manager.activeActivities.isEmpty {
            Button {
                showingEndAlert = true
            } label: {
                Label("End All Activities", systemImage: "stop.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.red.opacity(0.08))
                    )
            }
        }
    }

    // MARK: - Push Tokens Panel

    @ViewBuilder
    private var pushTokensPanel: some View {
        let hasAnyToken = manager.pushToStartToken != nil || !manager.activityPushTokens.isEmpty
        if hasAnyToken {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Copy tokens and send to your APNs server for push-triggered Live Activities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let token = manager.pushToStartToken {
                        TokenRow(
                            label: "Push-to-Start",
                            sublabel: "Starts a new activity when app is not running",
                            token: token,
                            color: .purple
                        )
                    }

                    ForEach(Array(manager.activityPushTokens.keys.sorted()), id: \.self) { key in
                        if let token = manager.activityPushTokens[key],
                           let promoType = PromoType(rawValue: key) {
                            TokenRow(
                                label: "\(promoType.displayName) Update Token",
                                sublabel: "Updates or ends the running \(promoType.displayName) activity",
                                token: token,
                                color: promoType.gradientColors.first ?? .gray
                            )
                        }
                    }

                    pushPayloadReference
                }
                .padding(.top, 8)
            } label: {
                Label("Push Token Dev Panel", systemImage: "key.horizontal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private var pushPayloadReference: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APNs Payload Reference")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach([
                ("event: start", "Starts activity (uses push-to-start token)", "play.circle.fill", Color.purple),
                ("event: update", "Updates content-state (uses update token)", "arrow.triangle.2.circlepath", Color.blue),
                ("event: end", "Ends activity (uses update token)", "stop.circle.fill", Color.red)
            ], id: \.0) { event, desc, icon, color in
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event)
                            .font(.caption.weight(.semibold).monospaced())
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.red.gradient)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    withAnimation { manager.errorMessage = nil }
                }
        }
        .animation(.spring(response: 0.4), value: manager.errorMessage)
    }
}

// MARK: - Promo Card

struct PromoCard: View {
    let promoType: PromoType
    let title: String
    let subtitle: String
    let badge: String
    let isActive: Bool
    let onStart: () -> Void
    let onEnd: () -> Void

    var body: some View {
        Button(action: isActive ? onEnd : onStart) {
            HStack(spacing: 16) {
                iconView
                textContent
                Spacer(minLength: 0)
                actionBadge
            }
            .padding(20)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isActive)
    }

    private var iconView: some View {
        Image(systemName: promoType.iconName)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: promoType.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionBadge: some View {
        Group {
            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            } else {
                Text(badge)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: promoType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.background)
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? LinearGradient(colors: promoType.gradientColors, startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - Active Activity Row

struct ActiveActivityRow: View {
    let promoType: PromoType
    var state: ActivityState?

    private var stateLabel: String {
        switch state {
        case .active: return "Running"
        case .ended: return "Ended"
        case .dismissed: return "Dismissed"
        case .stale: return "Stale"
        case .none: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var stateColor: Color {
        switch state {
        case .active: return .green
        case .stale: return .orange
        case .ended, .dismissed: return .secondary
        case .none: return .secondary
        @unknown default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: promoType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 10, height: 10)

            Text(promoType.displayName)
                .font(.subheadline.weight(.medium))

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                Text(stateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stateColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(stateColor.opacity(0.12)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Token Row

struct TokenRow: View {
    let label: String
    let sublabel: String
    let token: String
    let color: Color

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(sublabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = token
                    withAnimation(.spring(response: 0.3)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? .green : color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill((copied ? Color.green : color).opacity(0.12))
                        )
                }
            }

            Text(token)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
        )
    }
}

#Preview {
    ContentView()
}
