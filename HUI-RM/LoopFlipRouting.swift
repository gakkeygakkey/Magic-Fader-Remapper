import Foundation

/// Magic Fader Loop: zone 0F, port 3. The device sends repeated presses without releases.
struct LoopFlipRouting {
    private var inputZone: UInt8?
    private var feedbackZone: UInt8?
    private var consumedPress = false
    private var originalLED: UInt32 = 0x20B02C03
    private var lastLED: UInt32?
    private struct PendingLED {
        let id: UUID
        let value: UInt32
        let due: TimeInterval
    }
    private var pendingLED: PendingLED?
    var pendingID: UUID? { pendingLED?.id }

    mutating func hardware(_ words: [UInt32], enabled: Bool) -> (words: [UInt32], presses: Int) {
        var output: [UInt32] = []
        var presses = 0
        Self.walk(words) { message in
            let word = message.first!
            if word == 0x10FF0000 { self = Self(); presses = 0 }
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = (word >> 8) & 0xFF, value = word & 0xFF
                if cc == 0x0F { inputZone = UInt8(value) }
                if inputZone == 0x0F, cc == 0x2F {
                    if value == 0x43, enabled { consumedPress = true; presses += 1; return }
                    if value == 3, consumedPress { consumedPress = false; return }
                }
            }
            output.append(contentsOf: message)
        }
        return (output, presses)
    }

    mutating func feedback(_ words: [UInt32], enabled: Bool, active: Bool?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [UInt32] {
        var output: [UInt32] = []
        Self.walk(words) { message in
            let word = message.first!
            if word == 0x10FF0000 { self = Self() }
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = (word >> 8) & 0xFF, value = word & 0xFF
                if cc == 0x0C { feedbackZone = UInt8(value) }
                if feedbackZone == 0x0F, cc == 0x2C, value == 3 || value == 0x43 {
                    originalLED = word
                    if enabled { return } // Loop LED is sent separately after the display burst.
                }
            }
            output.append(contentsOf: message)
        }
        if enabled {
            let value: UInt32 = active == true ? 0x20B02C43 : 0x20B02C03
            if value == lastLED { pendingLED = nil }
            else if pendingLED?.value != value {
                pendingLED = PendingLED(id: UUID(), value: value, due: now + 0.1)
            }
        }
        return output
    }

    mutating func sync(enabled: Bool, active: Bool?, force: Bool = false) -> [UInt32] {
        pendingLED = nil
        let value: UInt32 = enabled ? (active == true ? 0x20B02C43 : 0x20B02C03) : originalLED
        guard force || lastLED != value else { return [] }
        lastLED = value
        return ledWords(value)
    }

    mutating func takeLED(_ id: UUID, now: TimeInterval) -> [UInt32] {
        guard let pending = pendingLED, pending.id == id, now >= pending.due else { return [] }
        pendingLED = nil
        lastLED = pending.value
        return ledWords(pending.value)
    }

    private func ledWords(_ value: UInt32) -> [UInt32] {
        var words: [UInt32] = [0x20B00C0F, value]
        if let feedbackZone, feedbackZone != 0x0F { words.append(0x20B00C00 | UInt32(feedbackZone)) }
        return words
    }

    private static func walk(_ words: [UInt32], _ body: (ArraySlice<UInt32>) -> Void) {
        var i = 0
        while i < words.count {
            let n = min(RecAutomationRemapper.messageWidth(words[i]), words.count - i)
            body(words[i..<(i+n)])
            i += n
        }
    }
}
