import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedTier = "pro"
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var contextMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                EEColors.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Context message
                        if let msg = contextMessage {
                            contextBanner(msg)
                        }

                        // Tier toggle
                        tierToggle

                        // Plan cards
                        planCards

                        // Billing toggle
                        billingToggle

                        // Purchase button
                        purchaseButton

                        // Restore
                        restoreButton

                        // Terms
                        termsSection

                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(EEColors.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Equi")
                    .font(.title2.weight(.light))
                    .foregroundStyle(EEColors.textPrimary)
                Text("Edge")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(EEColors.edgeGradientHorizontal)
                Text(" Premium")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(EEColors.textPrimary)
            }

            Text("Unlock AI-powered race analysis")
                .font(.subheadline)
                .foregroundStyle(EEColors.textSecondary)
        }
    }

    // MARK: - Context Banner

    private func contextBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(EEColors.gold)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(EEColors.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(EEColors.gold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EEColors.gold.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Tier Toggle

    private var tierToggle: some View {
        HStack(spacing: 0) {
            tierTab(title: "Basic", tier: "basic")
            tierTab(title: "Pro", tier: "pro")
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(EEColors.bgCard)
        )
    }

    private func tierTab(title: String, tier: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTier = tier }
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selectedTier == tier ? .white : EEColors.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedTier == tier ? EEColors.emerald.opacity(0.2) : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedTier == tier ? EEColors.emerald.opacity(0.4) : .clear, lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 0) {
            if selectedTier == "basic" {
                planDetail(
                    features: [
                        ("10.circle.fill", "10 track-day analyses per week"),
                        ("arrow.clockwise", "Free re-runs on same day"),
                        ("brain.head.profile", "Full 10-step AI analysis"),
                        ("chart.bar.fill", "ML confidence scores"),
                        ("bolt.fill", "Live track intel"),
                    ],
                    monthlyPrice: "$14.99",
                    annualPrice: "$11.99",
                    annualTotal: "$143.88"
                )
            } else {
                planDetail(
                    features: [
                        ("infinity", "Unlimited track-day analyses"),
                        ("checkmark.seal.fill", "Every track, every race"),
                        ("brain.head.profile", "Full 10-step AI analysis"),
                        ("chart.bar.fill", "ML confidence scores"),
                        ("bolt.fill", "Live track intel"),
                        ("star.fill", "Priority during peak racing"),
                    ],
                    monthlyPrice: "$34.99",
                    annualPrice: "$28.99",
                    annualTotal: "$347.88"
                )
            }
        }
    }

    private func planDetail(features: [(String, String)], monthlyPrice: String, annualPrice: String, annualTotal: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(features, id: \.1) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(EEColors.emerald)
                        .frame(width: 20)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(EEColors.textPrimary)
                }
            }

            Divider().overlay(EEColors.borderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionManager.isAnnual ? annualPrice : monthlyPrice)
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(EEColors.textPrimary)
                    Text(subscriptionManager.isAnnual ? "per month, billed annually (\(annualTotal)/yr)" : "per month")
                        .font(.caption)
                        .foregroundStyle(EEColors.textSecondary)
                }
                Spacer()
                if subscriptionManager.isAnnual {
                    EEBadge(text: "SAVE 20%", color: EEColors.emerald)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(EEColors.emerald.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack {
            Text("Monthly")
                .font(.caption.weight(.semibold))
                .foregroundStyle(!subscriptionManager.isAnnual ? EEColors.textPrimary : EEColors.textMuted)

            Toggle("", isOn: Binding(
                get: { subscriptionManager.isAnnual },
                set: { subscriptionManager.isAnnual = $0 }
            ))
            .toggleStyle(SwitchToggleStyle(tint: EEColors.emerald))
            .labelsHidden()

            Text("Annual")
                .font(.caption.weight(.semibold))
                .foregroundStyle(subscriptionManager.isAnnual ? EEColors.textPrimary : EEColors.textMuted)

            if subscriptionManager.isAnnual {
                Text("Save 20%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(EEColors.emerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(EEColors.emerald.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await handlePurchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe to \(selectedTier == "pro" ? "Pro" : "Basic")")
                }
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(EEColors.edgeGradient)
            )
        }
        .disabled(isPurchasing)

        // Error display
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(EEColors.red)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await subscriptionManager.restorePurchases()
                if subscriptionManager.currentTier == .basic || subscriptionManager.currentTier == .pro {
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(EEColors.textSecondary)
        }
    }

    // MARK: - Terms

    private var termsSection: some View {
        VStack(spacing: 6) {
            Text("Subscription renews automatically. Cancel anytime in Settings > Apple ID > Subscriptions.")
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Text("Terms of Use")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(EEColors.textSecondary)
                Text("Privacy Policy")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(EEColors.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func handlePurchase() async {
        let isAnnual = subscriptionManager.isAnnual
        let product: Product?
        if isAnnual {
            product = subscriptionManager.annualProduct(for: selectedTier)
        } else {
            product = subscriptionManager.monthlyProduct(for: selectedTier)
        }

        guard let product else {
            errorMessage = "Product not available. Please try again later."
            return
        }

        isPurchasing = true
        errorMessage = nil

        do {
            try await subscriptionManager.purchase(product)
            isPurchasing = false
            if subscriptionManager.currentTier == .basic || subscriptionManager.currentTier == .pro {
                dismiss()
            }
        } catch {
            isPurchasing = false
            if !(error is StoreKit.StoreKitError) || (error as? StoreKit.StoreKitError) != .userCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    PaywallView(contextMessage: "Your free trial has ended. Subscribe to continue.")
}
