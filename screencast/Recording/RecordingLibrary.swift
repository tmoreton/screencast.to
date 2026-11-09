import Darwin
import Foundation

/// Finished recordings live outside the temporary capture directory so they
/// survive restarts. Saving never replaces a movie that is already there.
nonisolated struct RecordingLibrary {
    let directory: URL

    init(directory: URL) {
        self.directory = directory.isFileURL ? directory.standardizedFileURL : directory
    }

    static func moviesDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return movies.appendingPathComponent("Screencast", isDirectory: true).standardizedFileURL
    }

    /// A durable fallback if the normal Movies folder cannot be written.
    static func recoveryDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return support
            .appendingPathComponent("Screencast", isDirectory: true)
            .appendingPathComponent("Recovered Recordings", isDirectory: true)
            .standardizedFileURL
    }

    @discardableResult
    func prepareDirectory() throws -> URL {
        guard directory.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func save(_ temporaryURL: URL) throws -> URL {
        guard temporaryURL.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let sourceValues = try temporaryURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        try prepareDirectory()

        let base = recordingBaseName(for: temporaryURL)
        let fileManager = FileManager.default
        var stagedURL: URL?
        defer {
            if let stagedURL { try? fileManager.removeItem(at: stagedURL) }
        }
        for index in 1...1_000 {
            let name = index == 1 ? base : "\(base) (\(index))"
            let destination = directory.appendingPathComponent(name).appendingPathExtension("mov")
            var failure = renameExclusively(from: stagedURL ?? temporaryURL, to: destination)
            if failure == EXDEV, stagedURL == nil {
                // A capture on another volume must be copied in full before it
                // becomes visible. Commit that hidden copy with the same atomic
                // no-replace operation, and retain the original until success.
                let staging = directory.appendingPathComponent(".screencast-\(UUID().uuidString).mov")
                stagedURL = staging
                try fileManager.copyItem(at: temporaryURL, to: staging)
                failure = renameExclusively(from: staging, to: destination)
            }
            if failure == 0 {
                if stagedURL != nil { try fileManager.removeItem(at: temporaryURL) }
                return destination
            }
            guard failure == EEXIST else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure),
                              userInfo: [NSFilePathErrorKey: destination.path])
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Scan without creating directories or traversing folders and symlinks.
    func recentRecordings(limit: Int) throws -> [URL] {
        guard limit > 0 else { return [] }
        guard directory.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               failure.code == CocoaError.fileReadNoSuchFile.rawValue || failure.code == CocoaError.fileNoSuchFile.rawValue {
                return []
            }
            throw error
        }

        return contents.compactMap { url -> (url: URL, modified: Date)? in
            guard url.pathExtension.lowercased() == "mov",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.url.path < $1.url.path
        }.prefix(limit).map(\.url)
    }

    private func recordingBaseName(for temporaryURL: URL) -> String {
        let base = temporaryURL.deletingPathExtension().lastPathComponent
        // RecordingEngine appends one UUID to its human-readable timestamp.
        // Leave all other names intact, including malformed UUID-like suffixes.
        if base.count > 37 {
            let suffix = String(base.suffix(37))
            let value = String(suffix.dropFirst())
            if suffix.first == "-", let uuid = UUID(uuidString: value),
               uuid.uuidString.lowercased() == value.lowercased() {
                return String(base.dropLast(37))
            }
        }
        return base.isEmpty ? "Screencast" : base
    }

    /// FileManager.moveItem checks for existence separately from its rename,
    /// which can overwrite a simultaneous save. RENAME_EXCL makes both one
    /// filesystem operation and also refuses existing symlinks and directories.
    private func renameExclusively(from source: URL, to destination: URL) -> Int32 {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return EINVAL }
                return renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
    }
}
