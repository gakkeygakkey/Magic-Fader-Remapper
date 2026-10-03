import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: ProxyModel
    @State private var testOperationsExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("Diagnostics & MIDI Log", comment: "")).font(.title2.bold())
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status)
                Text(model.flipLamp + " · " + model.flipNotice)
                Text(NSLocalizedString("Refresh: ", comment: "") + model.refreshNotice)
                Text(model.trimTarget.map { String(format: NSLocalizedString("Trim target: HUI channel %@", comment: ""), String($0)) } ?? NSLocalizedString("Trim target: Unknown", comment: ""))
            }.font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            DisclosureGroup(NSLocalizedString("Test Controls", comment: ""), isExpanded: $testOperationsExpanded) {
                HStack {
                    Button(NSLocalizedString("Toggle Flip", comment: "")) { model.toggleFlip() }
                        .disabled(!model.isConnected || !model.isMagicFader)
                    Spacer()
                }.padding(.top, 6)
            }
            HStack {
                Text("MIDI Monitor").font(.headline)
                Toggle(NSLocalizedString("Capture", comment: ""), isOn: $model.recording).toggleStyle(.switch).fixedSize()
                Button(NSLocalizedString("Copy", comment: "")) { model.copyLog() }.disabled(model.log.isEmpty)
                Button(NSLocalizedString("Clear", comment: "")) { model.clear() }
                Spacer()
                Text(String(format: NSLocalizedString("→ PT %@  /  → Controller %@  /  Errors %@", comment: ""), String(model.toHost), String(model.toDevice), String(model.failures)))
                    .font(.caption.monospacedDigit())
            }
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if model.log.isEmpty {
                        Text(model.recording ? NSLocalizedString("Waiting for MIDI…", comment: "") : NSLocalizedString("Turn on Capture to display MIDI traffic. MIDI routing continues while capture is off.", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.log.reversed()) { entry in
                        Text(entry.line)
                            .foregroundStyle(entry.status == 0 ? Color.primary : .orange)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(minWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            Text(String(format: NSLocalizedString("Raw data: UMP hexadecimal / t: CoreMIDI host ticks. Keeps the latest 2,000 entries (%@ omitted). Display truncation does not affect MIDI routing.", comment: ""), String(model.omitted)))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 840, minHeight: 480)
    }
}
