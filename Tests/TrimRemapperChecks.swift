import Foundation

@main
struct TrimRemapperChecks {
    static func main() {
        let click: [UInt32] = [0x20B00F0E, 0x20B02F45, 0x20B00F0E, 0x20B02F05]
        for zone in UInt32(0)..<8 {
            var r = RecAutomationRemapper()
            let feedback: [UInt32] = [0x20B00C00 | zone, 0x20B02C41]
            assert(r.processFeedback(feedback, enabled: false) == feedback)
            assert(r.trimTarget == UInt8(zone))
            let expected: [UInt32] = [0x20B00F0E, 0x20B00F18, 0x20B02F40,
                0x20B00F00 | zone, 0x20B02F44, 0x20B00F00 | zone, 0x20B02F04,
                0x20B00F18, 0x20B02F00, 0x20B00F0E, 0x20B00F0E]
            assert(r.process(click, enabled: true, trimEnabled: true) == expected)
            assert(r.process(click, enabled: true, trimEnabled: true) == expected)
            assert(r.process(click, enabled: false, trimEnabled: false) == click)
            assert(r.process(click, enabled: true) == click) // other hardware
            _ = r.processFeedback([0x20B02C01], enabled: true)
            assert(r.trimTarget == nil)
            assert(r.process(click, enabled: true, trimEnabled: true) == [0x20B00F0E, 0x20B00F0E])
        }
        // Every independent Rec/Trim combination, including original Rec LED passthrough.
        for recOn in [false, true] {
            for trimOn in [false, true] {
                var independent = RecAutomationRemapper()
                _ = independent.processFeedback([0x20B00C01, 0x20B02C41], enabled: recOn)
                let recInput: [UInt32] = [0x20B00F01, 0x20B02F47, 0x20B02F07]
                let recOutput = independent.process(recInput, enabled: recOn, trimEnabled: trimOn)
                assert((recOutput != recInput) == recOn)
                let trimOutput = independent.process(click, enabled: recOn, trimEnabled: trimOn)
                assert((trimOutput != click) == trimOn)
                let led: [UInt32] = [0x20B00C01, 0x20B02C24, 0x20B02C47]
                if !recOn { assert(independent.processFeedback(led, enabled: false) == led) }
            }
        }
        var r = RecAutomationRemapper()
        _ = r.processFeedback([0x20B00C03], enabled: false)
        _ = r.processFeedback([0x20B02C41], enabled: false)
        _ = r.processFeedback([0x20B00C06, 0x20B02C41], enabled: true)
        assert(r.trimTarget == nil) // ambiguous, no fallback
        _ = r.processFeedback([0x20B00C03, 0x20B02C01], enabled: true)
        assert(r.trimTarget == 6)
        _ = r.process([0x20B00F0E], enabled: true, trimEnabled: true)
        let mapped = r.process([0x20B02F45], enabled: true, trimEnabled: true)
        assert(mapped.contains(0x20B00F06))
        assert(r.process([0x20B02F45], enabled: true, trimEnabled: true) == mapped)
        assert(r.process([0x20B02F05], enabled: false, trimEnabled: true).isEmpty)
        _ = r.process([0x20B00F0A, 0x20B02F41], enabled: true, trimEnabled: true)
        assert(r.trimTarget == nil)
        let opaque: [UInt32] = [0x30160000, 0x20B02F40, 0x21B02F40, 0x20B12F40]
        assert(r.process(opaque, enabled: true, trimEnabled: true) == opaque)
        _ = r.processFeedback([0x20B00C02, 0x20B02C41], enabled: true)
        r.sendFailed()
        assert(r.trimTarget == nil)
        _ = r.processFeedback([0x20B00C02, 0x20B02C41], enabled: true)
        _ = r.processFeedback([0x10FF0000], enabled: true)
        assert(r.trimTarget == nil)
        // Trim Read green/orange alternation must not be mistaken for Touch.
        _ = r.processFeedback([0x20B00C02, 0x20B02C24, 0x20B02C64], enabled: true)
        let touch = r.process([0x20B00F02, 0x20B02F47], enabled: true)
        assert(touch.contains(0x20B02F45))
        // Check actual emitted Rec LED values, not just the mode command.
        var lamps = RecAutomationRemapper()
        for zone in UInt32(0)..<8 {
            let z = 0x20B00C00 | zone
            assert(lamps.processFeedback([z, 0x20B02C64], enabled: true).last == 0x20B02C07)
            for value: UInt32 in [0x24, 0x64, 0x24, 0x64] {
                assert(lamps.processFeedback([z, 0x20B02C00 | value], enabled: true).last == 0x20B02C07)
            }
            for value: UInt32 in [0x44, 0x64, 0x44, 0x64] {
                let expected: UInt32 = value == 0x44 ? 0x20B02C47 : 0x20B02C07
                assert(lamps.processFeedback([z, 0x20B02C00 | value], enabled: true).last == expected)
            }
            // Ordinary Touch blinking remains red/on, dark/off.
            assert(lamps.processFeedback([z, 0x20B02C04], enabled: true).last == 0x20B02C07)
            assert(lamps.processFeedback([z, 0x20B02C44], enabled: true).last == 0x20B02C47)
            assert(lamps.processFeedback([z, 0x20B02C24, 0x20B02C64], enabled: true).last == 0x20B02C07)
            // Rec feedback masking also uses the corrected orange decision.
            assert(lamps.processFeedback([z, 0x20B02C47], enabled: true).last == 0x20B02C07)
        }
        let sync = lamps.modeChanged(enabled: true)
        assert(!sync.contains(0x20B02C47))
        let restore = lamps.modeChanged(enabled: false)
        assert(restore.filter { $0 == 0x20B02C47 }.count == 8)
        let bypass: [UInt32] = [0x20B00C00, 0x20B02C64, 0x20B02C47]
        assert(lamps.processFeedback(bypass, enabled: false) == bypass)
        lamps.reset()
        assert(lamps.processFeedback([0x20B00C00, 0x20B02C64], enabled: true).last == 0x20B02C07)
        print("PASS: Trim 8ch selection, split input/feedback, toggle sequence, unknown/multiple selection, bank invalidation, bypass, release, opaque data, reset, Trim Read/Rec coexistence")
    }
}
