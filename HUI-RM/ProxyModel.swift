import AppKit
import Combine
import CoreMIDI

@MainActor
final class ProxyModel: ObservableObject {
    @Published var sources: [MIDIEndpoint] = []
    @Published var destinations: [MIDIEndpoint] = []
    @Published var selectedSource: MIDIEndpointRef = 0
    @Published var selectedDestination: MIDIEndpointRef = 0
    @Published private(set) var isReady = false
    @Published private(set) var isConnected = false
    @Published private(set) var status = NSLocalizedString("Initializing", comment: "")
    @Published private(set) var error: String?
    @Published private(set) var log: [MonitorEvent] = []
    @Published private(set) var omitted = 0
    @Published private(set) var toHost = 0
    @Published private(set) var toDevice = 0
    @Published private(set) var failures = 0
    @Published var recRemapEnabled = false {
        didSet {
            UserDefaults.standard.set(recRemapEnabled, forKey: Self.remapPreferenceKey)
            proxy.setRecRemap(recRemapEnabled)
            if isConnected { status = connectedStatus }
        }
    }
    @Published var trimRemapEnabled = false {
        didSet {
            UserDefaults.standard.set(trimRemapEnabled, forKey: Self.trimPreferenceKey)
            proxy.setTrimRemap(trimRemapEnabled)
            if isConnected { status = connectedStatus }
        }
    }
    private var connectedStatus: String {
        var modes: [String] = []
        if recRemapEnabled { modes.append("Rec Ready → Touch / Read") }
        if trimRemapEnabled && isMagicFader { modes.append(NSLocalizedString("Transport Record → Trim", comment: "")) }
        return NSLocalizedString("Routing · ", comment: "") + (modes.isEmpty ? "Remap OFF" : modes.joined(separator: " · "))
    }
    @Published var releaseRepairEnabled = false {
        didSet {
            UserDefaults.standard.set(releaseRepairEnabled, forKey: Self.releaseRepairPreferenceKey)
            proxy.setReleaseRepair(releaseRepairEnabled)
        }
    }
    @Published private(set) var isMagicFader = false
    @Published private(set) var trimTarget: Int?

    @Published var refreshEnabled = false {
        didSet {
            UserDefaults.standard.set(refreshEnabled, forKey: Self.refreshPreferenceKey)
            proxy.setRefresh(refreshEnabled)
        }
    }
    @Published private(set) var refreshNotice = NSLocalizedString("Waiting for stop and fader position", comment: "")

    @Published var loopFlipEnabled = false {
        didSet {
            UserDefaults.standard.set(loopFlipEnabled, forKey: "MagicFaderLoopFlipEnabled")
            proxy.setLoopFlip(loopFlipEnabled)
        }
    }
    @Published var transportSendEnabled = false {
        didSet {
            UserDefaults.standard.set(transportSendEnabled, forKey: "MagicFaderTransportSendEnabled")
            proxy.setTransportSend(transportSendEnabled)
        }
    }
    @Published var restoreSendEnabled = false {
        didSet {
            UserDefaults.standard.set(restoreSendEnabled, forKey: "MagicFaderRestoreSendEnabled")
            proxy.setRestoreSend(restoreSendEnabled)
        }
    }
    @Published private(set) var flipLamp = NSLocalizedString("PT Flip LED: No feedback", comment: "")
    @Published private(set) var flipNotice = NSLocalizedString("Not used yet", comment: "")

    func toggleFlip() {
        proxy.toggleFlip()
        poll()
    }

    @Published var recording = false {
        didSet { proxy.setRecording(recording) }
    }
    private static let refreshPreferenceKey = "MagicFaderRefreshEnabled"
    private static let releaseRepairPreferenceKey = "MagicFaderSoloReleaseRepairEnabled"
    private static let trimPreferenceKey = "MagicFaderTrimRemapEnabled"
    private static let remapPreferenceKey = "RemapEnabled"
    private let proxy = MIDIProxy()
    private var connectionMemory = ConnectionMemory()
    private var nextAutomaticAttempt: TimeInterval = 0
    private var nextEndpointScan: TimeInterval = 0
    private var connectedSourceUID: MIDIUniqueID = 0
    private var connectedDestinationUID: MIDIUniqueID = 0
    private var timer: AnyCancellable?
    private var connectedSource: MIDIEndpointRef = 0
    private var connectedDestination: MIDIEndpointRef = 0

    init() {
        recRemapEnabled = UserDefaults.standard.bool(forKey: Self.remapPreferenceKey)
        // Explicitly update the engine before start() can reconnect a saved device;
        // property observers are not relied on during initialization.
        proxy.setRecRemap(recRemapEnabled)
        // Keep the existing key for Rec. Seed Trim once from the legacy combined switch.
        let defaults = UserDefaults.standard
        trimRemapEnabled = defaults.object(forKey: Self.trimPreferenceKey) == nil
            ? recRemapEnabled : defaults.bool(forKey: Self.trimPreferenceKey)
        defaults.set(trimRemapEnabled, forKey: Self.trimPreferenceKey)
        proxy.setTrimRemap(trimRemapEnabled)
        releaseRepairEnabled = UserDefaults.standard.bool(forKey: Self.releaseRepairPreferenceKey)
        proxy.setReleaseRepair(releaseRepairEnabled)
        refreshEnabled = defaults.bool(forKey: Self.refreshPreferenceKey)
        proxy.setRefresh(refreshEnabled)
        loopFlipEnabled = defaults.bool(forKey: "MagicFaderLoopFlipEnabled")
        proxy.setLoopFlip(loopFlipEnabled)
        restoreSendEnabled = defaults.bool(forKey: "MagicFaderRestoreSendEnabled")
        proxy.setRestoreSend(restoreSendEnabled)
        transportSendEnabled = defaults.bool(forKey: "MagicFaderTransportSendEnabled")
        proxy.setTransportSend(transportSendEnabled)
        start()
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.poll()
        }
    }

    func start() {
        do {
            try proxy.start()
            isReady = true
            status = NSLocalizedString("Controller disconnected", comment: "")
            error = nil
            refresh()
        } catch {
            isReady = false
            status = NSLocalizedString("Could not create virtual MIDI ports", comment: "")
            self.error = error.localizedDescription
        }
    }

    func refresh() {
        sources = proxy.endpoints(sources: true)
        destinations = proxy.endpoints(sources: false)
        if isConnected && (!sources.contains { $0.id == connectedSource && $0.uniqueID == connectedSourceUID } || !destinations.contains { $0.id == connectedDestination && $0.uniqueID == connectedDestinationUID }) {
            disconnectRoute()
            status = NSLocalizedString("Controller was disconnected", comment: "")
            nextAutomaticAttempt = 0
        }
        if !sources.contains(where: { $0.id == selectedSource }) { selectedSource = 0 }
        if !destinations.contains(where: { $0.id == selectedDestination }) { selectedDestination = 0 }
        attemptAutomaticConnection()
    }

    private func attemptAutomaticConnection() {
        guard isReady, !isConnected, connectionMemory.automaticAllowed,
              let saved = connectionMemory.saved else { return }
        guard let (source, destination) = connectionMemory.candidate(sources: sources, destinations: destinations) else {
            status = String(format: NSLocalizedString("Waiting for previous device · %@", comment: ""), saved.sourceName)
            return
        }
        guard ProcessInfo.processInfo.systemUptime >= nextAutomaticAttempt else { return }
        selectedSource = source.id
        selectedDestination = destination.id
        nextAutomaticAttempt = ProcessInfo.processInfo.systemUptime + 2
        establishConnection(source: source, destination: destination)
    }

    func connect() {
        // A failed manual choice must not silently connect to a previous device.
        connectionMemory.suspendAutomaticConnection()
        guard let source = sources.first(where: { $0.id == selectedSource }),
              let destination = destinations.first(where: { $0.id == selectedDestination }) else {
            error = NSLocalizedString("Select the input and output devices again.", comment: "")
            return
        }
        establishConnection(source: source, destination: destination)
    }

    private func establishConnection(source: MIDIEndpoint, destination: MIDIEndpoint) {
        do {
            try proxy.connect(source: source.id, destination: destination.id)
            connectedSource = source.id
            connectedDestination = destination.id
            connectedSourceUID = source.uniqueID
            connectedDestinationUID = destination.uniqueID
            isConnected = true
            isMagicFader = MagicFaderReleaseRepair.matchesDevice(source.name)
            status = connectedStatus
            let remembered = connectionMemory.remember(source: source, destination: destination)
            error = remembered ? nil : NSLocalizedString("Connected, but the device identity could not be saved. Connect manually next time.", comment: "")
        } catch {
            isConnected = false
            isMagicFader = false
            status = NSLocalizedString("Connection failed", comment: "")
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        connectionMemory.suspendAutomaticConnection()
        disconnectRoute()
        status = NSLocalizedString("Disconnected manually · Auto-connect paused until next launch", comment: "")
    }

    private func disconnectRoute() {
        proxy.disconnect()
        isMagicFader = false
        trimTarget = nil
        isConnected = false
        connectedSource = 0
        connectedDestination = 0
        connectedSourceUID = 0
        connectedDestinationUID = 0
        status = NSLocalizedString("Controller disconnected", comment: "")
    }

    func clear() {
        proxy.clearMonitor()
        log.removeAll(keepingCapacity: true)
        omitted = 0
    }

    func copyLog() {
        let header = "MF-RM Phase 2 | Rec Ready → Touch / Read; Transport Record → Trim; Click → Refresh (optional); Flip / optional Send restore | UMP hexadecimal | retained \(log.count), omitted \(omitted) | timestamp: CoreMIDI host ticks\n"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(header + log.map(\.line).joined(separator: "\n"), forType: .string)
    }

    func shutdown() {
        timer?.cancel()
        proxy.stop()
    }

    private func poll() {
        let snapshot = proxy.snapshot()
        if snapshot.topologyChanged || (!isConnected && connectionMemory.automaticAllowed &&
            connectionMemory.saved != nil && ProcessInfo.processInfo.systemUptime >= nextEndpointScan) {
            refresh()
            nextEndpointScan = ProcessInfo.processInfo.systemUptime + 2
        }
        flipLamp = snapshot.flipLamp
        flipNotice = snapshot.flipNotice
        refreshNotice = snapshot.refreshNotice
        trimTarget = snapshot.trimTarget.map { Int($0) + 1 }
        toHost = snapshot.toHost
        toDevice = snapshot.toDevice
        if snapshot.failures != failures {
            error = String(format: NSLocalizedString("MIDI routing error: OSStatus %@", comment: ""), String(snapshot.lastFailure))
        }
        failures = snapshot.failures
        if !snapshot.events.isEmpty {
            log.append(contentsOf: snapshot.events)
            if log.count > 2000 {
                let excess = log.count - 2000
                log.removeFirst(excess)
                omitted += excess
            }
        }
        omitted += snapshot.omitted
    }
}
