import Foundation

@main
struct ConnectionMemoryChecks {
    static func main() {
        let name = "HUIRM.ConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let source = MIDIEndpoint(id: 1, name: "Magic Fader", uniqueID: 100)
        let destination = MIDIEndpoint(id: 2, name: "Magic Fader", uniqueID: -200)
        var memory = ConnectionMemory(defaults: defaults)
        precondition(memory.candidate(sources: [source], destinations: [destination]) == nil)
        precondition(memory.remember(source: source, destination: destination))
        // Reload defaults as on a fresh launch; CoreMIDI handles and names changed.
        var relaunched = ConnectionMemory(defaults: defaults)
        let newSource = MIDIEndpoint(id: 55, name: "Renamed input", uniqueID: 100)
        let newDestination = MIDIEndpoint(id: 66, name: "Renamed output", uniqueID: -200)
        let candidate = relaunched.candidate(sources: [newSource], destinations: [newDestination])
        precondition(candidate?.0.id == 55 && candidate?.1.id == 66)
        precondition(relaunched.candidate(sources: [newSource], destinations: []) == nil)
        precondition(relaunched.candidate(sources: [], destinations: [newDestination]) == nil)
        precondition(relaunched.candidate(sources: [newSource], destinations: [newDestination]) != nil)
        // Do not guess on matching names or duplicate IDs.
        let impostor = MIDIEndpoint(id: 77, name: "Magic Fader", uniqueID: 999)
        precondition(relaunched.candidate(sources: [impostor], destinations: [destination]) == nil)
        precondition(relaunched.candidate(sources: [source, newSource], destinations: [destination]) == nil)
        relaunched.suspendAutomaticConnection()
        precondition(relaunched.candidate(sources: [source], destinations: [destination]) == nil)
        precondition(ConnectionMemory(defaults: defaults).candidate(sources: [source], destinations: [destination]) != nil)
        precondition(relaunched.remember(source: newSource, destination: newDestination))
        precondition(relaunched.candidate(sources: [newSource], destinations: [newDestination]) != nil)
        // Switching devices replaces both endpoints, only after a successful connect.
        precondition(relaunched.remember(source: impostor, destination: destination))
        let switched = ConnectionMemory(defaults: defaults)
        precondition(switched.candidate(sources: [source], destinations: [destination]) == nil)
        precondition(switched.candidate(sources: [impostor], destinations: [destination]) != nil)
        let invalid = MIDIEndpoint(id: 88, name: "No UID", uniqueID: 0)
        precondition(!relaunched.remember(source: invalid, destination: destination))
        precondition(ConnectionMemory(defaults: defaults).saved == nil)
        print("PASS: saved pair reload, changed handles/name, unplug/replug, incomplete pair, duplicate ID, name mismatch, manual disconnect suppression, relaunch/manual reconnect, device replacement, invalid IDs")
    }
}
