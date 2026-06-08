import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum RuntimeSecurityRiskLevel: String, Equatable, CaseIterable {
    case normal
    case development
    case elevated
    case compromised

    var localizedTitle: String {
        switch self {
        case .normal:
            return "Normal"
        case .development:
            return "Development"
        case .elevated:
            return "Erhöht"
        case .compromised:
            return "Kompromittiert"
        }
    }
}

enum RuntimeSecurityFindingSeverity: String, Equatable, CaseIterable {
    case info
    case warning
    case critical

    var localizedTitle: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warnung"
        case .critical:
            return "Kritisch"
        }
    }
}

struct RuntimeSecurityFinding: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: RuntimeSecurityFindingSeverity
}

struct RuntimeSecuritySnapshot: Equatable {
    let generatedAt: Date
    let isSimulator: Bool
    let isMacRuntime: Bool
    let isDebugBuild: Bool
    let isDebuggerAttached: Bool
    let jailbreakSignals: [String]
    let hasInjectedDynamicLibraries: Bool

    var isDevelopmentRuntime: Bool {
        isSimulator || isMacRuntime || isDebugBuild
    }

    var isProductionLikeRuntime: Bool {
        isDevelopmentRuntime == false
    }

    var findings: [RuntimeSecurityFinding] {
        var result: [RuntimeSecurityFinding] = []

        if isSimulator {
            result.append(RuntimeSecurityFinding(
                id: "simulator",
                title: "Simulator/Testlaufzeit",
                detail: "Die App läuft im Simulator. Das ist für Entwicklung ok, aber keine produktive Sicherheitsbewertung.",
                severity: .info
            ))
        }

        if isMacRuntime {
            result.append(RuntimeSecurityFinding(
                id: "mac-runtime",
                title: "Mac-/Catalyst-Testlaufzeit",
                detail: "Die App läuft in einer Mac-Testumgebung. iOS-Jailbreak-Pfade werden hier bewusst nicht als kompromittiertes iPhone bewertet.",
                severity: .info
            ))
        }

        if isDebugBuild {
            result.append(RuntimeSecurityFinding(
                id: "debug-build",
                title: "Debug-Build",
                detail: "Debug-Builds enthalten Diagnosepfade und sind nicht für produktive Verteilung gedacht.",
                severity: .info
            ))
        }

        if isDebuggerAttached {
            result.append(RuntimeSecurityFinding(
                id: "debugger-attached",
                title: isDevelopmentRuntime ? "Debugger im Entwicklungsmodus" : "Debugger erkannt",
                detail: isDevelopmentRuntime ? "Ein Debugger ist verbunden. Das ist bei Xcode-Tests erwartbar und wird als Development-Risiko klassifiziert." : "Ein Debugger ist am Prozess angemeldet. Das kann Speicheranalyse und Runtime-Manipulation erleichtern.",
                severity: isDevelopmentRuntime ? .warning : .critical
            ))
        }

        if hasInjectedDynamicLibraries {
            result.append(RuntimeSecurityFinding(
                id: "dyld-injection",
                title: isDevelopmentRuntime ? "DYLD-Hinweis im Testmodus" : "DYLD Injection Indikator",
                detail: isDevelopmentRuntime ? "Es gibt Hinweise auf dynamische Library-Umgebung im Testlauf. In Release/Production wäre das kritisch." : "Es gibt Hinweise auf injizierte Dynamic Libraries. Das ist für eine sichere Laufzeit kritisch.",
                severity: isDevelopmentRuntime ? .warning : .critical
            ))
        }

        for signal in jailbreakSignals {
            result.append(RuntimeSecurityFinding(
                id: "jailbreak-\(signal)",
                title: "Jailbreak-Indikator",
                detail: signal,
                severity: .critical
            ))
        }

        if result.isEmpty {
            result.append(RuntimeSecurityFinding(
                id: "baseline-ok",
                title: "Keine kritischen Laufzeitindikatoren",
                detail: "Es wurden keine Debugger-, Jailbreak- oder Injection-Indikatoren erkannt.",
                severity: .info
            ))
        }

        return result
    }

    var riskLevel: RuntimeSecurityRiskLevel {
        if isProductionLikeRuntime && (isDebuggerAttached || hasInjectedDynamicLibraries || jailbreakSignals.isEmpty == false) {
            return .compromised
        }
        if isDevelopmentRuntime {
            return .development
        }
        if hasInjectedDynamicLibraries || isDebuggerAttached || jailbreakSignals.isEmpty == false {
            return .elevated
        }
        return .normal
    }

    var shouldBlockSensitiveTransport: Bool {
        isProductionLikeRuntime && (isDebuggerAttached || hasInjectedDynamicLibraries || jailbreakSignals.isEmpty == false)
    }

    var localizedSummary: String {
        switch riskLevel {
        case .normal:
            return "Laufzeit normal"
        case .development:
            return "Entwicklungs-/Testlaufzeit"
        case .elevated:
            return "Erhöhtes Laufzeitrisiko"
        case .compromised:
            return "Kompromittierungsindikatoren erkannt"
        }
    }
}

enum RuntimeSecurityEvaluator {
    static func assess(now: Date = Date()) -> RuntimeSecuritySnapshot {
        let simulator = isRunningInSimulator
        let macRuntime = isRunningOnMacRuntime
        let debug = isDebugBuild
        return RuntimeSecuritySnapshot(
            generatedAt: now,
            isSimulator: simulator,
            isMacRuntime: macRuntime,
            isDebugBuild: debug,
            isDebuggerAttached: isDebuggerAttached(),
            jailbreakSignals: jailbreakSignals(isSimulator: simulator, isMacRuntime: macRuntime),
            hasInjectedDynamicLibraries: hasInjectedDynamicLibraries()
        )
    }

    private static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static var isRunningOnMacRuntime: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
        }
        return false
        #endif
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static func isDebuggerAttached() -> Bool {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else {
            return false
        }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #else
        return false
        #endif
    }

    private static func hasInjectedDynamicLibraries() -> Bool {
        ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"]?.isEmpty == false
    }

    private static func jailbreakSignals(isSimulator: Bool, isMacRuntime: Bool) -> [String] {
        if isSimulator || isMacRuntime || isDebugBuild {
            return []
        }

        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt",
            "/private/var/stash"
        ]

        var signals: [String] = suspiciousPaths.filter { FileManager.default.fileExists(atPath: $0) }

        let probeURL = URL(fileURLWithPath: "/private/privatechat-jailbreak-probe.txt")
        do {
            try "probe".write(to: probeURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            signals.append("Schreibzugriff auf /private möglich")
        } catch {
            // Erwarteter Pfad auf nicht kompromittierten Geräten.
        }

        return signals
    }
}
