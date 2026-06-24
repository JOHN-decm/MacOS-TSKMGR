import SwiftUI

private enum DetailsColumnLayout {
    static let insetLeading: CGFloat = 8
    static let insetTrailing: CGFloat = 14
    static let scrollBarReserve: CGFloat = 18
    static let name: CGFloat = 220
    static let pid: CGFloat = 70
    static let status: CGFloat = 120
    static let user: CGFloat = 120
    static let cpu: CGFloat = 70
    static let memory: CGFloat = 96
    static let platform: CGFloat = 90
    static let totalWidth: CGFloat = name + pid + status + user + cpu + memory + platform
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 44
}

private enum DetailsSortKey {
    case name
    case pid
    case status
    case user
    case cpu
    case memory
    case platform
}

struct DetailsPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @ObservedObject var monitor: SystemMonitor
    @Binding var selectedPID: Int32?
    @Binding var memoryDisplayMode: ProcessResourceDisplayMode
    let onEndTask: (Int32) -> Void
    let onEndProcessTree: (Int32) -> Void
    let onRestartTask: (ProcessRowData) -> Void
    let onRevealInFinder: (String) -> Void
    let onSearchWeb: (String) -> Void
    let onShowProperties: (ProcessRowData) -> Void
    let onCopyProcessDetails: (ProcessRowData) -> Void
    let onOpenDetailsTab: (Int32) -> Void
    let onOpenServicesTab: () -> Void
    let onSetPriority: (Int32, ProcessPriorityPreset) -> Void
    @State private var sortKey: DetailsSortKey = .memory
    @State private var ascending = false

    var body: some View {
        GeometryReader { proxy in
            let widths = scaledWidths(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    headerCell(language.text("名称", "Name"), sortKey: .name, width: widths.name)
                    headerCell("PID", sortKey: .pid, width: widths.pid)
                    headerCell(language.text("状态", "Status"), sortKey: .status, width: widths.status)
                    headerCell(language.text("用户名", "User name"), sortKey: .user, width: widths.user)
                    headerCell("CPU", sortKey: .cpu, width: widths.cpu)
                    headerCell(language.text("内存(活动...)", "Memory (act...)"), sortKey: .memory, width: widths.memory)
                    headerCell(language.text("平台", "Platform"), sortKey: .platform, width: widths.platform)
                }
                .frame(width: widths.total, height: DetailsColumnLayout.headerHeight, alignment: .leading)
                .background(AppTheme.tableHeader(colorScheme))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.strongSeparator(colorScheme)).frame(height: 1)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                nameRowCell(row, width: widths.name)
                                rowCell("\(row.pid)", width: widths.pid)
                                rowCell(language.isChinese ? row.status : language.translateProcessStatus(row.status), width: widths.status)
                                rowCell(row.userName, width: widths.user)
                                rowCell(DisplayFormat.percentWithPrecision(row.cpuPercent, digits: 1), width: widths.cpu)
                                rowCell(memoryText(for: row), width: widths.memory)
                                rowCell(language.isChinese ? row.platform : language.translatePlatform(row.platform), width: widths.platform)
                            }
                            .frame(height: DetailsColumnLayout.rowHeight)
                            .background(detailsRowBackground(row, rowIndex: index))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPID = row.pid
                            }
                            .contextMenu {
                                detailsContextMenu(for: row)
                            }
                        }
                    }
                    .frame(width: widths.total, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 18)
            .padding(.leading, DetailsColumnLayout.insetLeading)
            .padding(.trailing, DetailsColumnLayout.insetTrailing)
        }
    }

    private var sortedRows: [DetailProcessRowData] {
        monitor.detailProcessRows.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .name: result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .pid: result = lhs.pid < rhs.pid
            case .status: result = lhs.status.localizedStandardCompare(rhs.status) == .orderedAscending
            case .user: result = lhs.userName.localizedStandardCompare(rhs.userName) == .orderedAscending
            case .cpu: result = lhs.cpuPercent < rhs.cpuPercent
            case .memory: result = lhs.memoryBytes < rhs.memoryBytes
            case .platform: result = lhs.platform.localizedStandardCompare(rhs.platform) == .orderedAscending
        }
        return ascending ? result : !result
        }
    }

    private func headerCell(_ title: String, sortKey: DetailsSortKey, width: CGFloat) -> some View {
        Button {
            if self.sortKey == sortKey {
                ascending.toggle()
            } else {
                self.sortKey = sortKey
                ascending = (sortKey == .name || sortKey == .status || sortKey == .user || sortKey == .platform)
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if self.sortKey == sortKey {
                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: DetailsColumnLayout.headerHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func nameRowCell(_ row: DetailProcessRowData, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(icon: row.icon)
            Text(row.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(AppTheme.primaryText(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: DetailsColumnLayout.rowHeight, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func rowCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: DetailsColumnLayout.rowHeight, alignment: .leading)
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
            }
    }

    private func detailsRowBackground(_ row: DetailProcessRowData, rowIndex: Int) -> Color {
        if selectedPID == row.pid {
            return AppTheme.selectedRow(colorScheme)
        }
        return rowIndex.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme)
    }

    private func scaledWidths(for availableWidth: CGFloat) -> DetailsScaledWidths {
        let usableWidth = max(
            900,
            availableWidth - DetailsColumnLayout.insetLeading - DetailsColumnLayout.insetTrailing - DetailsColumnLayout.scrollBarReserve
        )
        let scale = usableWidth / DetailsColumnLayout.totalWidth
        return DetailsScaledWidths(scale: scale)
    }

    private func detailsContextMenu(for row: DetailProcessRowData) -> some View {
        let processRow = toProcessRow(row)
        return Group {
            if shouldShowRestartInsteadOfTerminate(processRow) {
                Button(language.text("重新启动", "Restart")) {
                    selectedPID = row.pid
                    onRestartTask(processRow)
                }
            } else if canTerminate(processRow) {
                Button(language.text("结束任务", "End task")) {
                    selectedPID = row.pid
                    onEndTask(row.pid)
                }
                Button(language.text("结束进程树", "End process tree")) {
                    selectedPID = row.pid
                    onEndProcessTree(row.pid)
                }
            } else if canRestart(processRow) {
                Button(language.text("重新启动", "Restart")) {
                    selectedPID = row.pid
                    onRestartTask(processRow)
                }
            }

            Menu(language.text("设置优先级", "Set priority")) {
                ForEach(ProcessPriorityPreset.allCases, id: \.niceValue) { preset in
                    Button(preset.title(in: language)) {
                        onSetPriority(row.pid, preset)
                    }
                }
            }

            Button(language.text("打开文件所在的位置", "Open file location")) {
                onRevealInFinder(processRow.path)
            }
            .disabled(processRow.path.isEmpty)

            Button(language.text("在线搜索", "Search online")) {
                onSearchWeb(row.name)
            }

            Button(language.text("属性", "Properties")) {
                onShowProperties(processRow)
            }

            Button(language.text("转到服务", "Go to service")) {
                onOpenServicesTab()
            }

            Divider()

            Button(language.text("复制", "Copy")) {
                onCopyProcessDetails(processRow)
            }
        }
    }

    private func toProcessRow(_ row: DetailProcessRowData) -> ProcessRowData {
        let path = monitor.pidPath(pid: row.pid)
        return ProcessRowData(
            pid: row.pid,
            name: row.name,
            icon: row.icon,
            path: path,
            isApp: path.hasSuffix(".app") || path.contains("/Applications/") || path.contains("/System/Applications/"),
            isParent: false,
            parentPID: nil,
            childCount: 0,
            cpuPercent: row.cpuPercent,
            memoryBytes: row.memoryBytes,
            diskBytesPerSecond: 0,
            networkBytesPerSecond: 0,
            networkText: "0 Mbps",
            powerImpact: "",
            trend: "",
            threadCount: 0,
            openFiles: 0
        )
    }

    private func canTerminate(_ row: ProcessRowData) -> Bool {
        row.pid > 1 && row.pid != Int32(ProcessInfo.processInfo.processIdentifier)
    }

    private func canRestart(_ row: ProcessRowData) -> Bool {
        !canTerminate(row) && row.isApp && !row.path.isEmpty
    }

    private func shouldShowRestartInsteadOfTerminate(_ row: ProcessRowData) -> Bool {
        let lowerName = row.name.lowercased()
        let lowerPath = row.path.lowercased()
        return lowerName == "finder" || lowerName == "访达" || lowerPath.contains("/system/library/coreservices/finder.app")
    }

    private func memoryText(for row: DetailProcessRowData) -> String {
        switch memoryDisplayMode {
        case .value:
            return DisplayFormat.memory(row.memoryBytes)
        case .percent:
            guard monitor.memory.totalBytes > 0 else { return "0%" }
            let percent = Double(row.memoryBytes) / Double(monitor.memory.totalBytes) * 100
            return DisplayFormat.percentWithPrecision(percent, digits: 1)
        }
    }
}

private struct DetailsScaledWidths {
    let name: CGFloat
    let pid: CGFloat
    let status: CGFloat
    let user: CGFloat
    let cpu: CGFloat
    let memory: CGFloat
    let platform: CGFloat

    init(scale: CGFloat) {
        name = DetailsColumnLayout.name * scale
        pid = DetailsColumnLayout.pid * scale
        status = DetailsColumnLayout.status * scale
        user = DetailsColumnLayout.user * scale
        cpu = DetailsColumnLayout.cpu * scale
        memory = DetailsColumnLayout.memory * scale
        platform = DetailsColumnLayout.platform * scale
    }

    var total: CGFloat { name + pid + status + user + cpu + memory + platform }
}
