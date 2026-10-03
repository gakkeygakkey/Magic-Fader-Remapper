import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ProxyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "slider.vertical.3").font(.title)
                VStack(alignment: .leading, spacing: 3) {
                    Text("HUI-RM").font(.title2.bold())
                    Text("MagicFader ⇄ HUI-RM ⇄ Pro Tools").foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.status, systemImage: model.isConnected ? "circle.fill" : "circle")
                    .foregroundStyle(model.isConnected ? .green : .secondary)
            }
            GroupBox("コントローラー接続") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("入力（Controller → Mac）", selection: $model.selectedSource) {
                        Text("入力を選択").tag(UInt32(0))
                        ForEach(model.sources) { endpoint in
                            Text("\(endpoint.name) [\(endpoint.uniqueID)]").tag(endpoint.id)
                        }
                    }.disabled(model.isConnected)
                    Picker("出力（Mac → Controller）", selection: $model.selectedDestination) {
                        Text("出力を選択").tag(UInt32(0))
                        ForEach(model.destinations) { endpoint in
                            Text("\(endpoint.name) [\(endpoint.uniqueID)]").tag(endpoint.id)
                        }
                    }.disabled(model.isConnected)
                    HStack {
                        Button("一覧を更新") { model.refresh() }
                        if model.isConnected {
                            Button("切断") { model.disconnect() }
                        } else {
                            Button("接続") { model.connect() }
                                .disabled(!model.isReady || model.selectedSource == 0 || model.selectedDestination == 0)
                        }
                        if !model.isReady {
                            Button("仮想MIDIを再作成") { model.start() }
                        }
                        Spacer()

                    }
                    HStack(spacing: 24) {
                        Toggle("Rec → Touch / Read", isOn: $model.recRemapEnabled)
                        Toggle("録音ボタン → Trim", isOn: $model.trimRemapEnabled)
                    }.toggleStyle(.switch).fixedSize()
                    Text("それぞれのON／OFFを記憶します。録音ボタンの変換はMagic Fader専用です。")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.isMagicFader && model.trimRemapEnabled {
                        Text(model.trimTarget.map { "Trim対象: HUIチャンネル \($0)" }
                             ?? "Trim対象未確定：8ch内のトラックを1つ選択してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("接続した機器を記憶し、次回起動時やUSB再接続時に自動接続します。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Pro Tools: Peripherals → MIDI Controllers → HUI\nReceive From / Send To の両方を HUI-RM に設定してください。")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("中継中は物理MIDIへの接続状態を表します。Pro ToolsのHUI接続成立は実機で確認してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("Magic Fader Release補完") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("SoloのReleaseを50ms後に補完", isOn: $model.releaseRepairEnabled)
                        .toggleStyle(.switch)
                        .disabled(!model.isConnected || !model.isMagicFader)
                    Text("Soloを押したチャンネルに自動で追従します。ON／OFFは次回起動時も保持されます。RecのRemapとは独立した設定です。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("MG フェーダーリフレッシュ（試験機能）") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("メトロノーム → リフレッシュ", isOn: $model.refreshEnabled)
                        .toggleStyle(.switch)
                        .disabled(!model.isConnected || !model.isMagicFader)
                    Text(model.refreshNotice).font(.callout)
                    Text("停止中・手を離して試してください。約5％動かし、100ms後に戻します。途中で触るかPTから位置が届くと復帰を中止。ON／OFFは次回起動時も保持されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("MG Flip（試験機能）") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("ループ → Flip", isOn: $model.loopFlipEnabled)
                        .toggleStyle(.switch)
                        .disabled(!model.isConnected || !model.isMagicFader)
                    Text("ON／OFFを記憶します。ON時はループランプがFlip中に点灯。OFF時は通常のループ操作・表示に戻ります。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("巻き戻し／早送り → センド切替", isOn: $model.transportSendEnabled)
                        .toggleStyle(.switch)
                    Text("ON時はFlip状態に関係なく、巻き戻しで前、早送りで次のセンドへ。A〜Eを循環します。停止はそのまま。設定を記憶します。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("前回のセンドを復元", isOn: $model.restoreSendEnabled)
                        .toggleStyle(.switch)
                        .padding(.leading, 16)
                    Text("ON時は最後に本体で選んだセンドをFlip時に復元します。未選択ならA。設定とセンドは再起動後も保持します。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    HStack {
                        Button("Flip切替") { model.toggleFlip() }
                            .disabled(!model.isConnected || !model.isMagicFader)
                        Text(model.flipLamp).font(.callout)
                    }
                    Text(model.flipNotice).font(.caption).foregroundStyle(.secondary)
                    Text("MGで対象のセンドを選び、手を離して操作。もう一度押すと戻ります。Flip中はMuteもセンド側に切り替わります。PTランプの点滅は表示にも反映されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Text("MIDI Monitor").font(.headline)
                Toggle("記録", isOn: $model.recording).toggleStyle(.switch).fixedSize()
                Button("コピー") { model.copyLog() }.disabled(model.log.isEmpty)
                Button("消去") { model.clear() }
                Spacer()
                Text("→ PT \(model.toHost)  /  → Controller \(model.toDevice)  /  エラー \(model.failures)")
                    .font(.caption.monospacedDigit())
            }
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if model.log.isEmpty {
                        Text(model.recording ? "通信を待っています…" : "「記録」をONにすると通信を表示します。中継は記録OFFでも続きます。")
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
            Text("生データ: UMP 16進数 / t: CoreMIDI時刻。最新2,000件を保持（省略 \(model.omitted)件）。表示の省略は中継データに影響しません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 840, minHeight: 880)
    }
}
