import AppKit
import BarloomCore
import Charts
import SwiftUI

enum AppColors {
    static let violet = Color(red: 0.52, green: 0.40, blue: 0.94)
    static let mint = Color(red: 0.18, green: 0.68, blue: 0.57)
    static let blue = Color(red: 0.25, green: 0.56, blue: 0.92)
    static let amber = Color(red: 0.90, green: 0.62, blue: 0.23)
}

struct BloomLogo: View {
    var size: CGFloat = 38
    var body: some View {
        Image(nsImage: StatusArtwork.brandImage())
            .resizable().scaledToFit().padding(size * 0.20)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [AppColors.violet, AppColors.violet.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.065), lineWidth: 1))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
    }
}

struct StatusPill: View {
    let title: String
    var color: Color = AppColors.mint
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
        .foregroundStyle(color)
    }
}

struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let color: Color
    var progress: Double? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 14) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).foregroundStyle(.secondary)
            }.font(.system(size: 11, weight: .medium))
            Text(value).font(.system(size: compact ? 24 : 29, weight: .semibold, design: .rounded)).monospacedDigit()
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.10))
                        Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, progress / 100)))
                    }
                }.frame(height: 4)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.065), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct HistoryChart: View {
    let samples: [HistorySample]
    var height: CGFloat = 160
    var body: some View {
        Chart(samples) { sample in
            if let cpu = sample.cpuUsage {
                LineMark(x: .value("Time", sample.id), y: .value("Usage", cpu))
                    .foregroundStyle(by: .value("Metric", "CPU"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let memory = sample.memoryUsage {
                LineMark(x: .value("Time", sample.id), y: .value("Usage", memory))
                    .foregroundStyle(by: .value("Metric", "Memory"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartForegroundStyleScale(["CPU": AppColors.mint, "Memory": AppColors.violet])
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine().foregroundStyle(.primary.opacity(0.07))
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .overlay {
            if samples.count < 2 {
                Text("Collecting live samples…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("CPU and memory usage history, from zero to one hundred percent")
    }
}

struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            Label { Text("CPU") } icon: { Circle().fill(AppColors.mint).frame(width: 6, height: 6) }
            Label { Text("Memory") } icon: { Circle().fill(AppColors.violet).frame(width: 6, height: 6) }
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium).monospacedDigit()
        }.font(.system(size: 12)).padding(.vertical, 5)
    }
}

struct DisabledModule: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Surface {
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 35)).foregroundStyle(AppColors.violet)
                Text("\(title) is off").font(.title3).fontWeight(.semibold)
                Text("Enable this module to start using it.").foregroundStyle(.secondary)
                Button("Enable \(title)", action: action).buttonStyle(.borderedProminent).tint(AppColors.violet)
            }.frame(maxWidth: .infinity).padding(.vertical, 42)
        }
    }
}

struct PortSummaryRow: View {
    @EnvironmentObject private var model: AppModel
    let port: ListeningPort
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: port.isDevelopmentProcess ? "terminal" : "app.connected.to.app.below.fill")
                .font(.system(size: 13)).foregroundStyle(AppColors.blue)
                .frame(width: 30, height: 30).background(AppColors.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(port.command).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("PID \(port.pid)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(":\(String(port.port))").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            Button { model.openPort(port) } label: { Image(systemName: "arrow.up.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Open HTTP URL in your browser")
        }.padding(.vertical, 6)
    }
}
