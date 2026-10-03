import Foundation

/// Short, device-only replay of fresh PT feedback after a local Flip request.
/// Owned by MIDIProxy's lock. Never caches data across requests or sends to PT.
struct FlipFeedbackReplay {
    private(set) var id: UUID?
    private var inputZone: UInt8?
    private var feedbackZone: UInt8?
    private var displays: [UInt8: [UInt32]] = [:]
    private var positions: [UInt8: [UInt32]] = [:]
    private var highs: [UInt8: (UInt32, TimeInterval)] = [:]
    private var sysex: [UInt32] = []
    private var stage = 0
    private(set) var isSendChange = false
    private var expires: TimeInterval = 0

    mutating func begin(now: TimeInterval, sendChange: Bool = false) -> UUID {
        cancel()
        let token = UUID()
        id = token
        isSendChange = sendChange
        stage = sendChange ? 1 : 0
        expires = now + 0.7
        return token
    }

    mutating func cancel() {
        id = nil
        displays.removeAll(); positions.removeAll(); highs.removeAll()
        sysex.removeAll(); stage = 0
    }

    @discardableResult
    mutating func hardware(_ words: [UInt32], flipActive: Bool = false, now: TimeInterval = 0) -> UUID? {
        var requested: UUID?
        walk(words) { message in
            let word = message[0]
            if word == 0x10FF0000 { cancel(); return }
            guard word & 0xFFFF0000 == 0x20B00000 else { return }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0F { inputZone = value }
            // Interaction takes priority, including touch, bank, assignment and refresh.
            if cc < 8 || (0x20...0x27).contains(cc) { cancel() }
            if cc == 0x2F {
                let sendPress = inputZone == 0x0B && (0x43...0x47).contains(value)
                let sendRelease = inputZone == 0x0B && (3...7).contains(value)
                if !(inputZone == 0x0F && (value == 0x43 || value == 3)) && !sendRelease { cancel() }
                if sendPress, flipActive { requested = begin(now: now, sendChange: true) }
            }
        }
        return requested == id ? requested : nil
    }

    mutating func feedback(_ words: [UInt32], now: TimeInterval) {
        guard id != nil else { return }
        walk(words) { message in
            let word = message[0]
            if word == 0x10FF0000 { cancel(); return }
            guard id != nil else { return }
            if message.count == 2, word >> 24 == 0x30 {
                // Only exact HUI four-character display messages, including split callbacks.
                if word == 0x30160000, message[1] == 0x66050010 {
                    sysex = message
                } else if sysex.count == 2, word & 0xFFFF0000 == 0x30350000 {
                    let zone = UInt8((word >> 8) & 0xFF)
                    if zone <= 8 { displays[zone] = sysex + message }
                    sysex.removeAll()
                } else { sysex.removeAll() }
            }
            guard word & 0xFFFF0000 == 0x20B00000 else { return }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0C { feedbackZone = value }
            if cc == 0x2C, let zone = feedbackZone, zone < 8, value == 0x41 {
                cancel(); return // A new track selection invalidates this replay.
            }
            if cc < 8 {
                positions[cc] = nil
                highs[cc] = (word, now)
            } else if (0x20...0x27).contains(cc) {
                let zone = cc - 0x20
                if let high = highs.removeValue(forKey: zone), now - high.1 <= 0.1 {
                    positions[zone] = [high.0, word]
                }
            }
        }
    }

    /// Call first at 150ms, then every 20ms. One complete message per step.
    mutating func next(_ token: UUID, now: TimeInterval) -> [UInt32] {
        guard id == token else { return [] }
        guard now <= expires, isSendChange || displays[8] != nil else { cancel(); return [] }
        let output: [UInt32]
        if stage == 0 { output = displays[8] ?? [] }
        else if stage <= 8 { output = displays[UInt8(stage - 1)] ?? [] }
        else { output = positions[UInt8(stage - 9)] ?? [] }
        stage += 1
        if stage == 17 { cancel() }
        return output
    }

    private func walk(_ words: [UInt32], _ body: ([UInt32]) -> Void) {
        var offset = 0
        while offset < words.count {
            let width = min(RecAutomationRemapper.messageWidth(words[offset]), words.count - offset)
            body(Array(words[offset..<(offset + width)]))
            offset += width
        }
    }
}
