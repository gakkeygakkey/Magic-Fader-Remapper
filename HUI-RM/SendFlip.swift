import Foundation

/// HUI Select/Assign: zone 0C port 3 = SHIFT (Flip); preserve the current assignment.
/// Observe LED packets without mistaking a blinking LED's dark phase for mode OFF.
struct SendFlip {
    private var hostZone: UInt8?
    private var feedbackZone: UInt8?
    private var touched: Set<UInt8> = []
    private(set) var lamp: Bool?
    private(set) var flipActive: Bool?
    private var displayBytes: [UInt8]?
    private(set) var notice = NSLocalizedString("Not used yet", comment: "")
    private(set) var pendingPanID: UUID?
    private(set) var pendingFlipID: UUID?
    private var flipDue: TimeInterval = 0
    private var panDue: TimeInterval = 0
    private var nextRequestAt: TimeInterval = 0
    var isTouched: Bool { !touched.isEmpty }

    var lampText: String {
        guard let lamp else { return NSLocalizedString("PT Flip LED: No feedback", comment: "") }
        return lamp ? NSLocalizedString("PT Flip LED: On message", comment: "") : NSLocalizedString("PT Flip LED: Off message", comment: "")
    }

    mutating func observeHost(_ words: [UInt32]) {
        Self.walk(words) { word in
            if word == 0x10FF0000 { self = Self(); return }
            guard word & 0xFFFF0000 == 0x20B00000 else { return }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0F { hostZone = value }
            if cc == 0x2F, value & 0x40 != 0, hostZone == 0x0B || hostZone == 0x0A { pendingPanID = nil }
            if let zone = hostZone, zone < 8, cc == 0x2F {
                if value == 0x40 {
                    touched.insert(zone)
                    pendingPanID = nil

                }
                if value == 0 { touched.remove(zone) }
            }
        }
    }

    mutating func observeFeedback(_ words: [UInt32]) {
        var offset = 0
        while offset < words.count {
            let width = min(RecAutomationRemapper.messageWidth(words[offset]), words.count - offset)
            if width == 2, words[offset] >> 24 == 0x30 {
                observeDisplay(words[offset], words[offset + 1])
            }
            let word = words[offset]
            offset += width
            if word == 0x10FF0000 { self = Self(); continue }
            guard word & 0xFFFF0000 == 0x20B00000 else { continue }
            let cc = UInt8((word >> 8) & 0xFF), value = UInt8(word & 0xFF)
            if cc == 0x0C { feedbackZone = value }
            if feedbackZone == 0x0C, cc == 0x2C, value == 0x43 || value == 0x03 {
                lamp = value == 0x43
                if lamp == true { flipActive = true } // Dark phases never mean mode OFF.
            }
        }
    }

    mutating func request(now: TimeInterval, restorePort: UInt8? = nil) -> [UInt32] {
        guard !isTouched else { notice = NSLocalizedString("Take your hand off the fader", comment: ""); return [] }
        guard now >= nextRequestAt else { return [] }
        pendingFlipID = nil
        pendingPanID = flipActive == true ? UUID() : nil
        if flipActive != true, let port = restorePort, (3...7).contains(port) {
            pendingFlipID = UUID()
            flipDue = now + 0.2
            nextRequestAt = now + 0.5
            notice = NSLocalizedString("Last send selected: Flip scheduled in 200 ms", comment: "")
            return restoringZone([0x20B00F0B, 0x20B02F40 | UInt32(port), 0x20B00F0B, 0x20B02F00 | UInt32(port)])
        }
        panDue = now + 0.55
        nextRequestAt = now + 0.5
        notice = NSLocalizedString("Flip toggle sent", comment: "")
        return restoringZone([0x20B00F0C, 0x20B02F43, 0x20B00F0C, 0x20B02F03])
    }

    mutating func cancelRestore() { pendingFlipID = nil }

    /// Call only for physical input, before observeHost sees generated commands.
    mutating func observeRestoreInteraction(_ words: [UInt32]) {
        Self.walk(words) { word in
            if word == 0x10FF0000 { pendingFlipID = nil }
            guard word & 0xFFFF0000 == 0x20B00000 else { return }
            let cc = UInt8((word >> 8) & 0xFF)
            // A new physical switch, encoder or fader operation takes priority.
            if cc != 0x0F { pendingFlipID = nil }
        }
    }

    mutating func takeRestoredFlip(_ id: UUID, now: TimeInterval) -> [UInt32] {
        guard pendingFlipID == id, now >= flipDue else { return [] }
        pendingFlipID = nil
        guard !isTouched, flipActive != true, now <= flipDue + 0.3 else { return [] }
        notice = NSLocalizedString("Flip toggle sent for the last send", comment: "")
        return restoringZone([0x20B00F0C, 0x20B02F43, 0x20B00F0C, 0x20B02F03])
    }

    mutating func takePan(_ id: UUID, now: TimeInterval) -> [UInt32] {
        guard pendingPanID == id, now >= panDue else { return [] }
        pendingPanID = nil
        // Require PT confirmation, not the blinking lamp's dark phase.
        guard flipActive == false, !isTouched, now <= panDue + 0.3 else { return [] }
        notice = NSLocalizedString("Pan selection sent after exiting Flip", comment: "")
        return restoringZone([0x20B00F0B, 0x20B02F42, 0x20B00F0B, 0x20B02F02])
    }

    private func restoringZone(_ command: [UInt32]) -> [UInt32] {
        var words = command
        // Preserve a controller zone selection split across callbacks.
        if let hostZone { words.append(0x20B00F00 | UInt32(hostZone)) }
        return words
    }

    mutating func sendFailed() {
        pendingFlipID = nil
        pendingPanID = nil
        lamp = nil
        flipActive = nil
        displayBytes = nil
        notice = NSLocalizedString("Could not send the toggle. Check the log.", comment: "")
    }

    /// Select/Assign display (zone 8), observed in PT logs: FLIP / SndA.
    /// Channel names (zones 0...7) must never affect mode detection.
    private mutating func observeDisplay(_ first: UInt32, _ second: UInt32) {
        let status = Int((first >> 20) & 0xF)
        let count = Int((first >> 16) & 0xF)
        guard count <= 6, status <= 3 else { displayBytes = nil; return }
        let payload = [UInt8((first >> 8) & 0xFF), UInt8(first & 0xFF),
                       UInt8((second >> 24) & 0xFF), UInt8((second >> 16) & 0xFF),
                       UInt8((second >> 8) & 0xFF), UInt8(second & 0xFF)]
        if status == 0 || status == 1 { displayBytes = [] }
        guard displayBytes != nil else { return }
        displayBytes!.append(contentsOf: payload.prefix(count))
        guard displayBytes!.count <= 64 else { displayBytes = nil; return }
        if status == 0 || status == 3 {
            let bytes = displayBytes!
            displayBytes = nil
            guard bytes.count == 11, Array(bytes.prefix(7)) == [0,0,0x66,5,0,0x10,8] else { return }
            let label = String(bytes: bytes.suffix(4), encoding: .ascii)
            if label == "FLIP" { flipActive = true }
            else if let label, ["SndA", "SndB", "SndC", "SndD", "SndE", "Pan ", "Out ", "Inp "].contains(label) {
                flipActive = false
            }
        }
    }

    private static func walk(_ words: [UInt32], _ body: (UInt32) -> Void) {
        var index = 0
        while index < words.count {
            body(words[index])
            index += min(RecAutomationRemapper.messageWidth(words[index]), words.count - index)
        }
    }
}
