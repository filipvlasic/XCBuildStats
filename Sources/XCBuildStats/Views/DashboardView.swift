import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Bindable var model: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var chartProgress: Double = 1
    @State private var hoveredBar: Bar?
    @State private var toolPhases: [ToolAction: ToolPhase] = [:]
    @State private var toolWarning: String?
    @State private var toolWarningToken: Int = 0
    @State private var xcodeRunning: Bool = XcodeTools.isXcodeRunning

    enum ToolAction: Hashable {
        case derivedData
        case spmCache
        case xcode
        case cleanRestart
    }

    enum ToolPhase: Equatable {
        case working
        case done
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            picker
            navRow
            summaryRow
            sourceRow
            longestRow
            cleanRow
            failuresRow
            chartSection
            projectSection
            Divider()
            toolsRow
            footer
        }
        .padding(14)
        .frame(width: 380)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { note in
            refreshXcodeRunning(note)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { note in
            refreshXcodeRunning(note)
        }
        .onAppear {
            xcodeRunning = XcodeTools.isXcodeRunning
        }
    }

    private func refreshXcodeRunning(_ note: Notification) {
        guard let app: NSRunningApplication = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == XcodeTools.xcodeBundleId else {
            return
        }
        xcodeRunning = XcodeTools.isXcodeRunning
    }

    private var animationsOff: Bool {
        return reduceMotion || Preferences.shared.disableAnimations
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
            Text("XCBuildStats").font(.headline)
            Spacer()
            Picker("", selection: $model.sourceFilter) {
                ForEach(SourceFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .help("Xcode builds, command-line builds (xcodebuild: Claude Code and other agents, scripts), or both")
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

    /// Per-source split of the combined total; doubles as the chart's legend.
    @ViewBuilder
    private var sourceRow: some View {
        let stats: [SourceStat] = model.sourceStats
        if model.sourceFilter == .all, stats.contains(where: { $0.source == .cli }) {
            HStack(spacing: 12) {
                ForEach(stats) { stat in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stat.source.color)
                            .frame(width: 7, height: 7)
                        Text(stat.source.label)
                            .fontWeight(.medium)
                        Text("\(Format.duration(stat.totalDuration)) · \(stat.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
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
            let percent: Int = summary.successPercent
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
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            chart
        }
    }

    private var emptyStateText: String {
        if model.hasAnyBuilds {
            return "No builds in this period."
        }
        if model.sourceFilter == .cli {
            return "No command-line builds yet.\nxcodebuild runs (Claude Code, scripts) show up here."
        }
        return "Build something in Xcode to get started."
    }

    private var chart: some View {
        Chart {
            if model.sourceFilter == .all {
                // Marks sharing an x value stack: Xcode at the bottom, CLI on top.
                ForEach(model.sourceBars) { part in
                    BarMark(
                        x: .value("Vrijeme", part.start, unit: model.grouping.subComponent),
                        y: .value("Minute", part.minutes * chartProgress)
                    )
                    .foregroundStyle(barGradient(start: part.start, color: part.source.color))
                    .cornerRadius(4)
                }
            } else {
                ForEach(model.bars) { bar in
                    BarMark(
                        x: .value("Vrijeme", bar.start, unit: model.grouping.subComponent),
                        y: .value("Minute", bar.minutes * chartProgress)
                    )
                    .foregroundStyle(barGradient(start: bar.start, color: singleSourceColor))
                    .cornerRadius(4)
                }
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
        .onChange(of: model.sourceFilter) { _, _ in
            hoveredBar = nil
            animateBars()
        }
    }

    private var singleSourceColor: Color {
        return model.sourceFilter == .cli ? BuildSource.cli.color : BuildSource.xcode.color
    }

    private func barGradient(start: Date, color: Color) -> LinearGradient {
        let isDimmed: Bool = hoveredBar != nil && hoveredBar?.start != start
        return LinearGradient(
            colors: [
                color.opacity(isDimmed ? 0.35 : 1.0),
                color.opacity(isDimmed ? 0.2 : 0.6)
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
            if model.sourceFilter == .all {
                let parts: [SourceBar] = model.sourceBars.filter { $0.start == bar.start }
                if parts.count > 1 {
                    ForEach(parts) { part in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(part.source.color)
                                .frame(width: 5, height: 5)
                            Text("\(part.source.label) \(Format.duration(part.minutes * 60))")
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                }
            }
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

    private var toolsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                toolButton(
                    .derivedData, title: "DerivedData", icon: "trash",
                    help: "Delete all of DerivedData", failure: "Already empty",
                    requiresXcodeClosed: true
                ) {
                    XcodeTools.deleteDerivedDataContents()
                }
                toolButton(
                    .spmCache, title: "SPM Cache", icon: "shippingbox",
                    help: "Reset Swift Package caches", failure: "Nothing to delete",
                    requiresXcodeClosed: true
                ) {
                    XcodeTools.resetPackageCaches()
                }
            }
            HStack(spacing: 8) {
                if xcodeRunning {
                    toolButton(
                        .xcode, title: "Quit Xcode", icon: "power",
                        help: "Force quit Xcode", failure: "Not running"
                    ) {
                        XcodeTools.forceQuitXcode()
                    }
                } else {
                    toolButton(
                        .xcode, title: "Launch Xcode", icon: "play",
                        help: "Launch the last-used Xcode", failure: "Xcode not found"
                    ) {
                        XcodeTools.launchXcode()
                    }
                }
                toolButton(
                    .cleanRestart, title: "Clean restart", icon: "arrow.triangle.2.circlepath",
                    help: "Quit Xcode, delete DerivedData, and relaunch the same Xcode", failure: "Launch failed"
                ) {
                    XcodeTools.cleanRestart()
                }
            }
            // Reserved line so the popover height never jumps when it appears.
            Text(toolWarning ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(toolWarning == nil ? 0 : 1)
        }
    }

    private func showToolWarning(_ text: String) {
        toolWarningToken += 1
        let token: Int = toolWarningToken
        withAnimation(animationsOff ? nil : .easeInOut(duration: 0.15)) {
            toolWarning = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard token == toolWarningToken else {
                return
            }
            withAnimation(animationsOff ? nil : .easeInOut(duration: 0.3)) {
                toolWarning = nil
            }
        }
    }

    private func toolButton(
        _ action: ToolAction,
        title: String,
        icon: String,
        help: String,
        failure: String,
        requiresXcodeClosed: Bool = false,
        run: @escaping () -> Bool
    ) -> some View {
        let phase: ToolPhase? = toolPhases[action]
        let symbol: String
        var text: String = title
        switch phase {
        case .working:
            symbol = "hourglass"
        case .done:
            symbol = "checkmark"
        case .failed(let message):
            symbol = "xmark"
            text = message
        case nil:
            symbol = icon
        }
        return Button {
            // Deleting caches under a live Xcode leaves its package graph broken
            // (binary artifacts are not re-fetched) — refuse and say why.
            if requiresXcodeClosed && XcodeTools.isXcodeRunning {
                showToolWarning("Quit Xcode first — its open packages would break.")
                return
            }
            toolPhases[action] = .working
            DispatchQueue.global(qos: .userInitiated).async {
                let succeeded: Bool = run()
                DispatchQueue.main.async {
                    finishTool(action, phase: succeeded ? .done : .failed(failure))
                }
            }
        } label: {
            Label(text, systemImage: symbol)
                .foregroundStyle(phase == .done ? Color.green : (symbol == "xmark" ? Color.red : Color.primary))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
        .disabled(phase == .working)
        .help(help)
    }

    private func finishTool(_ action: ToolAction, phase: ToolPhase) {
        toolPhases[action] = phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            toolPhases[action] = nil
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.hasAnyBuilds, let last: Date = model.lastBuildDate {
                Text("Last build \(Format.relative(last, to: model.now))")
                    .lineLimit(1)
            }
            Spacer()
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

private extension BuildSource {
    var label: String {
        switch self {
        case .xcode:
            return "Xcode"
        case .cli:
            return "CLI"
        }
    }

    var color: Color {
        switch self {
        case .xcode:
            return .accentColor
        case .cli:
            return .orange
        }
    }
}
