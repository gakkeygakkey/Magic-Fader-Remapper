import Foundation
@main
struct TrimTransportLEDChecks {
    static func main() {
        var r = RecAutomationRemapper()
        let click: [UInt32] = [0x20B00F15,0x20B02F40,0x20B00F15,0x20B02F00]
        assert(r.process(click, enabled: true, trimEnabled: true) == click)
        let rec: [UInt32] = [0x20B00F0E,0x20B02F45]
        assert(r.process(rec, enabled: true, trimEnabled: false) == rec)
        for zone in UInt32(0)..<8 {
            r.reset()
            _ = r.processFeedback([0x20B00C00 | zone,0x20B02C41,0x20B02C64], enabled: false, trimEnabled: true, now: 0)
            assert(r.trimLEDUpdate(now: 0.3).isEmpty)
            let mask = r.processFeedback([0x20B00C0E,0x20B02C05], enabled: false, trimEnabled: true, now: 0.4)
            assert(mask == [0x20B00C0E,0x20B00C0E,0x20B02C45])
            _ = r.processFeedback([0x20B00C00 | zone,0x20B02C24], enabled: false, trimEnabled: true, now: 0.5)
            assert(r.trimLEDUpdate(now: 0.74).isEmpty)
            _ = r.processFeedback([0x20B02C64], enabled: false, trimEnabled: true, now: 0.77)
            assert(r.trimLEDUpdate(now: 30).isEmpty) // solid orange cannot expire
            _ = r.processFeedback([0x20B02C24], enabled: false, trimEnabled: true, now: 31)
            assert(r.trimLEDUpdate(now: 31.51) == [0x20B00C0E,0x20B02C05,0x20B00C00 | zone])
        }
        r.reset()
        _ = r.processFeedback([0x20B00C01,0x20B02C41,0x20B02C64], enabled: false, trimEnabled: true, now: 0)
        let deselect = r.processFeedback([0x20B02C01], enabled: false, trimEnabled: true, now: 0.1)
        assert(deselect.contains(0x20B02C05))
        let select = r.processFeedback([0x20B02C41], enabled: false, trimEnabled: true, now: 0.2)
        assert(select.contains(0x20B02C45))
        _ = r.processFeedback([0x20B00C0E,0x20B02C45], enabled: false, trimEnabled: true, now: 0.3)
        assert(r.trimModeChanged(enabled: false) == [0x20B00C0E,0x20B02C45])
        let native: [UInt32] = [0x20B00C0E,0x20B02C05]
        assert(r.processFeedback(native, enabled: false, trimEnabled: false) == native)
        // Local presses immediately predict the LED; feedback remains authoritative.
        r.reset()
        _ = r.processFeedback([0x20B00C00,0x20B02C41,0x20B02C24], enabled: false, trimEnabled: true, now: 0)
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 1)
        assert(r.trimLEDUpdate(now: 1).contains(0x20B02C45))
        _ = r.processFeedback([0x20B02C64], enabled: false, trimEnabled: true, now: 1.1)
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 2)
        assert(r.trimLEDUpdate(now: 2).contains(0x20B02C05))
        // An in-flight orange frame cannot immediately relight the predicted OFF.
        _ = r.processFeedback([0x20B02C64], enabled: false, trimEnabled: true, now: 2.01)
        assert(r.trimLEDUpdate(now: 2.02).isEmpty)
        _ = r.processFeedback([0x20B02C24], enabled: false, trimEnabled: true, now: 2.1)
        assert(r.trimLEDUpdate(now: 2.61).isEmpty)
        assert(r.trimLEDUpdate(now: 3).isEmpty)
        // Unconfirmed ON rolls back; rapid presses toggle the pending display.
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 4)
        assert(r.trimLEDUpdate(now: 4).contains(0x20B02C45))
        assert(r.trimLEDUpdate(now: 4.81).contains(0x20B02C05))
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 5)
        _ = r.trimLEDUpdate(now: 5)
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 5.1)
        assert(r.trimLEDUpdate(now: 5.1).contains(0x20B02C05))
        _ = r.process(rec, enabled: false, trimEnabled: true, now: 6)
        r.sendFailed()
        assert(!r.trimLEDUpdate(now: 6).contains(0x20B02C45))
        print("PASS: transport LED masking/restoration, 8ch Trim blink/solid/off, selection changes, metronome passthrough")
    }
}
