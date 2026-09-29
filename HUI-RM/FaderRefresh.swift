import Foundation

/// Manual motor movement. Owned exclusively by MIDIProxy's lock.
struct FaderRefresh {
    private struct High {
        let value: UInt8
        let at: TimeInterval
    }
    private struct Position {
        let zone: UInt8
        let value: UInt16
    }
    private struct Run {
        let position: Position
        let due: TimeInterval
    }
    private var highs: [UInt8: High] = [:]
    private var positions: [UInt8: Position] = [:]
    private var feedbackZone: UInt8?
    private var lastSelectedZone: UInt8?
    private var touched: Set<UInt8> = []
    private var inputZone: UInt8?
    private var run: Run?
    private var consumedClick = false
    private(set) var notice = "Pro Toolsの位置通知を待機"
    var active: Bool { run != nil }

    static func positionWords(zone: UInt8, value: UInt16) -> [UInt32] {
        [0x20B00000 | UInt32(zone) << 8 | UInt32(value >> 7),
         0x20B02000 | UInt32(zone) << 8 | UInt32(value & 0x7F)]
    }

    mutating func hardware(_ words: [UInt32], enabled: Bool, now: TimeInterval) -> (host: [UInt32], device: [UInt32]) {
        var host: [UInt32] = []
        var device: [UInt32] = []
        Self.walk(words) { message in
            let word = message.first!
            if word == 0x10FF0000 { self = Self() }
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
                if cc == 0x0F { inputZone = value }
                if let zone = inputZone, zone < 8, cc == 0x2F {
                    if value == 0x40 {
                        touched.insert(zone)
                        cancel("中断：フェーダー操作を優先")
                    } else if value == 0 { touched.remove(zone) }
                }
                if inputZone == 0x0A, cc == 0x2F, value & 0x40 != 0 {
                    cancel("中断：トラック移動を優先")
                }
                if inputZone == 0x15, cc == 0x2F {
                    if value == 0, consumedClick { consumedClick = false; return }
                    if value == 0x40, enabled {
                        guard !consumedClick else { return }
                        consumedClick = true
                        guard run == nil else { return }
                        guard touched.isEmpty else { notice = "フェーダーから手を離してください"; return }
                        guard let zone = lastSelectedZone else {
                            notice = "バンク内のトラックを一度選択してください"; return
                        }
                        guard let position = positions[zone] else { notice = "選択チャンネルの位置通知を待機"; return }
                        // About 5% of the 14-bit position range. Move upward near the bottom.
                        let distance: UInt16 = 819
                        let offset = position.value < distance ? position.value + distance : position.value - distance
                        run = Run(position: position, due: now + 0.1)
                        notice = "リフレッシュ中：約5％移動"
                        device = Self.positionWords(zone: position.zone, value: offset)
                        return
                    }
                }
            }
            // Physical touch and position messages retain their normal route.
            host.append(contentsOf: message)
        }
        // A touch or reset later in the same packet cancels even the initial move.
        if run == nil { device.removeAll() }
        return (host, device)
    }

    /// Cache only original PT positions; injected motor commands never enter here.
    mutating func feedback(_ words: [UInt32], now: TimeInterval) {
        Self.walk(words) { message in
            let word = message.first!
            if word == 0x10FF0000 { self = Self(); return }
            guard word & 0xFFFF0000 == 0x20B00000 else { return }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0C { feedbackZone = value }
            if let zone = feedbackZone, zone < 8, cc == 0x2C, value == 0x41 {
                if lastSelectedZone != zone { cancel("中断：トラック選択変更を優先") }
                lastSelectedZone = zone
                // MG retains its physical fader target after SELECT turns off.
                // Neither deselection nor other channels' positions replace it.
            }
            if cc < 8 {
                highs[cc] = High(value: value, at: now)
                cancel("Pro Toolsの新しい位置を優先")
            } else if (0x20...0x27).contains(cc) {
                let zone = cc - 0x20
                if let high = highs.removeValue(forKey: zone), now - high.at <= 0.1 {
                    positions[zone] = Position(zone: zone, value: UInt16(high.value) << 7 | UInt16(value))
                    if run == nil { notice = "準備完了" }
                }
                cancel("Pro Toolsの新しい位置を優先")
            }
        }
    }

    mutating func tick(now: TimeInterval) -> [UInt32] {
        guard let current = run, now >= current.due else { return [] }
        run = nil
        notice = "元の位置へ復帰指示を送信"
        return Self.positionWords(zone: current.position.zone, value: current.position.value)
    }

    mutating func disable(now: TimeInterval) -> [UInt32] {
        guard let current = run else { return [] }
        run = nil
        notice = "元の位置へ復帰指示を送信"
        return Self.positionWords(zone: current.position.zone, value: current.position.value)
    }

    private mutating func cancel(_ reason: String) {
        if run != nil { run = nil; notice = reason }
    }

    private static func walk(_ words: [UInt32], _ body: (ArraySlice<UInt32>) -> Void) {
        var index = 0
        while index < words.count {
            let width = min(RecAutomationRemapper.messageWidth(words[index]), words.count - index)
            body(words[index..<(index + width)])
            index += width
        }
    }
}
