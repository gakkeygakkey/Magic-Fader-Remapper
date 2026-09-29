import SwiftUI
import AppKit

@main
struct HUIRMApp: App {
    @StateObject private var model = ProxyModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("HUI-RM", systemImage: "slider.vertical.3") {
            Text(model.status)
            Button("接続とMIDI Monitor…") {
                openWindow(id: "monitor")
                NSApp.activate(ignoringOtherApps: true)
            }
            if model.isConnected {
                Button("コントローラーを切断") { model.disconnect() }
            }
            Divider()
            Toggle("Rec → Touch / Read", isOn: $model.recRemapEnabled)
            Toggle("録音ボタン → Trim", isOn: $model.trimRemapEnabled)
            Button("HUI-RMを終了") {
                model.shutdown()
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        }
        Window("HUI-RM — 接続とMIDI Monitor", id: "monitor") {
            ContentView(model: model)
        }
        .defaultSize(width: 920, height: 820)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}
