import Foundation

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

    var duration: TimeInterval {
        return stopped.timeIntervalSince(started)
    }

    var isClean: Bool {
        return title?.hasPrefix("Clean ") ?? false
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
