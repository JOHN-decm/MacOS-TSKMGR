import SwiftUI
import AppKit

private struct PerformanceChartHeights {
    let cpuCell: CGFloat
    let cpuSummary: CGFloat
    let standardMain: CGFloat
    let memoryMain: CGFloat
    let networkMain: CGFloat
    let gpuSingle: CGFloat
    let gpuDual: CGFloat
    let npuMain: CGFloat
}

struct PerformancePageView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var monitor: SystemMonitor
    @Binding var selectedPerf: PerfSelection
    @Binding var viewMode: PerformanceViewMode
    @Binding var showsGraphs: Bool
    @Binding var cpuGraphMode: CPUGraphMode
    @Binding var gpuGraphLayoutMode: GPUGraphLayoutMode
    @Binding var showsKernelTime: Bool
    var onOpenNetworkDetails: ((NetworkState) -> Void)? = nil
    @State private var leftGPUSelection: GPUGraphKind = .threeD
    @State private var rightGPUSelection: GPUGraphKind = .tilerCopy
    @State private var openGPUMenu: GPUGraphMenuTarget?
    @State private var openNPUMenu = false
    @State private var sidebarWidth: CGFloat = 214
    @State private var dragStartSidebarWidth: CGFloat?

    var body: some View {
        Group {
            if viewMode == .detailSummary {
                detailSummaryPanel
                    .background(WindowSurfaceBackground())
            } else if viewMode == .summary {
                summarySidebar
                    .background(WindowSurfaceBackground())
            } else {
                GeometryReader { proxy in
                    let minWidth: CGFloat = 180
                    let maxWidth = min(360, max(minWidth, proxy.size.width * 0.42))
                    let clampedSidebarWidth = min(max(sidebarWidth, minWidth), maxWidth)
                    let chartHeights = chartHeights(
                        for: proxy.size,
                        sidebarWidth: clampedSidebarWidth,
                        cpuChartCount: max(monitor.cpu.logicalCores, 8)
                    )

                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: clampedSidebarWidth)
                            .padding(.top, 10)

                        sidebarResizeHandle(minWidth: minWidth, maxWidth: maxWidth)

                        detailPanel(
                            chartHeights: chartHeights,
                            availableHeight: proxy.size.height
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .onAppear {
                        sidebarWidth = clampedSidebarWidth
                    }
                    .onChange(of: proxy.size.width) { _ in
                        sidebarWidth = min(max(sidebarWidth, minWidth), maxWidth)
                    }
                }
            }
        }
    }

    private func chartHeights(for availableSize: CGSize, sidebarWidth: CGFloat, cpuChartCount: Int) -> PerformanceChartHeights {
        let usableHeight = max(availableSize.height - 190, 240)
        let cpuColumns = 4
        let cpuRows = max(Int(ceil(Double(cpuChartCount) / Double(cpuColumns))), 1)
        let cpuAreaHeight = max(usableHeight * 0.58, 68)
        let cpuCellHeight = max(68, min(260, cpuAreaHeight / CGFloat(cpuRows)))

        return PerformanceChartHeights(
            cpuCell: cpuCellHeight,
            cpuSummary: max(68, min(520, usableHeight * 0.60)),
            standardMain: max(68, min(420, usableHeight * 0.42)),
            memoryMain: max(68, min(420, usableHeight * 0.42)),
            networkMain: max(68, min(520, usableHeight * 0.60)),
            gpuSingle: max(68, min(520, usableHeight * 0.60)),
            gpuDual: max(68, min(320, usableHeight * 0.36)),
            npuMain: max(68, min(520, usableHeight * 0.60))
        )
    }

    private func sidebarResizeHandle(minWidth: CGFloat, maxWidth: CGFloat) -> some View {
        SidebarResizeHandleView(
            onDragBegan: {
                dragStartSidebarWidth = sidebarWidth
            },
            onDragChanged: { delta in
                let baseWidth = dragStartSidebarWidth ?? sidebarWidth
                sidebarWidth = min(max(baseWidth + delta, minWidth), maxWidth)
            },
            onDragEnded: {
                dragStartSidebarWidth = nil
            }
        )
        .frame(width: 10)
        .overlay {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(width: 1)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(monitor.sidebarItems) { item in
                    sidebarItem(item)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var summarySidebar: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(monitor.sidebarItems) { item in
                    sidebarRow(item, summaryMode: true)
                    .contextMenu {
                        summaryContextMenu(for: item)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebarItem(_ item: PerfSidebarItem) -> some View {
        sidebarRow(item, summaryMode: false)
        .contextMenu {
            summaryContextMenu(for: item)
        }
    }

    private func sidebarRow(_ item: PerfSidebarItem, summaryMode: Bool) -> some View {
        HStack(spacing: 10) {
            if showsGraphs {
                GridChart(values: item.sparkline, color: item.accent, verticalSteps: 0, horizontalSteps: 0, lineWidth: 1.1, filled: true, ceiling: 100)
                    .frame(width: 58, height: 42)
                    .overlay(Rectangle().stroke(item.accent, lineWidth: 1))
            } else {
                Circle()
                    .fill(item.accent.opacity(0.34))
                    .overlay(Circle().stroke(item.accent, lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .padding(.leading, 2)
                    .frame(width: 16, height: 42, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.primaryText(colorScheme).opacity(summaryMode ? 0.88 : 1))
                    .lineLimit(summaryMode ? 2 : 1)
                    .truncationMode(.tail)
                if let tertiary = item.tertiary {
                    Text(tertiary)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.primaryText(colorScheme).opacity(summaryMode ? 0.88 : 1))
                        .lineLimit(summaryMode ? 2 : 1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, summaryMode ? 10 : 8)
        .padding(.vertical, 10)
        .background(selectedPerf == item.id ? item.selectedFill : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPerf = item.id
        }
    }

    private func detailPanel(chartHeights: PerformanceChartHeights, availableHeight: CGFloat) -> some View {
        let detail = monitor.detail(for: selectedPerf)
        return ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.title)
                                .font(.system(size: 28))
                                .foregroundStyle(AppTheme.primaryText(colorScheme))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(detail.topRight)
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.primaryText(colorScheme))
                        }
                    }

                    HStack(spacing: 8) {
                        Text(detail.primaryLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if shouldShowMainChartCeiling {
                            Text(detail.ceilingLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .cpu = selectedPerf {
                        cpuGraphContainer(detail, chartHeights: chartHeights)
                    } else if case .gpu = selectedPerf {
                        gpuGraphContainer(detail, chartHeights: chartHeights)
                    } else if case .npu = selectedPerf {
                        npuGraphContainer(detail, chartHeights: chartHeights)
                    } else {
                        standardDetailChartContainer(detail, chartHeights: chartHeights)
                    }

                    if case .cpu = selectedPerf {
                        HStack {
                            Text(language.text("60 秒", "60 sec"))
                            Spacer()
                            Text("0%")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text(language.text("60 秒", "60 sec"))
                            Spacer()
                            if shouldShowMainChartZeroLabel {
                                Text("0")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }

                    if detail.memoryComposition {
                        Text(language.text("内存组合", "Memory composition"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        GeometryReader { proxy in
                            let usedRatio = detail.chartCeiling > 0
                                ? max(0.0, min((detail.chartSets[0].last ?? 0) / detail.chartCeiling, 1.0))
                                : 0
                            let width = proxy.size.width
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .stroke(detail.accent, lineWidth: 1)
                                Rectangle()
                                    .fill(detail.accent.opacity(0.09))
                                    .frame(width: width * usedRatio)
                                Rectangle().fill(detail.accent.opacity(0.45)).frame(width: 1).offset(x: width * usedRatio)
                                Rectangle().fill(detail.accent.opacity(0.3)).frame(width: 1).offset(x: width * 0.72)
                            }
                        }
                        .frame(height: 52)
                    }

                    if let lower = detail.lowerChart, let lowerLabel = detail.lowerLabel {
                        HStack {
                            Text(lowerLabel)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(detail.lowerChartCeiling ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        GridChart(
                            values: lower,
                            color: detail.accent,
                            verticalSteps: 8,
                            horizontalSteps: 4,
                            lineWidth: 1.1,
                            ceiling: detail.lowerChartValueCeiling ?? 100
                        )
                            .frame(height: 52)
                            .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))

                        HStack {
                            Text(language.text("60 秒", "60 sec"))
                            Spacer()
                            if shouldShowLowerChartZeroLabel {
                                Text("0")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }

                    if case .memory = selectedPerf {
                        memoryStatsPanel(detail)
                            .padding(.top, 8)
                    } else if isGPU || isNetwork || isNPU {
                        sideBySideStatsPanel(detail)
                            .padding(.top, 8)
                    } else {
                        HStack(alignment: .top, spacing: 48) {
                            leftMetrics(detail.leftMetrics, networkCompact: isNetwork)
                                .frame(width: 180, alignment: .leading)
                            rightInfo(detail.rightPairs)
                                .frame(width: 320, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    currentDetailContextMenu()
                }
                .frame(minHeight: max(availableHeight - 36, 0), alignment: .top)
                .padding(.leading, PageInset.horizontal)
                .padding(.trailing, PageInset.horizontal)
                .padding(.top, PageInset.top)
                .padding(.bottom, PageInset.bottom)
            } else {
                Text(language.text("没有可用的数据", "No data available"))
                    .foregroundStyle(.secondary)
                    .padding(.leading, PageInset.horizontal)
                    .padding(.trailing, PageInset.horizontal)
                    .padding(.top, PageInset.top)
                    .padding(.bottom, PageInset.bottom)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(width: 1)
        }
    }

    private var shouldShowMainChartCeiling: Bool {
        if case .cpu = selectedPerf { return true }
        if case .memory = selectedPerf { return true }
        if case .network = selectedPerf { return true }
        return false
    }

    private var shouldShowMainChartZeroLabel: Bool {
        if case .memory = selectedPerf { return true }
        if case .network = selectedPerf { return true }
        return false
    }

    private var shouldShowLowerChartZeroLabel: Bool {
        if case .disk = selectedPerf { return true }
        return false
    }

    private var detailSummaryPanel: some View {
        let detail = monitor.detail(for: selectedPerf)
        return ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 10) {
                    cpuHeader(detail)
                    detailSummaryChartContainer(detail)
                    HStack {
                        Text(language.text("60 秒", "60 sec"))
                        Spacer()
                        Text("0")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    currentDetailContextMenu()
                }
                .padding(.leading, 24)
                .padding(.trailing, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var isNetwork: Bool {
        if case .network = selectedPerf { return true }
        return false
    }

    private var isGPU: Bool {
        if case .gpu = selectedPerf { return true }
        return false
    }

    private var isNPU: Bool {
        if case .npu = selectedPerf { return true }
        return false
    }

    private func cpuHeader(_ detail: PerformanceDetailViewData) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.title)
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                Text(detail.primaryLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(detail.topRight)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                Text(detail.ceilingLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryContextMenu(for item: PerfSidebarItem) -> some View {
        Group {
            Button(viewMode == .summary ? language.text("完整图形", "Full view") : language.text("摘要图形", "Summary view")) {
                selectedPerf = item.id
                viewMode = viewMode == .summary ? .full : .summary
            }
            Button(showsGraphs ? language.text("隐藏图形", "Hide graph") : language.text("显示图形", "Show graph")) {
                selectedPerf = item.id
                showsGraphs.toggle()
            }
            Button(language.text("复制", "Copy")) {
                selectedPerf = item.id
                copyCurrentPerformanceDetails()
            }
        }
    }

    @ViewBuilder
    private func currentDetailContextMenu() -> some View {
        switch selectedPerf {
        case .cpu:
            cpuContextMenu()
        case .gpu:
            gpuContextMenu()
        case .memory, .disk, .network, .npu:
            detailContextMenu()
        }
    }

    private func cpuContextMenu() -> some View {
        Group {
            Menu(language.text("将图形更改为", "Change graph to")) {
                Button(language.text("整体利用率", "Overall utilization")) {
                    cpuGraphMode = .overallUtilization
                }
                Button(language.text("逻辑处理器", "Logical processors")) {
                    cpuGraphMode = .logicalProcessors
                }
            }
            Button(showsKernelTime ? language.text("隐藏内核时间", "Hide kernel times") : language.text("显示内核时间", "Show kernel times")) {
                showsKernelTime.toggle()
            }
            Button(viewMode == .detailSummary ? language.text("图形完整视图", "Graph full view") : language.text("图形摘要视图", "Graph summary view")) {
                selectedPerf = .cpu
                viewMode = viewMode == .detailSummary ? .full : .detailSummary
            }
            Menu(language.text("查看", "View")) {
                ForEach(monitor.sidebarItems) { item in
                    Button(item.title) {
                        selectedPerf = item.id
                    }
                }
            }
            Button(language.text("复制", "Copy")) {
                selectedPerf = .cpu
                copyCurrentPerformanceDetails()
            }
        }
    }

    private func copyCurrentPerformanceDetails() {
        guard let detail = monitor.detail(for: selectedPerf) else { return }
        var lines: [String] = []
        lines.append(detail.title)
        lines.append(detail.topRight)
        lines.append("")

        for metric in detail.leftMetrics {
            lines.append("\(metric.label): \(metric.value)")
        }

        if !detail.rightPairs.isEmpty {
            lines.append("")
            for pair in detail.rightPairs {
                lines.append("\(pair.label): \(pair.value)")
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func leftMetrics(_ metrics: [DetailMetric], networkCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !networkCompact {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(metric.value)
                            .font(.system(size: metric.prominent ? 22 : 18))
                            .foregroundStyle(AppTheme.primaryText(colorScheme))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rightInfo(_ pairs: [InfoPair]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pairs) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pair.label)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: 128, alignment: .leading)
                    Text(pair.value)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memoryStatsPanel(_ detail: PerformanceDetailViewData) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            memoryStatsSection(
                title: language.text("当前内存", "Current memory"),
                rows: detail.leftMetrics.map { ($0.label, $0.value) }
            )
            memoryStatsSection(
                title: language.text("系统状态", "System state"),
                rows: detail.rightPairs.map { ($0.label, $0.value) }
            )
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func memoryStatsSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(row.1)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText(colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sideBySideStatsPanel(_ detail: PerformanceDetailViewData) -> some View {
        HStack(alignment: .top, spacing: 48) {
            leftMetrics(detail.leftMetrics, networkCompact: false)
                .frame(width: 180, alignment: .leading)
            rightInfo(detail.rightPairs)
                .frame(width: 320, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gpuHeader(title: String, valueText: String, target: GPUGraphMenuTarget) -> some View {
        Button {
            openGPUMenu = openGPUMenu == target ? nil : target
        } label: {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func gpuMenu(target: GPUGraphMenuTarget) -> some View {
        VStack(spacing: 0) {
            ForEach(GPUGraphKind.allCases) { kind in
                if isGPUKindAvailable(kind) {
                    Button {
                        if target == .left {
                            leftGPUSelection = kind
                        } else {
                            rightGPUSelection = kind
                        }
                        openGPUMenu = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: currentGPUSelection(for: target) == kind ? "checkmark" : "")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 12)
                            Text(kind.title(in: language))
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                    }
                    .buttonStyle(WinMenuButtonStyle())
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "")
                            .frame(width: 12)
                        Text(kind.title(in: language))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
            }
        }
        .frame(width: 150)
        .winMenuPanel()
    }

    private func currentGPUSelection(for target: GPUGraphMenuTarget) -> GPUGraphKind {
        target == .left ? leftGPUSelection : rightGPUSelection
    }

    private func gpuValueText(for kind: GPUGraphKind, detail: PerformanceDetailViewData) -> String {
        let value = gpuValues(for: kind, detail: detail).last ?? 0
        return DisplayFormat.percentWithPrecision(value, digits: 0)
    }

    private func gpuGraphContainer(_ detail: PerformanceDetailViewData, chartHeights: PerformanceChartHeights) -> some View {
        Group {
            if gpuGraphLayoutMode == .singleEngine {
                VStack(alignment: .leading, spacing: 4) {
                    gpuHeader(title: leftGPUSelection.title(in: language), valueText: gpuValueText(for: leftGPUSelection, detail: detail), target: .left)
                    GridChart(values: gpuValues(for: leftGPUSelection, detail: detail), color: detail.accent, filled: true)
                        .frame(height: chartHeights.gpuSingle)
                        .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
                }
                .overlay(alignment: .topLeading) {
                    if openGPUMenu == .left {
                        gpuMenu(target: .left)
                            .offset(x: 0, y: 22)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        gpuHeader(title: leftGPUSelection.title(in: language), valueText: gpuValueText(for: leftGPUSelection, detail: detail), target: .left)
                        GridChart(values: gpuValues(for: leftGPUSelection, detail: detail), color: detail.accent, filled: true)
                            .frame(height: chartHeights.gpuDual)
                            .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
                    }
                    .overlay(alignment: .topLeading) {
                        if openGPUMenu == .left {
                            gpuMenu(target: .left)
                                .offset(x: 0, y: 22)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        gpuHeader(title: rightGPUSelection.title(in: language), valueText: gpuValueText(for: rightGPUSelection, detail: detail), target: .right)
                        GridChart(values: gpuValues(for: rightGPUSelection, detail: detail), color: detail.accent, filled: true)
                            .frame(height: chartHeights.gpuDual)
                            .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
                    }
                    .overlay(alignment: .topLeading) {
                        if openGPUMenu == .right {
                            gpuMenu(target: .right)
                                .offset(x: 0, y: 22)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .id("gpu-detail-\(selectedPerf.id)-\(gpuGraphLayoutMode == .singleEngine ? "single" : "multi")-\(leftGPUSelection.rawValue)-\(rightGPUSelection.rawValue)")
    }

    private func gpuValues(for kind: GPUGraphKind, detail: PerformanceDetailViewData) -> [Double] {
        switch kind {
        case .overall:
            return detail.chartSets[safe: 0] ?? []
        case .threeD:
            return detail.chartSets[safe: 1] ?? []
        case .tilerCopy:
            return detail.chartSets[safe: 2] ?? []
        }
    }

    private func isGPUKindAvailable(_ kind: GPUGraphKind) -> Bool {
        switch kind {
        case .overall, .threeD, .tilerCopy:
            return true
        }
    }

    private func gpuContextMenu() -> some View {
        Group {
            Menu(language.text("将图形更改为", "Change graph to")) {
                Button(language.text("单个引擎", "Single engine")) {
                    gpuGraphLayoutMode = .singleEngine
                }
                Button(language.text("多个引擎", "Multiple engines")) {
                    gpuGraphLayoutMode = .multiEngine
                }
            }
            Button(viewMode == .detailSummary ? language.text("图形完整视图", "Graph full view") : language.text("图形摘要视图", "Graph summary view")) {
                viewMode = viewMode == .detailSummary ? .full : .detailSummary
            }
            Menu(language.text("查看", "View")) {
                ForEach(monitor.sidebarItems) { item in
                    Button(item.title) {
                        selectedPerf = item.id
                    }
                }
            }
            Button(language.text("复制", "Copy")) {
                copyCurrentPerformanceDetails()
            }
        }
    }

    private func cpuAdaptiveGrid(_ detail: PerformanceDetailViewData, chartHeights: PerformanceChartHeights) -> some View {
        let spacing: CGFloat = 6
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4)

        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(detail.chartSets.enumerated()), id: \.offset) { _, values in
                ZStack {
                    GridChart(values: values, color: detail.accent, filled: true)
                if showsKernelTime {
                    GridChart(
                        values: kernelOverlayValues(from: values),
                            color: detail.accent.opacity(0.65),
                            verticalSteps: 8,
                            horizontalSteps: 6,
                            lineWidth: 1.0,
                            filled: true,
                            fillOpacityMultiplier: 1.8
                        )
                        .padding(1)
                    }
                }
                .frame(height: chartHeights.cpuCell)
                .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
            }
        }
    }

    private func cpuGraphContainer(_ detail: PerformanceDetailViewData, chartHeights: PerformanceChartHeights) -> some View {
        ZStack {
            if cpuGraphMode == .overallUtilization {
                cpuSingleSummaryChart(detail, idealHeight: chartHeights.cpuSummary)
            } else {
                cpuAdaptiveGrid(detail, chartHeights: chartHeights)
            }
        }
        .contentShape(Rectangle())
        .id("cpu-graph-\(cpuGraphMode == .overallUtilization ? "overall" : "logical")-\(showsKernelTime ? "kernel" : "user")")
    }

    private func detailSummaryChartContainer(_ detail: PerformanceDetailViewData) -> some View {
        ZStack {
            if case .cpu = selectedPerf {
                cpuSingleSummaryChart(detail)
            } else {
                standardSingleChart(detail)
            }
        }
        .contentShape(Rectangle())
        .id("detail-summary-\(selectedPerf.id)-\(showsKernelTime ? "kernel" : "user")")
    }

    private func cpuSingleSummaryChart(_ detail: PerformanceDetailViewData, idealHeight: CGFloat? = nil) -> some View {
        let values = detail.chartSets.first ?? []
        return ZStack {
            GridChart(values: values, color: detail.accent, filled: true)
                .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))

            if showsKernelTime {
                GridChart(
                    values: kernelOverlayValues(from: values),
                    color: detail.accent.opacity(0.65),
                    verticalSteps: 8,
                    horizontalSteps: 6,
                    lineWidth: 1.0,
                    filled: true,
                    fillOpacityMultiplier: 1.8
                )
                    .padding(1)
            }
        }
        .frame(
            height: idealHeight ?? (viewMode == .detailSummary ? 340 : 360)
        )
    }

    private func kernelOverlayValues(from values: [Double]) -> [Double] {
        values.map { min($0 * 0.55, 100) }
    }

    private func standardSingleChart(_ detail: PerformanceDetailViewData) -> some View {
        GridChart(values: detail.chartSets.first ?? [], color: detail.accent, filled: true, ceiling: detail.chartCeiling)
            .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
            .frame(height: 340)
    }

    private func npuGraphContainer(_ detail: PerformanceDetailViewData, chartHeights: PerformanceChartHeights) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            npuHeader(valueText: DisplayFormat.percentWithPrecision((detail.chartSets.first ?? []).last ?? 0, digits: 0))

            GridChart(values: detail.chartSets.first ?? [], color: detail.accent, filled: true, ceiling: detail.chartCeiling)
                .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
                .frame(height: chartHeights.npuMain)
        }
        .overlay(alignment: .topLeading) {
            if openNPUMenu {
                npuMenu()
                    .offset(x: 0, y: 22)
            }
        }
        .contentShape(Rectangle())
        .id("npu-detail-\(selectedPerf.id)")
    }

    private func npuHeader(valueText: String) -> some View {
        Button {
            openNPUMenu.toggle()
        } label: {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(language.text("Compute", "Compute"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func npuMenu() -> some View {
        VStack(spacing: 0) {
            Button {
                openNPUMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                    Text(language.text("Compute", "Compute"))
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
            }
            .buttonStyle(WinMenuButtonStyle())
        }
        .frame(width: 150)
        .winMenuPanel()
    }

    private func standardDetailChartContainer(_ detail: PerformanceDetailViewData, chartHeights: PerformanceChartHeights) -> some View {
        ZStack {
            GridChart(values: detail.chartSets[0], color: detail.accent, filled: true, ceiling: detail.chartCeiling)
                .overlay(Rectangle().stroke(detail.accent, lineWidth: 1))
        }
        .frame(
            height: {
                if case .memory = selectedPerf { return chartHeights.memoryMain }
                if case .network = selectedPerf { return chartHeights.networkMain }
                return chartHeights.standardMain
            }()
        )
        .contentShape(Rectangle())
        .id("detail-chart-\(selectedPerf.id)")
    }

    private func detailContextMenu() -> some View {
        Group {
            Button(viewMode == .detailSummary ? language.text("图形完整视图", "Graph full view") : language.text("图形摘要视图", "Graph summary view")) {
                viewMode = viewMode == .detailSummary ? .full : .detailSummary
            }
            if case .npu = selectedPerf {
                Menu(language.text("将图形更改为", "Change graph to")) {
                    Button(language.text("单个引擎", "Single engine")) {
                        gpuGraphLayoutMode = .singleEngine
                    }
                    Button(language.text("多个引擎", "Multiple engines")) {
                        gpuGraphLayoutMode = .multiEngine
                    }
                }
            }
            Menu(language.text("查看", "View")) {
                ForEach(monitor.sidebarItems) { item in
                    Button(item.title) {
                        selectedPerf = item.id
                    }
                }
            }
            if case .network(let id) = selectedPerf, let network = monitor.networks.first(where: { $0.id == id }) {
                Button(language.text("查看网络详细信息", "View network details")) {
                    onOpenNetworkDetails?(network)
                }
            }
            Button(language.text("复制", "Copy")) {
                copyCurrentPerformanceDetails()
            }
        }
    }
}

private struct SidebarResizeHandleView: NSViewRepresentable {
    let onDragBegan: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> SidebarResizeHandleNSView {
        let view = SidebarResizeHandleNSView()
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: SidebarResizeHandleNSView, context: Context) {
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

private final class SidebarResizeHandleNSView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private var initialLocationInWindow: NSPoint?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        initialLocationInWindow = event.locationInWindow
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialLocationInWindow else { return }
        onDragChanged?(event.locationInWindow.x - initialLocationInWindow.x)
    }

    override func mouseUp(with event: NSEvent) {
        initialLocationInWindow = nil
        onDragEnded?()
    }
}

enum GPUGraphMenuTarget {
    case left
    case right
}

struct PlaceholderPageView: View {
    @Environment(\.appLanguage) private var language
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .font(.system(size: 28))
            Text(language.text("这一页还没接入对应的系统数据。", "This page has not been connected to real system data yet."))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
