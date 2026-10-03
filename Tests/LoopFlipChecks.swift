import Foundation
@main struct LoopFlipChecks {
    static func main() {
        var r = LoopFlipRouting()
        let press: [UInt32] = [0x20B00F0F,0x20B02F43]
        assert(r.hardware(press, enabled: false).words == press)
        assert(r.hardware(press, enabled: true).presses == 1)
        assert(r.hardware(press, enabled: true).presses == 1) // MG has no Release
        assert(r.hardware([0x20B02F03], enabled: false).words.isEmpty)
        assert(r.hardware([0x20B02F43], enabled: false).words == [0x20B02F43])
        assert(r.hardware([0x20B00F00,0x20B02F43], enabled: true).presses == 0) // Solo untouched
        let opaque: [UInt32] = [0x30160000,0x20B02F43,0x21B02F43,0x20B12F43,0x2090007F]
        assert(r.hardware(opaque, enabled: true).words == opaque)
        _ = r.hardware([0x20B00F0F], enabled: true)
        let split = r.hardware([0x20B02F43], enabled: true)
        assert(split.words.isEmpty && split.presses == 1)
        _ = r.hardware([0x10FF0000], enabled: true)
        assert(r.hardware([0x20B02F43], enabled: true).presses == 0)
        r = LoopFlipRouting()
        _ = r.feedback([0x20B00C0F,0x20B02C43,0x20B00C04], enabled: false, active: nil)
        assert(r.sync(enabled: true, active: false, force: true) == [0x20B00C0F,0x20B02C03,0x20B00C04])
        assert(r.feedback([0x20B00C0F,0x20B02C43], enabled: true, active: false) == [0x20B00C0F])
        let on = r.feedback([0x20B00C0C,0x20B02C43], enabled: true, active: true, now: 1)
        assert(on == [0x20B00C0C,0x20B02C43])
        let onID = r.pendingID!
        assert(r.takeLED(onID, now: 1.099).isEmpty)
        assert(r.takeLED(onID, now: 1.101) == [0x20B00C0F,0x20B02C43,0x20B00C0C])
        let dark: [UInt32] = [0x20B00C0C,0x20B02C03]
        assert(r.feedback(dark, enabled: true, active: true) == dark) // No flicker
        assert(r.feedback([0x20B00C0F,0x20B02C03], enabled: true, active: true) == [0x20B00C0F])
        assert(r.sync(enabled: false, active: true, force: true) == [0x20B00C0F,0x20B02C03])
        let normal: [UInt32] = [0x20B00C0F,0x20B02C43]
        assert(r.feedback(normal, enabled: false, active: false) == normal)
        assert(r.sync(enabled: false, active: false, force: true) == normal)
        // Display payload stays unchanged, OFF is a separate packet 100ms later.
        let display: [UInt32] = [0x30160000,0x66050010,0x30350853,0x6E644100]
        _ = r.sync(enabled: true, active: true, force: true)
        assert(r.feedback(display, enabled: true, active: false, now: 2) == display)
        let offID = r.pendingID!
        _ = r.feedback([0x20B00C07], enabled: true, active: false, now: 2.05)
        assert(r.pendingID == offID) // Incoming traffic does not postpone the deadline.
        assert(r.takeLED(offID, now: 2.099).isEmpty)
        assert(r.takeLED(offID, now: 2.101) == [0x20B00C0F,0x20B02C03,0x20B00C07])
        assert(r.takeLED(offID, now: 3).isEmpty)
        _ = r.feedback(display, enabled: true, active: true, now: 4)
        let stale = r.pendingID!
        _ = r.feedback(display, enabled: true, active: false, now: 4.05)
        assert(r.takeLED(stale, now: 5).isEmpty)
        _ = r.feedback(display, enabled: true, active: true, now: 6)
        let disabled = r.pendingID!
        _ = r.sync(enabled: false, active: nil, force: true)
        assert(r.takeLED(disabled, now: 7).isEmpty)
        print("PASS: Loop split/repeated presses, OFF passthrough, release cleanup, opaque UMP, steady Flip LED, original Loop restoration and pending cancellation")
    }
}
