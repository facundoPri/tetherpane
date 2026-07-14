import Foundation

enum RecordingDestination {
    static func nextURL() throws -> URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        let recordingsDirectory = moviesDirectory.appending(path: "AirDroid")
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory.appending(path: "AirDroid-\(timestamp).mp4")
    }
}
