import SwiftUI
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var isChinese: Bool { self == .chinese }

    func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    func translateImpact(_ value: String) -> String {
        switch value {
        case "非常高": return "Very high"
        case "高": return "High"
        case "中": return "Moderate"
        case "低": return "Low"
        case "非常低": return "Very low"
        default: return value
        }
    }

    func translateProcessSectionTitle(_ title: String) -> String {
        guard !isChinese else { return title }
        if title.hasPrefix("应用 (") {
            return title.replacingOccurrences(of: "应用", with: "Apps")
        }
        if title.hasPrefix("后台进程 (") {
            return title.replacingOccurrences(of: "后台进程", with: "Background")
        }
        return title
    }

    func translateStartupStatus(_ value: String) -> String {
        switch value {
        case "已启用": return "Enabled"
        case "已禁用": return "Disabled"
        default: return value
        }
    }

    func translateStartupImpact(_ value: String) -> String {
        switch value {
        case "高": return "High"
        case "未计算": return "N/A"
        default: return translateImpact(value)
        }
    }

    func translateDirectoryLabel(_ value: String) -> String {
        switch value {
        case "登录项": return "Login item"
        case "系统守护进程": return "System daemon"
        case "系统代理": return "System agent"
        case "用户代理": return "User agent"
        default: return value
        }
    }

    func translateServiceStatus(_ value: String) -> String {
        switch value {
        case "正在运行": return "Running"
        case "按需": return "On demand"
        case "已加载": return "Loaded"
        case "已停止": return "Stopped"
        case "未加载": return "Not loaded"
        case "已禁用": return "Disabled"
        default: return value
        }
    }

    func translateProcessStatus(_ value: String) -> String {
        switch value {
        case "正在创建": return "Starting"
        case "正在运行": return "Running"
        case "正在睡眠": return "Sleeping"
        case "已停止": return "Stopped"
        case "僵尸": return "Zombie"
        case "未知": return "Unknown"
        default: return value
        }
    }

    func translatePlatform(_ value: String) -> String {
        switch value {
        case "64位": return "64-bit"
        case "32位": return "32-bit"
        default: return value
        }
    }

    func translateDiskKind(_ value: String) -> String {
        switch value {
        case "可移动": return "Removable"
        case "内建": return "Internal"
        case "外建": return "External"
        default: return value
        }
    }

    func translateNetworkMedium(_ value: String) -> String {
        switch value {
        case "以太网": return "Ethernet"
        case "VPN隧道": return "VPN tunnel"
        case "虚拟网络": return "Virtual network"
        case "网络接口": return "Network interface"
        default: return value
        }
    }

    func translateDiskTitle(_ value: String) -> String {
        guard !isChinese else { return value }
        if value.hasPrefix("磁盘 ") {
            return value.replacingOccurrences(of: "磁盘", with: "Disk")
        }
        return value
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .chinese
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum TaskTab: String, CaseIterable, Identifiable {
    case processes
    case performance
    case history
    case startup
    case users
    case details
    case services

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .processes: language.text("进程", "Processes")
        case .performance: language.text("性能", "Performance")
        case .history: language.text("应用历史记录", "App history")
        case .startup: language.text("启动", "Startup")
        case .users: language.text("用户", "Users")
        case .details: language.text("详细信息", "Details")
        case .services: language.text("服务", "Services")
        }
    }
}

enum RefreshSpeedOption: String, CaseIterable, Identifiable {
    case high
    case normal
    case low
    case paused

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .high: language.text("高(H)", "High(H)")
        case .normal: language.text("正常(N)", "Normal(N)")
        case .low: language.text("低(L)", "Low(L)")
        case .paused: language.text("已暂停(P)", "Paused(P)")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .high: 0.5
        case .normal: 1.0
        case .low: 2.5
        case .paused: nil
        }
    }
}

enum ProcessSortKey {
    case name
    case status
    case cpu
    case memory
    case disk
    case network
    case power
    case trend
}

enum ProcessResourceDisplayMode {
    case value
    case percent
}

enum ProcessPriorityPreset: CaseIterable {
    case veryLow
    case low
    case normal
    case high
    case realtime

    var niceValue: Int32 {
        switch self {
        case .veryLow: 20
        case .low: 10
        case .normal: 0
        case .high: -5
        case .realtime: -10
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .veryLow: language.text("低", "Low")
        case .low: language.text("低于正常", "Below normal")
        case .normal: language.text("正常", "Normal")
        case .high: language.text("高于正常", "Above normal")
        case .realtime: language.text("高", "High")
        }
    }
}

enum PerfSelection: Hashable, Identifiable {
    case cpu
    case memory
    case disk(String)
    case network(String)
    case npu(String)
    case gpu(String)

    var id: String {
        switch self {
        case .cpu:
            "cpu"
        case .memory:
            "memory"
        case .disk(let diskID):
            "disk-\(diskID)"
        case .network(let interface):
            "network-\(interface)"
        case .npu(let npuID):
            "npu-\(npuID)"
        case .gpu(let gpuID):
            "gpu-\(gpuID)"
        }
    }
}

enum PerformanceViewMode {
    case full
    case summary
    case detailSummary
}

enum CPUGraphMode {
    case logicalProcessors
    case overallUtilization
}

enum GPUGraphLayoutMode {
    case singleEngine
    case multiEngine
}

enum GPUGraphKind: String, CaseIterable, Identifiable {
    case overall = "Overall"
    case threeD = "3D"
    case tilerCopy = "Tiler"

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .overall: language.text("总体", "Overall")
        case .threeD: "3D"
        case .tilerCopy: language.text("Tiler/Copy", "Tiler/Copy")
        }
    }
}

struct ProcessRowData: Identifiable {
    let pid: Int32
    let name: String
    let icon: NSImage?
    let path: String
    let isApp: Bool
    let isParent: Bool
    let parentPID: Int32?
    let childCount: Int
    let cpuPercent: Double
    let memoryBytes: UInt64
    let diskBytesPerSecond: UInt64
    let networkBytesPerSecond: UInt64
    let networkText: String
    let powerImpact: String
    let trend: String
    let threadCount: Int
    let openFiles: Int

    var id: Int32 { pid }
}

struct ProcessSectionData: Identifiable {
    let title: String
    let rows: [ProcessRowData]
    let id = UUID()
}

struct UserPageSectionData: Identifiable {
    let id = UUID()
    let userName: String
    let rows: [ProcessRowData]
}

struct AppHistoryRowData: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let path: String
    let cpuTime: String
    let cpuSeconds: Double
    let network: String
    let networkBytes: UInt64
    let meteredNetwork: String
    let meteredNetworkBytes: UInt64
}

struct StartupItemRowData: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let publisher: String
    let status: String
    let startupImpact: String
}

struct ServiceRowData: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let pid: Int32?
    let serviceDescription: String
    let status: String
    let group: String
    let label: String
}

struct DetailProcessRowData: Identifiable {
    let id: Int32
    let name: String
    let icon: NSImage?
    let pid: Int32
    let status: String
    let userName: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let platform: String
}

struct CPUState {
    var modelName: String = "Apple Silicon"
    var utilizationPercent: Double = 0
    var speedText: String = "--"
    var baseSpeedText: String = "--"
    var performanceCoreSpeedText: String = "--"
    var efficiencyCoreSpeedText: String = "--"
    var logicalCores: Int = 0
    var physicalCores: Int = 0
    var processCount: Int = 0
    var threadCount: Int = 0
    var openFilesCount: Int = 0
    var uptimeText: String = "0:00:00:00"
    var history: [Double] = Array(repeating: 0, count: 60)
    var coreHistories: [[Double]] = []
}

struct MemoryState {
    var totalBytes: UInt64 = 0
    var usedBytes: UInt64 = 0
    var availableBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var cachedBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var appMemoryBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var historyPercent: [Double] = Array(repeating: 0, count: 60)
    var historyUsedBytes: [Double] = Array(repeating: 0, count: 60)
    var chartCeilingBytes: Double = 1
}

struct DiskState: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var kindLabel: String
    var modelName: String
    var capacityBytes: UInt64
    var availableBytes: UInt64
    var isSystemDisk: Bool
    var activityPercent: Double
    var responseTimeMs: Double
    var readBytesPerSecond: UInt64
    var writeBytesPerSecond: UInt64
    var activityHistory: [Double]
    var transferHistory: [Double]
    var transferChartCeilingBytesPerSecond: Double
}

struct NetworkState: Identifiable {
    let id: String
    var displayName: String
    var subtitle: String
    var interfaceName: String
    var ipv4: String
    var ipv6: String
    var sendBytesPerSecond: UInt64
    var receiveBytesPerSecond: UInt64
    var totalSendBytes: UInt64
    var totalReceiveBytes: UInt64
    var packetsSent: UInt64
    var packetsReceived: UInt64
    var multicastSent: UInt64
    var multicastReceived: UInt64
    var errorsIn: UInt64
    var errorsOut: UInt64
    var dropsIn: UInt64
    var dropsOut: UInt64
    var mtu: UInt32
    var linkSpeedText: String
    var statusText: String
    var totalHistory: [Double]
    var detailHistory: [Double]
    var chartCeilingBytesPerSecond: Double
}

struct GPUState: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var modelName: String
    var gpuCount: Int
    var gpuType: String
    var coreCount: Int
    var utilizationPercent: Double
    var rendererUtilizationPercent: Double
    var tilerUtilizationPercent: Double
    var sharedMemoryUsedBytes: UInt64
    var sharedMemoryAllocatedBytes: UInt64
    var metalVersion: String
    var openGLVersion: String?
    var historyOverall: [Double]
    var history3D: [Double]
    var historyTiler: [Double]
    var memoryHistory: [Double]
}

struct NPUState: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var modelName: String
    var npuCount: Int
    var coreCount: Int
    var architecture: String
    var firmwareLoaded: Bool
    var currentPowerState: Int
    var maxPowerState: Int
    var activeClientCount: Int
    var utilizationPercent: Double
    var neuralFootprintBytes: UInt64
    var peakNeuralFootprintBytes: UInt64
    var historyCompute: [Double]
    var historyFootprint: [Double]
    var historyMemoryPressure: [Double]
}

struct PerfSidebarItem: Identifiable {
    let id: PerfSelection
    let title: String
    let subtitle: String
    let tertiary: String?
    let accent: Color
    let sparkline: [Double]
    let selectedFill: Color
}

struct DetailMetric: Identifiable {
    let label: String
    let value: String
    var prominent: Bool = false
    let id = UUID()
}

struct InfoPair: Identifiable {
    let label: String
    let value: String
    let id = UUID()
}

enum DisplayFormat {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func percentWithPrecision(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    static func frequency(_ hz: UInt64?) -> String {
        guard let hz, hz > 0 else { return "--" }
        return String(format: "%.2f GHz", Double(hz) / 1_000_000_000)
    }

    static func bytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func decimalBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func memory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    static func throughput(_ bytesPerSecond: UInt64) -> String {
        if bytesPerSecond == 0 {
            return "0 KB/秒"
        }
        let kb = Double(bytesPerSecond) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB/秒", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB/秒", mb)
    }

    static func networkRate(_ bytesPerSecond: UInt64) -> String {
        if bytesPerSecond == 0 {
            return "0 Kbps"
        }
        let kilobits = Double(bytesPerSecond) * 8 / 1000
        if kilobits < 1000 {
            return String(format: "%.1f Kbps", kilobits)
        }
        return String(format: "%.2f Mbps", kilobits / 1000)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, secs)
    }

    static func impactLabel(cpuPercent: Double) -> String {
        switch cpuPercent {
        case 30...:
            return "非常高"
        case 15..<30:
            return "高"
        case 5..<15:
            return "中"
        case 1..<5:
            return "低"
        default:
            return "非常低"
        }
    }

    static func impactLabel(cpuPercent: Double, language: AppLanguage) -> String {
        language.translateImpact(impactLabel(cpuPercent: cpuPercent))
    }
}
