import Foundation

/// Only the measured Solo switch is repaired. All state is owned by MIDIProxy's lock.
struct MagicFaderReleaseRepair {
    struct Ticket: Equatable, Sendable {
        let zone: UInt8
        let serial: UInt64
    }
    private(set) var zone: UInt8?
    private var serial: UInt64 = 0
    private var pending: [UInt8: Ticket] = [:]

    static func matchesDevice(_ name: String) -> Bool {
        name.lowercased().filter { $0.isLetter || $0.isNumber } == "magicfader"
    }

    mutating func cancel() { pending.removeAll() }

    mutating func process(_ words: [UInt32], enabled: Bool) -> (words: [UInt32], tickets: [Ticket]) {
        var output: [UInt32] = []
        var tickets: [Ticket] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let width = min(RecAutomationRemapper.messageWidth(word), words.count - index)
            if word == 0x10FF0000 { cancel(); zone = nil }
            if word & 0xFFFFFF00 == 0x20B00F00 { zone = UInt8(word & 0xFF) }
            if let zone, zone < 8 {
                if word == 0x20B02F03 { pending.removeValue(forKey: zone) }
                if enabled, word == 0x20B02F43 {
                    // Finish the old press before forwarding a fast second press.
                    if pending.removeValue(forKey: zone) != nil {
                        output += releaseWords(zone: zone)
                    }
                    serial &+= 1
                    let ticket = Ticket(zone: zone, serial: serial)
                    pending[zone] = ticket
                    tickets.append(ticket)
                }
            }
            output.append(contentsOf: words[index..<(index + width)])
            index += width
        }
        return (output, tickets)
    }

    func releaseWords(zone target: UInt8) -> [UInt32] {
        guard target < 8 else { return [] }
        var words: [UInt32] = [0x20B00F00 | UInt32(target), 0x20B02F03]
        if let zone, zone != target { words.append(0x20B00F00 | UInt32(zone)) }
        return words
    }

    mutating func take(_ ticket: Ticket) -> [UInt32] {
        guard pending[ticket.zone] == ticket else { return [] }
        pending.removeValue(forKey: ticket.zone)
        return releaseWords(zone: ticket.zone)
    }

    mutating func releaseNow(zone: UInt8) -> [UInt32] {
        pending.removeValue(forKey: zone)
        return releaseWords(zone: zone)
    }

    mutating func finishPending() -> [UInt32] {
        let words = pending.keys.sorted().flatMap { releaseWords(zone: $0) }
        cancel()
        return words
    }
}
