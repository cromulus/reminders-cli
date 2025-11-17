import Foundation

public struct VersionInfo: Codable {
    public let version: String
    public let gitCommit: String?
    public let buildTimestamp: String

    public static let current: VersionInfo = VersionInfo.detect()

    private static func detect() -> VersionInfo {
        let env = ProcessInfo.processInfo.environment
        let version = env["REMINDERS_VERSION"] ?? env["APP_VERSION"] ?? "dev"
        let gitCommit = env["REMINDERS_GIT_SHA"] ?? env["GIT_COMMIT_SHA"] ?? env["GITHUB_SHA"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        return VersionInfo(version: version, gitCommit: gitCommit, buildTimestamp: timestamp)
    }
}
