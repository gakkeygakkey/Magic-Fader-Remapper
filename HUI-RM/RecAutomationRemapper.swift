import Foundation

/// Single-fader MagicFader: group 0 / MIDI channel 1 / strip zones 00...07.
/// AUTO feedback is a red/green status indication, not an exact mode identifier.
struct RecAutomationRemapper {
    private var inputZone: UInt8?
    private var feedbackZone: UInt8?
    private var selectedZones: Set<UInt8> = []
    private var originalTransportLED: UInt8 = 0x05
    private var lastTrimLED: UInt8?
    private var touchedLEDZones: Set<UInt8> = []
    var trimTarget: UInt8? { selectedZones.count == 1 ? selectedZones.first : nil }
    private struct StripState {
        var autoValue: UInt8?
        var originalRecValue: UInt8?
        var armed: Bool?
        var requestedTouch: Bool?
        var requestedAt: TimeInterval = 0
        var observed = false
        var faderTouched = false
        var trimActive = false
        var predictedTrim: Bool?
        var predictionUntil: TimeInterval = 0
        var nonOrangeSince: TimeInterval?
        var recLED: UInt8 {
            let color = (autoValue ?? 0) & 0x60
            if faderTouched && armed == true && trimActive { return 0x47 }
            // Red lights Rec Ready. Orange is the dark phase for Trim Touch;
            // the transport Record LED separately indicates Trim enablement.
            return color == 0x40 ? 0x47 : 0x07
        }
    }
    private var strips = Array(repeating: StripState(), count: 8)

    mutating func reset() { self = Self() }

    mutating func modeChanged(enabled: Bool) -> [UInt32] {
        touchedLEDZones.removeAll()
        for index in strips.indices { strips[index].requestedTouch = nil }
        guard let feedbackZone else { return [] }
        var output: [UInt32] = []
        for index in strips.indices where strips[index].observed {
            let value = enabled ? strips[index].recLED : (strips[index].originalRecValue ?? 0x07)
            output += [0x20B00C00 | UInt32(index), 0x20B02C00 | UInt32(value)]
        }
        if !output.isEmpty { output.append(0x20B00C00 | UInt32(feedbackZone)) }
        return output
    }

    mutating func sendFailed() {
        selectedZones.removeAll()
        touchedLEDZones.removeAll()
        for index in strips.indices { strips[index].faderTouched = false; strips[index].requestedTouch = nil; strips[index].predictedTrim = nil }
    }

    mutating func process(_ words: [UInt32], enabled: Bool, trimEnabled: Bool = false, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [UInt32] {
        var output: [UInt32] = []
        Self.walk(words) { message in
            let word = message.first!
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = UInt8((word >> 8) & 0xFF)
                let value = UInt8(word & 0xFF)
                if cc == 0x0F { inputZone = value }
                // Navigation changes the bank mapping. Wait for fresh SELECT feedback.
                if inputZone == 0x0A, cc == 0x2F, value & 0x40 != 0 {
                    selectedZones.removeAll()
                    for index in strips.indices { strips[index].faderTouched = false; touchedLEDZones.insert(UInt8(index)); strips[index].trimActive = false; strips[index].nonOrangeSince = nil; strips[index].predictedTrim = nil }
                }
                if let zone = inputZone, zone < 8, cc == 0x2F, value == 0x40 || value == 0x00 {
                    let index = Int(zone)
                    let touched = value == 0x40
                    if strips[index].faderTouched != touched {
                        strips[index].faderTouched = touched
                        touchedLEDZones.insert(zone)
                    }
                    // Forward the physical touch/release unchanged to Pro Tools.
                }
                if inputZone == 0x0E, cc == 0x2F, trimEnabled {
                    if value == 0x05 { return }
                    if value == 0x45 {
                        // MG sends press only: each press completes its own HUI chord.
                        guard let target = trimTarget else { return }
                        _ = trimLED(now: now) // Expire old observations/predictions first.
                        let index = Int(target)
                        strips[index].predictedTrim = !(strips[index].predictedTrim ?? strips[index].trimActive)
                        strips[index].predictionUntil = now + 0.8
                        output += [0x20B00F18, 0x20B02F40,
                                   0x20B00F00 | UInt32(target), 0x20B02F44,
                                   0x20B00F00 | UInt32(target), 0x20B02F04,
                                   0x20B00F18, 0x20B02F00, 0x20B00F0E]
                        return
                    }
                }
                if enabled, let zone = inputZone, zone < 8, cc == 0x2F, value == 0x47 {
                    let index = Int(zone)
                    strips[index].observed = true
                    let touch = !(strips[index].requestedTouch ?? strips[index].armed ?? false)
                    strips[index].requestedTouch = touch
                    strips[index].requestedAt = now
                    let mode: UInt32 = touch ? 5 : 2
                    // Hold Touch/Read while pressing and releasing the originating strip AUTO.
                    // Release the mode button, then restore the incoming zone.
                    output += [0x20B00F18, 0x20B02F40 | mode,
                               0x20B00F00 | UInt32(zone), 0x20B02F44,
                               0x20B00F00 | UInt32(zone), 0x20B02F04,
                               0x20B00F18, 0x20B02F00 | mode, 0x20B00F00 | UInt32(zone)]
                    return
                }
                if enabled, let zone = inputZone, zone < 8, cc == 0x2F, value == 0x07 { return }
            }
            if word == 0x10FF0000 { reset() }
            output.append(contentsOf: message)
        }
        return output
    }

    mutating func processFeedback(_ words: [UInt32], enabled: Bool, trimEnabled: Bool = false, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [UInt32] {
        var output: [UInt32] = []
        Self.walk(words) { message in
            let word = message.first!
            if word & 0xFFFF0000 == 0x20B00000 {
                let cc = UInt8((word >> 8) & 0xFF)
                let value = UInt8(word & 0xFF)
                if cc == 0x0C { feedbackZone = value }
                if feedbackZone == 0x0E, cc == 0x2C, value == 0x05 || value == 0x45 {
                    originalTransportLED = value
                    if trimEnabled {
                        output += transportLEDWords(trimLED(now: now))
                        return
                    }
                }
                if let zone = feedbackZone, zone < 8, cc == 0x2C {
                    let index = Int(zone)
                    if value == 0x41 { selectedZones.insert(zone) }
                    else if value == 0x01 { selectedZones.remove(zone) }
                    if value == 0x04 || value == 0x24 || value == 0x44 || value == 0x64 {
                        strips[index].observed = true
                        strips[index].autoValue = value
                        if value == 0x64 {
                            strips[index].trimActive = true
                            if strips[index].predictedTrim == true { strips[index].predictedTrim = nil }
                            strips[index].nonOrangeSince = nil
                        } else if strips[index].trimActive, strips[index].nonOrangeSince == nil {
                            strips[index].nonOrangeSince = now
                        }
                        // An unlit frame may be the dark half of a blink. Do not
                        // treat it as Read. Orange (Trim) is also shared by Read and
                        // recordable modes; only pure red/green update the mode hint.
                        if value & 0x60 == 0x40 { strips[index].armed = true }
                        else if value & 0x60 == 0x20 { strips[index].armed = false }
                        if value & 0x60 == 0x40 || value & 0x60 == 0x20, strips[index].requestedTouch == strips[index].armed || now - strips[index].requestedAt > 1 { strips[index].requestedTouch = nil }
                        output.append(contentsOf: message)
                        // Match the explicit zone/port pairs observed from Pro Tools.
                        if enabled { output.append(contentsOf: [0x20B00C00 | UInt32(zone), 0x20B02C00 | UInt32(strips[index].recLED)]) }
                        return
                    }
                    if value == 0x07 || value == 0x27 || value == 0x47 || value == 0x67 {
                        strips[index].observed = true
                        strips[index].originalRecValue = value
                        if enabled {
                            output.append(contentsOf: [0x20B00C00 | UInt32(zone), 0x20B02C00 | UInt32(strips[index].recLED)])
                            return
                        }
                    }
                }
            }
            if word == 0x10FF0000 { reset() }
            output.append(contentsOf: message)
        }
        if trimEnabled { output += trimLEDUpdate(now: now) }
        return output
    }

    mutating func takeFaderLEDFeedback(enabled: Bool) -> [UInt32] {
        let zones = touchedLEDZones.sorted()
        touchedLEDZones.removeAll()
        guard enabled else { return [] }
        var words: [UInt32] = []
        for zone in zones where strips[Int(zone)].observed {
            words += [0x20B00C00 | UInt32(zone), 0x20B02C00 | UInt32(strips[Int(zone)].recLED)]
        }
        if !words.isEmpty, let feedbackZone { words.append(0x20B00C00 | UInt32(feedbackZone)) }
        return words
    }

    // Orange alternates with red/green about every 0.8s in Trim mode.
    // Observed Read non-orange gaps are ~0.27s; test a 0.5s release threshold.
    // No timeout while solid orange: writing may emit only a single LED update.
    private mutating func trimLED(now: TimeInterval) -> UInt8 {
        for index in strips.indices {
            if now >= strips[index].predictionUntil { strips[index].predictedTrim = nil }
            if let since = strips[index].nonOrangeSince, now - since >= 0.5 {
                strips[index].trimActive = false
                if strips[index].predictedTrim == false { strips[index].predictedTrim = nil }
                strips[index].nonOrangeSince = nil
            }
        }
        guard let target = trimTarget else { return 0x05 }
        let state = strips[Int(target)]
        return (state.predictedTrim ?? state.trimActive) ? 0x45 : 0x05
    }

    private func transportLEDWords(_ value: UInt8) -> [UInt32] {
        var words: [UInt32] = [0x20B00C0E, 0x20B02C00 | UInt32(value)]
        if let feedbackZone, feedbackZone != 0x0E { words.append(0x20B00C00 | UInt32(feedbackZone)) }
        return words
    }

    mutating func trimLEDUpdate(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [UInt32] {
        let value = trimLED(now: now)
        guard lastTrimLED != value else { return [] }
        lastTrimLED = value
        return transportLEDWords(value)
    }

    mutating func trimModeChanged(enabled: Bool) -> [UInt32] {
        for index in strips.indices { strips[index].predictedTrim = nil }
        lastTrimLED = nil
        return enabled ? trimLEDUpdate() : transportLEDWords(originalTransportLED)
    }

    // Call with a local copy of the iterator state so mutation within body is safe.
    private static func walk(_ words: [UInt32], _ body: (ArraySlice<UInt32>) -> Void) {
        var index = 0
        while index < words.count {
            let width = min(Self.messageWidth(words[index]), words.count - index)
            body(words[index..<(index + width)])
            index += width
        }
    }

    static func messageWidth(_ word: UInt32) -> Int {
        [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4][Int(word >> 28)]
    }
}
