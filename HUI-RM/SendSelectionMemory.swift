import Foundation

/// Observes MG input after optional transport remapping; automatic Pan/Send restoration never enters here.
struct SendSelectionMemory {
    static let preferenceKey = "MagicFaderLastSendPort"
    private let defaults: UserDefaults
    private var zone: UInt8?
    private(set) var port: UInt8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: Self.preferenceKey)
        port = (3...7).contains(saved) ? UInt8(saved) : 7 // Send A
    }

    mutating func resetRoute() { zone = nil }

    mutating func observe(_ words: [UInt32]) {
        var offset = 0
        while offset < words.count {
            let word = words[offset]
            offset += min(RecAutomationRemapper.messageWidth(word), words.count - offset)
            if word == 0x10FF0000 { zone = nil; continue }
            guard word & 0xFFFF0000 == 0x20B00000 else { continue }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0F { zone = value }
            if zone == 0x0B, cc == 0x2F, (0x43...0x47).contains(value) {
                let selected = value & 7
                if port != selected {
                    port = selected
                    defaults.set(Int(port), forKey: Self.preferenceKey)
                }
            }
        }
    }
}
