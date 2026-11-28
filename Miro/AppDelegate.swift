//
//  AppDelegate.swift
//  Miro
//
//  This file is part of Whisky.
//  Modified for Miro, 2026.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import AppKit
import SwiftUI
import WhiskyKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files opened from Finder ("다음으로 열기 → Miro") are added to the library
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            GameLibrary.shared.handle(urls: urls)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        Task.detached(priority: .background) {
            AppDelegate.deleteOldLogs()
        }
        // miroe: link the earlier Steam folder and clone save data into the miroe prefix (once; nothing is moved)
        Task { @MainActor in
            if MiroeEngine.isInstalled && !EngineManager.shared.isReady(.miroe) { await EngineManager.shared.prepareMiroe() }
            await MiroeMigration.run()
            SteamClient.shared.sync()
        }
    }

    /// Quitting Miro ends Steam and every Windows program it started, on every engine, so nothing keeps running
    /// without Miro
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppDelegate.killWine() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    static func killWine() {
        if let bottle = RuntimeManager.shared.bottle {
            try? Wine.killBottle(bottle: bottle)
        }
        // wineserver -k of each engine whose files are there (Steam runs on miroe; older engines may still have
        // something running from before)
        for engine in [WineEngine.modern, WineEngine.miroe] where engine.wineserverBinary.fileExists && engine.hasPrefix {
            engine.killAll()
        }
    }

    nonisolated static func deleteOldLogs() {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: MiroPaths.logs, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for url in urls where url.pathExtension == "log" {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}
