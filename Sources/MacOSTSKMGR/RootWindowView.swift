import SwiftUI
import AppKit

enum PageInset {
    static let horizontal: CGFloat = 24
    static let top: CGFloat = 16
    static let bottom: CGFloat = 16
}

private enum WindowPresentationMode: Equatable {
    case compact
    case performanceSummary
    case performanceDetailSummary
    case full
}

struct RootWindowView: View {
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var newTaskPanelManager = NewTaskPanelManager()
    @StateObject private var networkDetailsPanelManager = NetworkDetailsPanelManager()
    @StateObject private var aboutPanelManager = AboutPanelManager()
    @State private var language: AppLanguage = .chinese
    @State private var selectedTab: TaskTab = .processes
    @State private var selectedPerf: PerfSelection = .cpu
    @State private var performanceViewMode: PerformanceViewMode = .full
    @State private var showsPerformanceGraphs = true
    @State private var cpuGraphMode: CPUGraphMode = .logicalProcessors
    @State private var gpuGraphLayoutMode: GPUGraphLayoutMode = .multiEngine
    @State private var showsKernelTime = false
    @State private var compactMode = true
    @State private var activeMenu: MenuKind?
    @State private var showRefreshSpeedSubmenu = false
    @State private var showLanguageSubmenu = false
    @State private var refreshSpeedParentHovered = false
    @State private var refreshSpeedSubmenuHovered = false
    @State private var languageParentHovered = false
    @State private var languageSubmenuHovered = false
    @State private var alwaysOnTop = false
    @State private var hideWhenMinimized = false
    @State private var useSmallValues = false
    @State private var collapsedSections: Set<String> = []
    @State private var processMemoryDisplayMode: ProcessResourceDisplayMode = .value
    @State private var processDiskDisplayMode: ProcessResourceDisplayMode = .value
    @State private var processNetworkDisplayMode: ProcessResourceDisplayMode = .value
    @State private var selectedProcessPID: Int32?
    @State private var taskActionErrorMessage = ""
    @State private var lastWindowPresentationMode: WindowPresentationMode?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if compactMode {
                CompactModeContainer(
                    rows: compactApplicationRows,
                    selectedPID: $selectedProcessPID,
                    primaryActionTitle: primaryTaskActionTitle,
                    onToggleCompact: toggleCompactMode,
                    onPrimaryAction: performPrimaryTaskAction
                )
            } else if selectedTab == .performance && performanceViewMode == .detailSummary {
                PerformancePageView(
                    monitor: monitor,
                    selectedPerf: $selectedPerf,
                    viewMode: $performanceViewMode,
                    showsGraphs: $showsPerformanceGraphs,
                    cpuGraphMode: $cpuGraphMode,
                    gpuGraphLayoutMode: $gpuGraphLayoutMode,
                    showsKernelTime: $showsKernelTime,
                    onOpenNetworkDetails: { networkDetailsPanelManager.show(network: $0, language: language) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedTab == .performance && performanceViewMode == .summary {
                PerformancePageView(
                    monitor: monitor,
                    selectedPerf: $selectedPerf,
                    viewMode: $performanceViewMode,
                    showsGraphs: $showsPerformanceGraphs,
                    cpuGraphMode: $cpuGraphMode,
                    gpuGraphLayoutMode: $gpuGraphLayoutMode,
                    showsKernelTime: $showsKernelTime,
                    onOpenNetworkDetails: { networkDetailsPanelManager.show(network: $0, language: language) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    WindowChromeView(
                        selectedTab: $selectedTab,
                        activeMenu: $activeMenu
                    )

                    Group {
                        switch selectedTab {
                        case .processes:
                            ProcessesPageView(
                                monitor: monitor,
                                collapsedSections: $collapsedSections,
                                selectedPID: $selectedProcessPID,
                                memoryDisplayMode: $processMemoryDisplayMode,
                                diskDisplayMode: $processDiskDisplayMode,
                                networkDisplayMode: $processNetworkDisplayMode,
                                onEndTask: endTask(pid:),
                                onRestartTask: restartProcess,
                                onRevealInFinder: revealInFinder,
                                onSearchWeb: searchWeb,
                                onShowProperties: showProcessProperties,
                                onCopyProcessDetails: copyProcessDetails,
                                onOpenDetailsTab: openDetailsTab
                            )
                        case .performance:
                            PerformancePageView(
                                monitor: monitor,
                                selectedPerf: $selectedPerf,
                                viewMode: $performanceViewMode,
                                showsGraphs: $showsPerformanceGraphs,
                                cpuGraphMode: $cpuGraphMode,
                                gpuGraphLayoutMode: $gpuGraphLayoutMode,
                                showsKernelTime: $showsKernelTime,
                                onOpenNetworkDetails: { networkDetailsPanelManager.show(network: $0, language: language) }
                            )
                        case .history:
                            AppHistoryPageView(monitor: monitor)
                        case .startup:
                            StartupPageView(monitor: monitor)
                        case .users:
                            UsersPageView(
                                monitor: monitor,
                                selectedPID: $selectedProcessPID,
                                memoryDisplayMode: $processMemoryDisplayMode,
                                diskDisplayMode: $processDiskDisplayMode,
                                networkDisplayMode: $processNetworkDisplayMode,
                                onEndTask: endTask(pid:),
                                onRestartTask: restartProcess,
                                onRevealInFinder: revealInFinder,
                                onSearchWeb: searchWeb,
                                onShowProperties: showProcessProperties,
                                onCopyProcessDetails: copyProcessDetails,
                                onOpenDetailsTab: openDetailsTab
                            )
                        case .details:
                            DetailsPageView(
                                monitor: monitor,
                                selectedPID: $selectedProcessPID,
                                memoryDisplayMode: $processMemoryDisplayMode,
                                onEndTask: endTask(pid:),
                                onEndProcessTree: endProcessTree(pid:),
                                onRestartTask: restartProcess,
                                onRevealInFinder: revealInFinder,
                                onSearchWeb: searchWeb,
                                onShowProperties: showProcessProperties,
                                onCopyProcessDetails: copyProcessDetails,
                                onOpenDetailsTab: openDetailsTab,
                                onOpenServicesTab: openServicesTab,
                                onSetPriority: setProcessPriority(pid:preset:)
                            )
                        case .services:
                            ServicesPageView(
                                monitor: monitor,
                                selectedPID: $selectedProcessPID,
                                onStartService: startService,
                                onStopService: stopService,
                                onRestartService: restartService,
                                onSearchWeb: searchWeb,
                                onOpenDetailsTab: openDetailsTab
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    FooterBarView(
                        compactMode: $compactMode,
                        canEndTask: canEndSelectedTask,
                        primaryActionTitle: primaryTaskActionTitle,
                        onToggleCompact: toggleCompactMode,
                        onPrimaryAction: performPrimaryTaskAction
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let activeMenu {
                menuOverlay(for: activeMenu)
                    .padding(.top, 56)
                    .padding(.leading, menuXOffset(for: activeMenu))
                    .zIndex(10)
            }
        }
        .background(WindowSurfaceBackground())
        .ignoresSafeArea(.container, edges: selectedTab == .performance && performanceViewMode != .full ? .all : .top)
        .alert(language.text("结束任务失败", "End task failed"), isPresented: taskActionErrorPresented) {
            Button(language.text("确定", "OK"), role: .cancel) {
                taskActionErrorMessage = ""
            }
        } message: {
            Text(taskActionErrorMessage)
        }
        .background(MenuKeyHandlingView(
            onAltF: { openMenu(.file) },
            onAltO: { openMenu(.options) },
            onAltV: { openMenu(.view) },
            onEscape: { activeMenu = nil }
        ))
        .onChange(of: alwaysOnTop) { _, value in
            updateWindowLevel(alwaysOnTop: value)
        }
        .onChange(of: monitor.sidebarItems.map(\.id)) { oldIDs, newIDs in
            guard !newIDs.isEmpty else { return }
            guard !newIDs.contains(selectedPerf) else { return }

            if let previousIndex = oldIDs.firstIndex(of: selectedPerf) {
                let fallbackIndex = min(previousIndex, newIDs.count - 1)
                selectedPerf = newIDs[fallbackIndex]
            } else {
                selectedPerf = newIDs[0]
            }
        }
        .onChange(of: refreshSpeedParentHovered) { _, _ in
            reconcileRefreshSubmenuVisibility()
        }
        .onChange(of: refreshSpeedSubmenuHovered) { _, _ in
            reconcileRefreshSubmenuVisibility()
        }
        .onChange(of: languageParentHovered) { _, _ in
            reconcileLanguageSubmenuVisibility()
        }
        .onChange(of: languageSubmenuHovered) { _, _ in
            reconcileLanguageSubmenuVisibility()
        }
        .onAppear {
            let mode = currentWindowPresentationMode
            lastWindowPresentationMode = mode
            resizeWindowForCurrentMode(animated: false)
        }
        .onChange(of: compactMode) { _, _ in
            exitPerformanceSummaryIfNeeded()
            resizeWindowIfNeeded(animated: true)
        }
        .onChange(of: performanceViewMode) { _, _ in
            resizeWindowIfNeeded(animated: true)
            updateWindowTrafficLights()
        }
        .onChange(of: selectedTab) { _, _ in
            exitPerformanceSummaryIfNeeded()
            reconcileSelectionForCurrentTab()
            updateWindowTrafficLights()
            resizeWindowIfNeeded(animated: true)
        }
        .onChange(of: language) { _, newValue in
            monitor.language = newValue
            newTaskPanelManager.update(language: newValue)
            networkDetailsPanelManager.updateLanguage(newValue)
            aboutPanelManager.update(language: newValue)
        }
        .onAppear {
            monitor.language = language
            monitor.start()
            updateWindowTrafficLights()
        }
        .environment(\.appLanguage, language)
    }

    private var compactApplicationRows: [ProcessRowData] {
        monitor.processSections.first(where: { $0.title.hasPrefix("应用") || $0.title.hasPrefix("Apps") })?.rows ?? []
    }

    private var canEndSelectedTask: Bool {
        guard let pid = selectedProcessPID else { return false }
        if isFinderProcess(pid: pid) {
            return selectedProcessRow(pid: pid) != nil
        }
        return canTerminate(pid: pid)
    }

    private var primaryTaskActionTitle: String {
        guard let pid = selectedProcessPID else {
            return language.text("结束任务(E)", "End task(E)")
        }
        return isFinderProcess(pid: pid)
            ? language.text("重新启动(R)", "Restart(R)")
            : language.text("结束任务(E)", "End task(E)")
    }

    private var taskActionErrorPresented: Binding<Bool> {
        Binding(
            get: { !taskActionErrorMessage.isEmpty },
            set: { presented in
                if !presented {
                    taskActionErrorMessage = ""
                }
            }
        )
    }

    private func openMenu(_ menu: MenuKind) {
        activeMenu = menu
        showRefreshSpeedSubmenu = false
        showLanguageSubmenu = false
        refreshSpeedParentHovered = false
        refreshSpeedSubmenuHovered = false
        languageParentHovered = false
        languageSubmenuHovered = false
    }

    private func reconcileRefreshSubmenuVisibility() {
        showRefreshSpeedSubmenu = refreshSpeedParentHovered || refreshSpeedSubmenuHovered
    }

    private func reconcileLanguageSubmenuVisibility() {
        showLanguageSubmenu = languageParentHovered || languageSubmenuHovered
    }

    private func menuXOffset(for menu: MenuKind) -> CGFloat {
        switch menu {
        case .file: 14
        case .options: 72
        case .view: 140
        }
    }

    @ViewBuilder
    private func menuOverlay(for menu: MenuKind) -> some View {
        switch menu {
        case .file:
            menuPanel {
                menuItem(language.text("运行新任务(N)", "Run new task(N)"), altHint: nil) {
                    newTaskPanelManager.show(language: language)
                    activeMenu = nil
                }
                Divider()
                menuItem(language.text("关于", "About"), altHint: nil) {
                    aboutPanelManager.show(language: language)
                    activeMenu = nil
                }
                Divider()
                menuItem(language.text("退出(X)", "Exit(X)"), altHint: nil) {
                    NSApp.terminate(nil)
                }
            }
        case .options:
            menuPanel {
                checkableMenuItem(language.text("置于顶层(A)", "Always on top(A)"), checked: alwaysOnTop) {
                    alwaysOnTop.toggle()
                    activeMenu = nil
                }
                checkableMenuItem(language.text("使用小值(U)", "Use small values(U)"), checked: useSmallValues) {
                    useSmallValues.toggle()
                    activeMenu = nil
                }
                checkableMenuItem(language.text("最小化时隐藏(H)", "Hide when minimized(H)"), checked: hideWhenMinimized) {
                    hideWhenMinimized.toggle()
                    activeMenu = nil
                }
                Divider()
                subMenuItem(language.text("语言", "Language"), expanded: showLanguageSubmenu) {
                    languageMenu
                } action: {}
                .onHover { hovering in
                    languageParentHovered = hovering
                }
            }
        case .view:
            menuPanel {
                menuItem(language.text("立即刷新(R)", "Refresh now(R)"), altHint: nil) {
                    monitor.refreshNow()
                    activeMenu = nil
                }
                subMenuItem(language.text("更新速度(U)", "Update speed(U)"), expanded: showRefreshSpeedSubmenu) {
                    refreshSpeedSubmenu
                } action: {
                    showRefreshSpeedSubmenu = true
                    refreshSpeedParentHovered = true
                }
                Divider()
                menuItem(language.text("全部展开(E)", "Expand all(E)"), altHint: nil) {
                    collapsedSections.removeAll()
                    activeMenu = nil
                }
                menuItem(language.text("全部折叠(C)", "Collapse all(C)"), altHint: nil) {
                    collapsedSections = Set(monitor.processSections.map(\.title))
                    activeMenu = nil
                }
            }
        }
    }

    private var refreshSpeedSubmenu: some View {
        VStack(spacing: 0) {
            ForEach(RefreshSpeedOption.allCases) { option in
                Button {
                    monitor.setRefreshSpeed(option)
                    showRefreshSpeedSubmenu = false
                    activeMenu = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: monitor.refreshSpeed == option ? "checkmark" : "")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                        Text(option.title(in: language))
                            .font(.system(size: 13))
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WinMenuButtonStyle())
            }
        }
        .frame(width: 124)
        .winMenuPanel()
        .offset(x: 167, y: -1)
        .onHover { hovering in
            refreshSpeedSubmenuHovered = hovering
        }
    }

    private var languageMenu: some View {
        VStack(spacing: 0) {
            Button {
                language = .chinese
                showLanguageSubmenu = false
                activeMenu = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: language == .chinese ? "checkmark" : "")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                    Text("中文")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
            }
            .buttonStyle(WinMenuButtonStyle())

            Button {
                language = .english
                showLanguageSubmenu = false
                activeMenu = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: language == .english ? "checkmark" : "")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                    Text("English")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
            }
            .buttonStyle(WinMenuButtonStyle())
        }
        .frame(width: 132)
        .winMenuPanel()
        .offset(x: 167, y: -1)
        .onHover { hovering in
            languageSubmenuHovered = hovering
        }
    }

    private func menuPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(width: 168)
            .winMenuPanel()
    }

    private func menuItem(_ title: String, altHint: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let altHint {
                    Text(altHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(WinMenuButtonStyle())
    }

    private func disabledMenuItem(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func checkableMenuItem(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark" : "")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(WinMenuButtonStyle())
    }

    private func subMenuItem<Content: View>(_ title: String, expanded: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                    Text(title)
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(WinMenuButtonStyle())
            .onHover { hovering in
                refreshSpeedParentHovered = hovering
            }

            if expanded {
                content()
            }
        }
        .frame(height: 28, alignment: .topLeading)
    }

    private func updateWindowLevel(alwaysOnTop: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.level = alwaysOnTop ? .floating : .normal
    }

    private func toggleCompactMode() {
        compactMode.toggle()
    }

    private var currentWindowPresentationMode: WindowPresentationMode {
        if compactMode {
            return .compact
        }
        if selectedTab == .performance && performanceViewMode == .summary {
            return .performanceSummary
        }
        if selectedTab == .performance && performanceViewMode == .detailSummary {
            return .performanceDetailSummary
        }
        return .full
    }

    private func resizeWindowIfNeeded(animated: Bool) {
        let newMode = currentWindowPresentationMode
        if lastWindowPresentationMode == nil {
            lastWindowPresentationMode = newMode
        }
        guard newMode != lastWindowPresentationMode else { return }
        lastWindowPresentationMode = newMode
        resizeWindowForCurrentMode(animated: animated)
    }

    private func resizeWindowForCurrentMode(animated: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let targetSize: NSSize
        let minSize: NSSize

        if compactMode {
            targetSize = NSSize(width: 400, height: 340)
            minSize = NSSize(width: 400, height: 340)
        } else if selectedTab == .performance && performanceViewMode == .summary {
            targetSize = NSSize(width: 300, height: 560)
            minSize = NSSize(width: 260, height: 420)
        } else if selectedTab == .performance && performanceViewMode == .detailSummary {
            targetSize = NSSize(width: 780, height: 510)
            minSize = NSSize(width: 640, height: 420)
        } else if selectedTab == .performance && performanceViewMode == .full {
            targetSize = NSSize(width: 1120, height: 760)
            minSize = NSSize(width: 1120, height: 760)
        } else {
            targetSize = NSSize(width: 1120, height: 760)
            minSize = NSSize(width: 1120, height: 760)
        }
        window.minSize = minSize
        var frame = window.frame
        frame.size = targetSize
        if animated {
            window.animator().setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func updateWindowTrafficLights() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let shouldHide = selectedTab == .performance && performanceViewMode == .summary
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
    }

    private func endSelectedTask() {
        guard let pid = selectedProcessPID else { return }
        let result = TaskTerminator.terminate(pid: pid)
        switch result {
        case .success:
            selectedProcessPID = nil
            monitor.refreshNow()
        case .failure(let message):
            taskActionErrorMessage = message
        }
    }

    private func performPrimaryTaskAction() {
        guard let pid = selectedProcessPID else { return }
        if isFinderProcess(pid: pid), let row = selectedProcessRow(pid: pid) {
            restartProcess(row)
            return
        }
        endSelectedTask()
    }

    private func endTask(pid: Int32) {
        selectedProcessPID = pid
        endSelectedTask()
    }

    private func endProcessTree(pid: Int32) {
        let children = monitor.listChildPIDs(parentPID: pid)
        for child in children {
            _ = TaskTerminator.terminate(pid: child)
        }
        endTask(pid: pid)
    }

    private func openDetailsTab(_ pid: Int32) {
        selectedProcessPID = pid
        selectedTab = .details
    }

    private func openServicesTab() {
        selectedTab = .services
    }

    private func isFinderProcess(pid: Int32) -> Bool {
        let name = selectedProcessName(pid: pid).lowercased()
        let path = monitor.pidPath(pid: pid).lowercased()
        return name == "finder" || name == "访达" || path.contains("/system/library/coreservices/finder.app")
    }

    private func selectedProcessName(pid: Int32) -> String {
        if let row = monitor.processSections.flatMap(\.rows).first(where: { $0.pid == pid }) {
            return row.name
        }
        if let row = monitor.currentUserAppRows.first(where: { $0.pid == pid }) {
            return row.name
        }
        if let row = monitor.detailProcessRows.first(where: { $0.pid == pid }) {
            return row.name
        }
        if let row = monitor.serviceRows.first(where: { $0.pid == pid }) {
            return row.name
        }
        return ""
    }

    private func selectedProcessRow(pid: Int32) -> ProcessRowData? {
        if let row = monitor.processSections.flatMap(\.rows).first(where: { $0.pid == pid }) {
            return row
        }
        if let row = monitor.currentUserAppRows.first(where: { $0.pid == pid }) {
            return row
        }
        if let info = monitor.processInfo(pid: pid) {
            return ProcessRowData(
                pid: pid,
                name: info.displayName,
                icon: info.icon,
                path: info.path,
                isApp: info.isApplication,
                isParent: false,
                parentPID: nil,
                childCount: 0,
                cpuPercent: 0,
                memoryBytes: info.residentSize,
                diskBytesPerSecond: 0,
                networkBytesPerSecond: 0,
                networkText: "0 Mbps",
                powerImpact: "",
                trend: "",
                threadCount: info.threadCount,
                openFiles: info.openFiles
            )
        }
        return nil
    }

    private func startService(_ row: ServiceRowData) {
        let target = serviceTarget(for: row)
        guard !target.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["enable", target]
        try? process.run()
        process.waitUntilExit()
        monitor.refreshServicesNow()
    }

    private func stopService(_ row: ServiceRowData) {
        let target = serviceTarget(for: row)
        guard !target.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["disable", target]
        try? process.run()
        process.waitUntilExit()
        monitor.refreshServicesNow()
    }

    private func restartService(_ row: ServiceRowData) {
        let target = serviceTarget(for: row)
        guard !target.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", target]
        try? process.run()
        process.waitUntilExit()
        monitor.refreshServicesNow()
    }

    private func serviceTarget(for row: ServiceRowData) -> String {
        "\(row.group)/\(row.label)"
    }

    private func restartProcess(_ row: ProcessRowData) {
        guard !row.path.isEmpty else { return }
        let url = URL(fileURLWithPath: row.path)
        _ = NSWorkspace.shared.open(url)
    }

    private func revealInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func searchWeb(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showProcessProperties(_ row: ProcessRowData) {
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

    private func copyProcessDetails(_ row: ProcessRowData) {
        let lines = [
            language.text("名称", "Name") + ": \(row.name)",
            "PID: \(row.pid)",
            "CPU: \(DisplayFormat.percentWithPrecision(row.cpuPercent, digits: 1))",
            language.text("内存", "Memory") + ": \(DisplayFormat.memory(row.memoryBytes))",
            language.text("磁盘", "Disk") + ": \(DisplayFormat.throughput(row.diskBytesPerSecond))",
            language.text("网络", "Network") + ": \(row.networkText)",
            language.text("电源使用情况", "Power usage") + ": \(row.powerImpact)"
        ]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func setProcessPriority(pid: Int32, preset: ProcessPriorityPreset) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/renice")
        process.arguments = ["-n", "\(preset.niceValue)", "-p", "\(pid)"]
        try? process.run()
        process.waitUntilExit()
        monitor.refreshNow()
    }

    private func canTerminate(pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return pid != Int32(ProcessInfo.processInfo.processIdentifier)
    }

    private func reconcileSelectionForCurrentTab() {
        guard let pid = selectedProcessPID else { return }

        switch selectedTab {
        case .processes:
            if !monitor.processSections.flatMap(\.rows).contains(where: { $0.pid == pid }) {
                selectedProcessPID = nil
            }
        case .users:
            if !monitor.currentUserAppRows.contains(where: { $0.pid == pid }) {
                selectedProcessPID = nil
            }
        case .details:
            if !monitor.detailProcessRows.contains(where: { $0.pid == pid }) {
                selectedProcessPID = nil
            }
        case .services:
            if !monitor.serviceRows.contains(where: { $0.pid == pid }) {
                selectedProcessPID = nil
            }
        default:
            selectedProcessPID = nil
        }
    }

    private func exitPerformanceSummaryIfNeeded() {
        if selectedTab != .performance || compactMode {
            performanceViewMode = .full
        }
    }
}

enum MenuKind {
    case file
    case options
    case view
}

struct WindowSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.windowTop(colorScheme),
                    AppTheme.windowBottom(colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
                .opacity(0.82)

            LinearGradient(
                colors: [
                    AppTheme.topGlow(colorScheme),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct WindowChromeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @Binding var selectedTab: TaskTab
    @Binding var activeMenu: MenuKind?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Color.clear.frame(width: 88, height: 1)
                    Spacer()
                    Color.clear.frame(width: 88, height: 1)
                }

                HStack(spacing: 8) {
                    TaskManagerGlyph()
                    Text(language.text("任务管理器", "Task Manager"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)

            HStack(spacing: 16) {
                chromeButton(language.text("文件(F)", "File(F)"), menu: .file)
                chromeButton(language.text("选项(O)", "Options(O)"), menu: .options)
                chromeButton(language.text("查看(V)", "View(V)"), menu: .view)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(AppTheme.chromeBackground(colorScheme))

            HStack(spacing: 2) {
                ForEach(TaskTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                        activeMenu = nil
                    } label: {
                        Text(tab.title(in: language))
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.primaryText(colorScheme))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(tab == selectedTab ? AppTheme.chromeSelectedFill(colorScheme) : Color.clear)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(tab == selectedTab ? AppTheme.accentBlue : .clear)
                                    .frame(height: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .padding(.bottom, 4)
        }
        .background {
            ZStack {
                VisualEffectBlur(material: .headerView, blendingMode: .withinWindow)
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.34),
                        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(height: 1)
        }
    }

    private func chromeButton(_ title: String, menu: MenuKind) -> some View {
        Button {
            activeMenu = activeMenu == menu ? nil : menu
        } label: {
            Text(title)
                .frame(height: 22)
                .padding(.horizontal, 2)
                .background(activeMenu == menu ? AppTheme.menuHighlight(colorScheme) : Color.clear)
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(AppTheme.primaryText(colorScheme))
    }
}

struct TaskManagerGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.95))
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.gray.opacity(0.5), lineWidth: 1)
                )

            Path { path in
                path.move(to: CGPoint(x: 3, y: 12))
                path.addLine(to: CGPoint(x: 6, y: 12))
                path.addLine(to: CGPoint(x: 7.3, y: 8))
                path.addLine(to: CGPoint(x: 9.4, y: 10.4))
                path.addLine(to: CGPoint(x: 11.2, y: 4))
                path.addLine(to: CGPoint(x: 13, y: 11))
            }
            .stroke(AppTheme.accentBlue, lineWidth: 1.1)
            .frame(width: 16, height: 16)
        }
    }
}

struct FooterBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    @Binding var compactMode: Bool
    let canEndTask: Bool
    let primaryActionTitle: String
    let onToggleCompact: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCompact) {
                HStack(spacing: 8) {
                    Circle()
                        .stroke(AppTheme.secondaryText(colorScheme), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: compactMode ? "chevron.down" : "chevron.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        )
                    Text(compactMode ? language.text("详细信息(D)", "Fewer details(D)") : language.text("简略信息(D)", "Fewer details(D)"))
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)

            Button(language.text("打开资源监视器", "Open Activity Monitor")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.accentBlue)

            Spacer()

            Button(primaryActionTitle, action: onPrimaryAction)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(canEndTask ? AppTheme.primaryText(colorScheme) : AppTheme.secondaryText(colorScheme))
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.footerButtonFill(colorScheme, enabled: canEndTask))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.footerStroke(colorScheme), lineWidth: 1)
                )
                .disabled(!canEndTask)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            ZStack {
                VisualEffectBlur(material: .sheet, blendingMode: .withinWindow)
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.18),
                        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(height: 1)
        }
    }
}

struct CompactApplicationsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [ProcessRowData]
    @Binding var selectedPID: Int32?

    var body: some View {
        List {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    ProcessIconView(icon: row.icon)
                    Text(row.name)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedPID == row.pid ? AppTheme.selectedRow(colorScheme) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPID = row.pid
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            if selectedPID == nil {
                selectedPID = rows.first?.pid
            }
        }
    }
}

struct CompactModeContainer: View {
    let rows: [ProcessRowData]
    @Binding var selectedPID: Int32?
    let primaryActionTitle: String
    let onToggleCompact: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CompactModeHeader()
            CompactApplicationsView(rows: rows, selectedPID: $selectedPID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CompactModeFooter(
                canEndTask: selectedPID != nil,
                primaryActionTitle: primaryActionTitle,
                onToggleCompact: onToggleCompact,
                onPrimaryAction: onPrimaryAction
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct CompactModeHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    var body: some View {
        ZStack {
            Text(language.text("任务管理器", "Task Manager"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.primaryText(colorScheme))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(height: 1)
        }
    }
}

struct CompactModeFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language
    let canEndTask: Bool
    let primaryActionTitle: String
    let onToggleCompact: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCompact) {
                HStack(spacing: 8) {
                    Circle()
                        .stroke(AppTheme.secondaryText(colorScheme), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        )
                    Text(language.text("详细信息(D)", "Fewer details(D)"))
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(primaryActionTitle, action: onPrimaryAction)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(canEndTask ? AppTheme.primaryText(colorScheme) : AppTheme.secondaryText(colorScheme))
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.compactFooterFill(colorScheme, enabled: canEndTask))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.compactFooterStroke(colorScheme), lineWidth: 1)
                )
                .disabled(!canEndTask)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator(colorScheme))
                .frame(height: 1)
        }
    }
}

struct WinMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(red: 0.75, green: 0.88, blue: 1.0) : Color.clear)
    }
}

struct NewTaskPanelView: View {
    let language: AppLanguage
    let onClose: () -> Void
    @State private var command = ""
    @State private var useAdmin = false
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .frame(width: 40)
                Text(language.text("MacOS 将根据你所键入的名称，为你打开相应的程序、文件夹、文档或 Internet 资源。", "macOS will open the app, folder, document, or Internet resource you enter."))
                    .font(.system(size: 14))
            }

            HStack(spacing: 8) {
                Text(language.text("打开(O):", "Open(O):"))
                    .font(.system(size: 14))
                TextField("", text: $command)
                    .textFieldStyle(.roundedBorder)
                Button(language.text("浏览(B)...", "Browse(B)...")) { browse() }
                    .buttonStyle(.bordered)
            }

            Toggle(language.text("使用管理权限创建此任务。", "Create this task with admin privileges."), isOn: $useAdmin)
                .toggleStyle(.checkbox)

            if useAdmin {
                HStack(spacing: 8) {
                    Text(language.text("密码(P):", "Password(P):"))
                        .font(.system(size: 14))
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(language.text("取消", "Cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(isRunning ? language.text("执行中...", "Running...") : language.text("确定", "OK")) {
                    runTask()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (useAdmin && password.isEmpty) || isRunning)
            }
        }
        .padding(18)
        .frame(width: 480, height: 240, alignment: .topLeading)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.title = language.text("浏览", "Browse")
        if panel.runModal() == .OK, let url = panel.url {
            command = url.path.contains(" ") ? "\"\(url.path)\"" : url.path
        }
    }

    private func runTask() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = ""
        isRunning = true
        let admin = useAdmin
        let pwd = password

        DispatchQueue.global(qos: .userInitiated).async {
            let result = TaskRunner.executeCommand(trimmed, asAdmin: admin, password: pwd)
            DispatchQueue.main.async {
                isRunning = false
                switch result {
                case .success:
                    onClose()
                case .failure(let message):
                    errorMessage = message
                }
            }
        }
    }

    private var input: String { command }

}

@MainActor
final class NewTaskPanelManager: ObservableObject {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 480, height: 286)

    func show(language: AppLanguage) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = false
            panel.isMovableByWindowBackground = false
            panel.minSize = panelSize
            panel.maxSize = panelSize
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.standardWindowButton(.closeButton)?.isHidden = false
            panel.standardWindowButton(.closeButton)?.isEnabled = true
            self.panel = panel
        }

        update(language: language)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(language: AppLanguage) {
        guard let panel else { return }
        panel.title = language.text("新建任务", "Create new task")
        panel.contentView = NSHostingView(
            rootView: NewTaskPanelView(
                language: language,
                onClose: { [weak self] in
                    self?.panel?.close()
                }
            )
        )
    }
}

@MainActor
final class NetworkDetailsPanelManager: ObservableObject {
    private var panel: NSPanel?
    private var currentLanguage: AppLanguage = .chinese
    private let panelSize = NSSize(width: 560, height: 760)
    private var currentNetwork: NetworkState?

    func show(network: NetworkState, language: AppLanguage) {
        currentNetwork = network
        currentLanguage = language
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = false
            panel.isMovableByWindowBackground = false
            panel.minSize = panelSize
            panel.maxSize = panelSize
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            self.panel = panel
        }

        updatePanel()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateLanguage(_ language: AppLanguage) {
        currentLanguage = language
        updatePanel()
    }

    private func updatePanel() {
        guard let panel, let currentNetwork else { return }
        panel.title = currentLanguage.text("网络详细信息", "Network details")
        panel.contentView = NSHostingView(
            rootView: NetworkDetailsView(
                network: currentNetwork,
                language: currentLanguage
            )
        )
    }
}

@MainActor
final class AboutPanelManager: ObservableObject {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 420, height: 320)

    func show(language: AppLanguage) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = false
            panel.isMovableByWindowBackground = false
            panel.minSize = panelSize
            panel.maxSize = panelSize
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            self.panel = panel
        }

        update(language: language)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(language: AppLanguage) {
        guard let panel else { return }
        panel.title = language.text("关于 任务管理器", "About Task Manager")
        panel.contentView = NSHostingView(
            rootView: AboutPanelView(language: language)
        )
    }
}

struct AboutPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                TaskManagerGlyph()
                    .frame(width: 40, height: 40)
                    .scaleEffect(2.0)
                    .padding(.top, 8)

                Text("MacOSTSKMGR")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))

                Text(versionLine)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryText(colorScheme))
            }

            Text(language.text(
                "一个模仿 Windows 任务管理器交互与布局风格的 macOS 任务管理器实验项目。",
                "An experimental macOS task manager inspired by the layout and interactions of Windows Task Manager."
            ))
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

            VStack(spacing: 6) {
                Text(language.text("版权所有 © 2026 Linqin。保留所有权利。", "Copyright © 2026 Linqin. All rights reserved."))
                Text(language.text("部分代码由 AI 协助生成。", "Some portions of the code were created with AI assistance."))
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.secondaryText(colorScheme))
            .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowSurfaceBackground())
    }

    private var versionLine: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "1"
        return language.text("版本 \(shortVersion) (构建 \(buildVersion))", "Version \(shortVersion) (Build \(buildVersion))")
    }
}

struct NetworkDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let network: NetworkState
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                detailsHeaderCell(language.text("属性", "Property"), width: 240)
                detailsHeaderCell(network.displayName, width: 280)
            }
            .frame(height: 40)
            .background(AppTheme.tableHeader(colorScheme))
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.strongSeparator(colorScheme)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            detailCell(row.0, width: 240)
                            detailCell(row.1, width: 280)
                        }
                        .frame(height: 30)
                        .background(index.isMultiple(of: 2) ? AppTheme.rowEven(colorScheme) : AppTheme.rowOdd(colorScheme))
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 18)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .background(WindowSurfaceBackground())
    }

    private var detailRows: [(String, String)] {
        let totalBytes = network.totalSendBytes + network.totalReceiveBytes
        let totalPackets = network.packetsSent + network.packetsReceived
        let totalMulticast = network.multicastSent + network.multicastReceived
        let bytesPerInterval = network.sendBytesPerSecond + network.receiveBytesPerSecond

        return [
            (language.text("网络使用率", "Network utilization"), "0%"),
            (language.text("链接速度", "Link speed"), network.linkSpeedText),
            (language.text("状态", "Status"), network.statusText),
            (language.text("发送字节百分比", "Send byte rate"), "0%"),
            (language.text("接收字节百分比", "Recv byte rate"), "0%"),
            (language.text("字节百分比", "Byte rate"), "0%"),
            (language.text("已发送的字节", "Bytes sent"), formattedInteger(network.totalSendBytes)),
            (language.text("已接收的字节", "Bytes received"), formattedInteger(network.totalReceiveBytes)),
            (language.text("字节", "Bytes"), formattedInteger(totalBytes)),
            (language.text("每个间隔发送的字节", "Bytes sent / interval"), formattedInteger(network.sendBytesPerSecond)),
            (language.text("每个间隔接收的字节", "Bytes recv / interval"), formattedInteger(network.receiveBytesPerSecond)),
            (language.text("每个间隔的字节", "Bytes / interval"), formattedInteger(bytesPerInterval)),
            (language.text("已发送的单播", "Unicast sent"), formattedInteger(network.packetsSent - network.multicastSent)),
            (language.text("已接收的单播", "Unicast received"), formattedInteger(network.packetsReceived - network.multicastReceived)),
            (language.text("单播", "Unicast"), formattedInteger(totalPackets - totalMulticast)),
            (language.text("已发送的非单播", "Non-unicast sent"), formattedInteger(network.multicastSent)),
            (language.text("已接收的非单播", "Non-unicast received"), formattedInteger(network.multicastReceived)),
            (language.text("非单播", "Non-unicast"), formattedInteger(totalMulticast)),
            (language.text("IPv4 地址", "IPv4 address"), network.ipv4.isEmpty ? "--" : network.ipv4),
            (language.text("IPv6 地址", "IPv6 address"), network.ipv6.isEmpty ? "--" : network.ipv6),
            (language.text("MTU", "MTU"), "\(network.mtu)"),
            (language.text("输入错误", "Input errors"), formattedInteger(network.errorsIn)),
            (language.text("输出错误", "Output errors"), formattedInteger(network.errorsOut)),
            (language.text("输入丢弃", "Input drops"), formattedInteger(network.dropsIn)),
            (language.text("输出丢弃", "Output drops"), formattedInteger(network.dropsOut))
        ]
    }

    private func detailsHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: 40, alignment: .leading)
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
            }
    }

    private func detailCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: 30, alignment: .leading)
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppTheme.separator(colorScheme)).frame(width: 1)
            }
    }

    private func formattedInteger(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

enum TaskRunResult {
    case success
    case failure(String)
}

enum TaskTerminateResult {
    case success
    case failure(String)
}

enum TaskTerminator {
    static func terminate(pid: Int32) -> TaskTerminateResult {
        guard pid > 1 else {
            return .failure("不能结束该任务。")
        }

        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        guard pid != ownPID else {
            return .failure("不能结束当前任务管理器自身。")
        }

        if kill(pid, SIGTERM) == 0 {
            return .success
        }

        let termError = errno
        if termError == ESRCH {
            return .success
        }

        if kill(pid, SIGKILL) == 0 {
            return .success
        }

        let finalError = errno
        if finalError == ESRCH {
            return .success
        }

        return .failure(terminationErrorMessage(errnoValue: finalError))
    }

    private static func terminationErrorMessage(errnoValue: Int32) -> String {
        switch errnoValue {
        case EPERM:
            return "权限不足，无法结束该任务。"
        case EINVAL:
            return "结束任务请求无效。"
        case ESRCH:
            return "该任务已不存在。"
        default:
            return String(cString: strerror(errnoValue))
        }
    }
}

enum TaskRunner {
    static func executeCommand(_ input: String, asAdmin: Bool, password: String) -> TaskRunResult {
        if let appURL = appBundleURL(from: input) {
            return openApplication(at: appURL)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        if asAdmin {
            process.arguments = ["-lc", "sudo -S -- \(input)"]
            process.standardInput = inputPipe
        } else {
            process.arguments = ["-lc", input]
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .failure("无法启动任务：\(error.localizedDescription)")
        }

        if asAdmin {
            if let data = "\(password)\n".data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return .success
        }

        if asAdmin && errorText.localizedCaseInsensitiveContains("incorrect password") {
            return .failure("密码不正确。")
        }

        if errorText.isEmpty {
            return .failure("任务执行失败。")
        }

        return .failure(errorText)
    }

    private static func appBundleURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if candidate.hasPrefix("\""), candidate.hasSuffix("\""), candidate.count >= 2 {
            candidate.removeFirst()
            candidate.removeLast()
        }

        guard candidate.hasSuffix(".app") else { return nil }

        let url = URL(fileURLWithPath: candidate)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        return url
    }

    private static func openApplication(at url: URL) -> TaskRunResult {
        let openResult: Bool
        if Thread.isMainThread {
            openResult = NSWorkspace.shared.open(url)
        } else {
            openResult = DispatchQueue.main.sync {
                NSWorkspace.shared.open(url)
            }
        }

        return openResult ? .success : .failure("无法打开应用程序。")
    }
}

struct MenuKeyHandlingView: NSViewRepresentable {
    let onAltF: () -> Void
    let onAltO: () -> Void
    let onAltV: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyHandlingNSView {
        let view = KeyHandlingNSView()
        view.onAltF = onAltF
        view.onAltO = onAltO
        view.onAltV = onAltV
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyHandlingNSView, context: Context) {
        nsView.onAltF = onAltF
        nsView.onAltO = onAltO
        nsView.onAltV = onAltV
        nsView.onEscape = onEscape
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyHandlingNSView: NSView {
    var onAltF: (() -> Void)?
    var onAltO: (() -> Void)?
    var onAltV: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        let optionPressed = event.modifierFlags.contains(.option)
        guard optionPressed, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        switch chars {
        case "f": onAltF?()
        case "o": onAltO?()
        case "v": onAltV?()
        default: super.keyDown(with: event)
        }
    }
}
