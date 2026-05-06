import Foundation

struct LibraryManager {
    let projectBundleService: ProjectBundleService

    func loadLibrarySnapshot() async throws -> CaptureLibrarySnapshot {
        try await projectBundleService.loadLibrarySnapshot()
    }

    func bundleURL(for item: CaptureLibraryItem) throws -> URL {
        let libraryRoot = try projectBundleService.libraryRootURL()
        return libraryRoot.appendingPathComponent(item.bundleRelativePath, isDirectory: true)
    }
}
