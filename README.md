# HUI-RM — Phase 2: Rec → Touch / Read

MagicFader ⇄ HUI-RM ⇄ Pro Tools の双方向MIDI透過Proxy。
macOS 26.7以降。現段階は実機検証用。Remap OFFで透過、ONでMagicFaderのRecでTouch / Readを切り替えます。

## 承認済みの範囲

- macOSメニューバーアプリ。
- MIDI 1.0の仮想Source / Destinationを「HUI-RM」として公開。
- 物理デバイスの入力・出力を手動選択し、双方向に中継。
- Pingへ独自応答せず、未知のメッセージも変更しない。
- Rec → Touch / Readのみのリマップ。ON/OFFを保存し、次回起動時に復元する（未保存時はOFF）。
- ON時はチャンネルAUTOの赤点灯・点滅をRec LEDへ反映。Read相当の緑表示では消灯。OFF時は最後に受信した元のRec表示へ戻す（未受信なら消灯）。
- 方向、受信時刻、CoreMIDIタイムスタンプ、UMP生データ、転送エラーのMonitor。
- 仮想EndpointのUnique IDを保存・復元。IDの衝突はエラーにして黙って別IDへ変更しない。
- 接続成功した入出力を保存し、次回起動・USB再接続時に同じUnique IDの機器へ自動接続。
- 手動切断時は、その起動中の自動接続を停止（手動で接続に成功すると再開）。

## 使用手順

1. Xcodeで `HUI-RM.xcodeproj` を開き、My Macを選んで実行。
2. メニューバーのスライダーアイコン →「接続とMIDI Monitor…」。通常起動時はウインドウを表示しません。
3. MagicFaderをHUIモードにし、入力・出力でMagicFaderの対応ポートを選んで「接続」。
4. Pro ToolsのPeripherals → MIDI ControllersでTypeをHUI、Receive From / Send Toを両方HUI-RMに設定。
5. 同じMagicFaderへの直接HUI接続を重複して設定しないでください。
6. Monitorの「記録」をONにして操作し、必要なログを「コピー」。記録OFFでも中継は続きます。
7. 更新版で一度接続すると、その入出力を記憶します。以後のアプリ起動・USB再接続では同じ機器へ自動接続します。

HUI-RM終了時は仮想Endpointも消えます。「Remap OFF」とアプリ終了は別です。
「中継中」は物理接続の状態で、Pro ToolsのHUIセッション成立を保証する表示ではありません。
通信件数は送信を試みたCoreMIDIパケット数で、HUI操作数ではありません。

## Monitor表記

UMPはCoreMIDIのUniversal MIDI Packet表現です。MIDI 1.0の3バイトメッセージとは表示が異なります。
例: `20900000` はMIDI 1.0 Note On `90 00 00`（HUI Ping候補）。
`t` は受信パケットのホスト時刻。非ゼロの時刻は保持し、仮想Source送出で0だけを受信時のホスト時刻に補います。

画面は最新2,000件、受信から画面更新までの待機バッファは512件に制限。
各パケットは最大64ワードを表示し、超過は明示します。省略はログだけに適用され、中継データは省略しません。
ログ整形・UI更新は中継後に行います。高負荷での遅延・実機での長時間安定性は未検証です。

## 検証

Xcode 27で署名付きDebugビルド、macOS上でのアプリ起動継続、CoreMIDI上のHUI-RM Source / Destination公開を確認。
画面の目視・操作確認は未完了（UI操作ツールが新規アプリを認識できず）。今回のEndpoint一覧ではMagicFader名のポートは見つからず、実機通信は未確認。
パケット処理チェック（リポジトリルートで実行）:

```sh
xcrun swiftc -module-cache-path /tmp/HUIRM-swift-cache HUI-RM/RecAutomationRemapper.swift HUI-RM/EventListTransport.swift Tests/EventListTransportChecks.swift -o /tmp/HUIRM-transport-checks
/tmp/HUIRM-transport-checks
```

Ping、Press/Release、Fader、未知CC、Realtime、SysExのデータ保持、パケット順序、時刻、1,201ワードのデータ、入力バッファ不変、送信エラー返却、空リストを検証。
これはCoreMIDIパケット処理のテストで、MagicFader / Pro Toolsの実機試験ではありません。

## Phase 1 実機確認

2026-09-28、ユーザーから「動いている、今のところ問題なし、ログも取れている」と報告。提供ログでも双方向Pingを確認。以下の個別項目をすべて確認済みという意味ではありません。

### 継続確認項目

- 直接接続時と同じHUI接続維持、Motor Fader、Track Select、Solo / Mute、Transport、Knob、表示。
- Pro Tools → MagicFaderのフィードバックが戻る。
- Monitor ON / OFFで操作に支障がなく、長時間動作でエラーや通信停止がない。
- MagicFader切断で中継停止し、手動再接続で復帰。
- HUI-RM再起動、Pro Tools再起動、起動順変更で接続先設定と復帰挙動を確認。
- MagicFaderのEndpoint構成・名前、各操作のPress / Release、生データを記録。

## 後続段階（未実装）

Rec → Touch / Readの対象トラックとLEDへの影響を確認してから他のモードへ展開。
Mapping UI、Layer、Fader / Knob変換、Launch at Loginは後続範囲。前回接続先の記憶と自動再接続は実装済み。

## 調査資料

- Apple CoreMIDI: https://developer.apple.com/documentation/coremidi
- HUI実機解析（MagicFader実測ではない）: https://forum.bome.com/uploads/short-url/aX7AWqj6FpgMiEMQi0kACDDTSSi.pdf

## Rec → Touch / Read の実機テスト

1. 旧HUI-RMを終了し、Xcodeから更新版を実行。Magic Faderの入出力を接続。
2. Pro Toolsは引き続きHUI-RMを受信元・送信先に設定。
3. 再生停止中に対象トラックをReadへ設定。Monitor記録と「Remap · Rec → Touch / Read」をON。
4. Recを押してTouchへ変わるか、再度押してReadへ戻るかを確認。
5. Touch時のRec点灯/点滅、Read時の消灯、元の録音待機が変わらないことを確認。
6. Pro Tools側でReadへ手動変更してからRecを押し、Touchになるか確認。
7. Remap OFFで元のRec操作・ランプ表示に戻るか確認。

### 入力と送信シーケンス

実機ログの入力 `20B00F00` / `20B02F47`（別パケット）を捕捉する。
Touchは `20B00F18 20B02F45`、Readは `20B00F18 20B02F42` で押下。
その状態でRec入力のZone zz（00〜07）のAUTOを `20B00Fzz 20B02F44` で押し、
`20B00Fzz 20B02F04` で離す。その後モードボタンを解放し、元のZone zzへ戻す。
Rec入力が指すHUIチャンネルを対象とする。選択通知や直前のフェーダー移動には依存せず、任意のGUI選択トラックを検索する処理ではない。
根拠: Digidesign MIDI Control Surfaces GuideのHUI操作手順（モードボタン保持中に対象チャンネルのAUTO）。
https://device.report/m/8b4ab9875ce51d96b81c90560aaf741cb171bd4517c34df13a9b3a9eae2a7d2f

### フィードバックと制限

各チャンネルのAUTO（Zone 00〜07 / Port 4）の赤ビットを、同じチャンネルのRec LED（Port 7）へ反映。
モードの推定・要求中の状態・AUTO表示・元のRec表示は8チャンネル別に保持する。
元のAUTO表示は維持し、ON中の録音待機LEDメッセージだけを置換する。
受信ログの44/04の交互表示を点滅として扱い、04だけでReadと判定しない。
24の緑表示をRead相当として扱う。赤表示はTouch以外のWrite/Latchでも使われるため、厳密なTouch判定ではない。
最初の状態が不明ならTouchを要求し、以後は要求したモードを交互に切り替える。
フィードバックで状態を補正し、要求から1秒以内の古い反対状態による上書きを避ける。
ランプは要求した内部状態からではなく、受信したAUTO表示から生成する。
Remap ON/OFFは起動時に復元し、接続解除時にチャンネルの一時状態を破棄。OFF/切断時は元のRec表示とフィードバックZoneを復元する。

実機でのTouch/Read適用・ランプ対応は未検証。UI上の状態を優先して確認する。
元のRec→Write版はユーザー実機でRec抑止のみ、Writeへの変更は未成立。今回その不足したAUTO操作を追加。

### 追加テスト

```sh
xcrun swiftc -module-cache-path /tmp/HUIRM-swift-cache HUI-RM/RecAutomationRemapper.swift HUI-RM/EventListTransport.swift Tests/RecAutomationRemapperChecks.swift -o /tmp/HUIRM-toggle-checks
/tmp/HUIRM-toggle-checks
```

Touch/Read＋AUTOの押下解放順序、別パケット入力、連続押下、OFF透過、無関係メッセージ、
AUTO点滅・Readフィードバック、古いフィードバック、Rec表示の置換・復元、リセット、45,000ワード以上の出力を検証。

### RecランプのZone指定修正

2026-09-28、ユーザー実機でRecのTouch/Read切替は成功、ランプの連動は未成立。
提供ログではランプ出力生成と送信エラーなしを確認したが、実機点灯を意味するものではない。
この時点ではRecランプ出力の直前にも必ず `20B00C00` を追加し、元のPro Tools通信と同じ明示的なZone/Port対で送るよう修正。
点灯は `20B00C00 20B02C47`、消灯は `20B00C00 20B02C07`。
Touch/Read操作は変更なし。この修正による点灯改善は実機確認待ち。

### 8チャンネル対応

先頭のTouch/Read切替とZone指定追加後のランプ連動はユーザー実機で成功。
2番目では機能せず、提供ログで選択表示のZone 01、タッチ `20B00F01 / 20B02F40`、
フェーダー値 `20B001xx / 20B021xx` を確認。先頭固定をZone 00〜07対応へ修正した。
Rec入力・AUTO操作・ランプ反映で同じZoneを使用し、状態をチャンネルごとに分離。
Remap OFFと切断時は、観測した各チャンネルの元のRec表示を復元し、最後のフィードバックZoneへ戻す。
各ランプの直前の明示的なZone指定は維持する。

8chすべての個別切替、異なるAUTO状態と録音待機表示の混在、OFF透過・ランプ復元をテスト済み。
2番目以降のRec押下そのものの入力形式と動作は実機未確認。
実機では2番目・8番目・先頭への戻り、別バンクへ移動後について、対象だけが切り替わるかとランプの追従を確認する。

## 前回の接続先の記憶

接続成功時に入力・出力のCoreMIDI Unique IDを一組でUserDefaultsへ保存する。
起動時と機器構成変更時に照合し、両方が一意に見つかった場合に自動接続。
未接続・一方向のみ検出なら待機。待機中は2秒間隔の再確認も行う。
自動接続失敗はエラー表示し、2秒以上の間隔で再試行する。
名前は表示用途のみ。同名という理由では接続しない。Unique IDが変わった場合は手動で選び直し、接続成功時に保存を更新する。
手動切断は現在の起動中の自動接続を停止し、保存情報は保持。次回起動または手動接続成功で再開。
失敗した手動接続では以前の保存先へ勝手に戻らない。
Touch/Read・ランプ処理は変更なし。Remap ON/OFFも保存・復元する。

更新版で最初に一度入出力を選んで接続する必要がある。旧版の未保存の選択は引き継げない。
設定保存/再読込、再作成されたEndpoint参照、USB不在/復帰を模した候補照合、同名別ID、重複ID、手動切断抑止、機器変更をテスト済み。
実機での再起動・USB抜き差しとPro Tools側のセッション復帰は確認待ち。

```sh
xcrun swiftc -module-cache-path /tmp/HUIRM-swift-cache HUI-RM/ConnectionMemory.swift Tests/ConnectionMemoryChecks.swift -o /tmp/HUIRM-connection-checks
/tmp/HUIRM-connection-checks
```

## Remapスイッチの記憶

メニューバー・接続画面どちらから変更してもON/OFFを保存する。
次回起動時はMIDIクライアント作成・機器自動接続より前に、画面と中継エンジンへ保存値を反映。
設定が未保存ならOFF。Monitor記録状態とチャンネル別のモード推定状態は保存しない。
自動接続はユーザー実機で成功。Remap設定復元の実機確認は、ONで終了→再起動、OFFで終了→再起動の両方で行う。

## Magic Fader Solo Release補完（2026-09-29）

Magic FaderのSolo PressにはReleaseがないという実機比較に基づく検証機能。
接続入力名がMagic Fader（空白・記号・大小文字差を除く）に一致する場合だけ使用できる。
FaderPortには適用しない。未知の機器名は自動で対象にしない。
Rec Remapと独立したスイッチで、ON/OFFをUserDefaultsへ保存する。未保存時はOFF。
起動時は自動接続より前に復元し、USB再接続後も同じ設定を使う。
対象はUMP Group 0 / MIDI ch 1、Zone 00〜07、Solo port 3のみ。
Muteや他のボタン、Pingには追加送信しない。

Pressを直ちに中継し、転送成功後の約50ms後に明示的なZoneとSolo Releaseを送る。
50msは受信処理後からの待ち時間で、OSのスケジューリングによる遅れはあり得る。
本物のReleaseが先に来れば予約を取り消す。同じSoloの連打では前のReleaseを
次のPressより先に送り、古いタイマーは無効化する。
別Zoneに移っていたらRelease後に現在の入力Zoneへ戻す。
OFFにすると保留中のReleaseを送って終了する。切断・再接続では予約を無効化し、
古い接続から新しい接続に追加送信しない。システムリセットと送信失敗でも予約を取り消す。

### 実機確認と通常運用

ユーザー実機でRelease送信による問題解消を確認（2026-09-29）。
通常画面から手動チャンネル選択・単発送信テスト欄を撤去。
Soloを押したZoneに自動追従し、50ms後に同じZoneへReleaseを返す。
「記録」ONで自動補完の送信ログが残る。
自動テストは8ch、実Release優先、連打、Zone復元、取消、対象外データの透過、
Rec変換との併用を検証。設定保持の実機確認はONで終了→再起動、OFFで終了→再起動、
USB抜き差しで行う。未接続時やFaderPort接続時には補完を適用しない。

## MGメトロノーム → Trim（2026-09-29）

「メトロノーム → Trim」ONかつMagic Fader接続時、Zone 15 / port 0（HUIテンキー7に相当）の
Press/ReleaseをTrim切替に置換する。実測入力は別パケットの
`20B00F15 20B02F40 20B00F15 20B02F00`。TrimスイッチOFFでは元の通信を通す。
Rec・Trim・Solo補完はそれぞれ独立した保存済み設定で制御。

Pro ToolsのSELECT LED通知（Zone 00〜07 / port 1）の点灯集合から対象を追跡。
8ch内で1つだけ選択が判明している場合に限り、Trim（Zone 18 / port 0）を押したまま
対象チャンネルのAUTOを押して離し、Trimも離して入力Zone 15に戻す。
Trim状態自体はPro Toolsのトグルを使用し、アプリにON/OFFの推定値を持たない。
対象不明・複数選択の場合はメトロノーム信号を消費するだけで、Trimも元の7も送らない。
画面に対象HUIチャンネル／未確定を表示する。起動直後に未確定ならトラックを選び直す。
ハードウェアのチャンネル／バンク移動、切断、リセット、送信失敗では選択を無効化。
バンク外の選択は追跡対象外。Pro Toolsのグループに連動する動作はPro Tools側の設定に従う。
MGメトロノームランプへのTrim状態の反映は未実装。

HUIガイドのTrim＋AUTO操作を使用。現行Pro ToolsとMGでの動作確認はユーザー実機待ち。
https://device.report/m/8b4ab9875ce51d96b81c90560aaf741cb171bd4517c34df13a9b3a9eae2a7d2f
HUI実測プロトコルのZone/port表：
https://forum.bome.com/uploads/short-url/aX7AWqj6FpgMiEMQi0kACDDTSSi.pdf

8ch追従、分割パケット、複数選択／対象不明、OFF透過、Release抑制、バンク移動、
不透明UMP透過、リセット、Trim Read時のRecとの併用を自動テスト。
Trim表示のオレンジはReadとTouch等で共有するため、Recのモード推定には使用しない。
実機ではTrim ON→OFF、2番目・8番目への選択追従、バンク切替後、Recとの併用を確認する。

### Trim時のRecランプ修正

Trimのオレンジ（AUTO値64）を赤成分だけで判定していたため、Trim Readでも
Recランプが点灯していた。オレンジ時は同じチャンネルの純赤／純緑から追跡した
モード情報を使い、Readでは消灯、Touch等の録音可能モードでは点灯する。
モード不明のオレンジは消灯。通常の赤／消灯の点滅は従来どおり。
8chの緑↔オレンジ／赤↔オレンジ、Rec表示の上書き、Remap再同期／OFF復元、
リセット後を自動テスト済み。実機ランプでの確認はユーザー確認待ち。


## Rec／Trimスイッチの分離

接続画面とメニューバーに「Rec → Touch / Read」「メトロノーム → Trim」を個別表示。
Rec設定は既存のRemapEnabledキーを継続使用。TrimはMagicFaderTrimRemapEnabledに保存し、
キーがない初回だけ既存Remap値を引き継ぐ。以後はそれぞれ独立して保存・復元する。
復元は自動接続より前に行う。Solo Release補完は変更なし。
Rec OFFでは元のRec入力・ランプを使用し、Trim ONでもRecランプ変換を適用しない。
Rec ONのTrim Read消灯／Trim Touch点灯は維持。RecとTrimの全4組合せを自動テスト。
設定保持・移行・両画面の操作は実機確認待ち。
