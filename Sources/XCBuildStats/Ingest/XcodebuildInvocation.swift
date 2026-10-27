import Foundation

/// An `xcodebuild` command line, as read from a running process.
struct XcodebuildInvocation: Equatable {
    /// argv without the executable.
    let arguments: [String]
    let workingDirectory: String?

    struct Container: Equatable {
        enum Kind: String {
            case workspace
            case project
            case package
        }

        let path: String
        let kind: Kind

        var name: String {
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
    }

    private static let buildActions: Set<String> = [
        "build", "build-for-testing", "test", "archive", "analyze", "clean", "docbuild", "install"
    ]

    private static let otherActions: Set<String> = ["test-without-building", "installsrc"]

    /// Flags that make xcodebuild query or export something instead of building
    /// (IDEs and language servers run `-showBuildSettings` constantly).
    private static let utilityFlags: Set<String> = [
        "-version", "-list", "-showsdks", "-showBuildSettings", "-showBuildSettingsForIndex",
        "-showdestinations", "-showTestPlans", "-resolvePackageDependencies", "-exportArchive",
        "-exportLocalizations", "-importLocalizations", "-exportNotarizedApp", "-create-xcframework",
        "-checkFirstLaunchStatus", "-runFirstLaunch", "-downloadPlatform", "-downloadAllPlatforms",
        "-downloadComponent", "-importPlatform", "-importComponent", "-license", "-usage", "-help",
        "-find", "-find-executable", "-find-library", "-showComponent"
    ]

    /// Options that take no value, so a word right after one is an action rather
    /// than the option's argument (`-quiet build` vs `-scheme build`).
    private static let switches: Set<String> = [
        "-quiet", "-verbose", "-json", "-alltargets", "-allowProvisioningUpdates",
        "-allowProvisioningDeviceRegistration", "-skipPackagePluginValidation", "-skipMacroValidation",
        "-skipPackageUpdates", "-skipPackageSignatureValidation", "-disableAutomaticPackageResolution",
        "-onlyUsePackageVersionsFromResolvedFile", "-disablePackageRepositoryCache", "-parallelizeTargets",
        "-showBuildTimingSummary", "-hideShellScriptEnvironment", "-skipUnavailableActions",
        "-dry-run", "-n"
    ]

    var actions: [String] {
        var result: [String] = []
        for (index, argument) in arguments.enumerated()
        where Self.buildActions.contains(argument) || Self.otherActions.contains(argument) {
            if index > 0 {
                let previous: String = arguments[index - 1]
                if previous.hasPrefix("-"), !Self.switches.contains(previous) {
                    continue
                }
            }
            result.append(argument)
        }
        return result
    }

    /// True when the run compiles something; xcodebuild's default action is build.
    var isBuild: Bool {
        if arguments.contains(where: { Self.utilityFlags.contains($0) }) {
            return false
        }
        let actions: [String] = self.actions
        return actions.isEmpty || actions.contains { Self.buildActions.contains($0) }
    }

    var scheme: String? {
        return value(of: "-scheme")
    }

    var derivedDataPath: String? {
        return value(of: "-derivedDataPath").map(absolute)
    }

    /// The workspace, project or package being built. Without `-workspace` /
    /// `-project`, xcodebuild picks from the working directory, so that is listed
    /// — `list` returns nil where that is not allowed.
    func container(list: (String) -> [String]?) -> Container? {
        if let workspace: String = value(of: "-workspace") {
            return Container(path: absolute(workspace), kind: .workspace)
        }
        if let project: String = value(of: "-project") {
            return Container(path: absolute(project), kind: .project)
        }
        guard let workingDirectory, let entries: [String] = list(workingDirectory) else {
            return nil
        }
        let workspaces: [String] = entries.filter { $0.hasSuffix(".xcworkspace") }
        if workspaces.count == 1 {
            return Container(path: absolute(workspaces[0]), kind: .workspace)
        }
        let projects: [String] = entries.filter { $0.hasSuffix(".xcodeproj") }
        if projects.count == 1 {
            return Container(path: absolute(projects[0]), kind: .project)
        }
        if entries.contains("Package.swift") {
            return Container(path: Self.normalized(workingDirectory), kind: .package)
        }
        return nil
    }

    /// Named like Xcode's DerivedData folders (the workspace or project name), so
    /// command-line and Xcode builds of one project group together.
    func projectName(container: Container?) -> String {
        if let container {
            return container.name
        }
        if let scheme {
            return scheme
        }
        if let workingDirectory {
            return (workingDirectory as NSString).lastPathComponent
        }
        return "Unknown"
    }

    /// Mirrors the titles xcodebuild gives its own log entries
    /// ("Building workspace MyApp with scheme MyApp").
    func title(container: Container?, project: String) -> String {
        let actions: [String] = self.actions
        let primary: String = actions.last { $0 != "clean" } ?? (actions.isEmpty ? "build" : "clean")
        let verb: String
        switch primary {
        case "test":
            verb = "Testing"
        case "archive":
            verb = "Archiving"
        case "analyze":
            verb = "Analyzing"
        case "clean":
            verb = "Cleaning"
        default:
            verb = "Building"
        }
        var title: String = "\(verb) \(container?.kind.rawValue ?? "project") \(project)"
        if let scheme {
            title += " with scheme \(scheme)"
        }
        return title
    }

    private func value(of option: String) -> String? {
        guard let index: Int = arguments.firstIndex(of: option), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private func absolute(_ path: String) -> String {
        guard !path.hasPrefix("/"), let workingDirectory else {
            return Self.normalized(path)
        }
        return Self.normalized((workingDirectory as NSString).appendingPathComponent(path))
    }

    /// Standardized, with the `/private` firmlink prefix dropped so `/tmp/x` and
    /// `/private/tmp/x` compare equal without touching the file system.
    static func normalized(_ path: String) -> String {
        var result: String = (path as NSString).standardizingPath
        for root in ["/private/tmp", "/private/var", "/private/etc"] where result == root || result.hasPrefix(root + "/") {
            result.removeFirst("/private".count)
        }
        if result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

enum ProcessExit: Equatable {
    case exited(Int32)
    case signaled(Int32)

    /// Decodes a `wait(2)` status.
    init(waitStatus: Int32) {
        let signal: Int32 = waitStatus & 0x7f
        if signal == 0 {
            self = .exited((waitStatus >> 8) & 0xff)
        } else {
            self = .signaled(signal)
        }
    }
}

/// One finished `xcodebuild` process.
struct XcodebuildRun {
    let pid: pid_t
    let invocation: XcodebuildInvocation
    let started: Date
    let stopped: Date
    let exit: ProcessExit

    /// xcodebuild writes its log entry with a short lag after starting and
    /// finishes it just before exiting.
    private static let logTolerance: TimeInterval = 2

    /// What to store for this run. xcodebuild writes build-log entries only for
    /// `test` and when given `-resultBundlePath`; those carry error counts and
    /// split clean from build, so they replace the process timing when present.
    func buildRecords(
        derivedDataRoot: URL = ManifestScanner.derivedDataURL,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        list: (String) -> [String]? = Self.listUngated
    ) -> [BuildRecord] {
        let container: XcodebuildInvocation.Container? = invocation.container { directory in
            guard !AppLocation.isConsentGated(path: directory, home: home) else {
                return nil
            }
            return list(directory)
        }
        let project: String = invocation.projectName(container: container)
        let logged: [BuildRecord] = loggedRecords(container: container, project: project, derivedDataRoot: derivedDataRoot, home: home)
        if !logged.isEmpty {
            return logged
        }
        let succeeded: Bool = exit == .exited(0)
        let status: String
        switch exit {
        case .exited(0):
            status = "S"
        case .exited:
            status = "E"
        case .signaled:
            // Killed or interrupted (an agent's command timeout, Ctrl-C).
            status = "C"
        }
        let record: BuildRecord = BuildRecord(
            id: "xcodebuild|\(pid)|\(Int(started.timeIntervalSince1970 * 1000))",
            project: project,
            scheme: invocation.scheme,
            title: invocation.title(container: container, project: project),
            started: started,
            stopped: max(started, stopped),
            succeeded: succeeded,
            errors: 0,
            warnings: 0,
            status: status,
            source: .cli
        )
        return [record]
    }

    static func listUngated(_ directory: String) -> [String]? {
        return try? FileManager.default.contentsOfDirectory(atPath: directory)
    }

    private func loggedRecords(
        container: XcodebuildInvocation.Container?,
        project: String,
        derivedDataRoot: URL,
        home: String
    ) -> [BuildRecord] {
        var manifests: [(url: URL, project: String)] = []
        if let derivedData: String = invocation.derivedDataPath {
            guard !AppLocation.isConsentGated(path: derivedData, home: home) else {
                return []
            }
            let url: URL = URL(fileURLWithPath: derivedData, isDirectory: true)
                .appendingPathComponent("Logs/Build/LogStoreManifest.plist")
            manifests = [(url, project)]
        } else {
            manifests = ManifestScanner.manifestURLs(in: derivedDataRoot)
                .filter { url in
                    let folder: URL = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    return ownsDerivedData(workspacePath: ManifestScanner.workspacePath(ofDerivedDataFolder: folder), container: container)
                }
                .map { ($0, ManifestScanner.projectName(from: $0)) }
        }
        let from: Date = started.addingTimeInterval(-Self.logTolerance)
        let to: Date = stopped.addingTimeInterval(Self.logTolerance)
        return manifests
            .flatMap { ManifestScanner.records(inManifestAt: $0.url, project: $0.project) }
            .filter { $0.source == .cli && $0.started >= from && $0.stopped <= to }
    }

    /// Xcode names a default DerivedData folder after the workspace and records
    /// the workspace's path in its info.plist; matching that path (not just the
    /// name) keeps parallel builds of the same project in different worktrees apart.
    private func ownsDerivedData(workspacePath: String?, container: XcodebuildInvocation.Container?) -> Bool {
        guard let workspacePath else {
            return false
        }
        let path: String = XcodebuildInvocation.normalized(workspacePath)
        if let container {
            return path == container.path || (path as NSString).deletingLastPathComponent == container.path
        }
        guard let workingDirectory: String = invocation.workingDirectory else {
            return false
        }
        let directory: String = XcodebuildInvocation.normalized(workingDirectory)
        return path == directory || (path as NSString).deletingLastPathComponent == directory
    }
}
