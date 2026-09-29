import Foundation
@main
struct TrimFaderTouchChecks {
    static func main() {
        for zone in UInt32(0)..<8 {
            var r = RecAutomationRemapper()
            let inputZone = 0x20B00F00 | zone
            let outputZone = 0x20B00C00 | zone
            _ = r.processFeedback([outputZone,0x20B02C44,0x20B02C64], enabled: true, now: 0)
            let touch: [UInt32] = [inputZone,0x20B02F40]
            assert(r.process(touch, enabled: true, now: 0.1) == touch)
            assert(r.takeFaderLEDFeedback(enabled: true).contains(0x20B02C47))
            assert(r.takeFaderLEDFeedback(enabled: true).isEmpty)
            for value: UInt32 in [0x64,0x44,0x64] {
                assert(r.processFeedback([outputZone,0x20B02C00 | value], enabled: true, now: 0.2).last == 0x20B02C47)
            }
            // Another strip's touch/release does not release this strip.
            let other = (zone + 1) % 8
            _ = r.process([0x20B00F00 | other,0x20B02F40,0x20B02F00], enabled: true)
            assert(r.processFeedback([outputZone,0x20B02C64], enabled: true).last == 0x20B02C47)
            _ = r.process([inputZone], enabled: true)
            assert(r.process([0x20B02F00], enabled: true) == [0x20B02F00])
            assert(r.takeFaderLEDFeedback(enabled: true).contains(0x20B02C07))
            assert(r.processFeedback([outputZone,0x20B02C44], enabled: true).last == 0x20B02C47)
            assert(r.processFeedback([outputZone,0x20B02C64], enabled: true).last == 0x20B02C07)
            // Read stays off even if physically touched, and Rec OFF emits no LED override.
            _ = r.processFeedback([outputZone,0x20B02C24,0x20B02C64], enabled: true)
            _ = r.process(touch, enabled: true)
            assert(!r.takeFaderLEDFeedback(enabled: true).contains(0x20B02C47))
            _ = r.process([inputZone,0x20B02F00], enabled: false)
            assert(r.takeFaderLEDFeedback(enabled: false).isEmpty)
            r.reset()
            assert(r.takeFaderLEDFeedback(enabled: true).isEmpty)
        }
        print("PASS: Trim Touch held LED, release blink, 8ch isolation, split messages, Read/off bypass, reset")
    }
}
