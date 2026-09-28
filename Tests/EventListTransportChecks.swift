import CoreMIDI
import Foundation

@main
struct EventListTransportChecks {
    static func main() {
        let capacity = 65536
        let memory = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: MIDIEventList.self, capacity: 1)
        var cursor = MIDIEventListInit(list, ._1_0)
        // Includes HUI ping, switch press/release, fader, unknown CC, realtime,
        // and a SysEx7 start/continue/end sequence, with distinct timestamps.
        let samples: [(UInt64, [UInt32])] = [
            (111, [0x20900000]), (222, [0x20B00F18, 0x20B02F45]),
            (333, [0x20B00F18, 0x20B02F05]), (444, [0x20B0007F, 0x20B0207F]),
            (555, [0x20B07712, 0x10F80000]),
            (666, [0x30160000, 0x66050010]), (777, [0x30264142, 0x43444546]),
            (888, [0x30314700, 0x00000000])
        ]
        for (time, words) in samples {
            cursor = words.withUnsafeBufferPointer {
                MIDIEventListAdd(list, capacity, cursor, time, $0.count, $0.baseAddress!)
            }
        }
        let expected = read(UnsafePointer(list))
        var called = 0
        let result = EventListTransport.withSourceTimestamps(UnsafePointer(list)) { forwarded in
            called += 1
            precondition(forwarded == UnsafePointer(list), "Nonzero timestamps should use the original buffer")
            assertEqual(read(forwarded), expected)
            return -123
        }
        precondition(called == 1 && result == -123, "Forward once and propagate send errors")

        // More data than the imported Swift fixed-size struct can hold.
        cursor = MIDIEventListInit(list, ._1_0)
        let large = (0..<1200).map { UInt32(0x20B01000) | UInt32($0 % 128) }
        cursor = large.withUnsafeBufferPointer {
            MIDIEventListAdd(list, capacity, cursor, 0, $0.count, $0.baseAddress!)
        }
        let tail: [UInt32] = [0x2090007F]
        _ = tail.withUnsafeBufferPointer {
            MIDIEventListAdd(list, capacity, cursor, 999, $0.count, $0.baseAddress!)
        }
        let before = read(UnsafePointer(list))
        precondition(before.flatMap(\.1).count == 1201)
        _ = EventListTransport.withSourceTimestamps(UnsafePointer(list)) { forwarded in
            let after = read(forwarded)
            precondition(after.count == before.count)
            for (old, new) in zip(before, after) {
                precondition(old.1 == new.1, "Payload must not be truncated or rewritten")
                precondition(old.0 == 0 ? new.0 > 0 : old.0 == new.0, "Only zero timestamps may change")
            }
            return noErr
        }
        assertEqual(read(UnsafePointer(list)), before)

        _ = MIDIEventListInit(list, ._1_0)
        _ = EventListTransport.withSourceTimestamps(UnsafePointer(list)) {
            precondition($0.pointee.numPackets == 0)
            return noErr
        }
        print("PASS: HUI/unknown/SysEx/realtime payloads, packet ordering, nonzero timestamps, zero normalization, 1,201-word list, input immutability, send-error propagation, empty list")
    }

    static func read(_ list: UnsafePointer<MIDIEventList>) -> [(UInt64, [UInt32])] {
        var packets: [(UInt64, [UInt32])] = []
        EventListTransport.forEachPacket(list) { packet in
            let words = UnsafeRawPointer(packet)
                .advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                .assumingMemoryBound(to: UInt32.self)
            packets.append((packet.pointee.timeStamp, Array(UnsafeBufferPointer(start: words, count: Int(packet.pointee.wordCount)))))
        }
        return packets
    }

    static func assertEqual(_ lhs: [(UInt64, [UInt32])], _ rhs: [(UInt64, [UInt32])]) {
        precondition(lhs.count == rhs.count)
        for (a, b) in zip(lhs, rhs) { precondition(a.0 == b.0 && a.1 == b.1) }
    }
}
