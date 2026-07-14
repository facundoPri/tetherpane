import Foundation

public enum DeveloperToolPathResolver {
    public static func adbPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        resolve(
            override: environment["ADB_PATH"],
            knownPaths: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"],
            path: environment["PATH"],
            executableName: "adb"
        )
    }

    public static func scrcpyPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        resolve(
            override: environment["SCRCPY_PATH"],
            knownPaths: ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"],
            path: environment["PATH"],
            executableName: "scrcpy"
        )
    }

    private static func resolve(
        override: String?,
        knownPaths: [String],
        path: String?,
        executableName: String
    ) -> String? {
        let candidates = [override]
            .compactMap { $0 }
            + knownPaths
            + (path ?? "").split(separator: ":").map { "\($0)/\(executableName)" }

        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
