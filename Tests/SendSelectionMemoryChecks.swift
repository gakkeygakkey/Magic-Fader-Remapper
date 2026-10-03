import Foundation

@main
struct SendSelectionMemoryChecks {
    static func main() {
        let suite = "HUIRM-SendMemoryChecks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var memory = SendSelectionMemory(defaults: defaults)
        assert(memory.port == 7)
        for port in UInt32(3)...7 {
            memory.observe([0x20B00F0B])
            memory.observe([0x20B02F40 | port])
            assert(memory.port == UInt8(port))
            assert(SendSelectionMemory(defaults: defaults).port == UInt8(port))
        }
        memory.observe([0x20B00F0B,0x20B02F46])
        memory.observe([0x20B02F42,0x20B02F02]) // Pan does not forget B.
        assert(memory.port == 6)
        memory.resetRoute()
        memory.observe([0x20B02F45])
        assert(memory.port == 6)
        memory.observe([0x20B00F0B,0x301620B0,0x20B02F43]) // Opaque SysEx payload.
        assert(memory.port == 6)
        defaults.set(99, forKey: SendSelectionMemory.preferenceKey)
        assert(SendSelectionMemory(defaults: defaults).port == 7)

        let flipCommand: [UInt32] = [0x20B00F0C,0x20B02F43,0x20B00F0C,0x20B02F03]
        var flip = SendFlip()
        assert(flip.request(now: 1) == flipCommand) // OFF remains immediate.
        for port in UInt8(3)...7 {
            flip = SendFlip()
            flip.observeHost([0x20B00F03])
            let selected = flip.request(now: 1, restorePort: port)
            assert(selected == [0x20B00F0B,0x20B02F40 | UInt32(port),0x20B00F0B,0x20B02F00 | UInt32(port),0x20B00F03])
            let id = flip.pendingFlipID!
            flip.observeHost(selected) // Generated selection must not cancel the pending Flip.
            assert(flip.takeRestoredFlip(id, now: 1.19).isEmpty)
            flip.observeHost([0x20B00F06])
            assert(flip.takeRestoredFlip(id, now: 1.21) == flipCommand + [0x20B00F06])
            assert(flip.takeRestoredFlip(id, now: 1.3).isEmpty)
        }
        for event: [UInt32] in [[0x20B00F0B,0x20B02F45], [0x20B00F00,0x20B02F40], [0x10FF0000]] {
            flip = SendFlip()
            _ = flip.request(now: 1, restorePort: 6)
            let id = flip.pendingFlipID!
            flip.observeRestoreInteraction(event)
            assert(flip.takeRestoredFlip(id, now: 1.21).isEmpty)
        }
        flip = SendFlip()
        _ = flip.request(now: 1, restorePort: 6)
        let cancelled = flip.pendingFlipID!
        flip.cancelRestore()
        assert(flip.takeRestoredFlip(cancelled, now: 1.21).isEmpty)
        flip.observeFeedback([0x20B00C0C,0x20B02C43])
        assert(flip.request(now: 2, restorePort: 6) == flipCommand)
        assert(flip.pendingFlipID == nil && flip.pendingPanID != nil)
        print("PASS: A-E persistence, Pan preservation, route reset, opaque UMP, restore timing, generated vs physical input, OFF path and Flip exit")
    }
}
