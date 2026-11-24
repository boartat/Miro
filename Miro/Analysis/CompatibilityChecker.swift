//
//  CompatibilityChecker.swift
//  Miro
//
//  Static check before launch: which DLLs does the game import, and which of them are
//  bundled, installed in the prefix, provided by Wine, or missing?
//

import Foundation

struct DLLCheck: Identifiable, Hashable, Sendable {
    enum State: Int, Sendable {
        case missing = 0, builtin, installed, bundled

        var label: String {
            switch self {
            case .missing: return "없음"
            case .builtin: return "Wine 내장 대체"
            case .installed: return "설치됨"
            case .bundled: return "게임 폴더에 있음"
            }
        }
    }

    var id: String { name }
    let name: String
    let state: State
    let dependencyID: String?
}

struct CompatibilityReport: Sendable {
    var info: PEInfo?
    var engine = EngineInfo()
    /// DLLs worth showing (runtime libraries + anything missing)
    var dlls: [DLLCheck] = []
    /// Not yet installed packages this game is likely to need
    var recommendedIDs: [String] = []
    /// RPG Maker RTP packages that may be required
    var rtpIDs: [String] = []

    var missing: [DLLCheck] { dlls.filter { $0.state == .missing } }
}

enum CompatibilityChecker {
    static func check(game: Game, installed: Set<String>) -> CompatibilityReport {
        var report = CompatibilityReport()
        report.engine = EngineDetector.detect(executable: game.executableURL)
        guard let info = PEInspector.inspect(game.executableURL) else { return report }
        report.info = info

        let folder = game.folderURL
        let folderFiles = Dictionary(
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
                .map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let builtinFolder = MiroPaths.wineFolder.appending(path: "lib/wine")
            .appending(path: info.arch == .x86 ? "i386-windows" : "x86_64-windows")
        let systemFolder = MiroPaths.driveC.appending(path: "windows")
            .appending(path: info.arch == .x86 ? "syswow64" : "system32")
        // Without a readable Wine install we can't tell, so never claim a system DLL is missing
        let canJudge = builtinFolder.fileExists
        // API-set names (api-ms-win-*) are resolved through Wine's apiset schema, not files
        let apisetSchema = try? Data(contentsOf: builtinFolder.appending(path: "apisetschema.dll"), options: .alwaysMapped)
        func providedByWindows(_ dll: String) -> Bool {
            if !canJudge || builtinFolder.appending(path: dll).fileExists || systemFolder.appending(path: dll).fileExists {
                return true
            }
            if isAPISet(dll) {
                guard let apisetSchema else { return true }
                return apisetSchema.range(of: Data(apisetKey(dll).utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })) != nil
            }
            return false
        }

        // Imports of the exe, of every DLL shipped next to it (Unity loads GameAssembly.dll at runtime)
        // and one level of imports of those DLLs
        var imports = info.imports
        var delayed = Set(info.delayImports)
        func merge(_ pe: PEInfo) {
            for dll in pe.imports where !imports.contains(dll) { imports.append(dll) }
            delayed.formUnion(pe.delayImports)
        }
        let shippedDLLs = folderFiles.keys.filter { $0.hasSuffix(".dll") }.sorted().prefix(80)
        for dll in Set(shippedDLLs).union(info.imports.filter { folderFiles[$0] != nil }) {
            if let nested = PEInspector.inspect(folder.appending(path: folderFiles[dll]!)) { merge(nested) }
            if imports.count > 600 { break }
        }
        // Delay-loaded DLLs are only needed when used (often with a fallback): check them, never call them missing
        let delayOnly = delayed.subtracting(imports)
        imports.append(contentsOf: delayOnly.sorted())

        var checks: [DLLCheck] = []
        var recommended: [String] = []
        func recommend(_ id: String) {
            if !installed.contains(id) && !recommended.contains(id) { recommended.append(id) }
        }

        for dll in imports {
            let dependency = DependencyCatalog.provider(of: dll)
            let state: DLLCheck.State
            if folderFiles[dll] != nil {
                state = .bundled
            } else if let dependency, installed.contains(dependency.id) {
                state = .installed
            } else if providedByWindows(dll) {
                state = .builtin
            } else {
                state = .missing
            }
            if state == .missing && delayOnly.contains(dll) { continue }
            if let dependency, state != .bundled { recommend(dependency.id) }
            if dependency != nil || state == .missing {
                checks.append(DLLCheck(name: dll, state: state, dependencyID: dependency?.id))
            }
        }

        DependencyCatalog.recommended(for: report.engine.engine).forEach(recommend)
        if info.isDotNet {
            recommend("dotnet48")
            if info.referencesXNA { recommend("xna40") }
        }
        if let major = report.engine.dotnetCoreMajor, DependencyCatalog.dependency("dotnetdesktop\(major)") != nil {
            recommend("dotnetdesktop\(major)")
        }

        report.dlls = checks.sorted { ($0.state.rawValue, $0.name) < ($1.state.rawValue, $1.name) }
        report.recommendedIDs = recommended
        report.rtpIDs = report.engine.rtpDependencies.filter { !installed.contains($0) }
        return report
    }

    private static func isAPISet(_ dll: String) -> Bool {
        dll.hasPrefix("api-ms-win-") || dll.hasPrefix("ext-ms-")
    }

    /// `api-ms-win-core-synch-l1-2-0.dll` → `api-ms-win-core-synch-l1-2` (how the schema stores names)
    static func apisetKey(_ dll: String) -> String {
        var name = dll.lowercased()
        if name.hasSuffix(".dll") { name.removeLast(4) }
        if let dash = name.lastIndex(of: "-"), name[name.index(after: dash)...].allSatisfy(\.isNumber) {
            name = String(name[..<dash])
        }
        return name
    }
}

/// Reads a Wine log after a launch and explains what went wrong.
enum LogAnalyzer {
    struct Result: Sendable {
        var missingDLLs: [String] = []
        var dependencyIDs: [String] = []
        var hints: [String] = []
        var sawErrors = false
        /// `USER32.dll.IsMouseInPointerEnabled` … — Windows functions this Wine engine doesn't have yet
        var unimplementedFunctions: [String] = []
        /// Wine kept starting processes and Miro stopped it
        var processStorm = false
        /// The newer engine is likely to fix this run
        var needsNewerEngine: Bool { !unimplementedFunctions.isEmpty }
    }

    // swiftlint:disable:next force_try
    private static let missingLibrary = try! NSRegularExpression(
        pattern: #"(?:Library|library) ([^\s"]+?\.(?:dll|DLL|drv|ocx|exe)) \(which is needed by"#
    )

    // "wine: Call from 000000017002F018 to unimplemented function USER32.dll.IsMouseInPointerEnabled, aborting"
    // swiftlint:disable:next force_try
    private static let unimplemented = try! NSRegularExpression(
        pattern: #"unimplemented function ([A-Za-z0-9_\-]+\.(?:dll|DLL|drv|exe)\.[A-Za-z0-9_@?$]+)"#
    )

    static func analyze(_ log: String) -> Result {
        var result = Result()
        let range = NSRange(log.startIndex..., in: log)
        for match in unimplemented.matches(in: log, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: log) else { continue }
            let name = String(log[nameRange])
            if !result.unimplementedFunctions.contains(name) { result.unimplementedFunctions.append(name) }
        }
        if let function = result.unimplementedFunctions.first {
            result.hints.append("이 엔진(Wine)에는 게임이 부르는 Windows 기능 \(function)이(가) 아직 없어요. 최신 엔진(Wine \(ModernEngine.wineVersion))에는 들어 있어요.")
        }
        for match in missingLibrary.matches(in: log, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: log) else { continue }
            let name = String(log[nameRange])
            if !result.missingDLLs.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                result.missingDLLs.append(name)
            }
        }
        func suggest(_ id: String) {
            if !result.dependencyIDs.contains(id) { result.dependencyIDs.append(id) }
        }
        for dll in result.missingDLLs {
            if let dependency = DependencyCatalog.provider(of: dll) { suggest(dependency.id) }
        }

        let lower = log.lowercased()
        if lower.contains("wine mono") || lower.contains("err:mscoree") || lower.contains("clr error") {
            suggest("dotnet48")
            result.hints.append(".NET 런타임 오류가 보여요. .NET Framework 4.8을 설치하면 해결되는 경우가 많아요.")
        }
        if lower.contains("microsoft.xna.framework") {
            suggest("xna40")
        }
        if lower.contains("unhandled exception") && lower.contains("system.") {
            suggest("dotnet48")
        }
        if lower.contains("gameassembly.dll") && lower.contains("which is needed by") {
            result.hints.append("Unity IL2CPP 게임이에요. 'Failed to load il2cpp' 오류는 GameAssembly.dll이 필요로 하는 파일이 없어서 생겨요. 아래 항목을 설치하면 해결돼요.")
        }
        if lower.contains("bad cpu type") {
            result.hints.append("Rosetta 2가 설치되어 있지 않아요. 설정 → 런타임에서 다시 설치해 주세요.")
        }
        if lower.contains("nodrv_createwindow") {
            result.hints.append("Wine 그래픽 드라이버를 불러오지 못했어요. 런타임을 재설치해 보세요.")
        }
        if lower.contains("d3dcompiler") && !lower.contains("which is needed by") && lower.contains("err:") {
            suggest("d3dcompiler_47")
        }
        if lower.contains("xaudio2") && lower.contains("err:") { suggest("xact") }
        if lower.contains("err:dmusic") || lower.contains("err:dmime") { suggest("directmusic") }
        result.sawErrors = lower.contains("err:module") || lower.contains("c0000135") || lower.contains("err:seh")
        return result
    }
}
