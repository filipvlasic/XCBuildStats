import Foundation

/// Who ran the build: the Xcode app itself, or `xcodebuild` on the command line
/// (AI agents such as Claude Code, scripts, Terminal).
enum BuildSource: String, CaseIterable {
    case xcode
    case cli

    /// The log-store class Xcode writes for builds started by `xcodebuild`.
    static let commandLineLogClassName: String = "IDECommandLineBuildLog"

    static func from(className: String?, title: String?) -> BuildSource {
        if let className {
            return className == commandLineLogClassName ? .cli : .xcode
        }
        return inferred(fromTitle: title)
    }

    /// Xcode titles its own builds imperatively ("Build MyApp", "Clean MyApp"),
    /// while `xcodebuild` uses "Building project MyApp with scheme …",
    /// "Testing workspace MyApp with scheme …" — enough to classify rows stored
    /// before the source was recorded.
    static func inferred(fromTitle title: String?) -> BuildSource {
        guard let title,
              title.range(of: "^[A-Z][a-z]+ing (project|workspace) ", options: .regularExpression) != nil else {
            return .xcode
        }
        return .cli
    }
}

struct BuildRecord: Identifiable, Hashable {
    let id: String
    let project: String
    let scheme: String?
    let title: String?
    let started: Date
    let stopped: Date
    let succeeded: Bool
    let errors: Int
    let warnings: Int
    let status: String?
    var source: BuildSource = .xcode

    var duration: TimeInterval {
        return stopped.timeIntervalSince(started)
    }

    var isClean: Bool {
        guard let title else {
            return false
        }
        return title.hasPrefix("Clean ") || title.hasPrefix("Cleaning ")
    }
}

enum BuildEventType {
    static let derivedDataDeleted: String = "derived_data_deleted"
}

struct BuildEvent: Identifiable, Hashable {
    let id: String
    let type: String
    let project: String?
    let timestamp: Date
}
