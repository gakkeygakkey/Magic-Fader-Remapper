import Foundation

@main
struct Checks {
    static func main() {
        var repair = MagicFaderReleaseRepair()
        let press: [UInt32] = [0x20B00F01, 0x20B02F43]
        assert(repair.process(press, enabled: false).tickets.isEmpty)
        let first = repair.process(press, enabled: true)
        assert(first.words == press && first.tickets.count == 1)
        _ = repair.process([0x20B00F06], enabled: true)
        assert(repair.take(first.tickets[0]) == [0x20B00F01, 0x20B02F03, 0x20B00F06])
        assert(repair.take(first.tickets[0]).isEmpty)
        let second = repair.process(press, enabled: true)
        _ = repair.process([0x20B02F03], enabled: true)
        assert(repair.take(second.tickets[0]).isEmpty)
        let third = repair.process(press, enabled: true)
        let fourth = repair.process(press, enabled: true)
        assert(fourth.words == [0x20B00F01, 0x20B00F01, 0x20B02F03, 0x20B02F43])
        assert(repair.take(third.tickets[0]).isEmpty)
        assert(repair.take(fourth.tickets[0]) == [0x20B00F01, 0x20B02F03])
        for zone in UInt32(0)..<8 {
            let result = repair.process([0x20B00F00 | zone, 0x20B02F43], enabled: true)
            assert(repair.take(result.tickets[0]) == [0x20B00F00 | zone, 0x20B02F03])
        }
        for value: UInt32 in [0x42, 0x47, 0x40] {
            let words: [UInt32] = [0x20B00F00, 0x20B02F00 | value]
            let result = repair.process(words, enabled: true)
            assert(result.words == words && result.tickets.isEmpty)
        }
        let opaque: [UInt32] = [0x30160000, 0x20B02F43, 0x21B02F43, 0x20B12F43, 0x2090007F]
        assert(repair.process(opaque, enabled: true).tickets.isEmpty)
        let canceled = repair.process(press, enabled: true)
        repair.cancel()
        assert(repair.take(canceled.tickets[0]).isEmpty)
        let reset = repair.process(press, enabled: true)
        _ = repair.process([0x10FF0000], enabled: true)
        assert(repair.take(reset.tickets[0]).isEmpty)
        assert(repair.process([0x20B02F43], enabled: true).tickets.isEmpty)
        _ = repair.process(press, enabled: true)
        assert(repair.finishPending() == [0x20B00F01, 0x20B02F03])
        assert(repair.finishPending().isEmpty)
        _ = repair.process(press, enabled: true)
        assert(repair.releaseNow(zone: 1) == [0x20B00F01, 0x20B02F03])
        assert(repair.finishPending().isEmpty)
        assert(MagicFaderReleaseRepair.matchesDevice("Magic Fader"))
        assert(!MagicFaderReleaseRepair.matchesDevice("FaderPort"))
        var remapper = RecAutomationRemapper()
        var combined = MagicFaderReleaseRepair()
        let solo = combined.process([0x20B00F02, 0x20B02F43], enabled: true)
        assert(remapper.process(solo.words, enabled: true) == solo.words)
        let rec = combined.process([0x20B00F05, 0x20B02F47], enabled: true)
        assert(rec.tickets.isEmpty)
        let mapped = remapper.process(rec.words, enabled: true)
        assert(mapped.contains(0x20B00F18) && mapped.last == 0x20B00F05)
        assert(combined.take(solo.tickets[0]) == [0x20B00F02, 0x20B02F03, 0x20B00F05])
        print("Magic Fader Solo release checks passed")
    }
}
