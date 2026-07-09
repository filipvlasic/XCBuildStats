import AppKit

enum InstallerCleanup {
    private static let flagKey: String = "didOfferInstallerCleanup"

    /// On first launch after install, offers to eject the mounted installer and
    /// move its .dmg to the Trash. Shown at most once, and only when an installer
    /// disk image is actually mounted.
    static func offerIfNeeded() {
        // Only meaningful once the app runs from a real location. When launched from
        // the mounted DMG (directly, or via Gatekeeper's App Translocation copy),
        // offering to eject/trash the installer would pull the app out from under
        // itself — and consume the one-shot flag before the real install.
        guard !AppLocation.isEphemeral else {
            return
        }
        let defaults: UserDefaults = .standard
        guard !defaults.bool(forKey: flagKey) else {
            return
        }
        guard let installer = mountedInstaller() else {
            return
        }
        defaults.set(true, forKey: flagKey)

        let alert: NSAlert = NSAlert()
        alert.messageText = "Move the XCBuildStats installer to the Trash?"
        alert.informativeText = "XCBuildStats is installed. The disk image will be ejected and “\(installer.dmg.lastPathComponent)” moved to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        eject(mountPoint: installer.mountPoint)
        try? FileManager.default.trashItem(at: installer.dmg, resultingItemURL: nil)
    }

    private static func mountedInstaller() -> (dmg: URL, mountPoint: String)? {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            return nil
        }
        for image in images {
            guard let path = image["image-path"] as? String else {
                continue
            }
            let name: String = (path as NSString).lastPathComponent
            guard name.hasPrefix("XCBuildStats"), name.hasSuffix(".dmg") else {
                continue
            }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            guard let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                continue
            }
            return (URL(fileURLWithPath: path), mountPoint)
        }
        return nil
    }

    private static func eject(mountPoint: String) {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint]
        try? process.run()
        process.waitUntilExit()
    }
}
