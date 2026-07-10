import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Bindable var model: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var chartProgress: Double = 1
    @State private var hoveredBar: Bar?
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            picker
            navRow
            summaryRow
            longestRow
            cleanRow
            failuresRow
            chartSection
            projectSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var animationsOff: Bool {
        return reduceMotion || Preferences.shared.disableAnimations
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
            Text("XCBuildStats").font(.headline)
            Spacer()
            Button {
                // Close the popover first: it sits at status-window level and would
                // otherwise cover the settings window and keep key focus.
                dismiss()
                DispatchQueue.main.async {
                    SettingsWindowController.shared.show(model: model)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",")
            .help("Settings")
        }
    }

    private var picker: some View {
        HStack {
            Picker("", selection: $model.grouping) {
                ForEach(Grouping.allCases) { grouping in
                    Text(grouping.rawValue).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 8)
            if !model.isCurrentPeriod {
                Button {
                    model.goToCurrent()
                } label: {
                    Label("Current", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Jump to current period")
                .transition(.opacity)
            }
        }
        .animation(animationsOff ? nil : .easeInOut(duration: 0.2), value: model.isCurrentPeriod)
    }

    private var navRow: some View {
        HStack {
            Button {
                model.goPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Previous")
            Spacer()
            Text(model.periodTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.goNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canGoNext)
            .help("Next")
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Format.duration(model.summary.totalDuration))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(animationsOff ? nil : .snappy, value: model.summary.totalDuration)
            deltaBadge
            Spacer()
            Text("\(model.summary.count) \(model.summary.count == 1 ? "build" : "builds")  ·  avg \(Format.duration(model.summary.averageDuration))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deltaBadge: some View {
        if let delta: Double = model.previousPeriodDelta {
            let percent: Int = Int((abs(delta) * 100).rounded())
            if percent >= 1 {
                HStack(spacing: 1) {
                    Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                    Text("\(percent)%")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(delta > 0 ? Color.red : Color.green)
                .help("vs previous period")
            }
        }
    }

    @ViewBuilder
    private var longestRow: some View {
        if let longest: BuildRecord = model.longestBuild {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("Longest: \(Format.duration(longest.duration))")
                    .fontWeight(.medium)
                Text("· \(longest.project) · \(Format.stamp(longest.started))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var cleanRow: some View {
        if model.cleanCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Cleans: \(model.cleanCount) · \(Format.duration(model.cleanTotalDuration)) total")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var failuresRow: some View {
        let summary: PeriodSummary = model.summary
        if summary.count > 0 {
            let percent: Int = Int((summary.successRate * 100).rounded())
            HStack(spacing: 4) {
                Image(systemName: summary.failedCount == 0 ? "checkmark.circle" : "xmark.circle")
                Text("Failed: \(summary.failedCount) of \(summary.count)")
                    .fontWeight(.medium)
                Text(summary.failedCount > 0
                     ? "· \(percent)% success · \(Format.duration(summary.failedDuration)) on failed"
                     : "· \(percent)% success")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if model.summary.count == 0 {
            VStack(spacing: 8) {
                Image(systemName: model.hasAnyBuilds ? "chart.bar" : "hammer")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(model.hasAnyBuilds ? "No builds in this period." : "Build something in Xcode to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(model.bars) { bar in
                BarMark(
                    x: .value("Vrijeme", bar.start, unit: model.grouping.subComponent),
                    y: .value("Minute", bar.minutes * chartProgress)
                )
                .foregroundStyle(barGradient(for: bar))
                .cornerRadius(4)
            }
            if let hoveredBar {
                RuleMark(x: .value("Vrijeme", hoveredBar.start, unit: model.grouping.subComponent))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        hoverTooltip(hoveredBar)
                    }
            }
        }
        .chartXScale(domain: model.period.start ... model.period.end.addingTimeInterval(-1))
        .chartYScale(domain: 0 ... chartYMax)
        .chartXAxis {
            AxisMarks(values: axisTicks) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel("min", position: .topLeading)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredBar = bar(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredBar = nil
                        }
                    }
            }
        }
        .frame(height: 140)
        .onChange(of: model.grouping) { _, _ in
            hoveredBar = nil
            animateBars()
        }
        .onChange(of: model.periodOffset) { _, _ in
            hoveredBar = nil
            animateBars()
        }
    }

    private func barGradient(for bar: Bar) -> LinearGradient {
        let isDimmed: Bool = hoveredBar != nil && hoveredBar?.id != bar.id
        return LinearGradient(
            colors: [
                Color.accentColor.opacity(isDimmed ? 0.35 : 1.0),
                Color.accentColor.opacity(isDimmed ? 0.2 : 0.6)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func hoverTooltip(_ bar: Bar) -> some View {
        VStack(spacing: 1) {
            Text(hoverLabel(bar.start))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.duration(bar.minutes * 60))
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
    }

    private func hoverLabel(_ date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        switch model.grouping {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "EEE d"
        case .month:
            formatter.dateFormat = "MMM d"
        case .year:
            formatter.dateFormat = "MMMM"
        }
        return formatter.string(from: date)
    }

    private func bar(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Bar? {
        guard let plotAnchor = proxy.plotFrame else {
            return nil
        }
        let plotFrame: CGRect = geometry[plotAnchor]
        let xInPlot: CGFloat = location.x - plotFrame.minX
        guard xInPlot >= 0, xInPlot <= plotFrame.width,
              let date: Date = proxy.value(atX: xInPlot, as: Date.self) else {
            return nil
        }
        return model.bars.min {
            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
        }
    }

    private var chartYMax: Double {
        let maxMinutes: Double = model.bars.map { $0.minutes }.max() ?? 0
        return maxMinutes > 0 ? maxMinutes * 1.15 : 1
    }

    private func animateBars() {
        if animationsOff {
            chartProgress = 1
            return
        }
        chartProgress = 0
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            chartProgress = 1
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        let stats: [ProjectStat] = model.projectStats
        if !stats.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(stats) { stat in
                    HStack {
                        Text(stat.project).lineLimit(1)
                        Spacer()
                        Text("\(stat.count) \(stat.count == 1 ? "build" : "builds")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Format.duration(stat.totalDuration))
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.hasAnyBuilds, let last: Date = model.lastBuildDate {
                Text("Last build \(Format.relative(last, to: model.now))")
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.copySummary()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(model.summary.count == 0)
            .help("Copy summary to clipboard")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var axisTicks: [Date] {
        let calendar: Calendar = .current
        let start: Date = model.period.start
        switch model.grouping {
        case .day:
            return Swift.stride(from: 0, through: 21, by: 3).compactMap {
                calendar.date(byAdding: .hour, value: $0, to: start)
            }
        case .week:
            return (0..<7).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case .month:
            let days: Int = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            return Swift.stride(from: 0, to: days, by: 5).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case .year:
            return (0..<12).compactMap {
                calendar.date(byAdding: .month, value: $0, to: start)
            }
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch model.grouping {
        case .day:
            return .dateTime.hour(.defaultDigits(amPM: .omitted))
        case .week:
            return .dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US"))
        case .month:
            return .dateTime.day()
        case .year:
            return .dateTime.month(.defaultDigits)
        }
    }
}
