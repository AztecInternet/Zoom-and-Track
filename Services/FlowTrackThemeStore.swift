import Foundation

struct FlowTrackThemeStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var storageURL: URL {
        get throws {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = supportURL.appendingPathComponent("FlowTrack Capture", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL.appendingPathComponent("FlowTrackThemes.json")
        }
    }

    func loadLibrary() -> FlowTrackThemeLibrary {
        do {
            let url = try storageURL
            guard fileManager.fileExists(atPath: url.path) else {
                return FlowTrackThemeLibrary()
            }
            let data = try Data(contentsOf: url)
            var library = try decoder.decode(FlowTrackThemeLibrary.self, from: data)
            if let selectedThemeID = library.selectedThemeID,
               !library.savedThemes.contains(where: { $0.id == selectedThemeID }) {
                library.selectedThemeID = nil
            }
            if let selectedBuiltInThemeID = library.selectedBuiltInThemeID,
               !FlowTrackThemeDefaults.builtInThemes.contains(where: { $0.id == selectedBuiltInThemeID }) {
                library.selectedBuiltInThemeID = flowTrackBuiltInThemeID
            }
            let builtInIDs = Set(FlowTrackThemeDefaults.builtInThemes.map(\.id))
            library.builtInOverrides = library.builtInOverrides.filter { builtInIDs.contains($0.key) }
            return library
        } catch {
            return FlowTrackThemeLibrary()
        }
    }

    func saveLibrary(_ library: FlowTrackThemeLibrary) throws {
        let data = try encoder.encode(library)
        let url = try storageURL
        try data.write(to: url, options: .atomic)
    }
}
