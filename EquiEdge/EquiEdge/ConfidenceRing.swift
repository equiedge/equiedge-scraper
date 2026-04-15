import SwiftUI

// MARK: - Confidence Ring Component

struct ConfidenceRing: View {
    let confidence: Int
    var size: CGFloat = 48
    var lineWidth: CGFloat = 4.5
    var showLabel: Bool = true

    private var progress: CGFloat {
        CGFloat(confidence) / 100.0
    }

    private var ringColor: Color {
        EEColors.confidenceColor(for: confidence)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            // Foreground ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [ringColor, ringColor.opacity(0.6), ringColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * Double(progress))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center label
            if showLabel {
                Text("\(confidence)")
                    .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ringColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Mini Confidence Bar (for race list)

struct ConfidenceBar: View {
    let confidence: Int
    var width: CGFloat = 48

    private var color: Color {
        EEColors.confidenceColor(for: confidence)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(confidence)%")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)

            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: width * CGFloat(confidence) / 100.0)
                }
            }
            .frame(width: width, height: 4)
        }
    }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let dataPoints: [Double]
    var lineColor: Color = EEColors.emerald
    var height: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = (dataPoints.max() ?? 1)
            let minVal = (dataPoints.min() ?? 0)
            let range = max(maxVal - minVal, 1)

            // Build path
            let points: [CGPoint] = dataPoints.enumerated().map { i, val in
                let x = w * CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1))
                let y = h - (h * CGFloat(val - minVal) / CGFloat(range))
                return CGPoint(x: x, y: y)
            }

            // Area fill
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for pt in points.dropFirst() {
                    path.addLine(to: pt)
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [lineColor.opacity(0.25), lineColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Line
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for pt in points.dropFirst() {
                    path.addLine(to: pt)
                }
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}
