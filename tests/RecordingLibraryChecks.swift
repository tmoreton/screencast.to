import Dispatch
import Foundation

/// Use real files, without opening Finder or requesting screen permissions.
@main
nonisolated struct RecordingLibraryChecks {
    private struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckFailure(description: message) }
    }

    private static func requireFailure(_ message: String, operation: () throws -> Void) throws {
        do { try operation() }
        catch { return }
        throw CheckFailure(description: message)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("screencast-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try checkLocations()
        try checkSaving(in: root.appendingPathComponent("saving", isDirectory: true))
        try checkOccupiedNames(in: root.appendingPathComponent("occupied", isDirectory: true))
        try checkSaveFailure(in: root.appendingPathComponent("failure", isDirectory: true))
        try checkDiscovery(in: root.appendingPathComponent("discovery", isDirectory: true))
        try checkConcurrentSaves(in: root.appendingPathComponent("concurrent", isDirectory: true))
        print("Recording library checks passed: durable locations, unique saves, failure preservation, restart discovery, and concurrent collisions.")
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private static func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private static func checkLocations() throws {
        let movies = try RecordingLibrary.moviesDirectory()
        let recovery = try RecordingLibrary.recoveryDirectory()
        try require(movies.isFileURL && movies.lastPathComponent == "Screencast", "Movies location must be a local Screencast folder.")
        try require(movies.deletingLastPathComponent() == FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first,
                    "Movies must use the platform directory rather than a hard-coded home path.")
        try require(recovery.lastPathComponent == "Recovered Recordings"
                    && recovery.deletingLastPathComponent().lastPathComponent == "Screencast",
                    "Recovery must use a dedicated durable application-support folder.")
        try require(recovery.deletingLastPathComponent().deletingLastPathComponent()
                    == FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                    "Recovery must stay outside automatically purged temporary storage.")
    }

    private static func checkOccupiedNames(in root: URL) throws {
        let library = RecordingLibrary(directory: root.appendingPathComponent("library", isDirectory: true))
        let source = root.appendingPathComponent("capture/Occupied.mov")
        let folder = library.directory.appendingPathComponent("Occupied.mov", isDirectory: true)
        try write("nested content", to: folder.appendingPathComponent("keep.txt"))
        let target = root.appendingPathComponent("target.mov")
        try write("linked target", to: target)
        let link = library.directory.appendingPathComponent("Occupied (2).mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let existing = library.directory.appendingPathComponent("Occupied (3).mov")
        try write("existing recording", to: existing)
        try write("new recording", to: source)
        let saved = try library.save(source)
        try require(saved.lastPathComponent == "Occupied (4).mov", "Occupied directories, symlinks, and files must all get distinct save names.")
        try require(try contents(of: folder.appendingPathComponent("keep.txt")) == "nested content", "An existing folder must remain intact.")
        try require(try contents(of: target) == "linked target" && contents(of: existing) == "existing recording",
                    "Saving must not replace a symlink target or an existing movie.")
    }

    private static func checkSaving(in root: URL) throws {
        let directory = root.appendingPathComponent("Movies/Screencast", isDirectory: true)
        let library = RecordingLibrary(directory: directory)
        let title = "Screencast 2026-11-09 at 1.02.03 PM"
        let first = root.appendingPathComponent("capture/\(title)-\(UUID().uuidString).mov")
        try write("first movie", to: first)
        let savedFirst = try library.save(first)
        try require(savedFirst.lastPathComponent == "\(title).mov", "Only the generated UUID should be removed from a recording name.")
        try require(!FileManager.default.fileExists(atPath: first.path), "A successful save must move the capture out of temporary storage.")
        try require(try contents(of: savedFirst) == "first movie", "Saving must preserve movie bytes.")

        let second = root.appendingPathComponent("capture/\(title)-\(UUID().uuidString).mov")
        try write("second movie", to: second)
        let savedSecond = try library.save(second)
        try require(savedSecond.lastPathComponent == "\(title) (2).mov", "A filename collision must get a numeric suffix.")
        try require(try contents(of: savedFirst) == "first movie", "Saving a later recording must not replace the first recording.")
        try require(try contents(of: savedSecond) == "second movie", "Each collision must retain its own recording bytes.")

        let unusualName = "Meeting notes-not-a-valid-0000-0000-000000000000.MOV"
        let unusual = root.appendingPathComponent("capture/\(unusualName)")
        try write("unusual", to: unusual)
        let savedUnusual = try library.save(unusual)
        try require(savedUnusual.lastPathComponent == "Meeting notes-not-a-valid-0000-0000-000000000000.mov",
                    "Malformed UUID-like suffixes must remain intact, with the normal movie extension.")

        let unseparated = "Notes\(UUID().uuidString)"
        let unseparatedSource = root.appendingPathComponent("capture/\(unseparated).mov")
        try write("unseparated", to: unseparatedSource)
        let savedUnseparated = try library.save(unseparatedSource)
        try require(savedUnseparated.deletingPathExtension().lastPathComponent == unseparated,
                    "A UUID without the generated separator must not be removed.")
    }

    private static func checkSaveFailure(in root: URL) throws {
        let source = root.appendingPathComponent("capture/finished.mov")
        let blocked = root.appendingPathComponent("not-a-folder")
        try write("irreplaceable recording", to: source)
        try write("existing file", to: blocked)
        try requireFailure("Saving into an existing regular file should fail.") {
            _ = try RecordingLibrary(directory: blocked).save(source)
        }
        try require(try contents(of: source) == "irreplaceable recording", "A failed save must retain the completed capture.")
        try require(try contents(of: blocked) == "existing file", "A failed save must not replace a non-directory destination.")

        let link = root.appendingPathComponent("capture/linked.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        try requireFailure("A symbolic-link capture must not be treated as a regular movie.") {
            _ = try RecordingLibrary(directory: root.appendingPathComponent("library")).save(link)
        }
        try require(try contents(of: source) == "irreplaceable recording", "Rejecting a linked input must preserve its target.")

        let fullLibrary = RecordingLibrary(directory: root.appendingPathComponent("full", isDirectory: true))
        for index in 1...1_000 {
            let name = index == 1 ? "finished.mov" : "finished (\(index)).mov"
            try write("existing \(index)", to: fullLibrary.directory.appendingPathComponent(name))
        }
        try requireFailure("Collision retries must eventually stop without overwriting a movie.") {
            _ = try fullLibrary.save(source)
        }
        try require(try contents(of: source) == "irreplaceable recording", "Exhausting collision retries must preserve the source recording.")
        try require(try contents(of: fullLibrary.directory.appendingPathComponent("finished.mov")) == "existing 1"
                    && contents(of: fullLibrary.directory.appendingPathComponent("finished (1000).mov")) == "existing 1000",
                    "Exhausting collision retries must preserve existing recordings.")
    }

    private static func checkDiscovery(in root: URL) throws {
        let library = RecordingLibrary(directory: root.appendingPathComponent("library", isDirectory: true))
        let initiallyMissing = try library.recentRecordings(limit: 20)
        try require(initiallyMissing.isEmpty && !FileManager.default.fileExists(atPath: library.directory.path),
                    "Inspecting an empty library must not create its directory.")
        try library.prepareDirectory()
        try require(try library.recentRecordings(limit: 20).isEmpty, "An empty folder must have no recordings.")

        let older = library.directory.appendingPathComponent("older.mov")
        let tiedA = library.directory.appendingPathComponent("a.MOV")
        let tiedB = library.directory.appendingPathComponent("b.mov")
        for url in [older, tiedA, tiedB] { try write(url.lastPathComponent, to: url) }
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: earlier], ofItemAtPath: older.path)
        for url in [tiedA, tiedB] {
            try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
        }
        try write("hidden", to: library.directory.appendingPathComponent(".hidden.mov"))
        try write("not a movie", to: library.directory.appendingPathComponent("notes.txt"))
        let nested = library.directory.appendingPathComponent("nested.mov", isDirectory: true)
        try write("nested movie", to: nested.appendingPathComponent("child.mov"))
        try FileManager.default.createSymbolicLink(at: library.directory.appendingPathComponent("linked.mov"), withDestinationURL: tiedA)
        try FileManager.default.createSymbolicLink(at: library.directory.appendingPathComponent("broken.mov"), withDestinationURL: root.appendingPathComponent("missing.mov"))

        // A fresh instance has no in-memory knowledge of prior recordings.
        let afterRestart = RecordingLibrary(directory: library.directory)
        let found = try afterRestart.recentRecordings(limit: 20)
        try require(found.map(\.lastPathComponent) == ["a.MOV", "b.mov", "older.mov"],
                    "Discovery must sort newest first with stable ties, ignoring hidden files, subfolders, other extensions, and symlinks.")
        try require(try afterRestart.recentRecordings(limit: 1).map(\.lastPathComponent) == ["a.MOV"], "Discovery must honor its result limit.")
        try require(try afterRestart.recentRecordings(limit: 0).isEmpty, "A zero limit must return no files.")
        try require(try afterRestart.recentRecordings(limit: -1).isEmpty, "A negative limit must return no files.")
        try FileManager.default.removeItem(at: tiedA)
        try require(try afterRestart.recentRecordings(limit: 20).map(\.lastPathComponent) == ["b.mov", "older.mov"],
                    "A deleted recording must disappear on the next scan.")
    }

    private final class ConcurrentResults: @unchecked Sendable {
        let lock = NSLock()
        var urls: [URL] = []
        var errors: [Error] = []
    }

    private static func checkConcurrentSaves(in root: URL) throws {
        let library = RecordingLibrary(directory: root.appendingPathComponent("library", isDirectory: true))
        try library.prepareDirectory()
        let count = 12
        let sources = try (0..<count).map { index -> URL in
            let url = root.appendingPathComponent("capture-\(index)/same-name.mov")
            try write("movie \(index)", to: url)
            return url
        }
        let results = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: count) { index in
            do {
                let url = try library.save(sources[index])
                results.lock.lock()
                results.urls.append(url)
                results.lock.unlock()
            } catch {
                results.lock.lock()
                results.errors.append(error)
                results.lock.unlock()
            }
        }
        try require(results.errors.isEmpty && results.urls.count == count,
                    "Competing saves must retry filename collisions without losing a recording: \(results.errors).")
        try require(Set(results.urls).count == count, "Every simultaneous recording must get a distinct destination.")
        let savedContents = try Set(results.urls.map { try contents(of: $0) })
        try require(savedContents == Set((0..<count).map { "movie \($0)" }), "Concurrent saves must retain every movie's original bytes.")
    }
}
