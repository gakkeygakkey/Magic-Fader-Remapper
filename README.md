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

## MG録音ボタン → Trim（2026-09-29更新）

「録音ボタン → Trim」ONかつMagic Fader接続時、トランスポート録音
Zone 0E / port 5のPress（20B00F0E / 20B02F45）をTrim切替に置換する。
実測でReleaseがないため、押下ごとにTrim＋対象AUTOの押下／解除を完結する。
Releaseが来た場合も元の録音操作には流さない。OFF時は元の録音通信を通す。
メトロノーム（Zone 15 / port 0）は元の通信に戻す。
Rec・Trim・Solo補完は独立した保存済み設定。既存Trim設定キーはそのまま使用。

SELECT LED通知（Zone 00〜07 / port 1）から単一の選択対象を追跡し、
Trim（Zone 18 / port 0）を押したまま対象AUTOを押して離し、Trimも離す。
入力Zoneを0Eへ戻す。対象不明・複数選択では元の録音もTrimも送らない。
画面に対象チャンネル／未確定を表示。Pro Toolsのグループ設定による連動は維持。

録音LED（Zone 0E / port 5）は選択対象のAUTOオレンジ通知（64）からTrimを推定して点灯。
赤／緑との交互表示中は点灯を保つ。非オレンジに変わって0.5秒間オレンジが戻らなければ
消灯（ポーリング込み通常約0.5〜0.75秒）。オレンジが最後の通知なら連続点灯を維持。
未知・選択なし・複数選択は消灯。これは正確なモード照会ではなくHUI表示からの推定。
起動／対象変更後は通知待ちになり、実際の表示周期によっては調整が必要。
Pro Tools由来の録音LEDを置換し、設定OFF／切断時に最後の元の録音表示へ戻す。
チャンネル／バンク移動、切断、リセットで古い選択を利用しない。

HUI Trim＋AUTOの根拠：
https://device.report/m/8b4ab9875ce51d96b81c90560aaf741cb171bd4517c34df13a9b3a9eae2a7d2f
Zone/port表：
https://forum.bome.com/uploads/short-url/aX7AWqj6FpgMiEMQi0kACDDTSSi.pdf

8ch切替、Pressのみの連続操作、独立スイッチ4組合せ、LED点滅／連続点灯／消灯、
選択追従、元の録音表示の抑制／復元、メトロノーム透過をテスト。
実機での録音ボタン切替とLED追従は確認待ち。

### Trim時のRecランプ修正

Trimのオレンジ（AUTO値64）を赤成分だけで判定していたため、Trim Readでも
Recランプが点灯していた。オレンジ時は同じチャンネルの純赤／純緑から追跡した
モード情報を使い、Readでは消灯、Touch等の録音可能モードでは点灯する。
モード不明のオレンジは消灯。通常の赤／消灯の点滅は従来どおり。
8chの緑↔オレンジ／赤↔オレンジ、Rec表示の上書き、Remap再同期／OFF復元、
リセット後を自動テスト済み。実機ランプでの確認はユーザー確認待ち。


## Rec／Trimスイッチの分離

接続画面とメニューバーに「Rec → Touch / Read」「録音ボタン → Trim」を個別表示。
Rec設定は既存のRemapEnabledキーを継続使用。TrimはMagicFaderTrimRemapEnabledに保存し、
キーがない初回だけ既存Remap値を引き継ぐ。以後はそれぞれ独立して保存・復元する。
復元は自動接続より前に行う。Solo Release補完は変更なし。
Rec OFFでは元のRec入力・ランプを使用し、Trim ONでもRecランプ変換を適用しない。
Rec ONのTrim Read消灯／Trim Touch点灯は維持。RecとTrimの全4組合せを自動テスト。
設定保持・移行・両画面の操作は実機確認待ち。


### Trim LEDの即時反応（検証版）

MGの録音ボタン押下時は、最後に観測したTrim状態（連打中は直前の予測）を反転し、
Pro Toolsへの操作送信成功直後にLEDを更新。定期ポーリングを待たない。
予測は最大0.8秒で失効し、実際のAUTO表示に戻す。ONはオレンジ受信で確定し、
OFFは非オレンジが0.5秒続いた観測で確定する。古いオレンジが直後に届いても
OFF予測を即座に上書きしない。切断・リセット・送信失敗・Trim設定変更で予測を破棄。
予測は状態照会ではなく、対象状態が未知／古い場合は補正時にLEDが戻る可能性がある。

0.5秒の解除判定は実測Readの緑→オレンジ約0.27秒を基準にした試験値。
Touch・再生／書込み中の周期は実機確認が必要。点灯／消灯の即時更新、古い通知、
不成立時の補正、連打を自動テスト。HUI操作本体の送信順序・タイミングは変更しない。


### Rec Ready表示を通常Touch／Trim Touchで統一

録音ボタンのLEDでTrimを独立表示するため、Rec ReadyはAUTOの純赤44で点灯し、
オレンジ64・緑24・消灯04では消灯する。通常Touchの赤↔消灯、Trim Touchの
赤↔オレンジを、どちらもRec Readyの点灯↔消灯として表示。
Read／Trim Readは消灯を維持。点滅はPro Toolsの通知に従い、自前タイマーは追加しない。
この時点ではオレンジが連続する書込み中も消灯していた。下記の物理タッチ追従で修正。
録音ボタンのTrim LED・即時反映・Rec/Trim切替の送信処理は変更なし。
以前の「Trim TouchはRec連続点灯」の記述はこの変更で置き換える。


### Trim Touchの物理フェーダータッチ表示

Zone 00〜07 / port 0のPress40とRelease00をチャンネル別に追跡。
Pro Toolsの表示から録音可能モードかつTrimが確認でき、フェーダーに触れている間は
Rec Readyを連続点灯する。離すと赤で点灯／オレンジで消灯の待機表示に戻る。
物理入力をそのままPro Toolsへ転送後、同じチャンネルのRec LEDを即時更新する。
Readでは触れても点灯させず、RecリマップOFFでは追加LED送信なし。
実際の書込み開始を照会する機能ではなく、物理タッチとHUIモード表示による表示補助。
通常Touchの既存表示と録音ボタンのTrim表示は維持。初回のモード情報が不明なら
点灯を推測しない。切断・リセット・バンク移動・送信失敗でタッチ状態を破棄。
8ch、分割入力、別チャンネル操作、リリース復帰、Read/無効時を自動テスト済み。
実機でのタッチ／離した時の表示は確認待ち。

## MGメトロノーム：手動フェーダーリフレッシュ（試験機能）

専用スイッチ「メトロノーム → リフレッシュ」はON/OFFを保存し、次回起動時に復元する（初回はOFF）。Magic Faderのみ対象。
設定キーはMagicFaderRefreshEnabled。自動接続より前に画面と中継エンジンへ保存値を反映する。
ON時はZone 15 / port 0のPress/Releaseを消費し、OFF時は元の機能。
Pro Toolsから受け取った完全なフェーダー位置を8chそれぞれ保存し、
最後にSELECT LED ONを受け取ったチャンネルへ保存位置から約5％ずらした位置を送り、100ms後にその保存位置を送り直す。
移動幅は14bit位置範囲の819。通常は下へ、保存位置が819未満なら上へ動かす。
MGの動作に合わせ、SELECT LED OFFでも対象を保持し、バンク外のトラック選択時にも使える。
次のバンク内SELECT ONで対象を更新する。接続後に一度も対象を取得していない場合は移動しない。
Trim設定・STOP LEDには依存しない。選択通知で保存位置を消さない。
位置未取得・手で触れている場合には移動しない。

位置はGroup 0 / MIDI ch 1のCC00〜07・20〜27の組から取得する。
分割パケットは100ms以内の同一チャンネルの組に対応する。
保存するのはPT由来の値だけで、アプリが送る移動指示やMGからの値は混ぜない。
複数チャンネルが届いても、それぞれの位置を保存し、最後に選択されたチャンネルだけを使う。
このチャンネルでMGの物理フェーダーが動くことは実機で確認する。

MGからのフェーダー値は遮断せず、タッチ・Ping・他の操作とともに通常中継する。
途中でタッチ・別チャンネルのSELECT ON・バンク操作・新しいPT位置指示が来たら予約した復帰を取り消す。
タッチ解除後にも古い値への復帰は行わない。動作中の再押下は無視する。
OFF・切断時に復帰予約が残っていれば、可能なら即時に保存位置を送って終了する。
切断時は状態をリセットし、古いタイマーを新接続へ持ち越さない。

自動テストで8chの往復指示、選択変更後の位置保持、対象チャンネル一致、バンク外選択時の対象保持、分割位置、最新位置優先、
タッチ時中断、通常通信の透過、連打、OFF・リセットを確認する。
実際の移動と唸りの改善は実機確認が必要。停止中・手を離した状態で試し、
MGの往復とPro Toolsの値が変わらないことを確認する。

## Flip（実機テスト用）

接続画面の「Flip切替」と本体ループボタンは、Flipの押下・Releaseだけを即時送信する。
Send Aの強制選択や200msの待機は行わず、MGで選択した対象をPTに任せる。
MG接続時のみ有効。ON/OFFの絶対指定ではなくトグル操作。
起動・接続時には自動送信せず、Flip状態を設定として保存もしない。
Pan選択中の対象とセンドB〜Eの追従は、この版で実機確認する。

- Flip: Zone 0C / port 3、Press `B0 0F 0C / B0 2F 43`、Release `B0 0F 0C / B0 2F 03`
- PT Flipランプ: Zone 0C、`B0 2C 43` 点灯 / `B0 2C 03` 消灯

元の入力Zoneが分かっていればコマンド末尾で復元する。フェーダータッチ中の切替を拒否し、
Flipコマンドの末尾で最新の入力Zoneへ戻す。
0.5秒以内の連打を抑制。PT由来のランプ通知だけを表示し、送信成功をモード成立とみなさない。
Flipランプは点滅するため、消灯通知単体を「Flip OFF」と解釈しない。状態未受信も区別する。
リフレッシュの復帰予約と位置キャッシュは切替要求時に破棄し、新しい割り当ての位置通知を待つ。
Rec/Trim/Soloの変換や通常のフェーダー・タッチ通信は従来どおり。Flip中の意味はPT側の割り当てに従う。
アプリ終了時にもFlipを推測で切り替えない。テスト終了時は同じボタンで戻したことをPTで確認する。

確認手順：MGでセンドBを選んだ場合とPanを選んだ場合を比較する。センドを割り当てたトラックを選び、通常の音量とセンド音量を異なる位置にして、
停止中・フェーダーから手を離して切替。MGのモーター追従、センド音量の操作、タッチ通知と
オートメーションを確認し、再度切替してトラック音量操作へ戻ることを確認する。
HUIのFlipではチャンネルMuteもセンドMuteへ、V-PotはセンドPanへ切り替わる。

信号形式は[HUI実測解析資料のHardware layout](https://forum.bome.com/uploads/short-url/aX7AWqj6FpgMiEMQi0kACDDTSSi.pdf)、
機能は[Digidesign MIDI Control Surfaces GuideのFader Flip mode（p.56）](https://device.report/m/8b4ab9875ce51d96b81c90560aaf741cb171bd4517c34df13a9b3a9eae2a7d2f)に基づく。
MGと現在のPro Toolsでの往復・表示・操作解像度は実機未確認。

Flipの行き／戻り判定は、PTのSelect/Assign表示（Zone 8）のFLIP／SndA〜E／Pan／Out／Inpを使用する。
Flipランプの点灯通知でもFlip側と判断するが、点滅の消灯通知ではOFFへ変更しない。
チャンネル名（Zone 0〜7）は判定に使わない。状態未取得時もFlipだけを送信する。

## MG ループ → Flip

独立スイッチ「ループ → Flip」がONなら、MGのZone 0F / port 3 Pressを消費し、
画面の「Flip切替」と同じく、行きも戻りもFlipのみを送る。Releaseを送らないMGの実測に合わせ、各Pressを別操作として扱う
（既存の500ms連打抑止は維持）。スイッチはMagicFaderLoopFlipEnabledで保存、初回はOFF。
スイッチOFF時は通常のループ操作へ戻す。変換済みPressに対するReleaseが来た場合は消費する。

ON中のループランプはFlip状態に追従し、Flip中は点灯、通常時・未確定時は消灯する。
PTからの元のLoopランプ通知は保持し、ON中はその指示だけを中継から除く。
Flip状態が変わった時のLED指示は表示パケットへ追加せず、100ms後に単独送信する。
待機中は最新状態を優先し、OFF・切断・リセットで古い予約を無効にする。Flipランプの点滅の暗い位相では
ループランプを消さない。OFF・切断時は最後にPTから通知された通常Loop表示へ戻す
（未受信時は消灯）。追加LED指示の末尾ではフィードバックZoneを復元する。
スイッチOFFは割り当てを解除するだけで、PTのFlipモード自体を自動解除しない。
実機ではループ操作がPTへ漏れないこと、Flip往復、ランプ点灯・消灯、OFF時の元機能を確認する。

### Flip後のMF再送試験

Flip要求後に受け取ったPTのモード表示・8chの名前・位置だけを保持し、150ms後から
モード表示→名前（各ch）→位置（各ch）の順に20ms間隔で一度だけMFへ再送する。
元の中継は変更せず、PTへの追加操作は送らない。ループLEDは従来の100ms後の単独送信。
位置は再送時点の最新の完全なMSB/LSBペアを使用する。切替前のキャッシュは使わない。
新たなFlip要求、タッチや本体操作、PTのトラック選択通知、切断・リセットで古い再送を破棄し、
700msを超えて遅延した再送も破棄する。MFでの表示・モーター改善は実機確認が必要。

### Flip解除後のPan選択試験

Flip中と確認できている状態からの解除要求では、既存の再送が終わる550ms後にPanの
Press/Release（Zone 0B / port 2）を送信する。PTの解除表示を確認できた場合のみ実行する。
タッチ、本体での割り当て・バンク操作、新たなFlip要求、切断・リセット・送信失敗で取り消す。
Pan応答の表示も既存の間隔付き再送で補完する。センド選択の記憶・復元はまだ行わない。
Send B等へ戻った後にトラック名が復帰するか、MF実機で確認するための変更。

### 前回のセンドを復元（任意）

Flip設定のサブスイッチ。初期OFFで、MagicFaderRestoreSendEnabledに保存する。
MGの物理入力のZone 0B / port 3〜7のPressだけから最後のSend E〜Aを覚え、
MagicFaderLastSendPortに保存する。未選択・不正な保存値はSend Aを使う。
OFF中も本体で選んだセンドは記録するが、Flip動作は従来のまま。
ON時の入り操作は保存済みSendのPress/Release→200ms→Flip。
待機中の本体操作、OFFへの変更、切断・リセット・送信失敗は予約を取り消す。
解除は従来どおりFlip→550ms後Pan。本体Pan選択やアプリが生成するPan/Sendでは
保存済みセンドを上書きしない。アプリ起動時は復元操作を送らず、次のFlip時だけ適用する。

### Flip中の本体センド変更の補完

MGの物理入力でSend A〜Eが選ばれ、Flip中と判定できていてタッチ中でない場合は、
通常中継の後、150ms後から名前→位置を20ms間隔で一度だけMFへ再送する。
この操作ではPTがFLIP表示を再通知しないため、モード表示は必須とせず再送もしない。
新しく受け取った名前・完全な位置ペアのみ使用し、直前のセンドのデータは引き継がない。
連続選択では前の予約を置き換え、タッチ・トラック選択・Input/Output/Pan操作・切断・リセットで中止する。
センド選択Releaseでは中止しない。PTへの追加選択命令は送らない。

### 巻き戻し／早送り → センド切替

独立スイッチ（初期OFF、MagicFaderTransportSendEnabledで保存）。MG接続時のみ適用し、
Flip状態に関係なくZone 0E / port 1・2のPressを、前／次のSend選択へ置き換える。
早送りはA→B→C→D→E→A、巻き戻しは逆順。基準は最後に選んだセンド、未選択時はA。
停止（port 3）と他の通信はそのまま。OFF時は通常のトランスポート操作へ戻る。
Releaseなしの実測に合わせ各Pressを1操作とし、送信するSendにはPress/Releaseを付け、
入力Zoneを0Eに戻す。変換済みPressのReleaseが後から来た場合はOFF後も消費する。
本体V-Pot選択と同じセンド記憶を更新し、Flip中はBus名・位置再送も適用する。
長押しの自動連打は追加しない。実機ではトランスポートが移動せず、前後選択・循環・停止が機能するか確認する。

## 設定画面

本体図の左カラムと設定スイッチの右カラムで構成する。青いボタン表示は設定上の割り当てで、
実機LEDの状態ではない。項目にポインタを合わせると該当ボタンを強調し、詳細をツールチップで表示する。
接続ポートは上部の「接続設定」で開閉。「詳細・検証…」はログ、手動Flip、通信カウンターと状態表示の
別ウインドウを開く。両画面は同じProxyModelを共有し、通信・保存設定の動作は従来どおり。

設定項目のホバー時は下部の固定高の機能ガイドも即時更新する。ポインタを外しても最後の説明を保持する。
本体図・項目の強調はホバー中だけ。説明欄はスクロール領域の外にあり、小さいウインドウでも表示される。

## アプリ表示名 MF-RM

アプリ本体・メニュー・ウインドウの名称はMF-RM。設定画面の見出しにフェーダーマークを表示する。
既存設定を引き継ぐためbundle IDはcom.gakkey.HUI-RMを維持し、仮想MIDIポート名もHUI-RMのまま。
Pro Toolsで選ぶ受信元・送信先の再設定は不要。Xcodeのプロジェクト・ターゲット名はHUI-RMを維持する。
Soloの項目名は「Solo Release補完」。機能ガイドでは押された状態が残る問題の補正を説明し、リフレッシュはモーターの唸りへの対処として説明する。
