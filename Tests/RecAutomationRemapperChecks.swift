import CoreMIDI
import Foundation

@main
struct RecAutomationRemapperChecks {
    static func main() {
        var r = RecAutomationRemapper()
        let touch: [UInt32] = [0x20B00F18, 0x20B02F45, 0x20B00F00, 0x20B02F44, 0x20B00F00, 0x20B02F04, 0x20B00F18, 0x20B02F05, 0x20B00F00]
        let read: [UInt32] = [0x20B00F18, 0x20B02F42, 0x20B00F00, 0x20B02F44, 0x20B00F00, 0x20B02F04, 0x20B00F18, 0x20B02F02, 0x20B00F00]
        precondition(r.process([0x20B00F00], enabled: true, now: 0) == [0x20B00F00])
        precondition(r.process([0x2090007F], enabled: true, now: 0) == [0x2090007F])
        precondition(r.process([0x20B02F47], enabled: true, now: 0) == touch)
        precondition(r.process([0x20B02F47], enabled: true, now: 2) == read)
        precondition(r.process([0x20B02F07], enabled: true).isEmpty)
        let opaque: [UInt32] = [0x21B02F47, 0x20B12F47, 0x30060000, 0x20B02F47, 0x40900000, 0x20B02F47]
        precondition(r.process(opaque, enabled: true) == opaque)
        let rec: [UInt32] = [0x20B00F00, 0x20B02F47, 0x20B02F07]
        precondition(r.process(rec, enabled: false) == rec)
        precondition(r.process([0x20B00F08, 0x20B02F47], enabled: true) == [0x20B00F08, 0x20B02F47])
        r.reset()
        precondition(r.process([0x20B02F47], enabled: true) == [0x20B02F47])

        // Recorded channel AUTO red/on, blink-off, green frames. Rec-arm
        // feedback must not overwrite the remapped lamp. Zones span callbacks.
        precondition(r.processFeedback([0x20B00C00], enabled: true) == [0x20B00C00])
        precondition(r.processFeedback([0x20B02C44], enabled: true) == [0x20B02C44, 0x20B00C00, 0x20B02C47])
        precondition(r.processFeedback([0x20B02C07], enabled: true) == [0x20B00C00, 0x20B02C47])
        precondition(r.processFeedback([0x20B02C04], enabled: true) == [0x20B02C04, 0x20B00C00, 0x20B02C07])
        _ = r.process([0x20B00F00], enabled: true, now: 10)
        precondition(r.process([0x20B02F47], enabled: true, now: 10) == read, "Blink-off must retain armed state")
        _ = r.processFeedback([0x20B02C44], enabled: true, now: 10.1)
        precondition(r.process([0x20B02F47], enabled: true, now: 10.2) == touch, "Late old feedback must not undo pending toggle")
        _ = r.processFeedback([0x20B02C24], enabled: true, now: 12)
        precondition(r.process([0x20B02F47], enabled: true, now: 12) == touch, "External Read resynchronizes")
        precondition(r.processFeedback([0x20B02C24], enabled: true) == [0x20B02C24, 0x20B00C00, 0x20B02C07])
        let other: [UInt32] = [0x20B00C08, 0x20B02C44, 0x20900000]
        precondition(r.processFeedback(other, enabled: true) == other)
        precondition(r.modeChanged(enabled: false) == [0x20B00C00, 0x20B02C07, 0x20B00C08])
        let raw: [UInt32] = [0x20B00C00, 0x20B02C47, 0x20B02C44]
        precondition(r.processFeedback(raw, enabled: false) == raw)
        precondition(r.modeChanged(enabled: false) == [0x20B00C00, 0x20B02C47, 0x20B00C00])
        precondition(r.modeChanged(enabled: true) == [0x20B00C00, 0x20B02C47, 0x20B00C00])
        r.reset()
        precondition(r.modeChanged(enabled: true).isEmpty)
        precondition(r.modeChanged(enabled: false).isEmpty)

        // All 8 strips toggle independently, without a fader move or selection
        // notification. A Rec packet's zone is the operation's authoritative target.
        for zone in UInt32(0)...7 {
            _ = r.process([0x20B00F00 | zone], enabled: true, now: 20)
            let first = r.process([0x20B02F47], enabled: true, now: 20)
            precondition(first[1] == 0x20B02F45)
            precondition(first[2] == 0x20B00F00 | zone && first[4] == 0x20B00F00 | zone)
            precondition(first.last == 0x20B00F00 | zone)
        }
        for zone in UInt32(0)...7 {
            let second = r.process([0x20B00F00 | zone, 0x20B02F47], enabled: true, now: 21)
            precondition(second[2] == 0x20B02F42)
            precondition(r.process([0x20B02F07], enabled: true).isEmpty)
            let original: [UInt32] = [0x20B00F00 | zone, 0x20B02F47, 0x20B02F07]
            precondition(r.process(original, enabled: false) == original)
            // Opposite modes and Rec states on adjacent strips must stay isolated.
            let auto: UInt32 = zone % 2 == 0 ? 0x44 : 0x24
            let rec: UInt32 = zone % 2 == 0 ? 0x07 : 0x47
            let lamp: UInt32 = zone % 2 == 0 ? 0x47 : 0x07
            let zoneWord = 0x20B00C00 | zone
            _ = r.processFeedback([zoneWord], enabled: true)
            precondition(r.processFeedback([0x20B02C00 | auto], enabled: true) ==
                         [0x20B02C00 | auto, zoneWord, 0x20B02C00 | lamp])
            precondition(r.processFeedback([0x20B02C00 | rec], enabled: true) ==
                         [zoneWord, 0x20B02C00 | lamp])
        }
        var restored: [UInt32] = []
        for zone in UInt32(0)...7 {
            restored += [0x20B00C00 | zone, zone % 2 == 0 ? 0x20B02C07 : 0x20B02C47]
        }
        restored.append(0x20B00C07)
        precondition(r.modeChanged(enabled: false) == restored)
        for zone in UInt32(0)...7 {
            let next = r.process([0x20B00F00 | zone, 0x20B02F47], enabled: true)
            precondition(next[2] == (zone % 2 == 0 ? 0x20B02F42 : 0x20B02F45))
        }
        r.reset()

        // Expanded output exceeds one CoreMIDI list; keep order and UMP boundaries.
        let input = [UInt32(0x20B00F00)] + Array(repeating: UInt32(0x20B02F47), count: 5000) + opaque
        let expanded = r.process(input, enabled: true)
        precondition(expanded.count == 45001 + opaque.count)
        var received: [UInt32] = []
        EventListTransport.sendWords(expanded, timestamp: 123456) { list in
            EventListTransport.forEachPacket(list) { packet in
                precondition(packet.pointee.timeStamp == 123456)
                let base = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!).assumingMemoryBound(to: UInt32.self)
                let words = Array(UnsafeBufferPointer(start: base, count: Int(packet.pointee.wordCount)))
                var cursor = 0
                while cursor < words.count { cursor += RecAutomationRemapper.messageWidth(words[cursor]) }
                precondition(cursor == words.count)
                received += words
            }
            return noErr
        }
        precondition(received == expanded)
        print("PASS: 8 independent strips / per-strip LED restoration; Touch/Read + strip AUTO sequence, split Rec, repeated presses, bypass, opaque payloads, blink feedback, manual Read sync, stale feedback, Rec LED masking/restoration, reset, 45k-word output")
    }
}
