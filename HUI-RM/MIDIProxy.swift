import Foundation
import CoreMIDI

struct MonitorEvent: Identifiable {
    let id = UUID()
    let date: Date
    let timestamp: MIDITimeStamp
    let direction: String
    let words: [UInt32]
    let totalWords: Int
    let status: OSStatus

    var line: String {
        let time = date.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
        let data = words.map { String(format: "%08X", $0) }.joined(separator: " ")
        let suffix = totalWords > words.count ? " … [表示省略: 全\(totalWords) words]" : ""
        let result = status == noErr ? "" : " [未転送 / OSStatus \(status)]"
        return "\(time)  \(direction)  t=\(timestamp)  \(data)\(suffix)\(result)"
    }
}

/// Lifecycle calls run on the main actor. CoreMIDI callbacks never touch UI state.
/// The lock protects routing handles and the bounded monitor buffer. No UI work or
/// string formatting takes place in the receive callbacks.
final class MIDIProxy: @unchecked Sendable {
    private let lock = NSLock()
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var virtualSource: MIDIEndpointRef = 0
    private var virtualDestination: MIDIEndpointRef = 0
    private var hardwareSource: MIDIEndpointRef = 0
    private var hardwareDestination: MIDIEndpointRef = 0
    private var recRemapEnabled = false
    private var trimRemapEnabled = false
    private var remapper = RecAutomationRemapper()
    private var releaseRepair = MagicFaderReleaseRepair()
    private var releaseRepairEnabled = false
    private var isMagicFader = false
    private let releaseQueue = DispatchQueue(label: "HUI-RM.SoloRelease")
    private var recording = false
    private var events: [MonitorEvent] = []
    private var omitted = 0
    private var toHost = 0
    private var toDevice = 0
    private var failures = 0
    private var lastFailure: OSStatus = noErr
    private var topologyChanged = true
    private var generation = 0

    struct Snapshot {
        let events: [MonitorEvent]
        let omitted: Int
        let toHost: Int
        let toDevice: Int
        let failures: Int
        let lastFailure: OSStatus
        let topologyChanged: Bool
        let trimTarget: UInt8?
    }

    @MainActor
    func start() throws {
        guard client == 0 else { return }
        do {
            try check(MIDIClientCreateWithBlock("HUI-RM" as CFString, &client) { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.topologyChanged = true
                self.lock.unlock()
            }, "MIDIクライアント作成")
            try check(MIDISourceCreateWithProtocol(client, "HUI-RM" as CFString, ._1_0, &virtualSource), "仮想入力作成")
            try restoreID(virtualSource, key: "VirtualSourceID")
            try check(MIDIDestinationCreateWithProtocol(client, "HUI-RM" as CFString, ._1_0, &virtualDestination) { [weak self] list, _ in
                self?.forward(list, fromHardware: false)
            }, "仮想出力作成")
            try restoreID(virtualDestination, key: "VirtualDestinationID")
            try check(MIDIOutputPortCreate(client, "To Controller" as CFString, &outputPort), "MIDI出力作成")
        } catch {
            stop()
            throw error
        }
    }

    @MainActor
    private func restoreID(_ endpoint: MIDIEndpointRef, key: String) throws {
        let defaults = UserDefaults.standard
        let saved = Int32(truncatingIfNeeded: defaults.integer(forKey: key))
        if saved != 0 {
            // Do not silently change identity on collision: the user's DAW routing
            // would otherwise refer to a different endpoint.
            try check(MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, saved), "仮想MIDI IDの復元（重複時は他のHUI-RMを終了してください）")
        }
        var actual: Int32 = 0
        try check(MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &actual), "仮想MIDI IDの取得")
        defaults.set(Int(actual), forKey: key)
    }

    @MainActor
    func endpoints(sources: Bool) -> [MIDIEndpoint] {
        let count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        return (0..<count).compactMap { index in
            let ref = sources ? MIDIGetSource(index) : MIDIGetDestination(index)
            guard ref != 0, ref != virtualSource, ref != virtualDestination else { return nil }
            // Phase 1 only routes to device-owned endpoints, excluding virtual loopbacks.
            var entity: MIDIEntityRef = 0
            guard MIDIEndpointGetEntity(ref, &entity) == noErr, entity != 0 else { return nil }
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(ref, kMIDIPropertyOffline, &offline)
            guard offline == 0 else { return nil }
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
            return MIDIEndpoint(id: ref, name: name?.takeRetainedValue() as String? ?? "MIDI \(ref)", uniqueID: uid)
        }
    }

    @MainActor
    func connect(source: MIDIEndpointRef, destination: MIDIEndpointRef) throws {
        disconnect()
        guard client != 0,
              endpoints(sources: true).contains(where: { $0.id == source }),
              endpoints(sources: false).contains(where: { $0.id == destination }) else {
            throw ProxyError(message: "接続先が見つかりません。一覧を更新してください。")
        }
        // Each input port captures its connection generation. A late callback from
        // an old device must never be delivered through a newly selected route.
        lock.lock()
        generation += 1
        let token = generation
        lock.unlock()
        var port: MIDIPortRef = 0
        try check(MIDIInputPortCreateWithProtocol(client, "From Controller" as CFString, ._1_0, &port) { [weak self] list, _ in
            self?.forward(list, fromHardware: true, generation: token)
        }, "MIDI入力作成")
        lock.lock()
        inputPort = port
        isMagicFader = endpoints(sources: true).first(where: { $0.id == source }).map { MagicFaderReleaseRepair.matchesDevice($0.name) } ?? false
        hardwareSource = source
        hardwareDestination = destination
        lock.unlock()
        let status = MIDIPortConnectSource(port, source, nil)
        if status != noErr {
            disconnect()
            try check(status, "コントローラー接続")
        }
    }

    @MainActor
    func disconnect() {
        lock.lock()
        let port = inputPort
        let source = hardwareSource
        if recRemapEnabled, hardwareDestination != 0, outputPort != 0 {
            let restore = remapper.modeChanged(enabled: false)
            if !restore.isEmpty { sendToController(restore, timestamp: 0, direction: "HUI-RM → Controller [Recランプ復元]") }
        }
        inputPort = 0
        hardwareSource = 0
        hardwareDestination = 0
        generation += 1
        remapper.reset()
        releaseRepair = MagicFaderReleaseRepair()
        isMagicFader = false
        lock.unlock()
        // Dispose outside the lock, because CoreMIDI may wait for a callback.
        if port != 0 {
            if source != 0 { MIDIPortDisconnectSource(port, source) }
            MIDIPortDispose(port)
        }
    }

    @MainActor
    func stop() {
        disconnect()
        lock.lock()
        let oldClient = client
        client = 0
        virtualSource = 0
        virtualDestination = 0
        outputPort = 0
        lock.unlock()
        if oldClient != 0 { MIDIClientDispose(oldClient) }
    }

    func setRecRemap(_ enabled: Bool) {
        lock.lock()
        guard recRemapEnabled != enabled else { lock.unlock(); return }
        recRemapEnabled = enabled
        let feedback = remapper.modeChanged(enabled: enabled)
        if hardwareDestination != 0, outputPort != 0, !feedback.isEmpty {
            sendToController(feedback, timestamp: 0, direction: "HUI-RM → Controller [Recランプ復元/同期]")
        }
        lock.unlock()
    }

    func setTrimRemap(_ enabled: Bool) {
        lock.lock()
        trimRemapEnabled = enabled
        lock.unlock()
    }

    func setReleaseRepair(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !enabled, releaseRepairEnabled, isMagicFader, hardwareSource != 0 {
            _ = sendToHost(releaseRepair.finishPending(), direction: "HUI-RM → Pro Tools [Solo Release補完終了]")
        }
        releaseRepairEnabled = enabled
    }

    private func scheduleRelease(_ ticket: MagicFaderReleaseRepair.Ticket) {
        let token = generation
        releaseQueue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.generation == token, self.releaseRepairEnabled, self.isMagicFader,
                  self.hardwareSource != 0, self.virtualSource != 0 else { return }
            _ = self.sendToHost(self.releaseRepair.take(ticket), direction: "HUI-RM → Pro Tools [Solo Release補完]")
        }
    }

    @discardableResult
    private func sendToHost(_ words: [UInt32], timestamp: MIDITimeStamp = 0, direction: String) -> OSStatus {
        var failure: OSStatus = noErr
        EventListTransport.sendWords(words, timestamp: timestamp) { output in
            let result = EventListTransport.withSourceTimestamps(output) {
                MIDIReceivedEventList(virtualSource, $0)
            }
            toHost += Int(output.pointee.numPackets)
            countFailure(result)
            if result != noErr { failure = result; remapper.sendFailed(); releaseRepair.cancel() }
            record(output, direction: direction, status: result)
            return result
        }
        return failure
    }

    func setRecording(_ enabled: Bool) {
        lock.lock()
        recording = enabled
        lock.unlock()
    }

    func clearMonitor() {
        lock.lock()
        events.removeAll(keepingCapacity: true)
        omitted = 0
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let value = Snapshot(events: events, omitted: omitted, toHost: toHost, toDevice: toDevice,
                             failures: failures, lastFailure: lastFailure, topologyChanged: topologyChanged, trimTarget: remapper.trimTarget)
        events.removeAll(keepingCapacity: true)
        omitted = 0
        topologyChanged = false
        return value
    }

    private func forward(_ list: UnsafePointer<MIDIEventList>, fromHardware: Bool, generation token: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let token, token != generation { return }
        guard hardwareSource != 0, hardwareDestination != 0, virtualSource != 0, outputPort != 0 else { return }
        if fromHardware {
            if isMagicFader {
                EventListTransport.forEachPacket(list) { packet in
                    let words = packetWords(packet)
                    let repaired = releaseRepair.process(words, enabled: releaseRepairEnabled)
                    let output = remapper.process(repaired.words, enabled: recRemapEnabled, trimEnabled: trimRemapEnabled)
                    if output != words {
                        EventListTransport.sendWords(words, timestamp: packet.pointee.timeStamp) {
                            record($0, direction: "Controller → HUI-RM [入力]", status: noErr)
                            return noErr
                        }
                    }
                    let result = sendToHost(output, timestamp: packet.pointee.timeStamp,
                        direction: output == words ? "Controller → Pro Tools" : "HUI-RM → Pro Tools [変換後]")
                    if result == noErr { repaired.tickets.forEach { scheduleRelease($0) } }
                }
                return
            }
            // Track the controller's zone across packets, callbacks, and toggles.
            var packets: [(MIDITimeStamp, [UInt32])] = []
            var changed = false
            EventListTransport.forEachPacket(list) { packet in
                let words = packetWords(packet)
                let output = remapper.process(words, enabled: recRemapEnabled)
                changed = changed || output != words
                packets.append((packet.pointee.timeStamp, output))
            }
            if changed {
                record(list, direction: "Controller → HUI-RM [入力]", status: noErr)
                for (timestamp, words) in packets where !words.isEmpty {
                    // Chunk only on UMP message boundaries; expansion can exceed
                    // CoreMIDI's maximum event-list size for a large input list.
                    EventListTransport.sendWords(words, timestamp: timestamp) { output in
                        let result = EventListTransport.withSourceTimestamps(output) {
                            MIDIReceivedEventList(virtualSource, $0)
                        }
                        toHost += Int(output.pointee.numPackets)
                        countFailure(result)
                        if result != noErr { remapper.sendFailed() }
                        record(output, direction: "HUI-RM → Pro Tools [変換後]", status: result)
                        return result
                    }
                }
                return
            }
            let result = EventListTransport.withSourceTimestamps(list) {
                MIDIReceivedEventList(virtualSource, $0)
            }
            toHost += Int(list.pointee.numPackets)
            countFailure(result)
            record(list, direction: "Controller → Pro Tools", status: result)
        } else {
            var packets: [(MIDITimeStamp, [UInt32])] = []
            var changed = false
            EventListTransport.forEachPacket(list) { packet in
                let words = packetWords(packet)
                let output = remapper.processFeedback(words, enabled: recRemapEnabled)
                changed = changed || words != output
                packets.append((packet.pointee.timeStamp, output))
            }
            if changed {
                record(list, direction: "Pro Tools → HUI-RM [入力]", status: noErr)
                for (timestamp, words) in packets where !words.isEmpty {
                    sendToController(words, timestamp: timestamp, direction: "HUI-RM → Controller [Recランプ反映]")
                }
                return
            }
            let result = MIDISendEventList(outputPort, hardwareDestination, list)
            toDevice += Int(list.pointee.numPackets)
            countFailure(result)
            record(list, direction: "Pro Tools → Controller", status: result)
        }
    }

    private func sendToController(_ words: [UInt32], timestamp: MIDITimeStamp, direction: String) {
        EventListTransport.sendWords(words, timestamp: timestamp) { output in
            let result = MIDISendEventList(outputPort, hardwareDestination, output)
            toDevice += Int(output.pointee.numPackets)
            countFailure(result)
            record(output, direction: direction, status: result)
            return result
        }
    }

    private func packetWords(_ packet: UnsafePointer<MIDIEventPacket>) -> [UInt32] {
        let words = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
            .assumingMemoryBound(to: UInt32.self)
        return Array(UnsafeBufferPointer(start: words, count: Int(packet.pointee.wordCount)))
    }

    private func countFailure(_ status: OSStatus) {
        if status != noErr {
            failures += 1
            lastFailure = status
        }
    }

    private func record(_ list: UnsafePointer<MIDIEventList>, direction: String, status: OSStatus) {
        guard recording else { return }
        let now = Date()
        EventListTransport.forEachPacket(list) { packet in
            guard events.count < 512 else { omitted += 1; return }
            let count = Int(packet.pointee.wordCount)
            let words = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                .assumingMemoryBound(to: UInt32.self)
            events.append(MonitorEvent(date: now, timestamp: packet.pointee.timeStamp,
                                       direction: direction,
                                       words: Array(UnsafeBufferPointer(start: words, count: min(count, 64))),
                                       totalWords: count, status: status))
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw ProxyError(message: "\(operation): OSStatus \(status)") }
    }
}

struct ProxyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
