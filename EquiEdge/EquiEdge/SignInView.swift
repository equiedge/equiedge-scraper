import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @State private var authManager = AuthManager.shared
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Background
            EEColors.bgPrimary.ignoresSafeArea()

            // Ambient glow effects
            ambientGlows

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // App Icon
                    appIcon
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.85)
                        .animation(.spring(duration: 0.6).delay(0.15), value: appeared)

                    Spacer().frame(height: 24)

                    // Title
                    titleSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.5).delay(0.35), value: appeared)

                    Spacer().frame(height: 12)

                    // Subtitle
                    subtitleSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: appeared)

                    Spacer().frame(height: 32)

                    // Feature cards
                    featureCards

                    Spacer().frame(height: 28)

                    // Social proof stats
                    socialProofStats
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.5).delay(1.05), value: appeared)

                    Spacer().frame(height: 32)

                    // CTA
                    ctaSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.5).delay(1.2), value: appeared)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { appeared = true }
    }

    // MARK: - Ambient Glows

    private var ambientGlows: some View {
        ZStack {
            Circle()
                .fill(EEColors.emerald.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -80, y: -200)

            Circle()
                .fill(EEColors.blue.opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 100, y: 100)
        }
        .ignoresSafeArea()
    }

    // MARK: - App Icon

    private var appIcon: some View {
        ZStack {
            // Glow halo
            Circle()
                .fill(EEColors.emerald.opacity(0.15))
                .frame(width: 110, height: 110)
                .blur(radius: 20)

            // Icon background
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.06, blue: 0.09), Color(red: 0.03, green: 0.03, blue: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )

            // EE text
            HStack(spacing: 0) {
                Text("E")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(EEColors.emerald)
                Text("E")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(EEColors.blue)
            }
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        HStack(spacing: 0) {
            Text("Equi")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(EEColors.textPrimary)
            Text("Edge")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(EEColors.edgeGradientHorizontal)
        }
    }

    // MARK: - Subtitle

    private var subtitleSection: some View {
        Group {
            Text("10-step AI handicapping")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(EEColors.textPrimary)
            + Text(" with sniper selectivity \u{2014} only surfaces picks with a genuine, data-backed edge.")
                .font(.subheadline.weight(.light))
                .foregroundStyle(EEColors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    // MARK: - Feature Cards

    private var featureCards: some View {
        VStack(spacing: 12) {
            featureCard(
                icon: "brain.head.profile",
                title: "10-Step AI Analysis",
                description: "Pace maps, form, class profiling, ML cross-reference and a Devil's Advocate challenge on every pick",
                accent: EEColors.emerald,
                delay: 0.65
            )
            featureCard(
                icon: "chart.bar.fill",
                title: "ML Model + Confidence",
                description: "Independent ML probability rankings fused with AI reasoning. 60\u{2013}100 scores with calibrated unit sizing",
                accent: EEColors.blue,
                delay: 0.75
            )
            featureCard(
                icon: "bolt.fill",
                title: "Live Intelligence",
                description: "Real-time track bias, condition changes and late scratchings sourced live before every race",
                accent: EEColors.gold,
                delay: 0.85
            )
            featureCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "P&L Performance",
                description: "Track every bet with live ROI, win rate, profit sparklines and streak tracking built in",
                accent: EEColors.red,
                delay: 0.95
            )
        }
    }

    private func featureCard(icon: String, title: String, description: String, accent: Color, delay: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 48)

            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(EEColors.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(EEColors.textSecondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.5).delay(delay), value: appeared)
    }

    // MARK: - Social Proof Stats

    private var socialProofStats: some View {
        HStack(spacing: 0) {
            statItem(value: "3 Days", label: "Free Trial")
            statItem(value: "$14.99", label: "/month")
            statItem(value: "10-Step", label: "AI Pipeline")
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(EEColors.edgeGradientHorizontal)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(EEColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTA Section

    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Sign in with Apple button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                Task { await authManager.handleSignInResult(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if authManager.isLoading {
                ProgressView()
                    .tint(EEColors.emerald)
            }

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(EEColors.red)
                    .multilineTextAlignment(.center)
            }

            // Terms
            Text("By continuing, you agree to our ")
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)
            + Text("Terms of Service")
                .font(.caption2.weight(.medium))
                .foregroundStyle(EEColors.textSecondary)
            + Text(" and ")
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)
            + Text("Privacy Policy")
                .font(.caption2.weight(.medium))
                .foregroundStyle(EEColors.textSecondary)
        }
    }
}

#Preview {
    SignInView()
}
