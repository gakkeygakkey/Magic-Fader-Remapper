import Foundation

/// MG transport presses select adjacent send slots; STOP and other messages pass through.
struct TransportSendRouting {
    private var zone: UInt8?
    private var consumed: Set<UInt8> = []

    mutating func process(_ words: [UInt32], enabled: Bool, currentPort: UInt8) -> [UInt32] {
        var output: [UInt32] = []
        var selected = (3...7).contains(currentPort) ? currentPort : 7
        var offset = 0
        while offset < words.count {
            let word = words[offset]
            let width = min(RecAutomationRemapper.messageWidth(word), words.count - offset)
            let message = Array(words[offset..<(offset + width)])
            offset += width
            if word == 0x10FF0000 { self = Self() }
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
                if cc == 0x0F { zone = value }
                if zone == 0x0B, cc == 0x2F, (0x43...0x47).contains(value) {
                    selected = value & 7
                }
                if zone == 0x0E, cc == 0x2F {
                    if (value == 1 || value == 2), consumed.remove(value) != nil { continue }
                    if enabled, value == 0x41 || value == 0x42 {
                        consumed.insert(value & 7)
                        // Send A...E uses descending ports 7...3.
                        selected = value == 0x41
                            ? (selected == 7 ? 3 : selected + 1)
                            : (selected == 3 ? 7 : selected - 1)
                        output += [0x20B00F0B, 0x20B02F40 | UInt32(selected),
                                   0x20B00F0B, 0x20B02F00 | UInt32(selected), 0x20B00F0E]
                        continue
                    }
                    // An unconverted press starts a normal transport lifecycle.
                    if value == 0x41 || value == 0x42 { consumed.remove(value & 7) }
                }
            }
            output += message
        }
        return output
    }
}
