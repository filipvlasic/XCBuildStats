import AppKit
import Foundation
import UserNotifications

enum BuildNotifier {
    /// Builds that finished longer ago than this are backfill (app was closed,
    /// Mac was asleep), not "your build just ended" — never notify for them.
    static let freshnessWindow: TimeInterval = 180

    static let thresholdRange: ClosedRange<TimeInterval> = 30...600
    static let thresholdStep: TimeInterval = 30
    static let defaultThreshold: TimeInterval = 120

    /// UNUserNotificationCenter traps outside a real .app bundle (e.g. `swift run`).
    static var isSupported: Bool {
        return Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func requestAuthorization(completion: (() -> Void)? = nil) {
        guard isSupported else {
            completion?()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    static func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard isSupported else {
            completion(.notDetermined)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    static func openNotificationSettings() {
        let bundleId: String = Bundle.main.bundleIdentifier ?? ""
        guard let url: URL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func shouldNotify(_ build: BuildRecord, threshold: TimeInterval, now: Date) -> Bool {
        guard !build.isClean else {
            return false
        }
        guard build.duration >= threshold else {
            return false
        }
        return now.timeIntervalSince(build.stopped) <= freshnessWindow
    }

    static func notify(_ build: BuildRecord) {
        guard isSupported else {
            return
        }
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = build.succeeded ? "Build finished" : "Build failed"
        content.body = "\(build.project) · \(Format.duration(build.duration))"
        content.sound = .default
        let request: UNNotificationRequest = UNNotificationRequest(identifier: build.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func thresholdLabel(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else {
            return "All builds"
        }
        if seconds < 60 {
            return "\(Int(seconds)) sec"
        }
        let minutes: Double = seconds / 60
        if minutes.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(minutes)) min"
        }
        return String(format: "%.1f min", minutes)
    }
}
