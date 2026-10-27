import Foundation
import AppKit
import UniformTypeIdentifiers

enum Exporter {
    static func exportCSV(builds: [BuildRecord]) {
        let panel: NSSavePanel = NSSavePanel()
        panel.nameFieldStringValue = "xcbuildstats.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url: URL = panel.url else {
                return
            }
            let csv: String = makeCSV(builds)
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }

    static func makeCSV(_ builds: [BuildRecord]) -> String {
        var lines: [String] = ["project,scheme,title,started,stopped,duration_seconds,succeeded,errors,warnings,status,is_clean,source"]
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        for build in builds {
            let fields: [String] = [
                build.project,
                build.scheme ?? "",
                build.title ?? "",
                formatter.string(from: build.started),
                formatter.string(from: build.stopped),
                String(Int(build.duration.rounded())),
                build.succeeded ? "1" : "0",
                String(build.errors),
                String(build.warnings),
                build.status ?? "",
                build.isClean ? "1" : "0",
                build.source.rawValue
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
