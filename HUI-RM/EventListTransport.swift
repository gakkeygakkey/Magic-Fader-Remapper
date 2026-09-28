import CoreMIDI
import Darwin

/// Operate on pointers: MIDIEventList and MIDIEventPacket have variable lengths.
/// Copying their Swift struct values would truncate sufficiently large lists.
enum EventListTransport {
    static func forEachPacket(_ list: UnsafePointer<MIDIEventList>, _ body: (UnsafePointer<MIDIEventPacket>) -> Void) {
        var packet = UnsafeRawPointer(list)
            .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<list.pointee.numPackets {
            body(packet)
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
    }

    /// Bound each output allocation and retain complete UMP messages in order.
    static func sendWords(_ words: [UInt32], timestamp: MIDITimeStamp,
                          _ send: (UnsafePointer<MIDIEventList>) -> OSStatus) {
        let capacity = 4096
        let storage = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: MIDIEventList.self, capacity: 1)
        var start = 0
        while start < words.count {
            var end = start
            while end < words.count {
                let width = min(RecAutomationRemapper.messageWidth(words[end]), words.count - end)
                if end - start + width > 256 { break }
                end += width
            }
            let packet = MIDIEventListInit(list, ._1_0)
            words.withUnsafeBufferPointer { buffer in
                _ = MIDIEventListAdd(list, capacity, packet, timestamp, end - start, buffer.baseAddress! + start)
            }
            // Continue after an error so a synthesized release/restoration is
            // still attempted. The caller records every failed send.
            _ = send(UnsafePointer(list))
            start = end
        }
    }

    static func withSourceTimestamps(_ list: UnsafePointer<MIDIEventList>,
                                     _ send: (UnsafePointer<MIDIEventList>) -> OSStatus) -> OSStatus {
        var needsTimestamp = false
        var end = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
        forEachPacket(list) { packet in
            needsTimestamp = needsTimestamp || packet.pointee.timeStamp == 0
            end = UnsafeRawPointer(MIDIEventPacketNext(packet))
        }
        guard needsTimestamp else { return send(list) }
        let size = UnsafeRawPointer(list).distance(to: end)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: max(size, MemoryLayout<MIDIEventList>.size), alignment: 8)
        defer { storage.deallocate() }
        storage.copyMemory(from: UnsafeRawPointer(list), byteCount: size)
        let copy = storage.assumingMemoryBound(to: MIDIEventList.self)
        let now = mach_absolute_time()
        forEachPacket(UnsafePointer(copy)) { packet in
            if packet.pointee.timeStamp == 0 {
                UnsafeMutablePointer(mutating: packet).pointee.timeStamp = now
            }
        }
        return send(UnsafePointer(copy))
    }
}
