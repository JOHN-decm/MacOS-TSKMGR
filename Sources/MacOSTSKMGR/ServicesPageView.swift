import SwiftUI

private enum ServicesColumnLayout {
    static let insetLeading: CGFloat = 8
    static let insetTrailing: CGFloat = 14
    static let scrollBarReserve: CGFloat = 18
    static let name: CGFloat = 200
    static let pid: CGFloat = 80
    static let description: CGFloat = 420
    static let status: CGFloat = 110
    static let group: CGFloat = 140
    static let totalWidth: CGFloat = name + pid + description + status + group
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 44
}

private enum ServicesSortKey {
    case name
    case pid
    case description
    case status
    case group
}

struct ServicesPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @ObservedObject var monitor: SystemMonitor
    @Binding var selectedPID: Int32?
    let onStartService: (ServiceRowData) -> Void
    let onStopService: (ServiceRowData) -> Void
    let onRestartService: (ServiceRowData) -> Void
    let onSearchWeb: (String) -> Void
    let onOpenDetailsTab: (Int32) -> Void
    @State private var sortKey: ServicesSortKey = .name
    @State private var ascending = true

    var body: some View {
        GeometryReader { proxy in
            let widths = scaledWidths(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    headerCell(language.text("名称", "Name"), sortKey: .name, width: widths.name)
                    headerCell("PID", sortKey: .pid, width: widths.pid)
                    headerCell(language.text("描述", "Description"), sortKey: .description, width: widths.description)
                    headerCell(language.text("状态", "Status"), sortKey: .status, width: widths.status)
                    headerCell(language.text("组", "Group"), sortKey: .group, width: widths.group)
                }
                .frame(width: widths.total, height: ServicesColumnLayout.headerHeight, alignment: .leading)
                .background(AppTheme.tableHeader(colorScheme))
                .compatBottomDivider(AppTheme.strongSeparator(colorScheme))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                nameRowCell(row, width: widths.name)
                                rowCell(row.pid.map(String.init) ?? "", width: widths.pid)
                                rowCell(row.serviceDescription, width: widths.description)
                                rowCell(language.isChinese ? row.status : language.translateServiceStatus(row.status), width: widths.status)
                                rowCell(row.group, width: widths.group)
                            }
                            .frame(height: ServicesColumnLayout.rowHeight)
                            .background(serviceRowBackground(row, rowIndex: index))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPID = row.pid
                            }
                            .contextMenu {
                                serviceContextMenu(for: row)
                            }
                        }
                    }
                    .frame(width: widths.total, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 18)
            .padding(.leading, ServicesColumnLayout.insetLeading)
            .padding(.trailing, ServicesColumnLayout.insetTrailing)
            .onAppear {
                monitor.refreshServicesNow()
            }
        }
    }

    private var sortedRows: [ServiceRowData] {
        monitor.serviceRows.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .pid:
                result = (lhs.pid ?? -1) < (rhs.pid ?? -1)
            case .description:
                result = lhs.serviceDescription.localizedStandardCompare(rhs.serviceDescription) == .orderedAscending
            case .status:
                result = serviceStatusRank(lhs.status) < serviceStatusRank(rhs.status)
            case .group:
                result = lhs.group.localizedStandardCompare(rhs.group) == .orderedAscending
            }
            return ascending ? result : !result
        }
    }

    private func headerCell(_ title: String, sortKey: ServicesSortKey, width: CGFloat) -> some View {
        Button {
            if self.sortKey == sortKey {
                ascending.toggle()
            } else {
                self.sortKey = sortKey
                ascending = (sortKey == .name || sortKey == .description || sortKey == .group)
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
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: ServicesColumnLayout.headerHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func nameRowCell(_ row: ServiceRowData, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(icon: row.icon)
            Text(row.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .compatForegroundStyle(AppTheme.primaryText(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: ServicesColumnLayout.rowHeight, alignment: .leading)
        .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func rowCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(width: width, height: ServicesColumnLayout.rowHeight, alignment: .leading)
            .compatForegroundStyle(AppTheme.primaryText(colorScheme))
            .compatTrailingDivider(AppTheme.separator(colorScheme))
    }

    private func serviceRowBackground(_ row: ServiceRowData, rowIndex: Int) -> Color {
        if let pid = row.pid, selectedPID == pid {
            return AppTheme.selectedRow(colorScheme)
        }
        return rowIndex.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme)
    }

    private func scaledWidths(for availableWidth: CGFloat) -> ServicesScaledWidths {
        let usableWidth = max(
            900,
            availableWidth - ServicesColumnLayout.insetLeading - ServicesColumnLayout.insetTrailing - ServicesColumnLayout.scrollBarReserve
        )
        let scale = usableWidth / ServicesColumnLayout.totalWidth
        return ServicesScaledWidths(scale: scale)
    }

    private func serviceStatusRank(_ status: String) -> Int {
        switch language.translateServiceStatus(status) {
        case "Running": return 0
        case "On demand": return 1
        case "Loaded": return 2
        case "Stopped": return 3
        case "Not loaded": return 4
        case "Disabled": return 5
        default: return 6
        }
    }

    private func serviceContextMenu(for row: ServiceRowData) -> some View {
        Group {
            Button(language.text("开始", "Start")) {
                onStartService(row)
            }
            .disabled(!canStart(row))

            Button(language.text("停止", "Stop")) {
                onStopService(row)
            }
            .disabled(!canStop(row))

            Button(language.text("重新启动", "Restart")) {
                onRestartService(row)
            }
            .disabled(!canRestart(row))

            Divider()

            Button(language.text("打开服务", "Open service")) {
                if let pid = row.pid {
                    onOpenDetailsTab(pid)
                }
            }
            .disabled(row.pid == nil)

            Button(language.text("在线搜索", "Search online")) {
                onSearchWeb(row.name)
            }

            Button(language.text("转到详细信息", "Go to details")) {
                if let pid = row.pid {
                    onOpenDetailsTab(pid)
                }
            }
            .disabled(row.pid == nil)
        }
    }

    private func canStart(_ row: ServiceRowData) -> Bool {
        row.status == "已停止" || row.status == "未加载" || row.status == "已禁用"
    }

    private func canStop(_ row: ServiceRowData) -> Bool {
        row.status == "正在运行" || row.status == "按需" || row.status == "已加载"
    }

    private func canRestart(_ row: ServiceRowData) -> Bool {
        row.status == "正在运行"
    }
}

private struct ServicesScaledWidths {
    let name: CGFloat
    let pid: CGFloat
    let description: CGFloat
    let status: CGFloat
    let group: CGFloat

    init(scale: CGFloat) {
        name = ServicesColumnLayout.name * scale
        pid = ServicesColumnLayout.pid * scale
        description = ServicesColumnLayout.description * scale
        status = ServicesColumnLayout.status * scale
        group = ServicesColumnLayout.group * scale
    }

    var total: CGFloat { name + pid + description + status + group }
}
