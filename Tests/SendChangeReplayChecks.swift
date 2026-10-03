import Foundation

@main
struct SendChangeReplayChecks {
    static func main() throws {
        var r = FlipFeedbackReplay()
        let bus2: [UInt32] = [0x30160000,0x66050010,0x30350042,0x75733200]
        let position: [UInt32] = [0x20B00029,0x20B02020]
        assert(r.hardware([0x20B00F0B], flipActive: true, now: 0) == nil)
        let first = r.hardware([0x20B02F46], flipActive: true, now: 0)!
        r.feedback(bus2 + position, now: 0.001)
        assert(r.next(first, now: 0.15) == bus2) // No zone-8 FLIP message required or invented.
        for step in 1..<8 { assert(r.next(first, now: 0.15 + Double(step)*0.02).isEmpty) }
        assert(r.next(first, now: 0.31) == position)
        let second = r.hardware([0x20B02F47], flipActive: true, now: 0.32)!
        assert(r.next(first, now: 0.33).isEmpty)
        assert(r.next(second, now: 0.47).isEmpty) // Previous Bus2 is not reused.
        r.hardware([0x20B02F42], flipActive: true, now: 0.48)
        assert(r.id == nil) // Pan cancels, never starts replay.
        for port in UInt32(0)...2 {
            assert(r.hardware([0x20B00F0B,0x20B02F40 | port], flipActive: true, now: 1) == nil)
        }
        assert(r.hardware([0x20B00F0B,0x20B02F45], flipActive: false, now: 2) == nil)
        assert(r.hardware([0x20B00F0B,0x20B02F45,0x20B00F00,0x20B02F40], flipActive: true, now: 3) == nil)
        assert(r.id == nil)
        let released = r.hardware([0x20B00F0B,0x20B02F45,0x20B02F05], flipActive: true, now: 4)!
        assert(r.id == released)
        r.feedback([0x20B00C00,0x20B02C41], now: 4.1)
        assert(r.id == nil)

        // Exact PT response bursts for D, C, B, A, E from the supplied capture.
        let log = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        var bursts: [[[UInt32]]] = []
        let times = ["7:49:53.437", "7:49:54.366", "7:49:55.300", "7:49:56.656", "7:50:04.093"]
        for time in times {
            var collecting = false
            var packets: [[UInt32]] = []
            for line in log.split(separator: "\n") {
                if line.hasPrefix(time), line.contains("Controller → Pro Tools"), line.contains("20B02F") { collecting = true; continue }
                if collecting, line.contains("Controller → Pro Tools"), line.contains("20B00F") { break }
                if collecting, line.contains("Pro Tools → Controller"), let range = line.range(of: "t=0  ") {
                    packets.append(line[range.upperBound...].split(separator: " ").compactMap { UInt32($0, radix: 16) })
                }
            }
            bursts.append(packets)
        }
        let ports: [UInt32] = [4,5,6,7,3]
        let names: [UInt32] = [0x75733400,0x75733300,0x75733200,0x75733100,0x75733500]
        for index in 0..<5 {
            r = FlipFeedbackReplay()
            let id = r.hardware([0x20B00F0B,0x20B02F40 | ports[index]], flipActive: true, now: 0)!
            for words in bursts[index] { r.feedback(words, now: 0.001) }
            var outputs: [[UInt32]] = []
            for step in 0..<16 { outputs.append(r.next(id, now: 0.15 + Double(step)*0.02)) }
            assert(outputs[0] == [0x30160000,0x66050010,0x30350042,names[index]])
            assert(outputs[1..<8].allSatisfy { $0.isEmpty })
            assert(outputs[8..<16].allSatisfy { $0.count == 2 })
            assert(r.id == nil)
        }
        print("PASS: 5 captured send changes without mode text, latest-only replay, cancellation, release, and non-Flip/Input/Output/Pan passthrough")
    }
}
