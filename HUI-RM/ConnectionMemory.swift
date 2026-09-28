import Foundation
import CoreMIDI

struct MIDIEndpoint: Identifiable, Equatable {
    let id: MIDIEndpointRef
    let name: String
    let uniqueID: MIDIUniqueID
}

/// Persist stable CoreMIDI IDs, never process-local endpoint handles.
/// Names are display-only: a same-name device is not sufficient for reconnection.
struct ConnectionMemory {
    struct SavedPair: Codable {
        let sourceID: MIDIUniqueID
        let destinationID: MIDIUniqueID
        let sourceName: String
        let destinationName: String
    }

    private let defaults: UserDefaults
    private static let key = "LastSuccessfulControllerConnection.v1"
    private(set) var saved: SavedPair?
    private(set) var automaticAllowed = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let pair = try? JSONDecoder().decode(SavedPair.self, from: data),
           pair.sourceID != 0, pair.destinationID != 0 {
            saved = pair
        }
    }

    mutating func suspendAutomaticConnection() { automaticAllowed = false }

    /// Call only after CoreMIDI connection succeeds. Save both directions atomically.
    @discardableResult
    mutating func remember(source: MIDIEndpoint, destination: MIDIEndpoint) -> Bool {
        automaticAllowed = true
        guard source.uniqueID != 0, destination.uniqueID != 0 else {
            // Do not reconnect to an older device after a successful unsavable choice.
            saved = nil
            defaults.removeObject(forKey: Self.key)
            return false
        }
        let pair = SavedPair(sourceID: source.uniqueID, destinationID: destination.uniqueID,
                             sourceName: source.name, destinationName: destination.name)
        guard let data = try? JSONEncoder().encode(pair) else { return false }
        defaults.set(data, forKey: Self.key)
        saved = pair
        return true
    }

    func candidate(sources: [MIDIEndpoint], destinations: [MIDIEndpoint]) -> (MIDIEndpoint, MIDIEndpoint)? {
        guard automaticAllowed, let saved else { return nil }
        let inputs = sources.filter { $0.uniqueID == saved.sourceID }
        let outputs = destinations.filter { $0.uniqueID == saved.destinationID }
        guard inputs.count == 1, outputs.count == 1 else { return nil }
        return (inputs[0], outputs[0])
    }
}
