import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ProxyModel
    @Environment(\.openWindow) private var openWindow
    @State private var connectionExpanded = false
    @State private var hovered: FaderSetting?
    @State private var explained: FaderSetting?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Magic Fader Remapper", systemImage: "slider.vertical.3")
                        .font(.title2.bold())
                    Text(NSLocalizedString("MagicFader · Pro Tools Utility", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.isConnected ? NSLocalizedString("Connected", comment: "") : NSLocalizedString("Disconnected", comment: ""), systemImage: "circle.fill")
                    .font(.callout).foregroundStyle(model.isConnected ? .green : .secondary)
                    .help(model.status + NSLocalizedString(". Check Pro Tools communication in Diagnostics & MIDI Log.", comment: ""))
                Button { connectionExpanded.toggle() } label: {
                    Label(NSLocalizedString("Connection", comment: ""), systemImage: "cable.connector")
                }
                .accessibilityValue(connectionExpanded ? NSLocalizedString("Expanded", comment: "") : NSLocalizedString("Collapsed", comment: ""))
            }.padding(22)
            Divider()
            if connectionExpanded {
                connectionSettings.padding(20)
                Divider()
            }
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    VStack(spacing: 10) {
                        MagicFaderDiagram(model: model, hovered: hovered)
                            .frame(width: 280, height: 280 * 1672 / 941)
                        Text(NSLocalizedString("Button roles reflect your settings", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        settingsSection(NSLocalizedString("Button Assignments", comment: "")) {
                            settingRow(.rec, value: $model.recRemapEnabled)
                            settingRow(.trim, value: $model.trimRemapEnabled)
                            settingRow(.flip, value: $model.loopFlipEnabled,
                                       disabled: !model.isConnected || !model.isMagicFader)
                            settingRow(.restore, value: $model.restoreSendEnabled)
                                .padding(.leading, 16)
                            settingRow(.send, value: $model.transportSendEnabled)
                        }
                        settingsSection(NSLocalizedString("Utilities", comment: "")) {
                            settingRow(.solo, value: $model.releaseRepairEnabled,
                                       disabled: !model.isConnected || !model.isMagicFader)
                            settingRow(.refresh, value: $model.refreshEnabled,
                                       disabled: !model.isConnected || !model.isMagicFader)
                        }
                        Text(NSLocalizedString("All settings are saved between launches.", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(24)
            }
            explanationPanel
                .padding(.horizontal, 24).padding(.bottom, 16)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .padding(.horizontal, 22).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Text("MagicFader ⇄ MF-RM ⇄ Pro Tools")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(NSLocalizedString("Diagnostics & MIDI Log…", comment: "")) { openWindow(id: "diagnostics") }
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(minWidth: 790, minHeight: 750)
        .onAppear {
            connectionExpanded = !model.isConnected
        }
        .onChange(of: model.isConnected) { _, connected in
            connectionExpanded = !connected
        }
    }

    private var explanationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(explained?.title ?? NSLocalizedString("Feature Guide", comment: ""), systemImage: "info.circle")
                .font(.headline)
            ScrollView {
                Text(explained?.detail ?? NSLocalizedString("Hover over a setting to see its description here and highlight the corresponding button.", comment: ""))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }.id(explained)
        }
        .padding(16)
        .frame(height: 112, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).padding(.bottom, 4)
            VStack(spacing: 0, content: content)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func settingRow(_ setting: FaderSetting, value: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: 8) {
                Text(setting.title)
                if setting == .refresh { Text(NSLocalizedString("Experimental", comment: "")).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 8)
            Toggle(setting.title, isOn: value).labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: setting.color)).controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(hovered == setting ? Color.accentColor.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .disabled(disabled)
        .help(setting.detail)
        .accessibilityHint(setting.detail)
        .onHover { inside in
            if inside {
                hovered = setting
                explained = setting
            }
            else if hovered == setting { hovered = nil }
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(NSLocalizedString("Input (Controller → Mac)", comment: ""), selection: $model.selectedSource) {
                Text(NSLocalizedString("Select an input", comment: "")).tag(UInt32(0))
                ForEach(model.sources) { Text("\($0.name) [\($0.uniqueID)]").tag($0.id) }
            }.disabled(model.isConnected)
            Picker(NSLocalizedString("Output (Mac → Controller)", comment: ""), selection: $model.selectedDestination) {
                Text(NSLocalizedString("Select an output", comment: "")).tag(UInt32(0))
                ForEach(model.destinations) { Text("\($0.name) [\($0.uniqueID)]").tag($0.id) }
            }.disabled(model.isConnected)
            HStack {
                Button(NSLocalizedString("Refresh List", comment: "")) { model.refresh() }
                if model.isConnected { Button(NSLocalizedString("Disconnect", comment: "")) { model.disconnect() } }
                else {
                    Button(NSLocalizedString("Connect", comment: "")) { model.connect() }
                        .disabled(!model.isReady || model.selectedSource == 0 || model.selectedDestination == 0)
                }
                if !model.isReady { Button(NSLocalizedString("Recreate Virtual MIDI", comment: "")) { model.start() } }
            }
            Text(NSLocalizedString("Pro Tools: Peripherals → MIDI Controllers → HUI\nSet Receive From and Send To to MF-RM. Your controller will reconnect automatically.", comment: ""))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

enum FaderSetting: String {
    case rec, trim, flip, restore, send, solo, refresh
    var title: String {
        switch self {
        case .rec: "Rec Ready → Touch / Read"
        case .trim: NSLocalizedString("Transport Record → Trim", comment: "")
        case .flip: NSLocalizedString("Loop → Flip", comment: "")
        case .restore: NSLocalizedString("Restore Last Send", comment: "")
        case .send: NSLocalizedString("Rewind / FF → Select Send", comment: "")
        case .solo: NSLocalizedString("Solo Release Repair", comment: "")
        case .refresh: NSLocalizedString("Click → Fader Refresh", comment: "")
        }
    }
    var color: Color {
        switch self {
        case .flip, .restore:
            return Color(red: 0.12, green: 0.47, blue: 0.25)
        case .rec, .trim:
            return Color(red: 0.72, green: 0.18, blue: 0.20)
        case .solo, .send:
            return Color(red: 0.95, green: 0.66, blue: 0.15)
        case .refresh:
            return Color(red: 0.08, green: 0.34, blue: 0.67)
        }
    }

    var detail: String {
        switch self {
        case .rec: NSLocalizedString("Use the track’s Rec Ready button to switch between Touch and Read. Its LED follows the automation state.", comment: "")
        case .trim: NSLocalizedString("Use the transport Record button to toggle Trim for the selected HUI channel.", comment: "")
        case .flip: NSLocalizedString("Use Loop to flip the fader to send level. While flipped, V-Pot controls send pan and Mute controls send mute. Exiting Flip restores Pan assignment. Disable this option for normal Loop operation.", comment: "")
        case .restore: NSLocalizedString("Restore the last selected send (A–E) when entering Flip, or Send A if none has been selected. The send selection is saved between launches.", comment: "")
        case .send: NSLocalizedString("Use Rewind and Fast Forward to cycle backward or forward through sends A–E, whether Flip is on or off. Stop keeps its normal function. Disable this option for normal transport operation.", comment: "")
        case .solo: NSLocalizedString("Adds the missing Solo button release signal so Pro Tools does not treat the button as held down. This prevents Solo from becoming stuck on when using Shift+S.", comment: "")
        case .refresh: NSLocalizedString("If the fader motor keeps buzzing, press Click to briefly move the fader and return it to its position. This may stop the buzzing. Use with playback stopped and your hand off the fader.", comment: "")
        }
    }
}

struct MagicFaderDiagram: View {
    @ObservedObject var model: ProxyModel
    let hovered: FaderSetting?
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack(alignment: .topLeading) {
                Image("MagicFaderBody").resizable().scaledToFit()
                badge(.rec, "Touch\nRead", enabled: model.recRemapEnabled, x: 403, y: 1098, w: w, h: h)
                badge(.trim, "Trim", enabled: model.trimRemapEnabled, x: 403, y: 1266, w: w, h: h)
                badge(.flip, "Flip", enabled: model.loopFlipEnabled, x: 767, y: 758, w: w, h: h)
                badge(.send, "Send\n−", enabled: model.transportSendEnabled, x: 403, y: 928, w: w, h: h)
                badge(.send, "Send\n+", enabled: model.transportSendEnabled, x: 767, y: 928, w: w, h: h)
                badge(.solo, NSLocalizedString("Solo\nRepair", comment: ""), enabled: model.releaseRepairEnabled, x: 586, y: 1098, w: w, h: h)
                badge(.refresh, "Refresh", enabled: model.refreshEnabled, x: 586, y: 928, w: w, h: h)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("MagicFader button map. Use the switches on the right to change button assignments.", comment: ""))
    }

    private func badge(_ setting: FaderSetting, _ title: String, enabled: Bool,
                       x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let highlight = hovered == setting || (setting == .flip && hovered == .restore)
        return ZStack {
            if enabled {
                Circle().fill(setting.color)
                Text(title).font(.system(size: w * (setting == .refresh ? 0.027 : 0.032), weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(setting == .solo || setting == .send ? Color.black : Color.white)
            }
            if highlight {
                Circle().strokeBorder(Color.orange, lineWidth: 3)
            }
        }
        .frame(width: w * 112 / 941, height: w * 112 / 941)
        .position(x: w * x / 941, y: h * y / 1672)
        .help(setting.detail)
    }


}
