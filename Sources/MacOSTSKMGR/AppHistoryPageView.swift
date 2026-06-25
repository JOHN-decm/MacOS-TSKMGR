import SwiftUI

private enum AppHistoryColumnLayout {
    static let insetLeading: CGFloat = 8
    static let insetTrailing: CGFloat = 14
    static let scrollBarReserve: CGFloat = 18
    static let name: CGFloat = 210
    static let cpuTime: CGFloat = 110
    static let network: CGFloat = 110
    static let meteredNetwork: CGFloat = 118
    static let totalWidth: CGFloat = name + cpuTime + network + meteredNetwork
    static let rowHeight: CGFloat = 32
    static let headerHeight: CGFloat = 44
}

private enum AppHistorySortKey {
    case name
    case cpuTime
    case network
    case meteredNetwork
}

struct AppHistoryPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @ObservedObject var monitor: SystemMonitor
    let onSearchWeb: (String) -> Void = { query in
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
    let onShowProperties: (AppHistoryRowData) -> Void = { row in
        guard !row.path.isEmpty else { return }
        let script = """
        tell application "Finder"
            activate
            set targetItem to POSIX file "\(row.path)" as alias
            open information window of targetItem
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
    @State private var sortKey: AppHistorySortKey = .cpuTime
    @State private var ascending = false
    @State private var selectedRowID: String?

    var body: some View {
        GeometryReader { proxy in
            let widths = scaledWidths(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("自 2026/6/10 以来，当前用户帐户的资源使用情况。", "Resource usage for the current account since 2026/6/10."))
                        .font(.system(size: 14))
                        .compatForegroundStyle(AppTheme.primaryText(colorScheme))
                    Button(language.text("删除使用情况历史记录", "Delete usage history")) {
                        monitor.clearAppHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .compatForegroundStyle(Color(red: 0.13, green: 0.36, blue: 0.82))
                }
                .frame(width: widths.total, alignment: .leading)
                .padding(.bottom, 10)

                HStack(spacing: 0) {
                    historyHeaderCell(language.text("名称", "Name"), sortKey: .name, width: widths.name, alignLeading: true)
                    historyHeaderCell(language.text("CPU 时间", "CPU time"), sortKey: .cpuTime, width: widths.cpuTime, alignLeading: false)
                    historyHeaderCell(language.text("网络", "Network"), sortKey: .network, width: widths.network, alignLeading: false)
                    historyHeaderCell(language.text("按流量计费的网络", "Metered net"), sortKey: .meteredNetwork, width: widths.meteredNetwork, alignLeading: false)
                }
                .frame(width: widths.total, height: AppHistoryColumnLayout.headerHeight, alignment: .leading)
                .background(AppTheme.tableHeader(colorScheme))
                .compatBottomDivider(AppTheme.strongSeparator(colorScheme))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                historyNameRowCell(row, width: widths.name)
                                historyRowCell(row.cpuTime, width: widths.cpuTime, alignLeading: false)
                                historyRowCell(row.network, width: widths.network, alignLeading: false)
                                historyRowCell(row.meteredNetwork, width: widths.meteredNetwork, alignLeading: false)
                            }
                            .frame(height: AppHistoryColumnLayout.rowHeight)
                            .background(historyRowBackground(row, rowIndex: index))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRowID = row.id
                            }
                            .contextMenu {
                                Button(language.text("在线搜索", "Search online")) {
                                    onSearchWeb(row.name)
                                }
                                Button(language.text("属性", "Properties")) {
                                    onShowProperties(row)
                                }
                            }
                        }
                    }
                    .frame(width: widths.total, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 18)
            .padding(.leading, AppHistoryColumnLayout.insetLeading)
            .padding(.trailing, AppHistoryColumnLayout.insetTrailing)
        }
    }

    private var sortedRows: [AppHistoryRowData] {
        monitor.appHistoryRows.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .cpuTime:
                result = lhs.cpuSeconds < rhs.cpuSeconds
            case .network:
                result = lhs.networkBytes < rhs.networkBytes
            case .meteredNetwork:
                result = lhs.meteredNetworkBytes < rhs.meteredNetworkBytes
            }
            return ascending ? result : !result
        }
    }

    private func historyHeaderCell(_ title: String, sortKey: AppHistorySortKey, width: CGFloat, alignLeading: Bool) -> some View {
        Button {
            if self.sortKey == sortKey {
                ascending.toggle()
            } else {
                self.sortKey = sortKey
                ascending = sortKey == .name
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if self.sortKey == sortKey {
                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .compatSecondaryStyle()
                } else {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.secondary.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: AppHistoryColumnLayout.headerHeight, alignment: alignLeading ? .leading : .center)
        }
        .buttonStyle(.plain)
        .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func historyRowCell(_ value: String, width: CGFloat, alignLeading: Bool) -> some View {
        Text(value)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: AppHistoryColumnLayout.rowHeight, alignment: alignLeading ? .leading : .trailing)
            .compatForegroundStyle(AppTheme.primaryText(colorScheme))
            .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func historyNameRowCell(_ row: AppHistoryRowData, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(icon: row.icon)
            Text(row.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .compatForegroundStyle(AppTheme.primaryText(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: AppHistoryColumnLayout.rowHeight, alignment: .leading)
        .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func historyRowBackground(_ row: AppHistoryRowData, rowIndex: Int) -> Color {
        if selectedRowID == row.id {
            return AppTheme.selectedRow(colorScheme)
        }
        return rowIndex.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme)
    }

    private func scaledWidths(for availableWidth: CGFloat) -> AppHistoryScaledWidths {
        let usableWidth = max(
            600,
            availableWidth - AppHistoryColumnLayout.insetLeading - AppHistoryColumnLayout.insetTrailing - AppHistoryColumnLayout.scrollBarReserve
        )
        let scale = usableWidth / AppHistoryColumnLayout.totalWidth
        return AppHistoryScaledWidths(scale: scale)
    }
}

private struct AppHistoryScaledWidths {
    let name: CGFloat
    let cpuTime: CGFloat
    let network: CGFloat
    let meteredNetwork: CGFloat

    init(scale: CGFloat) {
        name = AppHistoryColumnLayout.name * scale
        cpuTime = AppHistoryColumnLayout.cpuTime * scale
        network = AppHistoryColumnLayout.network * scale
        meteredNetwork = AppHistoryColumnLayout.meteredNetwork * scale
    }

    var total: CGFloat { name + cpuTime + network + meteredNetwork }
}
