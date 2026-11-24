//
//  FullscreenMode.swift
//  Miro
//
//  "전체 화면 (노치까지)": start the game borderless at the display's full native size
//  (e.g. 3024×1964 on a 14" MacBook Pro — including the camera-housing band and the Dock area),
//  like a native Mac game. Implemented with each engine's own launch arguments, so the game's saved
//  settings are overridden for that run only.
//
//  화면 맞춤:
//   • 기본      — the game gets the whole screen and keeps its own aspect ratio
//                 (a 16:9 game on a 3:2-ish MacBook screen draws black bars itself).
//   • 꽉 채우기 — the game gets a window with *its* aspect ratio at full screen height
//                 (e.g. 3492×1964 for 16:9), centred, so the left/right edges fall off-screen.
//

import AppKit
import ApplicationServices
import Foundation

enum DisplayFit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fit, fill

    var id: String { rawValue }
    var title: String { self == .fit ? "기본" : "꽉 채우기" }
}

enum FullscreenMode {
    struct Size: Equatable, Sendable {
        let width: Int
        let height: Int
        var text: String { "\(width)×\(height)" }
    }

    /// Engines whose window mode / resolution can be set from the command line
    static func isSupported(_ engine: GameEngine) -> Bool {
        switch engine {
        case .unity, .unreal, .godot: return true
        default: return false
        }
    }

    /// Full size of the main display (menu bar screen) as Windows will see it.
    /// With Retina on Wine reports real pixels; with it off, points.
    @MainActor
    static func nativeSize(retina: Bool) -> Size? {
        guard let screen = NSScreen.screens.first else { return nil }
        let scale = retina ? screen.backingScaleFactor : 1
        return Size(width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale))
    }

    /// A comfortable window that fits under the menu bar / above the Dock (used when fullscreen is off)
    @MainActor
    static func windowedSize(retina: Bool) -> Size? {
        guard let screen = NSScreen.screens.first else { return nil }
        let scale = retina ? screen.backingScaleFactor : 1
        let visible = screen.visibleFrame.size
        let width = Int(visible.width * 0.9 * scale)
        let height = Int((visible.height - 28) * 0.9 * scale) // leave room for the title bar
        return Size(width: width, height: height)
    }

    /// Window for 꽉 채우기: the game's aspect ratio at full screen height (wider than the screen)
    static func fillSize(native: Size, aspect: Double) -> Size {
        let screenAspect = Double(native.width) / Double(native.height)
        guard aspect > screenAspect else {
            // Game is narrower/taller than the screen: full width, crop top/bottom instead
            return Size(width: native.width, height: Int((Double(native.width) / aspect).rounded()))
        }
        return Size(width: Int((Double(native.height) * aspect).rounded()), height: native.height)
    }

    /// Aspect ratio the game was designed for. Unity stores its default resolution in the registry
    /// under HKCU\Software\<company>\<product> (names from <exe>_Data/app.info); fallback 16:9.
    static func contentAspect(of game: Game, bottle: URL) -> Double {
        let fallback = 16.0 / 9.0
        guard game.engine == .unity else { return fallback }
        let exeBase = game.executableURL.deletingPathExtension().lastPathComponent
        guard let appInfo = try? String(contentsOf: game.folderURL.appending(path: "\(exeBase)_Data/app.info"), encoding: .utf8) else {
            return fallback
        }
        let names = appInfo.split(whereSeparator: \.isNewline).map(String.init)
        guard names.count >= 2,
              let data = try? Data(contentsOf: bottle.appending(path: "user.reg")) else { return fallback }
        let text = String(decoding: data, as: UTF8.self)
        let header = "[Software\\\\\(names[0])\\\\\(names[1])]"
        guard let section = text.range(of: header) else { return fallback }
        let end = text.range(of: "\n[", range: section.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let body = text[section.upperBound..<end]
        func dword(_ prefix: String) -> Int? {
            guard let key = body.range(of: "\"\(prefix)"),
                  let value = body.range(of: "dword:", range: key.upperBound..<body.endIndex) else { return nil }
            return Int(body[value.upperBound...].prefix(8), radix: 16)
        }
        guard let width = dword("Screenmanager Resolution Width Default"),
              let height = dword("Screenmanager Resolution Height Default"), width > 0, height > 0 else {
            return fallback
        }
        return Double(width) / Double(height)
    }

    /// Launch arguments for `engine`; empty when the engine can't be controlled this way.
    static func arguments(engine: GameEngine, fullscreen: Bool, fill: Size?, native: Size?, windowed: Size?) -> [String] {
        switch engine {
        case .unity:
            if fullscreen, let fill, let native, fill != native {
                // Borderless window bigger than the screen; Miro centres it after launch
                return ["-screen-fullscreen", "0", "-window-mode", "windowed", "-popupwindow",
                        "-screen-width", "\(fill.width)", "-screen-height", "\(fill.height)"]
            }
            if fullscreen, let native {
                return ["-screen-fullscreen", "1", "-window-mode", "borderless",
                        "-screen-width", "\(native.width)", "-screen-height", "\(native.height)"]
            }
            // Unity remembers the last mode, so switch back to a window explicitly
            var arguments = ["-screen-fullscreen", "0", "-window-mode", "windowed"]
            if let windowed {
                arguments += ["-screen-width", "\(windowed.width)", "-screen-height", "\(windowed.height)"]
            }
            return arguments
        case .unreal:
            if fullscreen, let fill, let native, fill != native {
                return ["-windowed", "-ResX=\(fill.width)", "-ResY=\(fill.height)",
                        "-WinX=\((native.width - fill.width) / 2)", "-WinY=\((native.height - fill.height) / 2)"]
            }
            if fullscreen, let native {
                return ["-fullscreen", "-ResX=\(native.width)", "-ResY=\(native.height)"]
            }
            return ["-windowed"]
        case .godot:
            if fullscreen, let fill, let native, fill != native {
                return ["--windowed", "--resolution", "\(fill.width)x\(fill.height)",
                        "--position", "\((native.width - fill.width) / 2),\((native.height - fill.height) / 2)"]
            }
            if fullscreen, let native {
                return ["--fullscreen", "--resolution", "\(native.width)x\(native.height)"]
            }
            return ["--windowed"]
        default:
            return []
        }
    }
}

/// Centres the 꽉 채우기 game window on the screen using the Accessibility API
/// (Unity has no launch argument for the window position).
enum WindowPlacer {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "allow Miro to control your computer" prompt
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Finds a window of the game's process tree that is at least `minWidth` points wide and centres it.
    /// Returns true when a window was moved.
    @discardableResult
    static func centerWideWindow(root: pid_t, minWidth: CGFloat, screen: CGRect) -> Bool {
        guard isTrusted else { return false }
        for pid in ProcessTree.family(of: root) {
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var sizeRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
                      let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
                var size = CGSize.zero
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
                guard size.width >= minWidth else { continue }
                var origin = CGPoint(x: screen.minX + (screen.width - size.width) / 2,
                                     y: (screen.height - size.height) / 2)
                if let position = AXValueCreate(.cgPoint, &origin),
                   AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success {
                    return true
                }
            }
        }
        return false
    }
}
