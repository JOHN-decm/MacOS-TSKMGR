import SwiftUI

private enum StartupColumnLayout {
    static let insetLeading: CGFloat = 8
    static let insetTrailing: CGFloat = 14
    static let scrollBarReserve: CGFloat = 18
    static let name: CGFloat = 280
    static let publisher: CGFloat = 210
    static let status: CGFloat = 120
    static let impact: CGFloat = 110
    static let totalWidth: CGFloat = name + publisher + status + impact
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 44
}

private enum StartupSortKey {
    case name
    case publisher
    case status
    case impact
}

struct StartupPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @ObservedObject var monitor: SystemMonitor
    @State private var sortKey: StartupSortKey = .name
    @State private var ascending = true
    @State private var selectedRowID: String?

    var body: some View {
        GeometryReader { proxy in
            let widths = scaledWidths(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text(language.text("本次系统启动时间: ", "Startup time: ") + "\(String(format: "%.1f", monitor.currentBootDurationSeconds())) " + language.text("秒", "s"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                }
                .frame(width: widths.total, alignment: .trailing)
                .padding(.bottom, 10)

                HStack(spacing: 0) {
                    headerCell(language.text("名称", "Name"), sortKey: .name, width: widths.name)
                    headerCell(language.text("发布者", "Publisher"), sortKey: .publisher, width: widths.publisher)
                    headerCell(language.text("状态", "Status"), sortKey: .status, width: widths.status)
                    headerCell(language.text("启动影响", "Impact"), sortKey: .impact, width: widths.impact)
                }
                .frame(width: widths.total, height: StartupColumnLayout.headerHeight, alignment: .leading)
                .background(AppTheme.tableHeader(colorScheme))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.strongSeparator(colorScheme)).frame(height: 1)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                nameRowCell(row, width: widths.name)
                                rowCell(language.isChinese ? row.publisher : language.translateDirectoryLabel(row.publisher), width: widths.publisher, align: .leading)
                                rowCell(statusText(for: row), width: widths.status, align: .leading)
                                rowCell(language.isChinese ? row.startupImpact : language.translateStartupImpact(row.startupImpact), width: widths.impact, align: .leading)
                            }
                            .frame(height: StartupColumnLayout.rowHeight)
                            .background(startupRowBackground(row, rowIndex: index))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRowID = row.id
                            }
                            .contextMenu {
                                Button(toggleMenuTitle(for: row)) {
                                    toggleStartupItem(row)
                                }
                                .disabled(!canToggleStartupItem(row))

                                Button(language.text("打开文件所在的位置", "Open file location")) {
                                    revealStartupItem(row)
                                }
                                .disabled(!canRevealStartupItem(row))

                                Button(language.text("在线搜索", "Search online")) {
                                    searchStartupItem(row)
                                }

                                Button(language.text("属性", "Properties")) {
                                    showStartupItemProperties(row)
                                }
                                .disabled(!canShowStartupItemProperties(row))
                            }
                        }
                    }
                    .frame(width: widths.total, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 18)
            .padding(.leading, StartupColumnLayout.insetLeading)
            .padding(.trailing, StartupColumnLayout.insetTrailing)
        }
    }

    private var sortedRows: [StartupItemRowData] {
        monitor.startupRows.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .publisher:
                result = lhs.publisher.localizedStandardCompare(rhs.publisher) == .orderedAscending
            case .status:
                result = lhs.status.localizedStandardCompare(rhs.status) == .orderedAscending
            case .impact:
                result = lhs.startupImpact.localizedStandardCompare(rhs.startupImpact) == .orderedAscending
            }
            return ascending ? result : !result
        }
    }

    private func headerCell(_ title: String, sortKey: StartupSortKey, width: CGFloat) -> some View {
        Button {
            if self.sortKey == sortKey {
                ascending.toggle()
            } else {
                self.sortKey = sortKey
                ascending = true
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
            .frame(width: width, height: StartupColumnLayout.headerHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func rowCell(_ value: String, width: CGFloat, align: Alignment) -> some View {
        Text(value)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: StartupColumnLayout.rowHeight, alignment: align)
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
            }
    }

    private func nameRowCell(_ row: StartupItemRowData, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(icon: row.icon)
            Text(row.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(AppTheme.primaryText(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: StartupColumnLayout.rowHeight, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
        }
    }

    private func startupRowBackground(_ row: StartupItemRowData, rowIndex: Int) -> Color {
        if selectedRowID == row.id {
            return AppTheme.selectedRow(colorScheme)
        }
        return rowIndex.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme)
    }

    private func statusText(for row: StartupItemRowData) -> String {
        let raw = isDisabled(row) ? language.text("已禁用", "Disabled") : row.status
        return language.isChinese ? raw : language.translateStartupStatus(raw)
    }

    private func isDisabled(_ row: StartupItemRowData) -> Bool {
        row.status == "已禁用"
    }

    private func toggleMenuTitle(for row: StartupItemRowData) -> String {
        isDisabled(row) ? language.text("启用", "Enable") : language.text("禁用", "Disable")
    }

    private func canToggleStartupItem(_ row: StartupItemRowData) -> Bool {
        guard row.id.hasPrefix("/") else { return false }
        if row.id.hasPrefix("/System/Library/") {
            return false
        }
        return startupLabel(forPlistAt: row.id) != nil
    }

    private func canRevealStartupItem(_ row: StartupItemRowData) -> Bool {
        row.id.hasPrefix("/")
    }

    private func canShowStartupItemProperties(_ row: StartupItemRowData) -> Bool {
        row.id.hasPrefix("/")
    }

    private func toggleStartupItem(_ row: StartupItemRowData) {
        guard canToggleStartupItem(row) else { return }
        let path = row.id
        let label = startupLabel(forPlistAt: path) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let group = startupGroup(for: path)
        let enable = isDisabled(row)

        if group == "system" {
            toggleSystemStartupItem(path: path, label: label, enable: enable)
        } else {
            toggleUserStartupItem(path: path, label: label, enable: enable)
        }
        monitor.refreshNow()
    }

    private func startupLabel(forPlistAt path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["Label"] as? String
    }

    private func startupGroup(for path: String) -> String {
        if path.contains("LaunchDaemons") {
            return "system"
        }
        return "gui/\(getuid())"
    }

    private func toggleUserStartupItem(path: String, label: String, enable: Bool) {
        let domain = "gui/\(getuid())/\(label)"
        let command = enable ? ["enable", domain] : ["disable", domain]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = command
        try? process.run()
        process.waitUntilExit()
        setDisabledFlagInPlist(path: path, disabled: !enable)
    }

    private func toggleSystemStartupItem(path: String, label: String, enable: Bool) {
        let command = enable ? "launchctl enable system/\(label)" : "launchctl disable system/\(label)"
        let plistFlag = enable ? "false" : "true"
        let script = """
        do shell script "\(command); /usr/bin/plutil -replace Disabled -bool \(plistFlag) '\(path)'" with administrator privileges
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }

    private func setDisabledFlagInPlist(path: String, disabled: Bool) {
        guard let data = FileManager.default.contents(atPath: path),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return }
        plist["Disabled"] = disabled
        if let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? updated.write(to: URL(fileURLWithPath: path))
        }
    }

    private func revealStartupItem(_ row: StartupItemRowData) {
        guard canRevealStartupItem(row) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.id)])
    }

    private func searchStartupItem(_ row: StartupItemRowData) {
        let encoded = row.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? row.name
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showStartupItemProperties(_ row: StartupItemRowData) {
        guard canShowStartupItemProperties(row) else { return }
        let targetPath = row.id.hasPrefix("/") ? row.id : row.name
        guard targetPath.hasPrefix("/") else { return }
        let script = """
        tell application "Finder"
            activate
            set targetItem to POSIX file "\(targetPath)" as alias
            open information window of targetItem
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func scaledWidths(for availableWidth: CGFloat) -> StartupScaledWidths {
        let usableWidth = max(
            720,
            availableWidth - StartupColumnLayout.insetLeading - StartupColumnLayout.insetTrailing - StartupColumnLayout.scrollBarReserve
        )
        let scale = usableWidth / StartupColumnLayout.totalWidth
        return StartupScaledWidths(scale: scale)
    }
}

private struct StartupScaledWidths {
    let name: CGFloat
    let publisher: CGFloat
    let status: CGFloat
    let impact: CGFloat

    init(scale: CGFloat) {
        name = StartupColumnLayout.name * scale
        publisher = StartupColumnLayout.publisher * scale
        status = StartupColumnLayout.status * scale
        impact = StartupColumnLayout.impact * scale
    }

    var total: CGFloat { name + publisher + status + impact }
}
