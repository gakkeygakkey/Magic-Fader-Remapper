import Foundation

@main
struct TransportSendRoutingChecks {
    static func command(_ port: UInt32) -> [UInt32] {
        [0x20B00F0B,0x20B02F40 | port,0x20B00F0B,0x20B02F00 | port,0x20B00F0E]
    }
    static func main() {
        var route = TransportSendRouting()
        assert(route.process([0x20B00F0E], enabled: true, currentPort: 7) == [0x20B00F0E])
        assert(route.process([0x20B02F41], enabled: true, currentPort: 7) == command(3)) // A -> E
        assert(route.process([0x20B02F42], enabled: true, currentPort: 3) == command(7)) // E -> A
        assert(route.process([0x20B02F43], enabled: true, currentPort: 7) == [0x20B02F43])
        assert(route.process([0x20B02F01], enabled: false, currentPort: 7).isEmpty)
        assert(route.process([0x20B02F02], enabled: false, currentPort: 7).isEmpty)
        let normal: [UInt32] = [0x20B02F41,0x20B02F01,0x20B02F42,0x20B02F02,0x20B02F43,0x20B02F03]
        assert(route.process(normal, enabled: false, currentPort: 7) == normal)
        // Repeated presses work even when MG sends no release.
        assert(route.process([0x20B02F42,0x20B02F42], enabled: true, currentPort: 7) == command(6) + command(5))
        let physical: [UInt32] = [0x20B00F0B,0x20B02F45,0x20B00F0E]
        assert(route.process(physical + [0x20B02F41], enabled: true, currentPort: 7) == physical + command(6))
        let opaque: [UInt32] = [0x301620B0,0x20B02F41,0x21B02F41,0x20B12F41]
        assert(route.process(opaque, enabled: true, currentPort: 7) == opaque)
        _ = route.process([0x10FF0000], enabled: true, currentPort: 7)
        assert(route.process([0x20B02F42], enabled: true, currentPort: 7) == [0x20B02F42])

        let suite = "HUIRM-TransportChecks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var memory = SendSelectionMemory(defaults: defaults)
        var replay = FlipFeedbackReplay()
        route = TransportSendRouting()
        let routed = route.process([0x20B00F0E,0x20B02F42], enabled: true, currentPort: memory.port)
        memory.observe(routed)
        assert(memory.port == 6 && SendSelectionMemory(defaults: defaults).port == 6)
        let replayID = replay.hardware(routed, flipActive: true, now: 0)!
        let bus: [UInt32] = [0x30160000,0x66050010,0x30350042,0x75733200]
        replay.feedback(bus + [0x20B00029,0x20B02020], now: 0.001)
        assert(replay.next(replayID, now: 0.15) == bus)
        var flip = SendFlip()
        flip.observeHost(routed)
        assert(flip.request(now: 1).last == 0x20B00F0E) // Restored input zone.
        print("PASS: previous/next wrap, repeated presses, STOP, OFF passthrough, release cleanup, split zones, opaque UMP, reset, memory and Flip replay integration")
    }
}
