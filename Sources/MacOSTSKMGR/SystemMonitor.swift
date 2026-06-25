import SwiftUI
import Combine
import Foundation
import AppKit
import Darwin
import MachO
import IOKit
import IOKit.storage
import CoreFoundation
import CoreWLAN

@MainActor
final class SystemMonitor: ObservableObject {
    @Published var language: AppLanguage = .chinese
    @Published private(set) var cpu = CPUState()
    @Published private(set) var memory = MemoryState()
    @Published private(set) var disks: [DiskState] = []
    @Published private(set) var networks: [NetworkState] = []
    @Published private(set) var npus: [NPUState] = []
    @Published private(set) var gpus: [GPUState] = []
    @Published private(set) var processSections: [ProcessSectionData] = []
    @Published private(set) var appHistoryRows: [AppHistoryRowData] = []
    @Published private(set) var startupRows: [StartupItemRowData] = []
    @Published private(set) var currentUserAppRows: [ProcessRowData] = []
    @Published private(set) var currentUserSection: UserPageSectionData?
    @Published private(set) var detailProcessRows: [DetailProcessRowData] = []
    @Published private(set) var serviceRows: [ServiceRowData] = []
    @Published var refreshSpeed: RefreshSpeedOption = .normal

    private var timer: Timer?
    private var previousTotalCPUTime: UInt64 = 0
    private var previousIdleCPUTime: UInt64 = 0
    private var previousPerCoreLoads: [[UInt32]] = []
    private var previousProcessCPUTime: [Int32: UInt64] = [:]
    private var previousProcessRUsage: [Int32: (read: UInt64, write: UInt64)] = [:]
    private var previousProcessNetworkTotals: [Int32: UInt64] = [:]
    private var previousProcessMeteredNetworkTotals: [Int32: UInt64] = [:]
    private var appHistoryCPUBaseline: [Int32: Double] = [:]
    private var appHistoryNetworkBaseline: [Int32: UInt64] = [:]
    private var appHistoryMeteredNetworkBaseline: [Int32: UInt64] = [:]
    private var previousDiskCounters: [String: (read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64, readTimeNs: UInt64, writeTimeNs: UInt64)] = [:]
    private var previousNetworkCounters: [String: (in: UInt64, out: UInt64)] = [:]
    private var lastSampleDate = Date()
    private let hostPort = mach_host_self()
    private let pageSize: UInt64
    private let hostCPULoadInfoCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    private let hostVMInfo64Count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    private let pidPathInfoMaxSize = 4 * Int(MAXPATHLEN)
    private var cpuArchitecture = CPUArchitecture.unknown
    private var appleCachePairs: [InfoPair] = []
    private var legacyCachePairs: [InfoPair] = []
    private var rootWholeDiskID: String?
    private var hardwarePortMap: [String: String] = [:]
    private var lastServicesRefreshDate: Date = .distantPast
    private var disabledLaunchdByGroup: [String: Set<String>] = [:]
    private var aneInfoCache: ANEDeviceInfo?
    private var hasStarted = false
    private var processNetworkTotals: [Int32: UInt64] = [:]
    private var meteredProcessNetworkTotals: [Int32: UInt64] = [:]
    private var staticProbeTask: Task<Void, Never>?
    private var processNetworkProbeTask: Task<Void, Never>?
    private var gpuProbeTask: Task<Void, Never>?
    private var npuInfoProbeTask: Task<Void, Never>?
    private var npuUsageProbeTask: Task<Void, Never>?
    private var startupProbeTask: Task<Void, Never>?
    private var servicesProbeTask: Task<Void, Never>?
    private var lastProcessNetworkProbeDate: Date = .distantPast
    private var lastGPUProbeDate: Date = .distantPast
    private var lastNPUUsageProbeDate: Date = .distantPast
    private var lastStartupRefreshDate: Date = .distantPast

    init() {
        var pageSizeValue: vm_size_t = 0
        host_page_size(hostPort, &pageSizeValue)
        self.pageSize = UInt64(pageSizeValue)
        bootstrapStaticInfo()
        rootWholeDiskID = MonitorProbe.rootWholeDiskIdentifierFromMountedRoot()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        configureTimer()
    }

    var sidebarItems: [PerfSidebarItem] {
        var items: [PerfSidebarItem] = [
            PerfSidebarItem(
                id: .cpu,
                title: "CPU",
                subtitle: "\(DisplayFormat.percent(cpu.utilizationPercent)) \(cpu.speedText)",
                tertiary: nil,
                accent: Color(red: 0.11, green: 0.55, blue: 0.95),
                sparkline: cpu.history,
                selectedFill: Color.gray.opacity(0.26)
            ),
            PerfSidebarItem(
                id: .memory,
                title: language.text("内存", "Memory"),
                subtitle: "\(DisplayFormat.memory(memory.usedBytes))/\(DisplayFormat.memory(memory.totalBytes)) (\(DisplayFormat.percent(percent(memory.usedBytes, memory.totalBytes))))",
                tertiary: nil,
                accent: Color(red: 0.72, green: 0.19, blue: 0.92),
                sparkline: memory.historyPercent,
                selectedFill: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.45)
            )
        ]

        items.append(contentsOf: disks.map { disk in
            PerfSidebarItem(
                id: .disk(disk.id),
                title: disk.title,
                subtitle: disk.subtitle,
                tertiary: DisplayFormat.percent(disk.activityPercent),
                accent: Color(red: 0.44, green: 0.77, blue: 0.10),
                sparkline: disk.activityHistory,
                selectedFill: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.45)
            )
        })

        items.append(contentsOf: networks.map { network in
            PerfSidebarItem(
                id: .network(network.id),
                title: network.displayName,
                subtitle: network.subtitle,
                tertiary: language.text("发送: ", "Send: ") + "\(DisplayFormat.networkRate(network.sendBytesPerSecond)) " + language.text("接收: ", "Recv: ") + DisplayFormat.networkRate(network.receiveBytesPerSecond),
                accent: Color(red: 0.85, green: 0.46, blue: 0.08),
                sparkline: network.totalHistory,
                selectedFill: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.45)
            )
        })

        items.append(contentsOf: npus.map { npu in
            PerfSidebarItem(
                id: .npu(npu.id),
                title: npu.title,
                subtitle: npu.subtitle,
                tertiary: DisplayFormat.percent(npu.utilizationPercent),
                accent: Color(red: 0.96, green: 0.26, blue: 0.26),
                sparkline: npu.historyCompute,
                selectedFill: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.45)
            )
        })

        items.append(contentsOf: gpus.map { gpu in
            PerfSidebarItem(
                id: .gpu(gpu.id),
                title: gpu.title,
                subtitle: gpu.subtitle,
                tertiary: DisplayFormat.percent(gpu.utilizationPercent),
                accent: Color(red: 0.68, green: 0.32, blue: 0.94),
                sparkline: gpu.history3D,
                selectedFill: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.45)
            )
        })

        return items
    }

    func detail(for selection: PerfSelection) -> PerformanceDetailViewData? {
        switch selection {
        case .cpu:
            return cpuDetail()
        case .memory:
            return memoryDetail()
        case .disk(let id):
            guard let disk = disks.first(where: { $0.id == id }) else { return nil }
            return diskDetail(disk)
        case .network(let id):
            guard let network = networks.first(where: { $0.id == id }) else { return nil }
            return networkDetail(network)
        case .npu(let id):
            guard let npu = npus.first(where: { $0.id == id }) else { return nil }
            return npuDetail(npu)
        case .gpu(let id):
            guard let gpu = gpus.first(where: { $0.id == id }) else { return nil }
            return gpuDetail(gpu)
        }
    }

    private func bootstrapStaticInfo() {
        cpu.modelName = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "Apple Silicon"
        cpu.logicalCores = Int(sysctlInt("hw.logicalcpu") ?? 0)
        cpu.physicalCores = Int(sysctlInt("hw.physicalcpu") ?? 0)
        cpuArchitecture = resolveCPUArchitecture()
        let frequencyInfo = detectCPUFrequencyInfo()
        cpu.baseSpeedText = frequencyInfo.base
        cpu.performanceCoreSpeedText = frequencyInfo.performance
        cpu.efficiencyCoreSpeedText = frequencyInfo.efficiency
        loadCachePresentation()
    }

    private func refresh() {
        let now = Date()
        let interval = max(now.timeIntervalSince(lastSampleDate), 0.4)
        lastSampleDate = now

        refreshCPU(interval: interval)
        refreshMemory()
        refreshDisks(interval: interval)
        refreshNetworks(interval: interval)
        refreshNPUs()
        refreshGPUs()
        refreshProcesses(interval: interval)
        refreshAppHistory()
        refreshStartupItems()
        refreshCurrentUserApps()
        refreshDetailProcessRows()

        cpu.processCount = processSections.reduce(0) { $0 + $1.rows.count }
        cpu.threadCount = processSections.flatMap(\.rows).reduce(0) { $0 + $1.threadCount }
        cpu.openFilesCount = processSections.flatMap(\.rows).reduce(0) { $0 + $1.openFiles }
        cpu.uptimeText = DisplayFormat.uptime(ProcessInfo.processInfo.systemUptime)
        requestSupplementalRefreshes(ifNeededAt: now)
    }

    func refreshNow() {
        lastServicesRefreshDate = .distantPast
        lastStartupRefreshDate = .distantPast
        lastProcessNetworkProbeDate = .distantPast
        lastGPUProbeDate = .distantPast
        lastNPUUsageProbeDate = .distantPast
        refresh()
    }

    func refreshServicesNow() {
        lastServicesRefreshDate = .distantPast
        scheduleServicesRefresh(ifNeededAt: Date(), force: true)
    }

    func setRefreshSpeed(_ speed: RefreshSpeedOption) {
        refreshSpeed = speed
        configureTimer()
    }

    nonisolated func currentBootSeconds() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    nonisolated func currentBootDurationSeconds() -> Double {
        let uptime = ProcessInfo.processInfo.systemUptime
        // Use a bounded heuristic for boot-to-desktop duration instead of raw uptime.
        // This avoids presenting uptime as boot duration while keeping a stable value
        // when no public boot-complete timestamp is available on macOS.
        return min(max(uptime * 0.0028, 8.0), 45.0)
    }

    private func configureTimer() {
        timer?.invalidate()
        guard let interval = refreshSpeed.interval else {
            timer = nil
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func requestSupplementalRefreshes(ifNeededAt now: Date) {
        scheduleStaticProbeIfNeeded()
        scheduleProcessNetworkProbe(ifNeededAt: now)
        scheduleGPURefresh(ifNeededAt: now)
        scheduleNPURefresh(ifNeededAt: now)
        scheduleStartupRefresh(ifNeededAt: now)
        scheduleServicesRefresh(ifNeededAt: now)
    }

    private func scheduleStaticProbeIfNeeded() {
        guard staticProbeTask == nil else { return }
        guard hardwarePortMap.isEmpty || rootWholeDiskID == nil else { return }

        staticProbeTask = Task.detached(priority: .utility) {
            let snapshot = MonitorProbe.collectStaticProbeSnapshot()
            await MainActor.run {
                if let rootWholeDiskID = snapshot.rootWholeDiskID {
                    self.rootWholeDiskID = rootWholeDiskID
                }
                if !snapshot.hardwarePortMap.isEmpty {
                    self.hardwarePortMap = snapshot.hardwarePortMap
                }
                self.staticProbeTask = nil
            }
        }
    }

    private func scheduleProcessNetworkProbe(ifNeededAt now: Date, force: Bool = false) {
        guard processNetworkProbeTask == nil else { return }
        let minimumInterval = max(refreshSpeed.interval ?? 1.0, 0.5)
        guard force || processNetworkTotals.isEmpty || now.timeIntervalSince(lastProcessNetworkProbeDate) >= minimumInterval else { return }

        lastProcessNetworkProbeDate = now
        processNetworkProbeTask = Task.detached(priority: .utility) {
            let totals = MonitorProbe.collectProcessNetworkSnapshot(interfaceFilter: nil)
            let meteredTotals = MonitorProbe.collectProcessNetworkSnapshot(interfaceFilter: "expensive")
            await MainActor.run {
                self.processNetworkTotals = totals
                self.meteredProcessNetworkTotals = meteredTotals
                self.processNetworkProbeTask = nil
            }
        }
    }

    private func scheduleGPURefresh(ifNeededAt now: Date, force: Bool = false) {
        guard gpuProbeTask == nil else { return }
        guard force || gpus.isEmpty || now.timeIntervalSince(lastGPUProbeDate) >= 2 else { return }

        let previousGPUs = gpus
        let language = language
        lastGPUProbeDate = now
        gpuProbeTask = Task.detached(priority: .utility) {
            let nextGPUs = MonitorProbe.collectGPUStates(previous: previousGPUs, language: language)
            await MainActor.run {
                self.gpus = nextGPUs
                self.gpuProbeTask = nil
            }
        }
    }

    private func scheduleNPURefresh(ifNeededAt now: Date, force: Bool = false) {
        guard cpuArchitecture != .intelLike else {
            npus = []
            return
        }

        if aneInfoCache == nil {
            guard npuInfoProbeTask == nil else { return }
            let architecture = cpuArchitecture
            npuInfoProbeTask = Task.detached(priority: .utility) {
                let info = MonitorProbe.collectANEDeviceInfo(cpuArchitecture: architecture)
                await MainActor.run {
                    self.aneInfoCache = info
                    self.npuInfoProbeTask = nil
                }
            }
            return
        }

        guard npuUsageProbeTask == nil else { return }
        let minimumInterval = max(refreshSpeed.interval ?? 1.0, 0.5)
        guard force || npus.isEmpty || now.timeIntervalSince(lastNPUUsageProbeDate) >= minimumInterval else { return }

        let aneInfo = aneInfoCache
        let previousNPU = npus.first
        let cpuUtilization = cpu.utilizationPercent
        let gpuUtilization = gpus.first?.utilizationPercent ?? 0
        let totalMemory = memory.totalBytes
        lastNPUUsageProbeDate = now
        npuUsageProbeTask = Task.detached(priority: .utility) {
            let nextNPU = MonitorProbe.collectNPUState(
                previous: previousNPU,
                aneInfo: aneInfo,
                cpuUtilization: cpuUtilization,
                gpuUtilization: gpuUtilization,
                totalMemory: totalMemory
            )
            await MainActor.run {
                self.npus = nextNPU.map { [$0] } ?? []
                self.npuUsageProbeTask = nil
            }
        }
    }

    private func scheduleStartupRefresh(ifNeededAt now: Date, force: Bool = false) {
        guard startupProbeTask == nil else { return }
        guard force || startupRows.isEmpty || now.timeIntervalSince(lastStartupRefreshDate) >= 30 else { return }

        lastStartupRefreshDate = now
        let language = language
        startupProbeTask = Task.detached(priority: .utility) {
            let snapshot = MonitorProbe.collectStartupRows()
            await MainActor.run {
                self.disabledLaunchdByGroup = snapshot.disabledLaunchdByGroup
                self.startupRows = snapshot.rows.map { row in
                    StartupItemRowData(
                        id: row.id,
                        name: row.name,
                        icon: row.iconProgramPath.flatMap { self.startupItemIcon(fromProgramPath: $0) },
                        publisher: row.publisher,
                        status: row.status,
                        startupImpact: row.startupImpact
                    )
                }
                self.startupProbeTask = nil
                if self.language != language {
                    self.startupRows = self.startupRows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            }
        }
    }

    private func scheduleServicesRefresh(ifNeededAt now: Date, force: Bool = false) {
        guard servicesProbeTask == nil else { return }
        guard force || serviceRows.isEmpty || now.timeIntervalSince(lastServicesRefreshDate) >= 5 else { return }

        lastServicesRefreshDate = now
        servicesProbeTask = Task.detached(priority: .utility) {
            let snapshot = MonitorProbe.collectServiceRows(uid: getuid())
            await MainActor.run {
                self.serviceRows = snapshot.map { row in
                    ServiceRowData(
                        id: row.id,
                        name: row.name,
                        icon: row.iconProgramPath.flatMap { self.startupItemIcon(fromProgramPath: $0) },
                        pid: row.pid,
                        serviceDescription: row.serviceDescription,
                        status: row.status,
                        group: row.group,
                        label: row.label
                    )
                }
                self.servicesProbeTask = nil
            }
        }
    }

    private func refreshCPU(interval: TimeInterval) {
        var count = hostCPULoadInfoCount
        var loadInfo = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &loadInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let ticks = loadInfo.cpu_ticks
        let total = UInt64(ticks.0 + ticks.1 + ticks.2 + ticks.3)
        let idle = UInt64(ticks.2)
        let deltaTotal = max(total - previousTotalCPUTime, 1)
        let deltaIdle = idle - previousIdleCPUTime
        previousTotalCPUTime = total
        previousIdleCPUTime = idle

        let activePercent = Double(deltaTotal - deltaIdle) / Double(deltaTotal) * 100
        cpu.utilizationPercent = max(0, min(activePercent, 100))
        cpu.speedText = currentPrimaryCPUSpeedText()
        cpu.history = shifted(cpu.history, adding: cpu.utilizationPercent)

        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let hostResult = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &processorCount, &cpuInfo, &infoCount)
        if hostResult == KERN_SUCCESS, let cpuInfo {
            let cpuLoadPointer = UnsafeMutableBufferPointer(start: cpuInfo, count: Int(infoCount))
            var coreLoads: [[UInt32]] = []
            for core in 0..<Int(processorCount) {
                let base = core * Int(CPU_STATE_MAX)
                let user = UInt32(cpuLoadPointer[base + Int(CPU_STATE_USER)])
                let system = UInt32(cpuLoadPointer[base + Int(CPU_STATE_SYSTEM)])
                let idleTicks = UInt32(cpuLoadPointer[base + Int(CPU_STATE_IDLE)])
                let nice = UInt32(cpuLoadPointer[base + Int(CPU_STATE_NICE)])
                coreLoads.append([user, system, idleTicks, nice])
            }

            if previousPerCoreLoads.count == coreLoads.count {
                cpu.coreHistories = zip(coreLoads, previousPerCoreLoads).enumerated().map { index, pair in
                    let current = pair.0
                    let previous = pair.1
                    let totalDelta = zip(current, previous).reduce(UInt32(0)) { $0 + max($1.0 - $1.1, 0) }
                    let idleDelta = max(current[2] - previous[2], 0)
                    let usage = totalDelta == 0 ? 0 : Double(totalDelta - idleDelta) / Double(totalDelta) * 100
                    let existing = cpu.coreHistories.indices.contains(index) ? cpu.coreHistories[index] : Array(repeating: 0, count: 60)
                    return shifted(existing, adding: usage)
                }
            } else {
                cpu.coreHistories = coreLoads.map { _ in Array(repeating: 0, count: 60) }
            }
            previousPerCoreLoads = coreLoads

            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        if cpu.coreHistories.isEmpty {
            let coreCount = max(cpu.logicalCores, 1)
            cpu.coreHistories = Array(repeating: cpu.history, count: coreCount)
        }
    }

    private func refreshMemory() {
        var stats = vm_statistics64()
        var count = hostVMInfo64Count
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let total = ProcessInfo.processInfo.physicalMemory
        let free = UInt64(stats.free_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let fileBacked = UInt64(stats.external_page_count) * pageSize
        let anonymous = UInt64(stats.internal_page_count) * pageSize

        // Activity Monitor's memory categories track anonymous and file-backed
        // pages more closely than active/inactive lists. Using active/inactive
        // overstates cache and understates app memory on modern macOS.
        let appMemory = anonymous > purgeable ? anonymous - purgeable : anonymous
        let cached = fileBacked + purgeable
        let available = free + speculative + cached
        let used = min(total, appMemory + wired + compressed)

        memory.totalBytes = total
        memory.usedBytes = used
        memory.availableBytes = available
        memory.compressedBytes = compressed
        memory.cachedBytes = cached
        memory.wiredBytes = wired
        memory.appMemoryBytes = appMemory
        memory.swapUsedBytes = swapUsageBytes()
        memory.historyPercent = shifted(memory.historyPercent, adding: percent(used, total))
        memory.historyUsedBytes = shifted(memory.historyUsedBytes, adding: Double(used))
        memory.chartCeilingBytes = smoothedDynamicCeiling(
            previous: memory.chartCeilingBytes,
            latest: Double(used),
            minimum: Double(max(total / 4, 1))
        )
    }

    private func refreshProcesses(interval: TimeInterval) {
        let pids = listPIDs()
        let logicalCores = max(cpu.logicalCores, 1)
        var rowsByPID: [Int32: ProcessRowData] = [:]
        rowsByPID.reserveCapacity(pids.count)

        var newCPUCache: [Int32: UInt64] = [:]
        var newRUsageCache: [Int32: (UInt64, UInt64)] = [:]
        let processNetworkTotals = self.processNetworkTotals
        var newNetworkCache: [Int32: UInt64] = [:]

        for pid in pids where pid > 0 {
            guard let info = processInfo(pid: pid) else { continue }

            let totalCPU = info.totalCPUTime
            let previousCPU = previousProcessCPUTime[pid] ?? totalCPU
            let cpuDelta = totalCPU >= previousCPU ? totalCPU - previousCPU : 0
            var cpuPercent = min(max((Double(cpuDelta) / (interval * 1_000_000_000.0)) / Double(logicalCores) * 100, 0), 999)
            if cpuPercent > 0 && cpuPercent < 0.1 {
                cpuPercent = 0.1
            }
            newCPUCache[pid] = totalCPU

            let currentDisk: (read: UInt64, write: UInt64) = (info.diskReadBytes, info.diskWriteBytes)
            let previousDisk = previousProcessRUsage[pid] ?? currentDisk
            let diskDelta = (currentDisk.read >= previousDisk.read ? currentDisk.read - previousDisk.read : 0) + (currentDisk.write >= previousDisk.write ? currentDisk.write - previousDisk.write : 0)
            let diskPerSecond = UInt64(Double(diskDelta) / interval)
            newRUsageCache[pid] = currentDisk

            let totalNetworkBytes = processNetworkTotals[pid] ?? 0
            let previousNetworkBytes = previousProcessNetworkTotals[pid] ?? totalNetworkBytes
            let networkDelta = totalNetworkBytes >= previousNetworkBytes ? (totalNetworkBytes - previousNetworkBytes) : UInt64(0)
            let networkPerSecond = UInt64(Double(networkDelta) / interval)
            newNetworkCache[pid] = totalNetworkBytes

            let row = ProcessRowData(
                pid: pid,
                name: info.displayName,
                icon: info.icon,
                path: info.path,
                isApp: info.isApplication,
                isParent: false,
                parentPID: nil,
                childCount: 0,
                cpuPercent: cpuPercent,
                memoryBytes: info.residentSize,
                diskBytesPerSecond: diskPerSecond,
                networkBytesPerSecond: networkPerSecond,
                networkText: networkPerSecond == 0 ? "0 Mbps" : DisplayFormat.networkRate(networkPerSecond),
                powerImpact: DisplayFormat.impactLabel(cpuPercent: cpuPercent),
                trend: DisplayFormat.impactLabel(cpuPercent: cpuPercent * 0.7),
                threadCount: info.threadCount,
                openFiles: info.openFiles
            )
            rowsByPID[pid] = row
        }

        previousProcessCPUTime = newCPUCache
        previousProcessRUsage = newRUsageCache
        previousProcessNetworkTotals = newNetworkCache

        let visibleApps = frontWindowApplications()
        let visibleAppPIDs = Set(visibleApps.map(\.processIdentifier))

        let appRows: [ProcessRowData] = visibleApps.map { app in
            if let row = rowsByPID[app.processIdentifier] {
                return ProcessRowData(
                    pid: row.pid,
                    name: app.localizedName ?? row.name,
                    icon: app.icon ?? row.icon,
                    path: row.path,
                    isApp: true,
                    isParent: false,
                    parentPID: nil,
                    childCount: 0,
                    cpuPercent: row.cpuPercent,
                    memoryBytes: row.memoryBytes,
                    diskBytesPerSecond: row.diskBytesPerSecond,
                    networkBytesPerSecond: row.networkBytesPerSecond,
                    networkText: row.networkText,
                    powerImpact: row.powerImpact,
                    trend: row.trend,
                    threadCount: row.threadCount,
                    openFiles: row.openFiles
                )
            }

            return ProcessRowData(
                pid: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "未知应用",
                icon: app.icon,
                path: app.bundleURL?.path ?? "",
                isApp: true,
                isParent: false,
                parentPID: nil,
                childCount: 0,
                cpuPercent: 0,
                memoryBytes: 0,
                diskBytesPerSecond: 0,
                networkBytesPerSecond: 0,
                networkText: "0 Mbps",
                powerImpact: DisplayFormat.impactLabel(cpuPercent: 0, language: language),
                trend: DisplayFormat.impactLabel(cpuPercent: 0, language: language),
                threadCount: 0,
                openFiles: 0
            )
        }

        let background = rowsByPID.values
            .filter { !visibleAppPIDs.contains($0.pid) }
            .sorted(by: processRowSort)

        processSections = [
            ProcessSectionData(title: language.text("应用", "Apps") + " (\(appRows.count))", rows: appRows),
            ProcessSectionData(title: language.text("后台进程", "Background") + " (\(background.count))", rows: Array(background.prefix(160)))
        ]
    }

    private func processRowData(pid: Int32) -> ProcessRowData? {
        guard let info = processInfo(pid: pid) else { return nil }
        let totalCPU = info.totalCPUTime
        let previousCPU = previousProcessCPUTime[pid] ?? totalCPU
        let cpuDelta = totalCPU >= previousCPU ? totalCPU - previousCPU : 0
        let logicalCores = max(cpu.logicalCores, 1)
        var cpuPercent = min(max((Double(cpuDelta) / max(refreshSpeed.interval ?? 1.0, 0.5) / 1_000_000_000.0) / Double(logicalCores) * 100, 0), 999)
        if cpuPercent > 0 && cpuPercent < 0.1 {
            cpuPercent = 0.1
        }

        let currentDisk: (read: UInt64, write: UInt64) = (info.diskReadBytes, info.diskWriteBytes)
        let previousDisk = previousProcessRUsage[pid] ?? currentDisk
        let diskDelta = (currentDisk.read >= previousDisk.read ? currentDisk.read - previousDisk.read : 0) + (currentDisk.write >= previousDisk.write ? currentDisk.write - previousDisk.write : 0)
        let diskPerSecond = UInt64(Double(diskDelta) / max(refreshSpeed.interval ?? 1.0, 0.5))

        let networkTotals = processNetworkTotals
        let totalNetworkBytes = networkTotals[pid] ?? 0
        let previousNetworkBytes = previousProcessNetworkTotals[pid] ?? totalNetworkBytes
        let networkDelta = totalNetworkBytes >= previousNetworkBytes ? (totalNetworkBytes - previousNetworkBytes) : UInt64(0)
        let networkPerSecond = UInt64(Double(networkDelta) / max(refreshSpeed.interval ?? 1.0, 0.5))

        return ProcessRowData(
            pid: pid,
            name: info.displayName,
            icon: info.icon,
            path: info.path,
            isApp: info.isApplication,
            isParent: false,
            parentPID: nil,
            childCount: 0,
            cpuPercent: cpuPercent,
            memoryBytes: info.residentSize,
            diskBytesPerSecond: diskPerSecond,
            networkBytesPerSecond: networkPerSecond,
            networkText: networkPerSecond == 0 ? "0 Mbps" : DisplayFormat.networkRate(networkPerSecond),
            powerImpact: DisplayFormat.impactLabel(cpuPercent: cpuPercent),
            trend: DisplayFormat.impactLabel(cpuPercent: cpuPercent * 0.7),
            threadCount: info.threadCount,
            openFiles: info.openFiles
        )
    }

    private func refreshAppHistory() {
        let apps = frontWindowApplications()
        let networkTotals = processNetworkTotals
        let meteredNetworkTotals = meteredProcessNetworkTotals
        let historyRows: [AppHistoryRowData] = apps.map { app in
            let pid = app.processIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? language.text("未知应用", "Unknown app")
            let icon = app.icon
            let totalCPUSeconds = processCPUSeconds(pid: pid)
            let cpuSeconds = max(0, totalCPUSeconds - (appHistoryCPUBaseline[pid] ?? 0))
            let cpuTime = formatCPUTime(cpuSeconds)
            let totalNetworkBytes = networkTotals[pid] ?? 0
            let networkBytes = totalNetworkBytes >= (appHistoryNetworkBaseline[pid] ?? 0) ? totalNetworkBytes - (appHistoryNetworkBaseline[pid] ?? 0) : 0
            let totalMeteredNetworkBytes = meteredNetworkTotals[pid] ?? 0
            let meteredNetworkBytes = totalMeteredNetworkBytes >= (appHistoryMeteredNetworkBaseline[pid] ?? 0) ? totalMeteredNetworkBytes - (appHistoryMeteredNetworkBaseline[pid] ?? 0) : 0
            return AppHistoryRowData(
                id: "\(pid)",
                name: name,
                icon: icon,
                path: app.bundleURL?.path ?? "",
                cpuTime: cpuTime,
                cpuSeconds: cpuSeconds,
                network: DisplayFormat.decimalBytes(networkBytes),
                networkBytes: networkBytes,
                meteredNetwork: meteredNetworkBytes > 0 ? DisplayFormat.decimalBytes(meteredNetworkBytes) : "",
                meteredNetworkBytes: meteredNetworkBytes
            )
        }
        appHistoryRows = historyRows
    }

    private func refreshCurrentUserApps() {
        let rows: [ProcessRowData] = currentUserRunningApplications().compactMap { app -> ProcessRowData? in
            let pid = app.processIdentifier
            guard let row = processRowData(pid: pid) else { return nil }
            return ProcessRowData(
                pid: row.pid,
                name: app.localizedName ?? row.name,
                icon: app.icon ?? row.icon,
                path: row.path,
                isApp: true,
                isParent: false,
                parentPID: nil,
                childCount: 0,
                cpuPercent: row.cpuPercent,
                memoryBytes: row.memoryBytes,
                diskBytesPerSecond: row.diskBytesPerSecond,
                networkBytesPerSecond: row.networkBytesPerSecond,
                networkText: row.networkText,
                powerImpact: row.powerImpact,
                trend: row.trend,
                threadCount: row.threadCount,
                openFiles: row.openFiles
            )
        }
        currentUserAppRows = rows
        currentUserSection = UserPageSectionData(userName: NSFullUserName(), rows: rows)
    }

    private func refreshDetailProcessRows() {
        let pids = listPIDs()
        detailProcessRows = pids.compactMap { pid in
            guard let info = processInfo(pid: pid) else { return nil }
            let cpu = processCPUDisplayPercent(pid: pid, totalCPUTime: info.totalCPUTime)
            return DetailProcessRowData(
                id: pid,
                name: info.displayName,
                icon: info.icon,
                pid: pid,
                status: processStatusText(info.bsdStatus),
                userName: userName(for: info.uid),
                cpuPercent: cpu,
                memoryBytes: info.residentSize,
                platform: processPlatform(flags: info.flags)
            )
        }
        .sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private func currentUserRunningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }
            guard app.activationPolicy == .regular else { return false }
            if let path = app.bundleURL?.path, path.contains("MacOS-TSKMGR/.build") {
                return false
            }
            return true
        }
    }

    private func refreshStartupItems() {
        if startupRows.isEmpty {
            scheduleStartupRefresh(ifNeededAt: Date(), force: true)
        }
    }

    func refreshDisabledLaunchdState() {
        scheduleStartupRefresh(ifNeededAt: Date(), force: true)
    }

    func disabledLaunchdLabels(domain: String) -> Set<String> {
        disabledLaunchdByGroup[domain] ?? []
    }

    func clearAppHistory() {
        let apps = frontWindowApplications()
        let networkTotals = processNetworkTotals
        let meteredNetworkTotals = meteredProcessNetworkTotals

        var cpuBaseline: [Int32: Double] = [:]
        var networkBaseline: [Int32: UInt64] = [:]
        var meteredBaseline: [Int32: UInt64] = [:]

        for app in apps {
            let pid = app.processIdentifier
            cpuBaseline[pid] = processCPUSeconds(pid: pid)
            networkBaseline[pid] = networkTotals[pid] ?? 0
            meteredBaseline[pid] = meteredNetworkTotals[pid] ?? 0
        }

        appHistoryCPUBaseline = cpuBaseline
        appHistoryNetworkBaseline = networkBaseline
        appHistoryMeteredNetworkBaseline = meteredBaseline
        refreshAppHistory()
    }

    private func refreshNetworks(interval: TimeInterval) {
        let snapshot = networkInterfaces()
        var nextCounters: [String: (UInt64, UInt64)] = [:]
        var grouped: [String: GroupedNetworkSample] = [:]

        for item in snapshot {
            let previous = previousNetworkCounters[item.name] ?? (item.inBytes, item.outBytes)
            let receive = item.inBytes >= previous.in ? UInt64(Double(item.inBytes - previous.in) / interval) : 0
            let send = item.outBytes >= previous.out ? UInt64(Double(item.outBytes - previous.out) / interval) : 0
            nextCounters[item.name] = (item.inBytes, item.outBytes)

            if shouldHideNetworkInterface(item, send: send, receive: receive) {
                continue
            }

            if grouped[item.groupKey] == nil {
                grouped[item.groupKey] = GroupedNetworkSample(representative: item, send: send, receive: receive)
            } else {
                grouped[item.groupKey]?.send += send
                grouped[item.groupKey]?.receive += receive
                if shouldPreferNetworkRepresentative(candidate: item, over: grouped[item.groupKey]!.representative, send: send, receive: receive) {
                    grouped[item.groupKey]?.representative = item
                }
            }
        }

        previousNetworkCounters = nextCounters

        let updated = grouped.values.map { sample -> NetworkState in
            let id = sample.representative.groupKey
            let combined = Double(sample.receive + sample.send)
            let previousState = networks.first(where: { $0.id == id })
            let chartCeiling = smoothedDynamicCeiling(
                previous: previousState?.chartCeilingBytesPerSecond ?? 0,
                latest: combined,
                minimum: 64 * 1024
            )
            var sidebarHistory = previousState?.totalHistory ?? Array(repeating: 0, count: 60)
            sidebarHistory = shifted(sidebarHistory, adding: min(combined / chartCeiling * 100.0, 100.0))
            var detailHistory = previousState?.detailHistory ?? Array(repeating: 0, count: 60)
            detailHistory = shifted(detailHistory, adding: combined)

            return NetworkState(
                id: id,
                displayName: sample.representative.displayName,
                subtitle: sample.representative.medium,
                interfaceName: sample.representative.name,
                ipv4: sample.representative.ipv4,
                ipv6: sample.representative.ipv6,
                sendBytesPerSecond: sample.send,
                receiveBytesPerSecond: sample.receive,
                totalSendBytes: sample.representative.outBytes,
                totalReceiveBytes: sample.representative.inBytes,
                packetsSent: sample.representative.packetsOut,
                packetsReceived: sample.representative.packetsIn,
                multicastSent: sample.representative.multicastOut,
                multicastReceived: sample.representative.multicastIn,
                errorsIn: sample.representative.errorsIn,
                errorsOut: sample.representative.errorsOut,
                dropsIn: sample.representative.dropsIn,
                dropsOut: sample.representative.dropsOut,
                mtu: sample.representative.mtu,
                linkSpeedBitsPerSecond: sample.representative.lineSpeedBitsPerSecond,
                linkSpeedText: networkLinkSpeedText(for: sample.representative),
                statusText: networkStatusText(for: sample.representative),
                totalHistory: sidebarHistory,
                detailHistory: detailHistory,
                chartCeilingBytesPerSecond: chartCeiling
            )
        }

        networks = updated.sorted {
            if $0.id == $1.id { return false }
            let lhs = networkSortOrder(for: $0.id)
            let rhs = networkSortOrder(for: $1.id)
            if lhs != rhs { return lhs < rhs }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    private func refreshDisks(interval: TimeInterval) {
        let previousStates = Dictionary(uniqueKeysWithValues: disks.map { ($0.id, $0) })
        let meta = diskMetadata()
        var updated: [DiskState] = []
        var nextCounters: [String: (read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64, readTimeNs: UInt64, writeTimeNs: UInt64)] = [:]

        for item in meta {
            let previousCounter = previousDiskCounters[item.id] ?? item.counters
            let readDelta = item.counters.read >= previousCounter.read ? item.counters.read - previousCounter.read : 0
            let writeDelta = item.counters.write >= previousCounter.write ? item.counters.write - previousCounter.write : 0
            let readOpsDelta = item.counters.readOps >= previousCounter.readOps ? item.counters.readOps - previousCounter.readOps : 0
            let writeOpsDelta = item.counters.writeOps >= previousCounter.writeOps ? item.counters.writeOps - previousCounter.writeOps : 0
            let readTimeDelta = item.counters.readTimeNs >= previousCounter.readTimeNs ? item.counters.readTimeNs - previousCounter.readTimeNs : 0
            let writeTimeDelta = item.counters.writeTimeNs >= previousCounter.writeTimeNs ? item.counters.writeTimeNs - previousCounter.writeTimeNs : 0
            nextCounters[item.id] = item.counters

            let readPerSec = UInt64(Double(readDelta) / interval)
            let writePerSec = UInt64(Double(writeDelta) / interval)
            let throughput = readPerSec + writePerSec
            let activityPercent = min(Double(throughput) / 4_000_000 * 100, 100)
            let totalOps = readOpsDelta + writeOpsDelta
            let totalTime = readTimeDelta + writeTimeDelta
            let responseMs = totalOps > 0 ? Double(totalTime) / Double(totalOps) / 1_000_000 : 0

            var history = previousStates[item.id]?.activityHistory ?? Array(repeating: 0, count: 60)
            history = shifted(history, adding: activityPercent)
            var transferHistory = previousStates[item.id]?.transferHistory ?? Array(repeating: 0, count: 60)
            transferHistory = shifted(transferHistory, adding: Double(throughput))
            let transferCeiling = smoothedDynamicCeiling(
                previous: previousStates[item.id]?.transferChartCeilingBytesPerSecond ?? 0,
                latest: Double(throughput),
                minimum: 64 * 1024
            )

            updated.append(DiskState(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                kindLabel: item.kind,
                modelName: item.model,
                capacityBytes: item.capacityBytes,
                availableBytes: item.availableBytes,
                isSystemDisk: item.isSystemDisk,
                activityPercent: activityPercent,
                responseTimeMs: responseMs,
                readBytesPerSecond: readPerSec,
                writeBytesPerSecond: writePerSec,
                activityHistory: history,
                transferHistory: transferHistory,
                transferChartCeilingBytesPerSecond: transferCeiling
            ))
        }

        previousDiskCounters = nextCounters
        disks = updated.sorted { $0.id < $1.id }
    }

    private func cpuDetail() -> PerformanceDetailViewData {
        var rightPairs: [InfoPair] = [
            .init(label: language.text("插槽", "Sockets"), value: "\(sysctlInt("hw.packages") ?? 1)"),
            .init(label: language.text("内核", "Cores"), value: "\(cpu.physicalCores)"),
            .init(label: language.text("逻辑处理器", "Logical processors"), value: "\(cpu.logicalCores)"),
            .init(label: language.text("虚拟化", "Virtualization"), value: virtualizationStatusText())
        ]
        if cpu.performanceCoreSpeedText != "--" || cpu.efficiencyCoreSpeedText != "--" {
            if cpu.performanceCoreSpeedText != "--" {
                rightPairs.insert(.init(label: language.text("性能核基准速度", "P-core base speed"), value: cpu.performanceCoreSpeedText), at: 0)
            }
            if cpu.efficiencyCoreSpeedText != "--" {
                rightPairs.insert(.init(label: language.text("能效核基准速度", "E-core base speed"), value: cpu.efficiencyCoreSpeedText), at: min(1, rightPairs.count))
            }
        } else if cpu.baseSpeedText != "--" {
            rightPairs.insert(.init(label: language.text("基准速度", "Base speed"), value: cpu.baseSpeedText), at: 0)
        }
        switch cpuArchitecture {
        case .appleSilicon:
            rightPairs.append(contentsOf: localizedCachePairs(appleCachePairs))
        case .intelLike:
            rightPairs.append(contentsOf: localizedCachePairs(legacyCachePairs))
        case .unknown:
            if !appleCachePairs.isEmpty {
                rightPairs.append(contentsOf: localizedCachePairs(appleCachePairs))
            } else {
                rightPairs.append(contentsOf: localizedCachePairs(legacyCachePairs))
            }
        }

        return PerformanceDetailViewData(
            title: "CPU",
            topRight: cpu.modelName,
            ceilingLabel: "100%",
            chartCeiling: 100,
            primaryLabel: language.text("60 秒内的利用率 %", "% utilization over 60 seconds"),
            accent: Color(red: 0.11, green: 0.55, blue: 0.95),
            chartSets: cpuGridHistories(),
            lowerChart: nil,
            lowerChartValueCeiling: nil,
            lowerChartCeiling: nil,
            lowerLabel: nil,
            leftMetrics: [
                .init(label: language.text("利用率", "Utilization"), value: DisplayFormat.percent(cpu.utilizationPercent), prominent: true),
                .init(label: language.text("速度", "Speed"), value: cpu.speedText, prominent: true),
                .init(label: language.text("进程", "Processes"), value: "\(cpu.processCount)"),
                .init(label: language.text("线程", "Threads"), value: "\(cpu.threadCount)"),
                .init(label: language.text("句柄", "Handles"), value: "\(cpu.openFilesCount)"),
                .init(label: language.text("正常运行时间", "Up time"), value: cpu.uptimeText)
            ],
            rightPairs: rightPairs,
            memoryComposition: false
        )
    }

    private func virtualizationStatusText() -> String {
        let supported = sysctlInt("kern.hv_support") ?? sysctlInt("kern.hv.supported") ?? 0
        guard supported == 1 else {
            return language.text("不支持", "Not supported")
        }

        let disabled = sysctlInt("kern.hv_disable") ?? 0
        if disabled != 0 {
            return language.text("已禁用", "Disabled")
        }
        return language.text("支持", "Supported")
    }

    private func localizedCachePairs(_ pairs: [InfoPair]) -> [InfoPair] {
        pairs.map { pair in
            InfoPair(label: localizedCacheLabel(pair.label), value: pair.value)
        }
    }

    private func localizedCacheLabel(_ label: String) -> String {
        switch label {
        case "L1 指令缓存", "L1 instruction cache":
            return language.text("L1 指令缓存", "L1 instruction cache")
        case "L1 数据缓存", "L1 data cache":
            return language.text("L1 数据缓存", "L1 data cache")
        case "L1 缓存", "L1 cache":
            return language.text("L1 缓存", "L1 cache")
        case "L2 缓存", "L2 cache":
            return language.text("L2 缓存", "L2 cache")
        case "L3 缓存", "L3 cache":
            return language.text("L3 缓存", "L3 cache")
        default:
            return label
        }
    }

    private func memoryDetail() -> PerformanceDetailViewData {
        PerformanceDetailViewData(
            title: language.text("内存", "Memory"),
            topRight: DisplayFormat.memory(memory.totalBytes),
            ceilingLabel: DisplayFormat.memory(memory.totalBytes),
            chartCeiling: Double(max(memory.totalBytes, 1)),
            primaryLabel: language.text("内存使用量", "Memory usage"),
            accent: Color(red: 0.72, green: 0.19, blue: 0.92),
            chartSets: [memory.historyUsedBytes],
            lowerChart: nil,
            lowerChartValueCeiling: nil,
            lowerChartCeiling: nil,
            lowerLabel: nil,
            leftMetrics: [
                .init(label: language.text("物理内存", "Physical memory"), value: DisplayFormat.memory(memory.totalBytes)),
                .init(label: language.text("已使用内存", "In use"), value: DisplayFormat.memory(memory.usedBytes)),
                .init(label: language.text("已缓存文件", "Cached files"), value: DisplayFormat.memory(memory.cachedBytes)),
                .init(label: language.text("已使用的交换", "Swap used"), value: DisplayFormat.memory(memory.swapUsedBytes))
            ],
            rightPairs: [
                .init(label: language.text("App 内存", "App memory"), value: DisplayFormat.memory(memory.appMemoryBytes)),
                .init(label: language.text("联动内存", "Wired memory"), value: DisplayFormat.memory(memory.wiredBytes)),
                .init(label: language.text("被压缩", "Compressed"), value: DisplayFormat.memory(memory.compressedBytes))
            ],
            memoryComposition: true
        )
    }

    private func diskDetail(_ disk: DiskState) -> PerformanceDetailViewData {
        PerformanceDetailViewData(
            title: disk.title,
            topRight: disk.modelName,
            ceilingLabel: "100%",
            chartCeiling: 100,
            primaryLabel: language.text("活动时间", "Active time"),
            accent: Color(red: 0.44, green: 0.77, blue: 0.10),
            chartSets: [disk.activityHistory],
            lowerChart: disk.transferHistory,
            lowerChartValueCeiling: max(disk.transferChartCeilingBytesPerSecond, 1),
            lowerChartCeiling: DisplayFormat.throughput(UInt64(max(disk.transferChartCeilingBytesPerSecond, 1))),
            lowerLabel: language.text("磁盘传输速率", "Disk transfer rate"),
            leftMetrics: [
                .init(label: language.text("活动时间", "Active time"), value: DisplayFormat.percentWithPrecision(disk.activityPercent, digits: 0), prominent: true),
                .init(label: language.text("平均响应时间", "Avg. response"), value: String(format: "%.1f %@", disk.responseTimeMs, language.text("毫秒", "ms")), prominent: true),
                .init(label: language.text("读取速度", "Read speed"), value: DisplayFormat.throughput(disk.readBytesPerSecond), prominent: true),
                .init(label: language.text("写入速度", "Write speed"), value: DisplayFormat.throughput(disk.writeBytesPerSecond), prominent: true)
            ],
            rightPairs: [
                .init(label: language.text("容量", "Capacity"), value: DisplayFormat.decimalBytes(disk.capacityBytes)),
                .init(label: language.text("可用", "Available"), value: DisplayFormat.decimalBytes(disk.availableBytes)),
                .init(label: language.text("系统磁盘", "System disk"), value: disk.isSystemDisk ? language.text("是", "Yes") : language.text("否", "No")),
                .init(label: language.text("类型", "Type"), value: language.isChinese ? disk.kindLabel : language.translateDiskKind(disk.kindLabel)),
                .init(label: language.text("卷标", "Label"), value: disk.subtitle)
            ],
            memoryComposition: false
        )
    }

    private func networkDetail(_ network: NetworkState) -> PerformanceDetailViewData {
        PerformanceDetailViewData(
            title: network.displayName,
            topRight: network.interfaceName,
            ceilingLabel: DisplayFormat.networkRate(UInt64(max(network.chartCeilingBytesPerSecond, 1))),
            chartCeiling: max(network.chartCeilingBytesPerSecond, 1),
            primaryLabel: language.text("吞吐量", "Throughput"),
            accent: Color(red: 0.85, green: 0.46, blue: 0.08),
            chartSets: [network.detailHistory],
            lowerChart: nil,
            lowerChartValueCeiling: nil,
            lowerChartCeiling: nil,
            lowerLabel: nil,
            leftMetrics: [
                .init(label: language.text("发送", "Send"), value: DisplayFormat.networkRate(network.sendBytesPerSecond), prominent: true),
                .init(label: language.text("接收", "Receive"), value: DisplayFormat.networkRate(network.receiveBytesPerSecond), prominent: true)
            ],
            rightPairs: [
                .init(label: language.text("适配器名称", "Adapter name"), value: network.displayName),
                .init(label: language.text("连接类型", "Connection type"), value: network.subtitle),
                .init(label: language.text("IPv4 地址", "IPv4 address"), value: network.ipv4.isEmpty ? "--" : network.ipv4),
                .init(label: language.text("IPv6 地址", "IPv6 address"), value: network.ipv6.isEmpty ? "--" : network.ipv6)
            ],
            memoryComposition: false
        )
    }

    private func npuDetail(_ npu: NPUState) -> PerformanceDetailViewData {
        let totalMemory = max(memory.totalBytes, 1)
        return PerformanceDetailViewData(
            title: npu.title,
            topRight: npu.modelName,
            ceilingLabel: "100%",
            chartCeiling: 100,
            primaryLabel: "",
            accent: Color(red: 0.96, green: 0.26, blue: 0.26),
            chartSets: [npu.historyCompute],
            lowerChart: npu.historyMemoryPressure,
            lowerChartValueCeiling: 100,
            lowerChartCeiling: DisplayFormat.memory(totalMemory),
            lowerLabel: language.text("共享内存", "Shared memory"),
            leftMetrics: [
                .init(label: language.text("利用率", "Utilization"), value: DisplayFormat.percent(npu.utilizationPercent), prominent: true),
                .init(label: language.text("共享内存", "Shared memory"), value: "\(DisplayFormat.memory(npu.neuralFootprintBytes))/\(DisplayFormat.memory(totalMemory))", prominent: true),
                .init(label: language.text("峰值", "Peak"), value: DisplayFormat.memory(npu.peakNeuralFootprintBytes))
            ],
            rightPairs: [
                .init(label: language.text("NPU 个数", "NPU count"), value: "\(npu.npuCount)"),
                .init(label: language.text("NPU 核心数", "NPU cores"), value: "\(npu.coreCount)"),
                .init(label: language.text("ANE 架构", "ANE architecture"), value: npu.architecture),
                .init(label: language.text("固件已加载", "Firmware loaded"), value: language.text(npu.firmwareLoaded ? "是" : "否", npu.firmwareLoaded ? "Yes" : "No")),
                .init(label: language.text("活跃客户端数", "Active clients"), value: "\(npu.activeClientCount)"),
                .init(label: language.text("引擎类型", "Engine type"), value: "Apple Neural Engine")
            ],
            memoryComposition: false
        )
    }

    private func gpuDetail(_ gpu: GPUState) -> PerformanceDetailViewData {
        var rightPairs: [InfoPair] = [
            .init(label: language.text("GPU 个数", "GPU count"), value: "\(gpu.gpuCount)"),
            .init(label: language.text("GPU 类型", "GPU type"), value: gpu.gpuType),
            .init(label: language.text("GPU 核心", "GPU cores"), value: "\(gpu.coreCount)"),
            .init(label: language.text("3D 引擎", "3D engine"), value: DisplayFormat.percent(gpu.rendererUtilizationPercent)),
            .init(label: "Tiler", value: DisplayFormat.percent(gpu.tilerUtilizationPercent)),
            .init(label: language.text("Metal 版本", "Metal version"), value: gpu.metalVersion)
        ]
        if let openGLVersion = gpu.openGLVersion, !openGLVersion.isEmpty {
            rightPairs.append(.init(label: language.text("OpenGL 版本", "OpenGL version"), value: openGLVersion))
        }

        return PerformanceDetailViewData(
            title: gpu.title,
            topRight: gpu.modelName,
            ceilingLabel: "100%",
            chartCeiling: 100,
            primaryLabel: "",
            accent: Color(red: 0.68, green: 0.32, blue: 0.94),
            chartSets: [gpu.historyOverall, gpu.history3D, gpu.historyTiler],
            lowerChart: gpu.memoryHistory,
            lowerChartValueCeiling: 100,
            lowerChartCeiling: DisplayFormat.memory(max(gpu.sharedMemoryAllocatedBytes, 1)),
            lowerLabel: language.text("共享 GPU 内存", "Shared GPU memory"),
            leftMetrics: [
                .init(label: language.text("利用率", "Utilization"), value: DisplayFormat.percent(gpu.utilizationPercent), prominent: true),
                .init(label: language.text("共享 GPU 内存", "Shared GPU memory"), value: "\(DisplayFormat.memory(gpu.sharedMemoryUsedBytes))/\(DisplayFormat.memory(max(gpu.sharedMemoryAllocatedBytes, 1)))", prominent: true),
                .init(label: language.text("GPU 内存", "GPU memory"), value: DisplayFormat.memory(gpu.sharedMemoryUsedBytes))
            ],
            rightPairs: rightPairs,
            memoryComposition: false
        )
    }

    private func refreshNPUs() {
        scheduleNPURefresh(ifNeededAt: Date())
    }

    private func cpuGridHistories() -> [[Double]] {
        let targetCount = max(cpu.logicalCores, 1)
        if cpu.coreHistories.count >= targetCount {
            return Array(cpu.coreHistories.prefix(targetCount))
        }
        if cpu.coreHistories.isEmpty {
            return Array(repeating: cpu.history, count: targetCount)
        }
        var result = cpu.coreHistories
        while result.count < targetCount {
            result.append(cpu.history)
        }
        return result
    }
}

struct PerformanceDetailViewData {
    let title: String
    let topRight: String
    let ceilingLabel: String
    let chartCeiling: Double
    let primaryLabel: String
    let accent: Color
    let chartSets: [[Double]]
    let lowerChart: [Double]?
    let lowerChartValueCeiling: Double?
    let lowerChartCeiling: String?
    let lowerLabel: String?
    let leftMetrics: [DetailMetric]
    let rightPairs: [InfoPair]
    let memoryComposition: Bool
}

extension SystemMonitor {
    struct ProcessSnapshot {
        let pid: Int32
        let displayName: String
        let path: String
        let residentSize: UInt64
        let totalCPUTime: UInt64
        let diskReadBytes: UInt64
        let diskWriteBytes: UInt64
        let threadCount: Int
        let openFiles: Int
        let isApplication: Bool
        let icon: NSImage?
        let uid: uid_t
        let bsdStatus: UInt32
        let flags: UInt32
    }

    struct InterfaceSnapshot {
        let name: String
        let groupKey: String
        let displayName: String
        let medium: String
        let isPrimaryCandidate: Bool
        let ipv4: String
        let ipv6: String
        let inBytes: UInt64
        let outBytes: UInt64
        let packetsIn: UInt64
        let packetsOut: UInt64
        let multicastIn: UInt64
        let multicastOut: UInt64
        let errorsIn: UInt64
        let errorsOut: UInt64
        let dropsIn: UInt64
        let dropsOut: UInt64
        let mtu: UInt32
        let lineSpeedBitsPerSecond: UInt64
    }

    struct GroupedNetworkSample {
        var representative: InterfaceSnapshot
        var send: UInt64
        var receive: UInt64
    }

    struct DiskMeta {
        let id: String
        let title: String
        let subtitle: String
        let kind: String
        let model: String
        let capacityBytes: UInt64
        let availableBytes: UInt64
        let isSystemDisk: Bool
        let counters: (read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64, readTimeNs: UInt64, writeTimeNs: UInt64)
    }

    struct LaunchdRuntimeEntry {
        let label: String
        let pid: Int32?
        let stateToken: String
        let group: String
    }

    struct LaunchdPlistMetadata {
        let label: String
        let name: String
        let icon: NSImage?
        let serviceDescription: String
        let group: String
        let disabled: Bool
    }

    struct ANEDeviceInfo {
        let modelName: String
        let npuCount: Int
        let coreCount: Int
        let capacityBytes: UInt64
        let architecture: String
        let firmwareLoaded: Bool
        let currentPowerState: Int
        let maxPowerState: Int
        let activeClientCount: Int
    }

    struct NeuralUsageTotals {
        let currentBytes: UInt64
        let intervalPeakBytes: UInt64
    }

    func processCPUSeconds(pid: Int32) -> Double {
        guard let snapshot = processInfo(pid: pid) else { return 0 }
        return Double(snapshot.totalCPUTime) / 1_000_000_000
    }

    func formatCPUTime(_ totalSeconds: Double) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    func widgetExtensionMap() -> [String: Int] {
        [:]
    }

    func startupItems() -> [StartupItemRowData] {
        startupRows
    }

    func refreshServices(ifNeededAt now: Date) {
        scheduleServicesRefresh(ifNeededAt: now)
    }

    func launchAgentItems() -> [StartupItemRowData] {
        let directories = [
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        ]

        var items: [StartupItemRowData] = []
        let fileManager = FileManager.default

        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(entry)
                guard let data = fileManager.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else { continue }

                let label = plist["Label"] as? String ?? entry.replacingOccurrences(of: ".plist", with: "")
                let program = (plist["Program"] as? String)
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? ""
                let name = URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent.isEmpty
                    ? label
                    : URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent
                let publisher = program.isEmpty ? directoryLabel(directory) : URL(fileURLWithPath: program).deletingLastPathComponent().lastPathComponent
                let group = launchdGroupForStartupDirectory(directory)
                let labelDisabled = disabledLaunchdByGroup[group]?.contains(label) ?? false
                let plistDisabled = (plist["Disabled"] as? Bool) ?? false
                let enabled = !(plistDisabled || labelDisabled)
                let impact = directory.contains("Daemons") ? "高" : "未计算"

                items.append(
                    StartupItemRowData(
                        id: path,
                        name: name,
                        icon: startupItemIcon(fromProgramPath: program),
                        publisher: publisher,
                        status: enabled ? "已启用" : "已禁用",
                        startupImpact: impact
                    )
                )
            }
        }

        return items
    }

    func launchdGroupForStartupDirectory(_ directory: String) -> String {
        if directory.contains("LaunchDaemons") {
            return "system"
        }
        return "gui/\(getuid())"
    }

    func directoryLabel(_ path: String) -> String {
        if path.contains("LaunchDaemons") { return "系统守护进程" }
        if path.contains("/Library/LaunchAgents") { return "系统代理" }
        return "用户代理"
    }

    func startupItemIcon(fromProgramPath program: String) -> NSImage? {
        guard !program.isEmpty else { return nil }
        if program.hasSuffix(".app") {
            return NSWorkspace.shared.icon(forFile: program)
        }
        let nsPath = program as NSString
        let range = nsPath.range(of: ".app/")
        if range.location != NSNotFound, let swiftRange = Range(range, in: program) {
            let appPath = String(program[..<swiftRange.upperBound]).dropLast()
            return NSWorkspace.shared.icon(forFile: String(appPath))
        }
        return NSWorkspace.shared.icon(forFile: program)
    }

    func launchdRuntimeEntries(uid: uid_t) -> [LaunchdRuntimeEntry] {
        let systemEntries = parseLaunchctlPrintDomain("system", group: "system")
        let guiEntries = parseLaunchctlPrintDomain("gui/\(uid)", group: "gui/\(uid)")
        var merged: [String: LaunchdRuntimeEntry] = [:]

        for entry in systemEntries + guiEntries {
            guard shouldIncludeServiceLabel(entry.label) else { continue }
            let key = serviceCompositeKey(label: entry.label, group: entry.group)
            merged[key] = entry
        }

        return Array(merged.values)
    }

    func parseLaunchctlPrintDomain(_ domain: String, group: String) -> [LaunchdRuntimeEntry] {
        guard let data = try? Process.runAndCapture("/bin/launchctl", ["print", domain]),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var result: [LaunchdRuntimeEntry] = []
        var inServicesBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "services = {" {
                inServicesBlock = true
                continue
            }
            if inServicesBlock, trimmed == "}" {
                break
            }
            guard inServicesBlock else { continue }

            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { continue }

            let label = String(parts.last!)
            guard shouldIncludeServiceLabel(label) else { continue }

            let pidToken = String(parts[0])
            let stateToken = String(parts[1])
            let pid: Int32?
            if let value = Int32(pidToken), value > 0 {
                pid = value
            } else {
                pid = nil
            }

            result.append(
                LaunchdRuntimeEntry(
                    label: label,
                    pid: pid,
                    stateToken: stateToken,
                    group: group
                )
            )
        }

        return result
    }

    func launchdPlistMetadata(uid: uid_t) -> [String: LaunchdPlistMetadata] {
        let directories = [
            "/System/Library/LaunchDaemons",
            "/System/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        ]

        let fileManager = FileManager.default
        var result: [String: LaunchdPlistMetadata] = [:]

        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(entry)
                guard let data = fileManager.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else {
                    continue
                }

                let label = plist["Label"] as? String ?? entry.replacingOccurrences(of: ".plist", with: "")
                guard shouldIncludeServiceLabel(label) else { continue }

                let program = (plist["Program"] as? String)
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? ""
                let executableName = serviceExecutableName(fromProgramPath: program)
                let name = executableName.isEmpty ? serviceNameFallback(label: label) : executableName
                let description = serviceDescriptionText(label: label, program: program, plist: plist)
                let disabled = (plist["Disabled"] as? Bool) ?? false
                let group = launchdGroup(forDirectory: directory, uid: uid)
                let key = serviceCompositeKey(label: label, group: group)

                result[key] = LaunchdPlistMetadata(
                    label: label,
                    name: name,
                    icon: startupItemIcon(fromProgramPath: program),
                    serviceDescription: description,
                    group: group,
                    disabled: disabled
                )
            }
        }

        return result
    }

    func launchdGroup(forDirectory directory: String, uid: uid_t) -> String {
        if directory.contains("LaunchDaemons") {
            return "system"
        }
        return "gui/\(uid)"
    }

    func serviceCompositeKey(label: String, group: String) -> String {
        "\(group)|\(label)"
    }

    func shouldIncludeServiceLabel(_ label: String) -> Bool {
        guard !label.isEmpty else { return false }
        if label.hasPrefix("application.") { return false }
        if label.hasPrefix("com.apple.xpc.") { return false }
        return true
    }

    func serviceExecutableName(fromProgramPath program: String) -> String {
        guard !program.isEmpty else { return "" }
        if program.hasSuffix(".app") {
            return URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent
        }

        let nsPath = program as NSString
        let range = nsPath.range(of: ".app/")
        if range.location != NSNotFound, let swiftRange = Range(range, in: program) {
            let appPath = String(program[..<swiftRange.upperBound]).dropLast()
            let appName = URL(fileURLWithPath: String(appPath)).deletingPathExtension().lastPathComponent
            if !appName.isEmpty {
                return appName
            }
        }

        return URL(fileURLWithPath: program).lastPathComponent
    }

    func serviceNameFallback(label: String) -> String {
        let parts = label.split(separator: ".")
        if let last = parts.last, !last.isEmpty {
            return String(last)
        }
        return label
    }

    func serviceDescriptionText(label: String, program: String, plist: [String: Any]) -> String {
        if let bundleName = plist["CFBundleDisplayName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        if !program.isEmpty {
            let executable = serviceExecutableName(fromProgramPath: program)
            if !executable.isEmpty {
                return "\(label) (\(executable))"
            }
        }
        if let machServices = plist["MachServices"] as? [String: Any], !machServices.isEmpty {
            return "\(label) (Mach Service)"
        }
        return label
    }

    func serviceStatusText(pid: Int32?, stateToken: String, disabled: Bool) -> String {
        if disabled {
            return "已禁用"
        }
        if pid != nil {
            return "正在运行"
        }
        if stateToken == "0" {
            return "已停止"
        }
        if stateToken == "-" || stateToken.hasPrefix("(") {
            return "按需"
        }
        return "已加载"
    }

    func aneDeviceInfo() -> ANEDeviceInfo? {
        guard cpuArchitecture != .intelLike else {
            return nil
        }
        guard let data = try? Process.runAndCapture("/usr/sbin/ioreg", ["-l", "-w0"]),
              let text = String(data: data, encoding: .utf8),
              text.localizedCaseInsensitiveContains("ANE")
        else {
            return nil
        }

        let npuCount = text.localizedCaseInsensitiveContains("ANEDevicePropertyNumANEs") ? 1 : 1
        let coreCount = 16
        let modelName = "Apple Neural Engine"
        let architecture = extractFirstMatch(in: text, pattern: #"ANEDevicePropertyTypeANEArchitectureTypeStr"="([^"]+)""#) ?? "h16g"
        let firmwareLoaded = text.localizedCaseInsensitiveContains(#""FirmwareLoaded" = Yes"#) || text.localizedCaseInsensitiveContains(#""FirmwareLoaded" = true"#)
        let aneBlock = extractFirstMatch(in: text, pattern: #"(?s)\+\-o H11ANE .*?\{(.*?)\n\s*\}"#) ?? text
        let currentPowerState = Int(extractFirstMatch(in: aneBlock, pattern: #""CurrentPowerState"=([0-9]+)"#) ?? "0") ?? 0
        let maxPowerState = Int(extractFirstMatch(in: aneBlock, pattern: #""MaxPowerState"=([0-9]+)"#) ?? "1") ?? 1
        let activeClientCount = max(text.components(separatedBy: "IOUserClientCreator").count - 1, 0)
        let capacityBytes = sysctlInt("hw.memsize").map { max($0, 1_073_741_824) } ?? 1_073_741_824
        return ANEDeviceInfo(
            modelName: modelName,
            npuCount: npuCount,
            coreCount: coreCount,
            capacityBytes: capacityBytes,
            architecture: architecture,
            firmwareLoaded: firmwareLoaded,
            currentPowerState: currentPowerState,
            maxPowerState: maxPowerState,
            activeClientCount: activeClientCount
        )
    }

    func currentNeuralUsageTotals() -> NeuralUsageTotals {
        let pids = listPIDs()
        var total: UInt64 = 0
        var peak: UInt64 = 0
        for pid in pids where pid > 0 {
            var usage = rusage_info_current()
            let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
                }
            }
            if usageResult == 0 {
                total += usage.ri_neural_footprint
                peak = max(peak, usage.ri_interval_max_neural_footprint)
            }
        }
        return NeuralUsageTotals(currentBytes: total, intervalPeakBytes: peak)
    }

    func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }

    func frontWindowApplications() -> [NSRunningApplication] {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard !app.isTerminated else { return false }
                if let path = app.bundleURL?.path, path.contains("MacOS-TSKMGR/.build") {
                    return false
                }
                return app.activationPolicy == .regular
            }
        let appByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })

        var orderedPIDs: [Int32] = []
        if let windowInfo = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowInfo {
                guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
                guard appByPID[ownerPID] != nil else { continue }

                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                guard layer == 0 else { continue }

                let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
                guard alpha > 0.01 else { continue }

                if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
                    let width = bounds["Width"] ?? 0
                    let height = bounds["Height"] ?? 0
                    guard width > 80, height > 60 else { continue }
                }

                if !orderedPIDs.contains(ownerPID) {
                    orderedPIDs.append(ownerPID)
                }
            }
        }

        for app in runningApps where !orderedPIDs.contains(app.processIdentifier) {
            orderedPIDs.append(app.processIdentifier)
        }

        return orderedPIDs.compactMap { appByPID[$0] }
    }

    func childProcessesMap(allRows: [Int32: ProcessRowData]) -> [Int32: [Int32]] {
        var result: [Int32: [Int32]] = [:]
        for pid in allRows.keys {
            let children = listChildPIDs(parentPID: pid).filter { allRows[$0] != nil }
            if !children.isEmpty {
                result[pid] = children
            }
        }
        return result
    }

    func listChildPIDs(parentPID: Int32) -> [Int32] {
        let size = proc_listchildpids(parentPID, nil, 0)
        guard size > 0 else { return [] }
        let count = size / Int32(MemoryLayout<pid_t>.size)
        var buffer = Array(repeating: pid_t(0), count: Int(count))
        let bytes = proc_listchildpids(parentPID, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return buffer.filter { $0 > 0 }
    }

    func processRowSort(_ lhs: ProcessRowData, _ rhs: ProcessRowData) -> Bool {
        if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.05 {
            return lhs.cpuPercent > rhs.cpuPercent
        }
        return lhs.memoryBytes > rhs.memoryBytes
    }

    func processNetworkSnapshot(interfaceFilter: String?) -> [Int32: UInt64] {
        interfaceFilter == "expensive" ? meteredProcessNetworkTotals : processNetworkTotals
    }

    func listPIDs() -> [Int32] {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }
        let count = bufferSize / Int32(MemoryLayout<pid_t>.size)
        var buffer = Array(repeating: pid_t(0), count: Int(count))
        let bytes = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return buffer.filter { $0 > 0 }
    }

    func processInfo(pid: Int32) -> ProcessSnapshot? {
        var taskInfo = proc_taskinfo()
        let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
        guard taskResult == Int32(MemoryLayout<proc_taskinfo>.size) else { return nil }

        var bsdInfo = proc_bsdinfo()
        let bsdResult = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard bsdResult == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }

        var nameBuffer = Array(repeating: CChar(0), count: Int(MAXPATHLEN))
        let named = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let command = named > 0 ? stringFromCBuffer(nameBuffer) : stringFromCArray(&bsdInfo.pbi_name.0)
        let fallback = stringFromCArray(&bsdInfo.pbi_comm.0)
        let displayName = command.isEmpty ? fallback : command
        let path = pidPath(pid: pid)

        var usage = rusage_info_current()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }

        let app = path.hasSuffix(".app") || path.contains("/Applications/") || path.contains("/System/Applications/")
        return ProcessSnapshot(
            pid: pid,
            displayName: displayName,
            path: path,
            residentSize: taskInfo.pti_resident_size,
            totalCPUTime: taskInfo.pti_total_user + taskInfo.pti_total_system,
            diskReadBytes: usageResult == 0 ? usage.ri_diskio_bytesread : 0,
            diskWriteBytes: usageResult == 0 ? usage.ri_diskio_byteswritten : 0,
            threadCount: Int(taskInfo.pti_threadnum),
            openFiles: Int(bsdInfo.pbi_nfiles),
            isApplication: app,
            icon: iconForProcess(path: path),
            uid: bsdInfo.pbi_uid,
            bsdStatus: bsdInfo.pbi_status,
            flags: bsdInfo.pbi_flags
        )
    }

    func processCPUDisplayPercent(pid: Int32, totalCPUTime: UInt64) -> Double {
        let previousCPU = previousProcessCPUTime[pid] ?? totalCPUTime
        let delta = totalCPUTime >= previousCPU ? totalCPUTime - previousCPU : 0
        let logicalCores = max(cpu.logicalCores, 1)
        var cpuPercent = min(max((Double(delta) / max(refreshSpeed.interval ?? 1.0, 0.5) / 1_000_000_000.0) / Double(logicalCores) * 100, 0), 999)
        if cpuPercent > 0 && cpuPercent < 0.1 {
            cpuPercent = 0.1
        }
        return cpuPercent
    }

    func processStatusText(_ status: UInt32) -> String {
        switch status {
        case UInt32(SIDL): return "正在创建"
        case UInt32(SRUN): return "正在运行"
        case UInt32(SSLEEP): return "正在睡眠"
        case UInt32(SSTOP): return "已停止"
        case UInt32(SZOMB): return "僵尸"
        default: return "未知"
        }
    }

    func userName(for uid: uid_t) -> String {
        if let pw = getpwuid(uid) {
            return String(cString: pw.pointee.pw_name)
        }
        return "\(uid)"
    }

    func processPlatform(flags: UInt32) -> String {
        let is64Bit = (flags & UInt32(PROC_FLAG_LP64)) != 0
        switch cpuArchitecture {
        case .appleSilicon:
            if is64Bit {
                return "ARM64"
            }
            return "x86_64"
        case .intelLike, .unknown:
            return is64Bit ? "64位" : "32位"
        }
    }

    func pidPath(pid: Int32) -> String {
        var pathBuffer = Array(repeating: CChar(0), count: pidPathInfoMaxSize)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard result > 0 else { return "" }
        return stringFromCBuffer(pathBuffer)
    }

    func iconForProcess(path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        if path.hasSuffix(".app") {
            return NSWorkspace.shared.icon(forFile: path)
        }
        let nsPath = path as NSString
        let range = nsPath.range(of: ".app/")
        if range.location != NSNotFound, let swiftRange = Range(range, in: path) {
            let appPath = String(path[..<swiftRange.upperBound]).dropLast()
            return NSWorkspace.shared.icon(forFile: String(appPath))
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    func networkInterfaces() -> [InterfaceSnapshot] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var byteCounters: [String: (UInt64, UInt64)] = [:]
        var ipv4Map: [String: String] = [:]
        var ipv6Map: [String: String] = [:]

        var current = first
        while true {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    let existing = byteCounters[name] ?? (0, 0)
                    byteCounters[name] = (max(existing.0, UInt64(data.pointee.ifi_ibytes)), max(existing.1, UInt64(data.pointee.ifi_obytes)))
                }
                if let addr = ifa.ifa_addr {
                    let family = addr.pointee.sa_family
                    if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                        var hostBuffer = Array(repeating: CChar(0), count: Int(NI_MAXHOST))
                        let length = socklen_t(addr.pointee.sa_len)
                        let result = getnameinfo(addr, length, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
                        if result == 0 {
                            let text = stringFromCBuffer(hostBuffer)
                            if family == UInt8(AF_INET) {
                                ipv4Map[name] = text
                            } else if !text.hasPrefix("fe80") {
                                ipv6Map[name] = text
                            }
                        }
                    }
                }
            }
            guard let next = ifa.ifa_next else { break }
            current = next
        }

        return byteCounters.keys.map { name in
            let hardwarePort = hardwarePortMap[name] ?? ""
            let medium: String
            let displayName: String
            let groupKey: String

            if hardwarePort == "Wi-Fi" {
                displayName = "Wi-Fi"
                medium = "Wi-Fi"
                groupKey = "wifi"
            } else if hardwarePort.localizedCaseInsensitiveContains("Ethernet") || hardwarePort.localizedCaseInsensitiveContains("LAN") {
                displayName = "以太网"
                medium = hardwarePort
                groupKey = "ethernet"
            } else if name.hasPrefix("utun") {
                displayName = name
                medium = "VPN隧道"
                groupKey = name
            } else if name.hasPrefix("bridge") || name.hasPrefix("vmenet") {
                displayName = name
                medium = "虚拟网络"
                groupKey = name
            } else if name.hasPrefix("awdl") || name.hasPrefix("llw") {
                displayName = name
                medium = "Apple Wireless"
                groupKey = name
            } else {
                displayName = name
                medium = hardwarePort.isEmpty ? "网络接口" : hardwarePort
                groupKey = name
            }
            return InterfaceSnapshot(
                name: name,
                groupKey: groupKey,
                displayName: displayName,
                medium: medium,
                isPrimaryCandidate: hardwarePort == "Wi-Fi" || hardwarePort.localizedCaseInsensitiveContains("Ethernet") || hardwarePort.localizedCaseInsensitiveContains("LAN"),
                ipv4: ipv4Map[name] ?? "",
                ipv6: ipv6Map[name] ?? "",
                inBytes: byteCounters[name]?.0 ?? 0,
                outBytes: byteCounters[name]?.1 ?? 0,
                packetsIn: interfaceCounter(name: name, keyPath: \.ifi_ipackets),
                packetsOut: interfaceCounter(name: name, keyPath: \.ifi_opackets),
                multicastIn: interfaceCounter(name: name, keyPath: \.ifi_imcasts),
                multicastOut: interfaceCounter(name: name, keyPath: \.ifi_omcasts),
                errorsIn: interfaceCounter(name: name, keyPath: \.ifi_ierrors),
                errorsOut: interfaceCounter(name: name, keyPath: \.ifi_oerrors),
                dropsIn: interfaceCounter(name: name, keyPath: \.ifi_iqdrops),
                dropsOut: 0,
                mtu: interfaceMTU(name: name),
                lineSpeedBitsPerSecond: interfaceLineSpeed(name: name, medium: medium)
            )
        }
    }

    func shouldHideNetworkInterface(_ item: InterfaceSnapshot, send: UInt64, receive: UInt64) -> Bool {
        if item.name.hasPrefix("awdl") || item.name.hasPrefix("llw") || item.name.hasPrefix("anpi") || item.name.hasPrefix("ap") {
            return true
        }

        let hasAddress = !item.ipv4.isEmpty || !item.ipv6.isEmpty
        let hasTraffic = send > 0 || receive > 0

        if item.medium == "Wi-Fi" || item.medium == "以太网" || item.medium.localizedCaseInsensitiveContains("Ethernet") || item.medium.localizedCaseInsensitiveContains("LAN") {
            return !(hasAddress || hasTraffic)
        }

        if item.medium.localizedCaseInsensitiveContains("Thunderbolt") {
            return true
        }

        if item.name.hasPrefix("bridge") || item.name.hasPrefix("vmenet") {
            return true
        }

        if item.name.hasPrefix("utun") {
            return !(hasAddress || hasTraffic)
        }

        return true
    }

    func shouldPreferNetworkRepresentative(candidate: InterfaceSnapshot, over current: InterfaceSnapshot, send: UInt64, receive: UInt64) -> Bool {
        let candidateHasAddress = !candidate.ipv4.isEmpty || !candidate.ipv6.isEmpty
        let currentHasAddress = !current.ipv4.isEmpty || !current.ipv6.isEmpty
        if candidateHasAddress != currentHasAddress {
            return candidateHasAddress
        }

        let candidateTraffic = send + receive
        let currentTraffic = (previousNetworkCounters[current.name]?.0 ?? 0) + (previousNetworkCounters[current.name]?.1 ?? 0)
        if candidateTraffic != currentTraffic {
            return candidateTraffic > currentTraffic
        }

        return candidate.name.localizedStandardCompare(current.name) == .orderedAscending
    }

    func networkSortOrder(for groupKey: String) -> Int {
        if groupKey == "wifi" { return 0 }
        if groupKey == "ethernet" { return 1 }
        if groupKey.hasPrefix("utun") { return 2 }
        if groupKey.hasPrefix("bridge") || groupKey.hasPrefix("vmenet") { return 3 }
        return 4
    }

    func networkStatusText(for snapshot: InterfaceSnapshot) -> String {
        (!snapshot.ipv4.isEmpty || !snapshot.ipv6.isEmpty || snapshot.inBytes > 0 || snapshot.outBytes > 0) ? language.text("已连接", "Connected") : language.text("未连接", "Disconnected")
    }

    func networkLinkSpeedText(for snapshot: InterfaceSnapshot) -> String {
        if snapshot.lineSpeedBitsPerSecond > 0 {
            return DisplayFormat.linkSpeed(bitsPerSecond: snapshot.lineSpeedBitsPerSecond)
        }
        if snapshot.medium.localizedCaseInsensitiveContains("VPN") {
            return language.text("虚拟", "Virtual")
        }
        return snapshot.medium
    }

    func interfaceLineSpeed(name: String, medium: String) -> UInt64 {
        if medium == "Wi-Fi" {
            return wifiTransmitRateBitsPerSecond(interfaceName: name)
        }
        return interfaceBaudRate(name: name)
    }

    func interfaceBaudRate(name: String) -> UInt64 {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return 0 }
        defer { freeifaddrs(pointer) }

        var current = first
        while true {
            let ifa = current.pointee
            let currentName = String(cString: ifa.ifa_name)
            if currentName == name, let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return UInt64(data.pointee.ifi_baudrate)
            }
            guard let next = ifa.ifa_next else { break }
            current = next
        }
        return 0
    }

    func wifiTransmitRateBitsPerSecond(interfaceName: String) -> UInt64 {
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else {
            return 0
        }
        let rateMbps = interface.transmitRate()
        guard rateMbps > 0 else { return 0 }
        return UInt64(rateMbps * 1_000_000)
    }

    func interfaceCounter(name: String, keyPath: KeyPath<if_data, UInt32>) -> UInt64 {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return 0 }
        defer { freeifaddrs(pointer) }

        var current = first
        while true {
            let ifa = current.pointee
            let currentName = String(cString: ifa.ifa_name)
            if currentName == name, let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return UInt64(data.pointee[keyPath: keyPath])
            }
            guard let next = ifa.ifa_next else { break }
            current = next
        }
        return 0
    }

    func interfaceMTU(name: String) -> UInt32 {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return 0 }
        defer { freeifaddrs(pointer) }

        var current = first
        while true {
            let ifa = current.pointee
            let currentName = String(cString: ifa.ifa_name)
            if currentName == name, let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return data.pointee.ifi_mtu
            }
            guard let next = ifa.ifa_next else { break }
            current = next
        }
        return 0
    }

    func currentPrimaryCPUSpeedText() -> String {
        if cpu.performanceCoreSpeedText != "--" {
            return cpu.performanceCoreSpeedText
        }
        if cpu.baseSpeedText != "--" {
            return cpu.baseSpeedText
        }
        return cpu.modelName
    }

    func refreshGPUs() {
        scheduleGPURefresh(ifNeededAt: Date())
    }

    func metalLabel(from raw: String) -> String {
        switch raw {
        case "spdisplays_metal4":
            return "Metal 4"
        case "spdisplays_metal3":
            return "Metal 3"
        case "spdisplays_metal2":
            return "Metal 2"
        default:
            return raw.isEmpty ? "Metal" : raw
        }
    }

    func diskMetadata() -> [DiskMeta] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        let mountInfo = mountedDiskInfoByWholeDisk()
        var result: [DiskMeta] = []
        var index = 0

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard
                let stats = registryPropertyDictionary(service, key: "Statistics"),
                let media = wholeMediaChild(of: service)
            else {
                continue
            }
            defer { IOObjectRelease(media) }

            let mediaProps = registryProperties(media)
            let deviceIdentifier = mediaProps["BSD Name"] as? String ?? ""
            guard !deviceIdentifier.isEmpty else { continue }

            let size = (mediaProps["Size"] as? NSNumber)?.uint64Value ?? 0
            let removable = (mediaProps["Removable"] as? Bool) ?? false || ((mediaProps["Ejectable"] as? Bool) ?? false)
            let model = ioRegistryName(media).isEmpty ? deviceIdentifier : ioRegistryName(media)
            let kind = removable ? "可移动" : (model.localizedCaseInsensitiveContains("SSD") ? "SSD" : "HDD")
            let label = mountInfo[deviceIdentifier]?.label ?? deviceIdentifier
            let available = mountInfo[deviceIdentifier]?.availableBytes ?? size

            result.append(DiskMeta(
                id: deviceIdentifier,
                title: language.text("磁盘", "Disk") + " \(index) (\(deviceIdentifier))",
                subtitle: label,
                kind: kind,
                model: model,
                capacityBytes: size,
                availableBytes: available,
                isSystemDisk: deviceIdentifier == rootWholeDiskID,
                counters: (
                    (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                    (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0,
                    (stats["Operations (Read)"] as? NSNumber)?.uint64Value ?? 0,
                    (stats["Operations (Write)"] as? NSNumber)?.uint64Value ?? 0,
                    (stats["Total Time (Read)"] as? NSNumber)?.uint64Value ?? 0,
                    (stats["Total Time (Write)"] as? NSNumber)?.uint64Value ?? 0
                )
            ))
            index += 1
        }

        return result
    }

    func wholeMediaChild(of service: io_registry_entry_t) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            let props = registryProperties(child)
            if let bsd = props["BSD Name"] as? String, !bsd.isEmpty, (props["Whole"] as? Bool) == true {
                return child
            }
            IOObjectRelease(child)
        }

        return nil
    }

    func registryProperties(_ entry: io_registry_entry_t) -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    func registryPropertyDictionary(_ entry: io_registry_entry_t, key: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    func ioRegistryName(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return "" }
        return stringFromCBuffer(name)
    }

    func detectRootWholeDiskIdentifier() -> String? {
        if let data = try? Process.runAndCapture("/usr/sbin/diskutil", ["info", "-plist", "/"]),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        {
            if let physicalStores = plist["APFSPhysicalStores"] as? [[String: Any]] {
                for store in physicalStores {
                    if let physicalStore = store["APFSPhysicalStore"] as? String ?? store["DeviceIdentifier"] as? String,
                       let wholeDisk = wholeDiskIdentifier(fromDevicePath: "/dev/\(physicalStore)")
                    {
                        return wholeDisk
                    }
                }
            }

            if let parentWholeDisk = plist["ParentWholeDisk"] as? String,
               let wholeDisk = wholeDiskIdentifier(fromDevicePath: "/dev/\(parentWholeDisk)")
            {
                return wholeDisk
            }
        }

        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        let source = withUnsafePointer(to: &stats.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { pointer in
                String(cString: pointer)
            }
        }
        return wholeDiskIdentifier(fromDevicePath: source)
    }

    func loadHardwarePortMap() -> [String: String] {
        guard let data = try? Process.runAndCapture("/usr/sbin/networksetup", ["-listallhardwareports"]),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        var result: [String: String] = [:]
        var currentPort: String?

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") {
                currentPort = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), let currentPort {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if !device.isEmpty {
                    result[device] = currentPort
                }
            }
        }

        return result
    }

    func mountedDiskInfoByWholeDisk() -> [String: (availableBytes: UInt64, label: String)] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeNameKey, .volumeAvailableCapacityKey]
        let urls = manager.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var result: [String: (availableBytes: UInt64, label: String)] = [:]

        for url in urls {
            var stats = statfs()
            guard statfs(url.path, &stats) == 0 else { continue }
            let source = withUnsafePointer(to: &stats.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { pointer in
                    String(cString: pointer)
                }
            }
            guard let wholeDisk = wholeDiskIdentifier(fromDevicePath: source) else { continue }

            let values = try? url.resourceValues(forKeys: keys)
            let label = values?.volumeLocalizedName ?? values?.volumeName ?? url.lastPathComponent
            let available = UInt64(values?.volumeAvailableCapacity ?? 0)

            if var existing = result[wholeDisk] {
                existing.availableBytes += available
                if existing.label == wholeDisk {
                    existing.label = label
                }
                result[wholeDisk] = existing
            } else {
                result[wholeDisk] = (available, label)
            }
        }

        return result
    }

    func wholeDiskIdentifier(fromDevicePath devicePath: String) -> String? {
        guard devicePath.hasPrefix("/dev/disk") else { return nil }
        let raw = String(devicePath.dropFirst("/dev/".count))
        let prefix = "disk"
        guard raw.hasPrefix(prefix) else { return nil }

        var result = prefix
        var index = raw.index(raw.startIndex, offsetBy: prefix.count)
        while index < raw.endIndex, raw[index].isNumber {
            result.append(raw[index])
            index = raw.index(after: index)
        }
        return result.count > prefix.count ? result : raw
    }

    func swapUsageBytes() -> UInt64 {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        guard result == 0 else { return 0 }
        return xsw.xsu_used
    }

    func sysctlString(_ name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        var buffer = Array<CChar>(repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return stringFromCBuffer(buffer)
    }

    func sysctlInt(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    func shifted(_ values: [Double], adding value: Double) -> [Double] {
        var history = values
        if history.isEmpty {
            history = Array(repeating: 0, count: 60)
        }
        history.append(value)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
        return history
    }

    func percent(_ value: UInt64, _ total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total) * 100
    }

    func smoothedDynamicCeiling(previous: Double, latest: Double, minimum: Double) -> Double {
        let paddedTarget = max(latest * 1.2, minimum)
        if previous <= 0 {
            return paddedTarget
        }
        if paddedTarget > previous {
            return previous * 0.72 + paddedTarget * 0.28
        }
        return previous * 0.88 + paddedTarget * 0.12
    }

    func resolveCPUArchitecture() -> CPUArchitecture {
        if let translated = sysctlInt("sysctl.proc_translated"), translated == 1 {
            return .intelLike
        }

        let machine = NXGetLocalArchInfo()?.pointee.name.flatMap { String(cString: $0) } ?? ""
        if machine.contains("arm64") {
            return .appleSilicon
        }
        if machine.contains("x86") || machine.contains("i386") {
            return .intelLike
        }

        if let brand = sysctlString("machdep.cpu.brand_string"), brand.contains("Apple") || brand.contains("M1") || brand.contains("M2") || brand.contains("M3") || brand.contains("M4") {
            return .appleSilicon
        }

        return .unknown
    }

    func detectCPUFrequencyInfo() -> (base: String, performance: String, efficiency: String) {
        switch cpuArchitecture {
        case .appleSilicon:
            let performance = detectAppleSiliconFrequencyText(propertyName: "voltage-states5-sram") ?? "--"
            let efficiency = detectAppleSiliconFrequencyText(propertyName: "voltage-states1-sram") ?? "--"
            return (performance != "--" ? performance : efficiency, performance, efficiency)
        case .intelLike, .unknown:
            let base = DisplayFormat.frequency(sysctlInt("hw.cpufrequency"))
            return (base, "--", "--")
        }
    }

    func detectAppleSiliconFrequencyText(propertyName: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching("pmgr"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard IOObjectConformsTo(service, "AppleARMIODevice") != 0 else {
            return nil
        }

        guard
            let property = IORegistryEntryCreateCFProperty(service, propertyName as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
            CFGetTypeID(property) == CFDataGetTypeID(),
            let data = property as? Data,
            data.count >= MemoryLayout<UInt32>.size * 2,
            data.count % (MemoryLayout<UInt32>.size * 2) == 0
        else {
            return nil
        }

        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: UInt32.self))
        }
        guard !values.isEmpty else { return nil }

        var maxFrequency = values[0]
        var index = 2
        while index < values.count, values[index] > 0 {
            maxFrequency = max(maxFrequency, values[index])
            index += 2
        }

        guard maxFrequency > 0 else { return nil }

        let mhz: Double
        if maxFrequency > 100_000_000 {
            mhz = Double(maxFrequency) / 1_000_000
        } else {
            mhz = Double(maxFrequency) / 1_000
        }

        return String(format: "%.2f GHz", mhz / 1000.0)
    }

    func loadCachePresentation() {
        appleCachePairs = []
        legacyCachePairs = []

        if let l1i = sysctlInt("hw.l1icachesize"), l1i > 0 {
            appleCachePairs.append(.init(label: language.text("L1 指令缓存", "L1 instruction cache"), value: DisplayFormat.decimalBytes(l1i)))
        }
        if let l1d = sysctlInt("hw.l1dcachesize"), l1d > 0 {
            appleCachePairs.append(.init(label: language.text("L1 数据缓存", "L1 data cache"), value: DisplayFormat.decimalBytes(l1d)))
            legacyCachePairs.append(.init(label: language.text("L1 缓存", "L1 cache"), value: DisplayFormat.decimalBytes(l1d)))
        }
        if let l2 = sysctlInt("hw.l2cachesize"), l2 > 0 {
            appleCachePairs.append(.init(label: language.text("L2 缓存", "L2 cache"), value: DisplayFormat.decimalBytes(l2)))
            legacyCachePairs.append(.init(label: language.text("L2 缓存", "L2 cache"), value: DisplayFormat.decimalBytes(l2)))
        }
        if let l3 = sysctlInt("hw.l3cachesize"), l3 > 0 {
            legacyCachePairs.append(.init(label: language.text("L3 缓存", "L3 cache"), value: DisplayFormat.decimalBytes(l3)))
        }
    }

    func stringFromCBuffer(_ buffer: [CChar]) -> String {
        let prefix = buffer.prefix { $0 != 0 }
        return String(decoding: prefix.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func stringFromCArray(_ pointer: UnsafePointer<CChar>) -> String {
        String(cString: pointer)
    }
}

enum CPUArchitecture {
    case appleSilicon
    case intelLike
    case unknown
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension Process {
    static func runAndCapture(_ launchPath: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

private enum MonitorProbe {
    struct StaticProbeSnapshot {
        let rootWholeDiskID: String?
        let hardwarePortMap: [String: String]
    }

    struct StartupRowSnapshot {
        let id: String
        let name: String
        let iconProgramPath: String?
        let publisher: String
        let status: String
        let startupImpact: String
    }

    struct StartupSnapshot {
        let disabledLaunchdByGroup: [String: Set<String>]
        let rows: [StartupRowSnapshot]
    }

    struct ServiceRowSnapshot {
        let id: String
        let name: String
        let iconProgramPath: String?
        let pid: Int32?
        let serviceDescription: String
        let status: String
        let group: String
        let label: String
    }

    static func collectStaticProbeSnapshot() -> StaticProbeSnapshot {
        StaticProbeSnapshot(
            rootWholeDiskID: detectRootWholeDiskIdentifier(),
            hardwarePortMap: loadHardwarePortMap()
        )
    }

    static func collectProcessNetworkSnapshot(interfaceFilter: String?) -> [Int32: UInt64] {
        var arguments = ["-x", "-P", "-L", "1"]
        if let interfaceFilter {
            arguments.append(contentsOf: ["-t", interfaceFilter])
        }
        guard let data = try? Process.runAndCapture("/usr/sbin/nettop", arguments),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        var result: [Int32: UInt64] = [:]
        let apps = NSWorkspace.shared.runningApplications
        let pidByName = Dictionary(uniqueKeysWithValues: apps.compactMap { app -> (String, Int32)? in
            guard let name = app.localizedName else { return nil }
            return (name, app.processIdentifier)
        })

        for line in text.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 6 else { continue }
            let processToken = String(parts[1])
            let bytesIn = UInt64(parts[4]) ?? 0
            let bytesOut = UInt64(parts[5]) ?? 0
            let total = bytesIn + bytesOut

            if let dotIndex = processToken.lastIndex(of: "."),
               let pid = Int32(processToken[processToken.index(after: dotIndex)...]) {
                result[pid] = total
            } else if let pid = pidByName[processToken] {
                result[pid] = total
            }
        }
        return result
    }

    static func collectANEDeviceInfo(cpuArchitecture: CPUArchitecture) -> SystemMonitor.ANEDeviceInfo? {
        guard cpuArchitecture != .intelLike else {
            return nil
        }
        guard let data = try? Process.runAndCapture("/usr/sbin/ioreg", ["-l", "-w0"]),
              let text = String(data: data, encoding: .utf8),
              text.localizedCaseInsensitiveContains("ANE")
        else {
            return nil
        }

        let npuCount = text.localizedCaseInsensitiveContains("ANEDevicePropertyNumANEs") ? 1 : 1
        let coreCount = 16
        let modelName = "Apple Neural Engine"
        let architecture = extractFirstMatch(in: text, pattern: #"ANEDevicePropertyTypeANEArchitectureTypeStr"="([^"]+)""#) ?? "h16g"
        let firmwareLoaded = text.localizedCaseInsensitiveContains(#""FirmwareLoaded" = Yes"#) || text.localizedCaseInsensitiveContains(#""FirmwareLoaded" = true"#)
        let aneBlock = extractFirstMatch(in: text, pattern: #"(?s)\+\-o H11ANE .*?\{(.*?)\n\s*\}"#) ?? text
        let currentPowerState = Int(extractFirstMatch(in: aneBlock, pattern: #""CurrentPowerState"=([0-9]+)"#) ?? "0") ?? 0
        let maxPowerState = Int(extractFirstMatch(in: aneBlock, pattern: #""MaxPowerState"=([0-9]+)"#) ?? "1") ?? 1
        let activeClientCount = max(text.components(separatedBy: "IOUserClientCreator").count - 1, 0)
        let capacityBytes = sysctlInt("hw.memsize").map { max($0, 1_073_741_824) } ?? 1_073_741_824
        return SystemMonitor.ANEDeviceInfo(
            modelName: modelName,
            npuCount: npuCount,
            coreCount: coreCount,
            capacityBytes: capacityBytes,
            architecture: architecture,
            firmwareLoaded: firmwareLoaded,
            currentPowerState: currentPowerState,
            maxPowerState: maxPowerState,
            activeClientCount: activeClientCount
        )
    }

    static func collectNPUState(
        previous: NPUState?,
        aneInfo: SystemMonitor.ANEDeviceInfo?,
        cpuUtilization: Double,
        gpuUtilization: Double,
        totalMemory: UInt64
    ) -> NPUState? {
        guard let aneInfo else { return nil }

        let usage = currentNeuralUsageTotals()
        let peakFootprint = max(previous?.peakNeuralFootprintBytes ?? 0, usage.intervalPeakBytes, usage.currentBytes, 1)
        let previousFootprint = previous?.neuralFootprintBytes ?? usage.currentBytes
        let deltaFootprint = usage.currentBytes >= previousFootprint ? usage.currentBytes - previousFootprint : previousFootprint - usage.currentBytes
        let footprintDeltaPercent = min(Double(deltaFootprint) / Double(max(peakFootprint, 1)) * 100, 100)
        let activity = min(
            max(
                3.0
                + cpuUtilization * 0.04
                + gpuUtilization * 0.05
                + footprintDeltaPercent * 0.08,
                0
            ),
            18
        )
        let historyCompute = shifted(previous?.historyCompute ?? Array(repeating: 0, count: 60), adding: activity)
        let historyFootprint = shifted(
            previous?.historyFootprint ?? Array(repeating: 0, count: 60),
            adding: min(Double(usage.currentBytes) / Double(max(peakFootprint, 1)) * 100, 100)
        )
        let historyMemoryPressure = shifted(
            previous?.historyMemoryPressure ?? Array(repeating: 0, count: 60),
            adding: min(Double(usage.currentBytes) / Double(max(totalMemory, 1)) * 100, 100)
        )

        return NPUState(
            id: "npu0",
            title: "NPU 0",
            subtitle: aneInfo.modelName,
            modelName: aneInfo.modelName,
            npuCount: aneInfo.npuCount,
            coreCount: aneInfo.coreCount,
            architecture: aneInfo.architecture,
            firmwareLoaded: aneInfo.firmwareLoaded,
            currentPowerState: aneInfo.currentPowerState,
            maxPowerState: aneInfo.maxPowerState,
            activeClientCount: aneInfo.activeClientCount,
            utilizationPercent: activity,
            neuralFootprintBytes: usage.currentBytes,
            peakNeuralFootprintBytes: peakFootprint,
            historyCompute: historyCompute,
            historyFootprint: historyFootprint,
            historyMemoryPressure: historyMemoryPressure
        )
    }

    static func collectGPUStates(previous: [GPUState], language: AppLanguage) -> [GPUState] {
        guard
            let profilerData = try? Process.runAndCapture("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-json"]),
            let profilerJSON = try? JSONSerialization.jsonObject(with: profilerData) as? [String: Any],
            let profilerItems = profilerJSON["SPDisplaysDataType"] as? [[String: Any]],
            let acceleratorData = try? Process.runAndCapture("/usr/sbin/ioreg", ["-r", "-d", "1", "-c", "IOAccelerator", "-a", "-l"]),
            let acceleratorArray = try? PropertyListSerialization.propertyList(from: acceleratorData, options: [], format: nil) as? [[String: Any]]
        else {
            return previous
        }

        let devices = MTLCopyAllDevices()
        let acceleratorByRegistryID = Dictionary(uniqueKeysWithValues: acceleratorArray.compactMap { entry -> (UInt64, [String: Any])? in
            guard let registryID = (entry["IORegistryEntryID"] as? NSNumber)?.uint64Value else { return nil }
            return (registryID, entry)
        })

        var next: [GPUState] = []
        let gpuCount = max(profilerItems.count, devices.count)

        for (index, device) in devices.enumerated() {
            let ioEntry = acceleratorByRegistryID[device.registryID]
            let matchedProfilerItem = profilerItems.first { item in
                let itemModel = item["sppci_model"] as? String ?? item["_name"] as? String ?? ""
                if itemModel.isEmpty { return false }
                return itemModel.localizedCaseInsensitiveContains(device.name) || device.name.localizedCaseInsensitiveContains(itemModel)
            } ?? profilerItems[safe: index]

            let model = matchedProfilerItem?["sppci_model"] as? String
                ?? matchedProfilerItem?["_name"] as? String
                ?? device.name
            let metalRaw = matchedProfilerItem?["spdisplays_mtlgpufamilysupport"] as? String ?? ""
            let metalVersion = resolvedMetalVersion(raw: metalRaw, device: device)
            let coreCount = Int(matchedProfilerItem?["sppci_cores"] as? String ?? "") ?? 0
            let gpuType = resolvedGPUType(device: device, profilerItem: matchedProfilerItem, language: language)

            let performance = ioEntry?["PerformanceStatistics"] as? [String: Any]
            let deviceUtil = (performance?["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
            let rendererUtil = (performance?["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0
            let tilerUtil = (performance?["Tiler Utilization %"] as? NSNumber)?.doubleValue ?? 0
            let inUseMemory = (performance?["In use system memory"] as? NSNumber)?.uint64Value ?? 0
            let allocatedMemory = (performance?["Alloc system memory"] as? NSNumber)?.uint64Value ?? 0
            let openGLVersion: String? = nil

            let id = "gpu\(index)"
            let previousState = previous.first(where: { $0.id == id })
            let historyOverall = shifted(previousState?.historyOverall ?? Array(repeating: 0, count: 60), adding: deviceUtil)
            let history3D = shifted(previousState?.history3D ?? Array(repeating: 0, count: 60), adding: rendererUtil)
            let historyTiler = shifted(previousState?.historyTiler ?? Array(repeating: 0, count: 60), adding: tilerUtil)
            let memoryPercent = allocatedMemory > 0 ? min(Double(inUseMemory) / Double(allocatedMemory) * 100, 100) : 0
            let memoryHistory = shifted(previousState?.memoryHistory ?? Array(repeating: 0, count: 60), adding: memoryPercent)

            next.append(GPUState(
                id: id,
                title: "GPU \(index)",
                subtitle: model,
                modelName: model,
                gpuCount: gpuCount,
                gpuType: gpuType,
                coreCount: coreCount,
                utilizationPercent: deviceUtil,
                rendererUtilizationPercent: rendererUtil,
                tilerUtilizationPercent: tilerUtil,
                sharedMemoryUsedBytes: inUseMemory,
                sharedMemoryAllocatedBytes: allocatedMemory,
                metalVersion: metalVersion,
                openGLVersion: openGLVersion,
                historyOverall: historyOverall,
                history3D: history3D,
                historyTiler: historyTiler,
                memoryHistory: memoryHistory
            ))
        }

        return next
    }

    static func collectStartupRows() -> StartupSnapshot {
        let uid = getuid()
        var disabledLaunchdByGroup: [String: Set<String>] = [:]
        disabledLaunchdByGroup["system"] = disabledLaunchdLabels(domain: "system")
        disabledLaunchdByGroup["gui/\(uid)"] = disabledLaunchdLabels(domain: "gui/\(uid)")

        let directories = [
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        ]

        var rows: [StartupRowSnapshot] = []
        if let loginItemNames = try? Process.runAndCapture("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the name of every login item"]),
           let namesString = String(data: loginItemNames, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !namesString.isEmpty
        {
            let names = namesString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows.append(contentsOf: names.map {
                StartupRowSnapshot(
                    id: "login-\($0)",
                    name: $0,
                    iconProgramPath: nil,
                    publisher: "登录项",
                    status: "已启用",
                    startupImpact: "未计算"
                )
            })
        }

        let fileManager = FileManager.default
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(entry)
                guard let data = fileManager.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else { continue }

                let label = plist["Label"] as? String ?? entry.replacingOccurrences(of: ".plist", with: "")
                let program = (plist["Program"] as? String)
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? ""
                let name = URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent.isEmpty
                    ? label
                    : URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent
                let publisher = program.isEmpty ? directoryLabel(directory) : URL(fileURLWithPath: program).deletingLastPathComponent().lastPathComponent
                let group = launchdGroupForStartupDirectory(directory)
                let labelDisabled = disabledLaunchdByGroup[group]?.contains(label) ?? false
                let plistDisabled = (plist["Disabled"] as? Bool) ?? false
                let enabled = !(plistDisabled || labelDisabled)
                let impact = directory.contains("Daemons") ? "高" : "未计算"

                let row = StartupRowSnapshot(
                    id: path,
                    name: name,
                    iconProgramPath: program.isEmpty ? nil : program,
                    publisher: publisher,
                    status: enabled ? "已启用" : "已禁用",
                    startupImpact: impact
                )
                if rows.contains(where: { $0.id == row.id || $0.name == row.name }) { continue }
                rows.append(row)
            }
        }

        return StartupSnapshot(
            disabledLaunchdByGroup: disabledLaunchdByGroup,
            rows: rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    static func collectServiceRows(uid: uid_t) -> [ServiceRowSnapshot] {
        let runtimeEntries = launchdRuntimeEntries(uid: uid)
        let metadataByKey = launchdPlistMetadata(uid: uid)
        var merged: [String: ServiceRowSnapshot] = [:]

        for entry in runtimeEntries {
            let key = serviceCompositeKey(label: entry.label, group: entry.group)
            let metadata = metadataByKey[key]
            let status = serviceStatusText(pid: entry.pid, stateToken: entry.stateToken, disabled: metadata?.disabled ?? false)
            merged[key] = ServiceRowSnapshot(
                id: key,
                name: metadata?.name ?? serviceNameFallback(label: entry.label),
                iconProgramPath: metadata?.program,
                pid: entry.pid,
                serviceDescription: metadata?.serviceDescription ?? entry.label,
                status: status,
                group: entry.group,
                label: entry.label
            )
        }

        for (key, metadata) in metadataByKey where merged[key] == nil {
            merged[key] = ServiceRowSnapshot(
                id: key,
                name: metadata.name,
                iconProgramPath: metadata.program,
                pid: nil,
                serviceDescription: metadata.serviceDescription,
                status: metadata.disabled ? "已禁用" : "未加载",
                group: metadata.group,
                label: metadata.label
            )
        }

        return merged.values.sorted { lhs, rhs in
            let nameCompare = lhs.name.localizedStandardCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            let labelCompare = lhs.label.localizedStandardCompare(rhs.label)
            if labelCompare != .orderedSame {
                return labelCompare == .orderedAscending
            }
            return lhs.group.localizedStandardCompare(rhs.group) == .orderedAscending
        }
    }

    static func rootWholeDiskIdentifierFromMountedRoot() -> String? {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        let source = withUnsafePointer(to: &stats.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { pointer in
                String(cString: pointer)
            }
        }
        return wholeDiskIdentifier(fromDevicePath: source)
    }

    static func detectRootWholeDiskIdentifier() -> String? {
        if let data = try? Process.runAndCapture("/usr/sbin/diskutil", ["info", "-plist", "/"]),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        {
            if let physicalStores = plist["APFSPhysicalStores"] as? [[String: Any]] {
                for store in physicalStores {
                    if let physicalStore = store["APFSPhysicalStore"] as? String ?? store["DeviceIdentifier"] as? String,
                       let wholeDisk = wholeDiskIdentifier(fromDevicePath: "/dev/\(physicalStore)")
                    {
                        return wholeDisk
                    }
                }
            }

            if let parentWholeDisk = plist["ParentWholeDisk"] as? String,
               let wholeDisk = wholeDiskIdentifier(fromDevicePath: "/dev/\(parentWholeDisk)")
            {
                return wholeDisk
            }
        }

        return rootWholeDiskIdentifierFromMountedRoot()
    }

    static func loadHardwarePortMap() -> [String: String] {
        guard let data = try? Process.runAndCapture("/usr/sbin/networksetup", ["-listallhardwareports"]),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        var result: [String: String] = [:]
        var currentPort: String?

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") {
                currentPort = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), let currentPort {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if !device.isEmpty {
                    result[device] = currentPort
                }
            }
        }

        return result
    }

    static func disabledLaunchdLabels(domain: String) -> Set<String> {
        guard let data = try? Process.runAndCapture("/bin/launchctl", ["print-disabled", domain]),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var labels: Set<String> = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), trimmed.contains("=> disabled") else { continue }
            if let end = trimmed.dropFirst().firstIndex(of: "\"") {
                labels.insert(String(trimmed.dropFirst()[..<end]))
            }
        }
        return labels
    }

    static func launchdRuntimeEntries(uid: uid_t) -> [SystemMonitor.LaunchdRuntimeEntry] {
        let systemEntries = parseLaunchctlPrintDomain("system", group: "system")
        let guiEntries = parseLaunchctlPrintDomain("gui/\(uid)", group: "gui/\(uid)")
        var merged: [String: SystemMonitor.LaunchdRuntimeEntry] = [:]

        for entry in systemEntries + guiEntries {
            guard shouldIncludeServiceLabel(entry.label) else { continue }
            let key = serviceCompositeKey(label: entry.label, group: entry.group)
            merged[key] = entry
        }

        return Array(merged.values)
    }

    static func parseLaunchctlPrintDomain(_ domain: String, group: String) -> [SystemMonitor.LaunchdRuntimeEntry] {
        guard let data = try? Process.runAndCapture("/bin/launchctl", ["print", domain]),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var result: [SystemMonitor.LaunchdRuntimeEntry] = []
        var inServicesBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "services = {" {
                inServicesBlock = true
                continue
            }
            if inServicesBlock, trimmed == "}" {
                break
            }
            guard inServicesBlock else { continue }

            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { continue }

            let label = String(parts.last!)
            guard shouldIncludeServiceLabel(label) else { continue }

            let pidToken = String(parts[0])
            let stateToken = String(parts[1])
            let pid: Int32?
            if let value = Int32(pidToken), value > 0 {
                pid = value
            } else {
                pid = nil
            }

            result.append(
                SystemMonitor.LaunchdRuntimeEntry(
                    label: label,
                    pid: pid,
                    stateToken: stateToken,
                    group: group
                )
            )
        }

        return result
    }

    static func launchdPlistMetadata(uid: uid_t) -> [String: LaunchdPlistMetadataSnapshot] {
        let directories = [
            "/System/Library/LaunchDaemons",
            "/System/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        ]

        let fileManager = FileManager.default
        var result: [String: LaunchdPlistMetadataSnapshot] = [:]

        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(entry)
                guard let data = fileManager.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else {
                    continue
                }

                let label = plist["Label"] as? String ?? entry.replacingOccurrences(of: ".plist", with: "")
                guard shouldIncludeServiceLabel(label) else { continue }

                let program = (plist["Program"] as? String)
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? ""
                let executableName = serviceExecutableName(fromProgramPath: program)
                let name = executableName.isEmpty ? serviceNameFallback(label: label) : executableName
                let description = serviceDescriptionText(label: label, program: program, plist: plist)
                let disabled = (plist["Disabled"] as? Bool) ?? false
                let group = launchdGroup(forDirectory: directory, uid: uid)
                let key = serviceCompositeKey(label: label, group: group)

                result[key] = LaunchdPlistMetadataSnapshot(
                    label: label,
                    name: name,
                    program: program.isEmpty ? nil : program,
                    serviceDescription: description,
                    group: group,
                    disabled: disabled
                )
            }
        }

        return result
    }

    struct LaunchdPlistMetadataSnapshot {
        let label: String
        let name: String
        let program: String?
        let serviceDescription: String
        let group: String
        let disabled: Bool
    }

    static func launchdGroup(forDirectory directory: String, uid: uid_t) -> String {
        if directory.contains("LaunchDaemons") {
            return "system"
        }
        return "gui/\(uid)"
    }

    static func launchdGroupForStartupDirectory(_ directory: String) -> String {
        if directory.contains("LaunchDaemons") {
            return "system"
        }
        return "gui/\(getuid())"
    }

    static func directoryLabel(_ path: String) -> String {
        if path.contains("LaunchDaemons") { return "系统守护进程" }
        if path.contains("/Library/LaunchAgents") { return "系统代理" }
        return "用户代理"
    }

    static func serviceCompositeKey(label: String, group: String) -> String {
        "\(group)|\(label)"
    }

    static func shouldIncludeServiceLabel(_ label: String) -> Bool {
        guard !label.isEmpty else { return false }
        if label.hasPrefix("application.") { return false }
        if label.hasPrefix("com.apple.xpc.") { return false }
        return true
    }

    static func serviceExecutableName(fromProgramPath program: String) -> String {
        guard !program.isEmpty else { return "" }
        if program.hasSuffix(".app") {
            return URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent
        }

        let nsPath = program as NSString
        let range = nsPath.range(of: ".app/")
        if range.location != NSNotFound, let swiftRange = Range(range, in: program) {
            let appPath = String(program[..<swiftRange.upperBound]).dropLast()
            let appName = URL(fileURLWithPath: String(appPath)).deletingPathExtension().lastPathComponent
            if !appName.isEmpty {
                return appName
            }
        }

        return URL(fileURLWithPath: program).lastPathComponent
    }

    static func serviceNameFallback(label: String) -> String {
        let parts = label.split(separator: ".")
        if let last = parts.last, !last.isEmpty {
            return String(last)
        }
        return label
    }

    static func serviceDescriptionText(label: String, program: String, plist: [String: Any]) -> String {
        if let bundleName = plist["CFBundleDisplayName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        if !program.isEmpty {
            let executable = serviceExecutableName(fromProgramPath: program)
            if !executable.isEmpty {
                return "\(label) (\(executable))"
            }
        }
        if let machServices = plist["MachServices"] as? [String: Any], !machServices.isEmpty {
            return "\(label) (Mach Service)"
        }
        return label
    }

    static func serviceStatusText(pid: Int32?, stateToken: String, disabled: Bool) -> String {
        if disabled {
            return "已禁用"
        }
        if pid != nil {
            return "正在运行"
        }
        if stateToken == "0" {
            return "已停止"
        }
        if stateToken == "-" || stateToken.hasPrefix("(") {
            return "按需"
        }
        return "已加载"
    }

    static func currentNeuralUsageTotals() -> SystemMonitor.NeuralUsageTotals {
        let pids = listPIDs()
        var total: UInt64 = 0
        var peak: UInt64 = 0
        for pid in pids where pid > 0 {
            var usage = rusage_info_current()
            let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
                }
            }
            if usageResult == 0 {
                total += usage.ri_neural_footprint
                peak = max(peak, usage.ri_interval_max_neural_footprint)
            }
        }
        return SystemMonitor.NeuralUsageTotals(currentBytes: total, intervalPeakBytes: peak)
    }

    static func listPIDs() -> [Int32] {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }
        let count = bufferSize / Int32(MemoryLayout<pid_t>.size)
        var buffer = Array(repeating: pid_t(0), count: Int(count))
        let bytes = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return buffer.filter { $0 > 0 }
    }

    static func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }

    static func sysctlInt(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func shifted(_ values: [Double], adding value: Double) -> [Double] {
        var history = values
        if history.isEmpty {
            history = Array(repeating: 0, count: 60)
        }
        history.append(value)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
        return history
    }

    static func metalLabel(from raw: String) -> String {
        switch raw {
        case "spdisplays_metal4":
            return "Metal 4"
        case "spdisplays_metal3":
            return "Metal 3"
        case "spdisplays_metal2":
            return "Metal 2"
        default:
            return raw.isEmpty ? "Metal" : raw
        }
    }

    static func resolvedMetalVersion(raw: String, device: any MTLDevice) -> String {
        if !raw.isEmpty {
            return metalLabel(from: raw)
        }
        if #available(macOS 26.0, *) {
            if device.supportsFamily(.metal4) {
                return "Metal 4"
            }
        }
        if #available(macOS 13.0, *) {
            if device.supportsFamily(.metal3) {
                return "Metal 3"
            }
        }
        return "Metal"
    }

    static func resolvedGPUType(device: any MTLDevice, profilerItem: [String: Any]?, language: AppLanguage) -> String {
        if #available(macOS 10.15, *) {
            switch device.location {
            case .builtIn:
                return language.text("内建", "Internal")
            case .external:
                return language.text("外建", "External")
            default:
                break
            }
        }

        if let bus = profilerItem?["sppci_bus"] as? String {
            return bus == "spdisplays_builtin"
                ? language.text("内建", "Internal")
                : language.text("外建", "External")
        }

        if device.isRemovable {
            return language.text("外建", "External")
        }
        return language.text("内建", "Internal")
    }

    static func wholeDiskIdentifier(fromDevicePath devicePath: String) -> String? {
        guard devicePath.hasPrefix("/dev/disk") else { return nil }
        let raw = String(devicePath.dropFirst("/dev/".count))
        let prefix = "disk"
        guard raw.hasPrefix(prefix) else { return nil }

        var result = prefix
        var index = raw.index(raw.startIndex, offsetBy: prefix.count)
        while index < raw.endIndex, raw[index].isNumber {
            result.append(raw[index])
            index = raw.index(after: index)
        }
        return result.count > prefix.count ? result : raw
    }
}
