import Foundation

@main
struct FlipFeedbackReplayChecks {
    static let pan: [UInt32] = [0x30160000,0x66050010,0x30350850,0x616E2000]
    static let name: [UInt32] = [0x30160000,0x66050010,0x30350057,0x4C326300]
    static func main() throws {
        var r = FlipFeedbackReplay()
        let id = r.begin(now: 0)
        r.feedback(Array(pan.prefix(2)), now: 0.001)
        r.feedback(Array(pan.suffix(2)), now: 0.002)
        r.feedback(name + [0x20B00032,0x20B02000], now: 0.003)
        assert(r.next(id, now: 0.15) == pan)
        assert(r.next(id, now: 0.17) == name)
        for i in 2...8 { assert(r.next(id, now: 0.15 + Double(i)*0.02).isEmpty) }
        // Latest feedback replaces the captured position, even across packet boundaries.
        r.feedback([0x20B0005F], now: 0.30)
        r.feedback([0x20B02060], now: 0.301)
        assert(r.next(id, now: 0.33) == [0x20B0005F,0x20B02060])
        for i in 10...16 { _ = r.next(id, now: 0.15 + Double(i)*0.02) }
        assert(r.id == nil && r.next(id, now: 0.6).isEmpty)

        for event: [UInt32] in [[0x20B00F03,0x20B02F40], [0x20B00F0B,0x20B02F46],
                                [0x20B00F0A,0x20B02F41], [0x20B00F15,0x20B02F40],
                                [0x20B00040], [0x10FF0000]] {
            let token = r.begin(now: 1)
            r.feedback(pan, now: 1)
            r.hardware(event)
            assert(r.next(token, now: 1.15).isEmpty && r.id == nil)
        }
        let old = r.begin(now: 2)
        r.feedback(pan + name, now: 2)
        let new = r.begin(now: 2.1)
        assert(r.next(old, now: 2.15).isEmpty && r.id == new)
        assert(r.next(new, now: 2.25).isEmpty && r.id == nil) // No data inherited.
        let expired = r.begin(now: 3)
        r.feedback(pan, now: 3)
        assert(r.next(expired, now: 4).isEmpty)
        _ = r.begin(now: 5)
        r.feedback(pan + [0x20B00C01,0x20B02C41], now: 5)
        assert(r.id == nil)
        _ = r.begin(now: 6)
        r.feedback(pan + [0x10FF0000], now: 6)
        assert(r.id == nil)

        // Replay each real transition burst from the user's capture independently.
        if CommandLine.arguments.count > 1 {
            let log = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            var bursts: [[[UInt32]]] = []
            for line in log.split(separator: "\n") {
                if line.contains("[Flip切替・再選択なし]") { bursts.append([]) }
                guard !bursts.isEmpty, line.contains("Pro Tools → Controller"),
                      let start = line.range(of: "t=0  ") else { continue }
                bursts[bursts.count - 1].append(line[start.upperBound...].split(separator: " ").compactMap { UInt32($0, radix: 16) })
            }
            assert(bursts.count == 8)
            for (index, burst) in bursts.enumerated() {
                r = FlipFeedbackReplay()
                let token = r.begin(now: 0)
                // Limit to the immediate switch burst; later track selection intentionally cancels replay.
                for words in burst {
                    r.feedback(words, now: 0.001)
                    if words == [0x20B00C0C, index % 2 == 0 ? 0x20B02C43 : 0x20B02C03] { break }
                }
                var outputs: [[UInt32]] = []
                for step in 0..<17 { outputs.append(r.next(token, now: 0.15 + Double(step)*0.02)) }
                assert(outputs[0] == (index % 2 == 0 ? [0x30160000,0x66050010,0x30350846,0x4C495000] : pan))
                assert(outputs[1] == (index % 2 == 0 ? [0x30160000,0x66050010,0x30350042,0x75733100] : name))
                assert(outputs[9] == (index % 2 == 0 ? [0x20B00032,0x20B02000] : [0x20B0005F,0x20B02060]))
                assert(outputs.allSatisfy { !$0.isEmpty })
            }
        }
        print("PASS: paced fresh feedback, latest positions, cancellation, expiration, split SysEx, and 8 captured transitions")
    }
}
