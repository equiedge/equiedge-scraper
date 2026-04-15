import SwiftUI

// MARK: - EquiEdge Design System

enum EEColors {
    // Primary backgrounds
    static let bgPrimary = Color(red: 0.04, green: 0.04, blue: 0.06)     // #0A0A0F
    static let bgSecondary = Color(red: 0.07, green: 0.07, blue: 0.10)   // #12121A
    static let bgCard = Color(red: 0.10, green: 0.10, blue: 0.15)        // #1A1A26

    // Accent colors
    static let emerald = Color(red: 0.0, green: 0.863, blue: 0.51)       // #00DC82
    static let blue = Color(red: 0.29, green: 0.62, blue: 1.0)           // #4A9EFF
    static let gold = Color(red: 1.0, green: 0.72, blue: 0.0)            // #FFB800
    static let red = Color(red: 1.0, green: 0.278, blue: 0.341)          // #FF4757

    // Text
    static let textPrimary = Color(red: 0.94, green: 0.94, blue: 0.96)   // #F0F0F5
    static let textSecondary = Color(red: 0.54, green: 0.54, blue: 0.60) // #8A8A9A
    static let textMuted = Color(red: 0.33, green: 0.33, blue: 0.42)     // #55556A

    // Dim variants (for backgrounds/badges)
    static let emeraldDim = Color(red: 0.0, green: 0.863, blue: 0.51).opacity(0.15)
    static let goldDim = Color(red: 1.0, green: 0.72, blue: 0.0).opacity(0.15)
    static let redDim = Color(red: 1.0, green: 0.278, blue: 0.341).opacity(0.15)
    static let blueDim = Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.12)

    // Borders
    static let borderSubtle = Color.white.opacity(0.06)

    // Gradients
    static let edgeGradient = LinearGradient(
        colors: [emerald, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let edgeGradientHorizontal = LinearGradient(
        colors: [emerald, blue],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Confidence tier color
    static func confidenceColor(for value: Int) -> Color {
        if value >= 75 { return emerald }
        if value >= 55 { return gold }
        return red
    }

    static func confidenceGradient(for value: Int) -> LinearGradient {
        if value >= 75 {
            return LinearGradient(colors: [emerald, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if value >= 55 {
            return LinearGradient(colors: [gold, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [red, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Branded Navigation Title

struct EEBrandedTitle: View {
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text("Equi")
                .font(.title3.weight(.light))
                .foregroundStyle(EEColors.textPrimary)
            Text("Edge")
                .font(.title3.weight(.heavy))
                .foregroundStyle(EEColors.edgeGradientHorizontal)
            if let subtitle {
                Text(" ")
                Text(subtitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(EEColors.textSecondary)
            }
        }
    }
}

// MARK: - Reusable Card Style

struct EECardModifier: ViewModifier {
    var borderColor: Color = EEColors.borderSubtle
    var leftAccent: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(EEColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .overlay(alignment: .leading) {
                if let accent = leftAccent {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
    }
}

extension View {
    func eeCard(borderColor: Color = EEColors.borderSubtle, leftAccent: Color? = nil) -> some View {
        modifier(EECardModifier(borderColor: borderColor, leftAccent: leftAccent))
    }
}

// MARK: - Glass Card (for AI suggestion cards)

struct EEGlassCardModifier: ViewModifier {
    var accentColor: Color = EEColors.emerald

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.06),
                                EEColors.blue.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentColor.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func eeGlassCard(accent: Color = EEColors.emerald) -> some View {
        modifier(EEGlassCardModifier(accentColor: accent))
    }
}

// MARK: - Chip / Pill Button Style

struct EEChipStyle: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? EEColors.emerald.opacity(0.15) : EEColors.bgCard)
                    .overlay(
                        Capsule()
                            .stroke(isActive ? EEColors.emerald.opacity(0.3) : EEColors.borderSubtle, lineWidth: 1)
                    )
            )
            .foregroundStyle(isActive ? EEColors.emerald : EEColors.textSecondary)
    }
}

extension View {
    func eeChip(isActive: Bool) -> some View {
        modifier(EEChipStyle(isActive: isActive))
    }
}

// MARK: - Badge Style

struct EEBadge: View {
    let text: String
    var color: Color = EEColors.emerald
    var style: BadgeStyle = .filled

    enum BadgeStyle {
        case filled, subtle
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(style == .filled ? 0.15 : 0.08))
            )
            .foregroundStyle(color)
    }
}

// MARK: - Stat Card

struct EEStatCard: View {
    let value: String
    let label: String
    var valueColor: Color = EEColors.textPrimary

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(valueColor)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(EEColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - Gradient Button

struct EEGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(EEColors.edgeGradient)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct EEOutlineButtonStyle: ButtonStyle {
    var color: Color = EEColors.emerald

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.4), lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct EESectionHeader: View {
    let title: String
    var color: Color = EEColors.textSecondary

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .tracking(1)
    }
}
