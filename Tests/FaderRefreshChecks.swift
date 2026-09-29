import Foundation
@main
struct FaderRefreshChecks {
    static let click: [UInt32] = [0x20B00F15,0x20B02F40,0x20B00F15,0x20B02F00]
    static func ready(_ zone: UInt8 = 0) -> FaderRefresh {
        var r = FaderRefresh()
        r.feedback(FaderRefresh.positionWords(zone: zone, value: 12256), now: 0)
        r.feedback([0x20B00C00 | UInt32(zone), 0x20B02C41], now: 0.1)
        return r
    }
    static func main() {
        for zone in UInt8(0)..<8 {
            var r = ready(zone)
            assert(r.hardware(click, enabled: false, now: 1).host == click)
            // Selection changes must not discard the cached motor command.
            r.feedback([0x20B00C00 | UInt32(zone),0x20B02C01,0x20B02C41], now: 1.5)
            let start = r.hardware(click, enabled: true, now: 2)
            assert(start.device == FaderRefresh.positionWords(zone: zone, value: 11437))
            assert(start.host == [0x20B00F15,0x20B00F15])
            let mixed: [UInt32] = [0x2090007F,0x20B00040,0x20B02000,0x20B00F00,0x20B02F43]
            assert(r.hardware(mixed, enabled: true, now: 2.01).host == mixed)
            assert(r.hardware(click, enabled: true, now: 2.02).device.isEmpty)
            assert(r.tick(now: 2.099).isEmpty)
            assert(r.tick(now: 2.101) == FaderRefresh.positionWords(zone: zone, value: 12256))
            assert(!r.active && r.tick(now: 3).isEmpty)
            // Injected zero did not replace the saved PT position.
            assert(!r.hardware(click, enabled: true, now: 4).device.isEmpty)
            assert(r.tick(now: 5) == FaderRefresh.positionWords(zone: zone, value: 12256))
        }
        var r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        r.feedback(FaderRefresh.positionWords(zone: 7, value: 500), now: 1.1)
        assert(!r.active && r.tick(now: 2).isEmpty)
        r.feedback([0x20B00C00,0x20B02C01,0x20B00C07,0x20B02C41], now: 2.1)
        assert(r.hardware(click, enabled: true, now: 3).device == FaderRefresh.positionWords(zone: 7, value: 1319))
        assert(r.tick(now: 4) == FaderRefresh.positionWords(zone: 7, value: 500))
        r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        r.feedback([0x20B00038], now: 1.1)
        assert(!r.active) // cancel before even a split position is complete
        r.feedback([0x20B02060], now: 1.11)
        assert(r.tick(now: 2).isEmpty)
        r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        let touch: [UInt32] = [0x20B00F00,0x20B02F40,0x20B0007F,0x20B0207F]
        assert(r.hardware(touch, enabled: true, now: 1.1).host == touch)
        assert(!r.active && r.tick(now: 2).isEmpty)
        assert(r.hardware(click, enabled: true, now: 2).device.isEmpty)
        _ = r.hardware([0x20B00F00,0x20B02F00], enabled: true, now: 2.1)
        assert(r.tick(now: 3).isEmpty) // no delayed restore after hand release
        r = ready()
        assert(r.hardware(click + touch, enabled: true, now: 1).device.isEmpty)
        r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        assert(r.disable(now: 1.1) == FaderRefresh.positionWords(zone: 0, value: 12256))
        assert(!r.active && r.tick(now: 2).isEmpty)
        r = FaderRefresh()
        assert(r.hardware(click, enabled: true, now: 1).device.isEmpty)
        r.feedback([0x20B00C00,0x20B02C41], now: 1.1)
        r.feedback([0x20B00040], now: 2)
        r.feedback([0x20B02000], now: 2.2)
        assert(r.hardware(click, enabled: true, now: 3).device.isEmpty) // stale pair
        r.feedback(FaderRefresh.positionWords(zone: 0, value: 0), now: 4)
        assert(r.hardware(click, enabled: true, now: 5).device == FaderRefresh.positionWords(zone: 0, value: 819))
        assert(r.tick(now: 6) == FaderRefresh.positionWords(zone: 0, value: 0))
        r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        _ = r.hardware([0x20B00F0A,0x20B02F41], enabled: true, now: 1.1)
        assert(!r.active && r.tick(now: 2).isEmpty)
        r = ready()
        _ = r.hardware(click, enabled: true, now: 1)
        _ = r.hardware([0x10FF0000], enabled: true, now: 1.1)
        assert(!r.active && r.tick(now: 2).isEmpty)
        let opaque: [UInt32] = [0x30160000,0x20B00040,0x21B00040,0x20B10040]
        assert(r.hardware(opaque, enabled: true, now: 3).host == opaque)
        r.feedback(opaque, now: 3)
        assert(r.hardware(click, enabled: true, now: 4).device.isEmpty)
        // Regression: PT sends all eight positions, then only selection LEDs.
        r = FaderRefresh()
        for zone in UInt8(0)..<8 {
            r.feedback(FaderRefresh.positionWords(zone: zone, value: 1000 + UInt16(zone) * 100), now: 0)
        }
        for zone in UInt8(0)..<8 {
            if zone > 0 { r.feedback([0x20B00C00 | UInt32(zone - 1), 0x20B02C01], now: 1) }
            r.feedback([0x20B00C00 | UInt32(zone)], now: 1)
            r.feedback([0x20B02C41], now: 1)
            assert(r.hardware(click, enabled: true, now: 2).device == FaderRefresh.positionWords(zone: zone, value: 181 + UInt16(zone) * 100))
            assert(r.tick(now: 3) == FaderRefresh.positionWords(zone: zone, value: 1000 + UInt16(zone) * 100))
        }
        _ = r.hardware(click, enabled: true, now: 4)
        r.feedback([0x20B00C07,0x20B02C01,0x20B00C00,0x20B02C41], now: 4.1)
        assert(r.tick(now: 5).isEmpty && !r.active)
        r.feedback([0x20B00C01,0x20B02C41], now: 6)
        assert(r.hardware(click, enabled: true, now: 7).device == FaderRefresh.positionWords(zone: 1, value: 281))
        assert(r.tick(now: 7.5) == FaderRefresh.positionWords(zone: 1, value: 1100))
        r.feedback([0x20B02C01,0x20B00C00,0x20B02C01], now: 8)
        assert(r.hardware(click, enabled: true, now: 9).device == FaderRefresh.positionWords(zone: 1, value: 281))
        assert(r.tick(now: 10) == FaderRefresh.positionWords(zone: 1, value: 1100))
        // All eight targets persist outside the bank, using their latest PT value.
        for zone in UInt8(0)..<8 {
            r = ready(zone)
            r.feedback([0x20B00C00 | UInt32(zone),0x20B02C01], now: 1)
            r.feedback(FaderRefresh.positionWords(zone: zone, value: 4321), now: 1.1)
            r.feedback(FaderRefresh.positionWords(zone: (zone + 1) % 8, value: 9999), now: 1.2)
            assert(r.hardware(click, enabled: true, now: 2).device == FaderRefresh.positionWords(zone: zone, value: 3502))
            // Repeated deselection does not cancel a return to the retained target.
            r.feedback([0x20B00C00 | UInt32(zone),0x20B02C01], now: 2.1)
            assert(r.tick(now: 3) == FaderRefresh.positionWords(zone: zone, value: 4321))
            r.feedback([0x10FF0000], now: 4)
            r.feedback(FaderRefresh.positionWords(zone: zone, value: 4321), now: 4.1)
            assert(r.hardware(click, enabled: true, now: 5).device.isEmpty)
        }
        // Lower edge, direction boundary and upper edge remain in range.
        for (original, offset): (UInt16, UInt16) in [(0,819),(818,1637),(819,0),(16383,15564)] {
            r = ready()
            r.feedback(FaderRefresh.positionWords(zone: 0, value: original), now: 1)
            assert(r.hardware(click, enabled: true, now: 2).device == FaderRefresh.positionWords(zone: 0, value: offset))
            assert(r.tick(now: 2.099).isEmpty)
            assert(r.tick(now: 2.101) == FaderRefresh.positionWords(zone: 0, value: original))
        }
        print("PASS: simple 8ch motor refresh, last selected target retained outside bank, cached positions across selection changes, transparent input, PT/touch priority, split pairs, repeat, OFF and reset")
    }
}
