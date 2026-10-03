import Foundation

@main
struct SendFlipChecks {
    static let flipCommand: [UInt32] = [0x20B00F0C,0x20B02F43,0x20B00F0C,0x20B02F03]
    static func main() {
        var flip = SendFlip()
        assert(flip.lamp == nil)
        assert(flip.request(now: 1) == flipCommand)
        assert(flip.lamp == nil && flip.flipActive == nil)
        assert(flip.request(now: 1.1).isEmpty)
        assert(flip.request(now: 2) == flipCommand)
        for zone in UInt8(0)..<8 {
            flip = SendFlip()
            flip.observeHost([0x20B00F00 | UInt32(zone)])
            assert(flip.request(now: 1) == flipCommand + [0x20B00F00 | UInt32(zone)])
            flip.observeHost([0x20B02F40])
            assert(flip.isTouched && flip.request(now: 2).isEmpty)
            flip.observeHost([0x20B02F00])
            assert(!flip.isTouched)
            assert(flip.request(now: 3) == flipCommand + [0x20B00F00 | UInt32(zone)])
        }
        // Pan and Send A...E selection must not add or force any assignment command.
        for port in UInt32(2)...7 {
            flip = SendFlip()
            flip.observeHost([0x20B00F0B, 0x20B02F40 | port])
            assert(flip.request(now: 1) == flipCommand + [0x20B00F0B])
        }
        flip = SendFlip()
        flip.observeFeedback([0x20B00C0C])
        flip.observeFeedback([0x20B02C43])
        assert(flip.lamp == true)
        flip.observeFeedback([0x20B02C03])
        assert(flip.lamp == false) // Raw dark phase, not a claimed mode transition.
        flip.observeFeedback([0x20B02C43])
        assert(flip.lamp == true)
        flip.observeFeedback([0x20B00C00,0x20B02C03,0x20B00C0C,0x20B02C04])
        assert(flip.lamp == true)
        flip.observeFeedback([0x30160000,0x20B02C03,0x21B02C03,0x20B12C03])
        assert(flip.lamp == true) // Sysex payload, other group/channel stay opaque.
        // Lamp ON followed by its dark phase still takes the Flip-only return path.
        flip.observeFeedback([0x20B00C0C,0x20B02C03])
        assert(flip.request(now: 4) == flipCommand)
        // Select/Assign SndA confirms return; channel text must not change mode.
        flip.observeFeedback([0x30160000,0x66050010])
        flip.observeFeedback([0x30350853,0x6E644100])
        assert(flip.flipActive == false)
        flip.sendFailed()
        assert(flip.lamp == nil && flip.flipActive == nil)
        assert(flip.request(now: 7) == flipCommand)
        flip.observeFeedback([0x20B00C0C,0x20B02C43,0x10FF0000])
        assert(flip.lamp == nil && !flip.isTouched)
        assert(flip.request(now: 8) == flipCommand)

        flip = SendFlip()
        flip.observeFeedback([0x30160000,0x66050010,0x30350046,0x4C495000])
        assert(flip.flipActive == nil) // A track called FLIP is not mode feedback.
        flip.observeFeedback([0x30160000,0x66050010])
        flip.observeFeedback([0x30350846,0x4C495000])
        assert(flip.flipActive == true)
        flip.observeHost([0x20B00F06])
        assert(flip.request(now: 1) == flipCommand + [0x20B00F06])
        flip.observeFeedback([0x30160000,0x66050010,0x30350853,0x6E644100,0x20B00C0C,0x20B02C03])
        assert(flip.flipActive == false)
        assert(flip.request(now: 2) == flipCommand + [0x20B00F06])

        // Pan/Input/Output returns also clear the inferred Flip state.
        for label: UInt32 in [0x50616E20, 0x496E7020, 0x4F757420] {
            flip.observeFeedback([0x20B00C0C, 0x20B02C43])
            flip.observeFeedback([0x30160000, 0x66050010, 0x30350800 | (label >> 24), label << 8])
            assert(flip.flipActive == false)
            flip.observeFeedback([0x20B00C0C, 0x20B02C03])
            assert(flip.flipActive == false)
        }

        let off: [UInt32] = [0x30160000,0x66050010,0x30350853,0x6E644200]
        let panCommand: [UInt32] = [0x20B00F0B,0x20B02F42,0x20B00F0B,0x20B02F02]
        func returning() -> SendFlip {
            var f = SendFlip()
            f.observeFeedback([0x20B00C0C,0x20B02C43])
            _ = f.request(now: 10)
            return f
        }
        flip = returning()
        let panID = flip.pendingPanID!
        assert(flip.takePan(panID, now: 10.54).isEmpty)
        flip.observeFeedback(off)
        flip.observeHost([0x20B00F07])
        assert(flip.takePan(panID, now: 10.56) == panCommand + [0x20B00F07])
        assert(flip.takePan(panID, now: 10.6).isEmpty)
        for event: [UInt32] in [[0x20B00F00,0x20B02F40,0x20B02F00],
                                [0x20B00F0B,0x20B02F45], [0x20B00F0A,0x20B02F41], [0x10FF0000]] {
            flip = returning()
            let id = flip.pendingPanID!
            flip.observeFeedback(off)
            flip.observeHost(event)
            assert(flip.takePan(id, now: 10.56).isEmpty)
        }
        flip = returning()
        let unconfirmed = flip.pendingPanID!
        flip.observeFeedback([0x20B00C0C,0x20B02C03])
        assert(flip.takePan(unconfirmed, now: 10.56).isEmpty)
        flip = returning()
        let obsolete = flip.pendingPanID!
        flip.observeFeedback(off)
        _ = flip.request(now: 10.51)
        assert(flip.pendingPanID == nil && flip.takePan(obsolete, now: 10.56).isEmpty)
        flip = returning()
        let failed = flip.pendingPanID!
        flip.sendFailed()
        assert(flip.takePan(failed, now: 10.56).isEmpty)
        flip = returning()
        let late = flip.pendingPanID!
        flip.observeFeedback(off)
        assert(flip.takePan(late, now: 11).isEmpty)

        var refresh = FaderRefresh()
        refresh.feedback([0x20B00C00,0x20B02C41] + FaderRefresh.positionWords(zone: 0, value: 10000), now: 0)
        let click: [UInt32] = [0x20B00F15,0x20B02F40,0x20B00F15,0x20B02F00]
        assert(!refresh.hardware(click, enabled: true, now: 1).device.isEmpty)
        refresh.assignmentChanged()
        assert(refresh.tick(now: 2).isEmpty)
        assert(refresh.hardware(click, enabled: true, now: 3).device.isEmpty)
        refresh.feedback(FaderRefresh.positionWords(zone: 0, value: 8000), now: 4)
        assert(!refresh.hardware(click, enabled: true, now: 5).device.isEmpty)
        assert(refresh.tick(now: 6) == FaderRefresh.positionWords(zone: 0, value: 8000))
        print("PASS: Flip-only press-release, zone restoration, touch guard, debounce, raw LED feedback, reset, assignment cache invalidation")
    }
}
