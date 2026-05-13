//
//  CreatorEffectDefaultsService.swift
//  Zoom and Track
//

import Foundation

struct CreatorEffectDefaultsService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadCreatorEffectDefaults() -> CreatorEffectDefaults {
        let url: URL
        do {
            url = try defaultsFileURL()
        } catch {
            return .default
        }

        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let defaults = try? JSONDecoder().decode(CreatorEffectDefaults.self, from: data) else {
            return .default
        }

        return defaults
    }

    func saveCreatorEffectDefaults(_ defaults: CreatorEffectDefaults) throws {
        let directoryURL = try defaultsDirectoryURL()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder.creatorDefaultsEncoder.encode(defaults)
        try data.write(to: directoryURL.appendingPathComponent("effectDefaults.json"), options: .atomic)
    }

    private func defaultsDirectoryURL() throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent("FlowTrack Capture", isDirectory: true)
            .appendingPathComponent("CreatorDefaults", isDirectory: true)
    }

    private func defaultsFileURL() throws -> URL {
        try defaultsDirectoryURL().appendingPathComponent("effectDefaults.json")
    }
}

private extension JSONEncoder {
    static let creatorDefaultsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
