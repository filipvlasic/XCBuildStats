import Foundation

struct LogStoreManifest: Decodable {
    let logs: [String: LogRecord]
}

struct LogRecord: Decodable {
    let className: String?
    let domainType: String?
    let title: String?
    let signature: String?
    let uniqueIdentifier: String?
    let fileName: String?
    let timeStartedRecording: Double?
    let timeStoppedRecording: Double?
    let schemeName: String?
    let containerName: String?
    let primaryObservable: PrimaryObservable?

    enum CodingKeys: String, CodingKey {
        case className
        case domainType
        case title
        case signature
        case uniqueIdentifier
        case fileName
        case timeStartedRecording
        case timeStoppedRecording
        case schemeName = "schemeIdentifier-schemeName"
        case containerName = "schemeIdentifier-containerName"
        case primaryObservable
    }
}

struct PrimaryObservable: Decodable {
    let highLevelStatus: String?
    let totalNumberOfErrors: Int?
    let totalNumberOfWarnings: Int?
    let totalNumberOfTestFailures: Int?
    let totalNumberOfAnalyzerIssues: Int?
}
