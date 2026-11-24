//
//  PerformanceProfile.swift
//  Miro
//
//  Per-game core allocation on Apple silicon:
//   • 효율 — the whole game process tree is put in Darwin background (E-cores only, low priority).
//            Applied live with setpriority(), so it can be switched while the game runs.
//   • 기본 — macOS decides.
//   • 성능 — launched through `taskpolicy -t 0 -l 0` (no timer coalescing / best throughput tier)
//            with user-interactive QoS, so the scheduler prefers P-cores.
//

import Darwin
import Foundation

enum PerformanceProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case efficiency, balanced, performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .efficiency: return "효율"
        case .balanced: return "기본"
        case .performance: return "성능"
        }
    }

    var subtitle: String {
        switch self {
        case .efficiency: return "저전력 코어만"
        case .balanced: return "자동 분배"
        case .performance: return "고성능 코어 우선"
        }
    }

    var symbol: String {
        switch self {
        case .efficiency: return "leaf.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .performance: return "bolt.fill"
        }
    }

    var detail: String {
        switch self {
        case .efficiency:
            return "게임을 저전력 코어(E코어)에서만 낮은 우선순위로 돌려요. 발열·팬 소음이 크게 줄고 2D 게임에 알맞아요. 3D 게임은 느려질 수 있어요."
        case .balanced:
            return "macOS가 알아서 코어를 나눠요."
        case .performance:
            return "고성능 코어(P코어)를 우선 쓰고 타이머 지연을 꺼서 반응성을 높여요. 발열이 늘어요."
        }
    }

    var qualityOfService: QualityOfService {
        self == .performance ? .userInteractive : .userInitiated
    }

    /// `(executable, argumentPrefix)` wrapping the wine binary for this profile
    func wrap(_ executable: URL) -> (URL, [String]) {
        guard self == .performance else { return (executable, []) }
        return (URL(fileURLWithPath: "/usr/sbin/taskpolicy"),
                ["-t", "0", "-l", "0", executable.path(percentEncoded: false)])
    }
}

/// Process-tree helpers for applying a profile to a running game
enum ProcessTree {
    /// `root` and every process below it
    static func family(of root: pid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [root] }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return [root] }

        var children: [pid_t: [pid_t]] = [:]
        for process in processes.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            children[process.kp_eproc.e_ppid, default: []].append(process.kp_proc.p_pid)
        }
        var result: [pid_t] = []
        var queue = [root]
        while let pid = queue.popLast() {
            guard !result.contains(pid) else { continue }
            result.append(pid)
            queue.append(contentsOf: children[pid] ?? [])
        }
        return result
    }

    /// Moves a process tree into (or out of) Darwin background — E-cores only, like `taskpolicy -b/-B -p`.
    /// Children spawned later inherit the state.
    @discardableResult
    static func setBackground(_ background: Bool, root: pid_t) -> Int {
        let prioDarwinProcess: Int32 = 4        // PRIO_DARWIN_PROCESS
        let prioDarwinBackground: Int32 = 0x1000 // PRIO_DARWIN_BG
        var changed = 0
        for pid in family(of: root) where pid > 1 {
            if setpriority(prioDarwinProcess, id_t(pid), background ? prioDarwinBackground : 0) == 0 {
                changed += 1
            }
        }
        return changed
    }
}

/// Wine's Retina mode lives in the prefix registry (HKCU\Software\Wine\Mac Driver\RetinaMode)
enum RetinaSetting {
    /// Current value from user.reg (nil = never set → Wine's default, off)
    static func current(in bottle: URL) -> Bool? {
        guard let data = try? Data(contentsOf: bottle.appending(path: "user.reg")) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let section = text.range(of: "[Software\\\\Wine\\\\Mac Driver]") else { return nil }
        let end = text.range(of: "\n[", range: section.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        guard let key = text.range(of: "\"RetinaMode\"=\"", range: section.upperBound..<end) else { return nil }
        return text[key.upperBound...].first == "y"
    }
}
