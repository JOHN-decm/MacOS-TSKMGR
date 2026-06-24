import SwiftUI

private enum UsersColumnLayout {
    static let insetLeading: CGFloat = 8
    static let insetTrailing: CGFloat = 14
    static let scrollBarReserve: CGFloat = 18
    static let user: CGFloat = 330
    static let status: CGFloat = 120
    static let cpu: CGFloat = 88
    static let memory: CGFloat = 108
    static let disk: CGFloat = 96
    static let network: CGFloat = 88
    static let totalWidth: CGFloat = user + status + cpu + memory + disk + network
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 44
}

private enum UsersSortKey {
    case user
    case status
    case cpu
    case memory
    case disk
    case network
}

struct UsersPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @ObservedObject var monitor: SystemMonitor
    @Binding var selectedPID: Int32?
    @Binding var memoryDisplayMode: ProcessResourceDisplayMode
    @Binding var diskDisplayMode: ProcessResourceDisplayMode
    @Binding var networkDisplayMode: ProcessResourceDisplayMode
    let onEndTask: (Int32) -> Void
    let onRestartTask: (ProcessRowData) -> Void
    let onRevealInFinder: (String) -> Void
    let onSearchWeb: (String) -> Void
    let onShowProperties: (ProcessRowData) -> Void
    let onCopyProcessDetails: (ProcessRowData) -> Void
    let onOpenDetailsTab: (Int32) -> Void
    @State private var expanded = true
    @State private var sortKey: UsersSortKey = .memory
    @State private var ascending = false

    var body: some View {
        GeometryReader { proxy in
            let widths = scaledWidths(for: proxy.size.width)
            let rows = sortedRows
            let userName = monitor.currentUserSection?.userName ?? NSFullUserName()
            let totalCPU = rows.reduce(0.0) { $0 + $1.cpuPercent }
            let totalMemory = rows.reduce(UInt64(0)) { $0 + $1.memoryBytes }
            let totalDisk = rows.reduce(UInt64(0)) { $0 + $1.diskBytesPerSecond }
            let totalNetwork = rows.reduce(UInt64(0)) { $0 + $1.networkBytesPerSecond }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    headerCell(language.text("用户", "User"), sortKey: .user, width: widths.user)
                    headerCell(language.text("状态", "Status"), sortKey: .status, width: widths.status)
                    metricHeaderCell(DisplayFormat.percent(totalCPU), label: "CPU", sortKey: .cpu, width: widths.cpu)
                    metricHeaderCell(DisplayFormat.memory(totalMemory), label: language.text("内存", "Memory"), sortKey: .memory, width: widths.memory)
                    metricHeaderCell(DisplayFormat.throughput(totalDisk), label: language.text("磁盘", "Disk"), sortKey: .disk, width: widths.disk)
                    metricHeaderCell(totalNetwork == 0 ? "0 Mbps" : DisplayFormat.networkRate(totalNetwork), label: language.text("网络", "Network"), sortKey: .network, width: widths.network)
                }
                .frame(width: widths.total, height: UsersColumnLayout.headerHeight, alignment: .leading)
                .background(AppTheme.tableHeader(colorScheme))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.strongSeparator(colorScheme)).frame(height: 1)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            expanded.toggle()
                        } label: {
                            HStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("\(userName) (\(rows.count))")
                                        .font(.system(size: 15))
                                }
                                .foregroundStyle(Color(red: 0.16, green: 0.34, blue: 0.77))
                                .padding(.horizontal, 10)
                                .frame(width: widths.user, height: UsersColumnLayout.rowHeight, alignment: .leading)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1)
                                }

                                rowCell("", width: widths.status)
                                rowCell(DisplayFormat.percentWithPrecision(totalCPU, digits: 1), width: widths.cpu)
                                rowCell(summaryMemoryText(totalMemory), width: widths.memory)
                                rowCell(summaryDiskText(totalDisk), width: widths.disk)
                                rowCell(summaryNetworkText(totalNetwork), width: widths.network)
                            }
                        }
                        .buttonStyle(.plain)
                        .background(AppTheme.rowEven(colorScheme))

                        if expanded {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 0) {
                                    HStack(spacing: 8) {
                                        Color.clear.frame(width: 12, height: 12)
                                        ProcessIconView(icon: row.icon)
                                        Text(row.name)
                                            .font(.system(size: 13))
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: widths.user, height: UsersColumnLayout.rowHeight, alignment: .leading)
                                    .overlay(alignment: .trailing) {
                                        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1)
                                    }

                                    rowCell("", width: widths.status)
                                    rowCell(DisplayFormat.percentWithPrecision(row.cpuPercent, digits: 1), width: widths.cpu)
                                    rowCell(memoryText(for: row), width: widths.memory)
                                    rowCell(diskText(for: row), width: widths.disk)
                                    rowCell(networkText(for: row), width: widths.network)
                                }
                                .frame(height: UsersColumnLayout.rowHeight)
                                .background(userAppRowBackground(row, rowIndex: index))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPID = row.pid
                                }
                                .contextMenu {
                                    processContextMenu(for: row)
                                }
                            }
                        }
                    }
                    .frame(width: widths.total, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 18)
            .padding(.leading, UsersColumnLayout.insetLeading)
            .padding(.trailing, UsersColumnLayout.insetTrailing)
        }
    }

    private var sortedRows: [ProcessRowData] {
        monitor.currentUserAppRows.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .user:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .status:
                result = true
            case .cpu:
                result = lhs.cpuPercent < rhs.cpuPercent
            case .memory:
                result = lhs.memoryBytes < rhs.memoryBytes
            case .disk:
                result = lhs.diskBytesPerSecond < rhs.diskBytesPerSecond
            case .network:
                result = lhs.networkBytesPerSecond < rhs.networkBytesPerSecond
            }
            return ascending ? result : !result
        }
    }

    private func headerCell(_ title: String, sortKey: UsersSortKey, width: CGFloat) -> some View {
        Button {
            changeSort(to: sortKey)
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
            .frame(width: width, height: UsersColumnLayout.headerHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func metricHeaderCell(_ value: String, label: String, sortKey: UsersSortKey, width: CGFloat) -> some View {
        Button {
            changeSort(to: sortKey)
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(size: 15))
                    if self.sortKey == sortKey {
                        Image(systemName: ascending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(width: width, height: UsersColumnLayout.headerHeight)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func rowCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: UsersColumnLayout.rowHeight, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
            }
    }

    private func userAppRowBackground(_ row: ProcessRowData, rowIndex: Int) -> Color {
        if selectedPID == row.pid {
            return AppTheme.selectedRow(colorScheme)
        }
        return rowIndex.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme)
    }

    private func scaledWidths(for availableWidth: CGFloat) -> UsersScaledWidths {
        let usableWidth = max(
            760,
            availableWidth - UsersColumnLayout.insetLeading - UsersColumnLayout.insetTrailing - UsersColumnLayout.scrollBarReserve
        )
        let scale = usableWidth / UsersColumnLayout.totalWidth
        return UsersScaledWidths(scale: scale)
    }

    private func changeSort(to key: UsersSortKey) {
        if sortKey == key {
            ascending.toggle()
        } else {
            sortKey = key
            ascending = (key == .user || key == .status)
        }
    }

    private func processContextMenu(for row: ProcessRowData) -> some View {
        Group {
            if shouldShowRestartInsteadOfTerminate(row) {
                Button(language.text("重新启动", "Restart")) {
                    selectedPID = row.pid
                    onRestartTask(row)
                }
            } else if canTerminate(row) {
                Button(language.text("结束任务", "End task")) {
                    selectedPID = row.pid
                    onEndTask(row.pid)
                }
            } else if canRestart(row) {
                Button(language.text("重新启动", "Restart")) {
                    selectedPID = row.pid
                    onRestartTask(row)
                }
            }

            Menu(language.text("资源值", "Resource values")) {
                Menu(language.text("内存", "Memory")) {
                    Button(language.text("百分比", "Percent")) {
                        memoryDisplayMode = .percent
                    }
                    Button(language.text("值", "Values")) {
                        memoryDisplayMode = .value
                    }
                }
                Menu(language.text("磁盘", "Disk")) {
                    Button(language.text("百分比", "Percent")) {
                        diskDisplayMode = .percent
                    }
                    Button(language.text("值", "Values")) {
                        diskDisplayMode = .value
                    }
                }
                Menu(language.text("网络", "Network")) {
                    Button(language.text("百分比", "Percent")) {
                        networkDisplayMode = .percent
                    }
                    Button(language.text("值", "Values")) {
                        networkDisplayMode = .value
                    }
                }
            }

            Button(language.text("转到详细信息", "Go to details")) {
                selectedPID = row.pid
                onOpenDetailsTab(row.pid)
            }

            Button(language.text("打开文件所在的位置", "Open file location")) {
                onRevealInFinder(row.path)
            }
            .disabled(row.path.isEmpty)

            Button(language.text("在线搜索", "Search online")) {
                onSearchWeb(row.name)
            }

            Button(language.text("属性", "Properties")) {
                onShowProperties(row)
            }

            Divider()

            Button(language.text("复制", "Copy")) {
                onCopyProcessDetails(row)
            }
        }
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

    private func memoryText(for row: ProcessRowData) -> String {
        switch memoryDisplayMode {
        case .value:
            return DisplayFormat.memory(row.memoryBytes)
        case .percent:
            guard monitor.memory.totalBytes > 0 else { return "0%" }
            let percent = Double(row.memoryBytes) / Double(monitor.memory.totalBytes) * 100
            return DisplayFormat.percentWithPrecision(percent, digits: 1)
        }
    }

    private func diskText(for row: ProcessRowData) -> String {
        switch diskDisplayMode {
        case .value:
            return DisplayFormat.throughput(row.diskBytesPerSecond)
        case .percent:
            let percent = min(Double(row.diskBytesPerSecond) / 4_000_000 * 100, 100)
            return DisplayFormat.percentWithPrecision(percent, digits: 0)
        }
    }

    private func networkText(for row: ProcessRowData) -> String {
        switch networkDisplayMode {
        case .value:
            return row.networkText
        case .percent:
            let total = monitor.networks.reduce(UInt64(0)) { $0 + $1.sendBytesPerSecond + $1.receiveBytesPerSecond }
            guard total > 0 else { return "0%" }
            let percent = min(Double(row.networkBytesPerSecond) / Double(total) * 100, 100)
            return DisplayFormat.percentWithPrecision(percent, digits: 0)
        }
    }

    private func summaryMemoryText(_ totalMemory: UInt64) -> String {
        switch memoryDisplayMode {
        case .value:
            return DisplayFormat.memory(totalMemory)
        case .percent:
            guard monitor.memory.totalBytes > 0 else { return "0%" }
            let percent = Double(totalMemory) / Double(monitor.memory.totalBytes) * 100
            return DisplayFormat.percentWithPrecision(percent, digits: 1)
        }
    }

    private func summaryDiskText(_ totalDisk: UInt64) -> String {
        switch diskDisplayMode {
        case .value:
            return DisplayFormat.throughput(totalDisk)
        case .percent:
            let percent = min(Double(totalDisk) / 4_000_000 * 100, 100)
            return DisplayFormat.percentWithPrecision(percent, digits: 0)
        }
    }

    private func summaryNetworkText(_ totalNetwork: UInt64) -> String {
        switch networkDisplayMode {
        case .value:
            return totalNetwork == 0 ? "0 Mbps" : DisplayFormat.networkRate(totalNetwork)
        case .percent:
            let total = monitor.networks.reduce(UInt64(0)) { $0 + $1.sendBytesPerSecond + $1.receiveBytesPerSecond }
            guard total > 0 else { return "0%" }
            let percent = min(Double(totalNetwork) / Double(total) * 100, 100)
            return DisplayFormat.percentWithPrecision(percent, digits: 0)
        }
    }
}

private struct UsersScaledWidths {
    let user: CGFloat
    let status: CGFloat
    let cpu: CGFloat
    let memory: CGFloat
    let disk: CGFloat
    let network: CGFloat

    init(scale: CGFloat) {
        user = UsersColumnLayout.user * scale
        status = UsersColumnLayout.status * scale
        cpu = UsersColumnLayout.cpu * scale
        memory = UsersColumnLayout.memory * scale
        disk = UsersColumnLayout.disk * scale
        network = UsersColumnLayout.network * scale
    }

    var total: CGFloat { user + status + cpu + memory + disk + network }
}
