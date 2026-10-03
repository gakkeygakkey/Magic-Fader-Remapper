import SwiftUI
import AppKit

@main
struct HUIRMApp: App {
    @StateObject private var model = ProxyModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("MF-RM", systemImage: "slider.vertical.3") {
            Button(NSLocalizedString("Settings…", comment: "")) {
                openWindow(id: "monitor")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button(NSLocalizedString("Quit MF-RM", comment: "")) {
                model.shutdown()
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        }
        Window(NSLocalizedString("MF-RM — Settings", comment: ""), id: "monitor") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 790, height: 870)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        Window(NSLocalizedString("MF-RM — Diagnostics & MIDI Log", comment: ""), id: "diagnostics") {
            DiagnosticsView(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1060, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)

    }
}
