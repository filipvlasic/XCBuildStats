import Foundation
import Observation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case todayTotal = "Today's total"
    case currentPeriod = "Selected period"

    var id: String {
        return rawValue
    }
}

@Observable
final class Preferences {
    static let shared: Preferences = Preferences()

    var menuBarDisplay: MenuBarDisplay {
        didSet {
            defaults.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay)
        }
    }

    var sourceFilter: SourceFilter {
        didSet {
            defaults.set(sourceFilter.rawValue, forKey: Keys.sourceFilter)
        }
    }

    var trackCommandLineBuilds: Bool {
        didSet {
            defaults.set(trackCommandLineBuilds, forKey: Keys.trackCommandLineBuilds)
        }
    }

    var excludedProjects: Set<String> {
        didSet {
            defaults.set(Array(excludedProjects), forKey: Keys.excludedProjects)
        }
    }

    var disableAnimations: Bool {
        didSet {
            defaults.set(disableAnimations, forKey: Keys.disableAnimations)
        }
    }

    var pulseMenuBar: Bool {
        didSet {
            defaults.set(pulseMenuBar, forKey: Keys.pulseMenuBar)
        }
    }

    var notifyOnBuildEnd: Bool {
        didSet {
            defaults.set(notifyOnBuildEnd, forKey: Keys.notifyOnBuildEnd)
        }
    }

    var notifyAllBuilds: Bool {
        didSet {
            defaults.set(notifyAllBuilds, forKey: Keys.notifyAllBuilds)
        }
    }

    var notifyMinimumDuration: TimeInterval {
        didSet {
            defaults.set(notifyMinimumDuration, forKey: Keys.notifyMinimumDuration)
        }
    }

    var effectiveNotifyThreshold: TimeInterval {
        return notifyAllBuilds ? 0 : notifyMinimumDuration
    }

    private let defaults: UserDefaults = .standard

    private enum Keys {
        static let menuBarDisplay: String = "menuBarDisplay"
        static let sourceFilter: String = "sourceFilter"
        static let trackCommandLineBuilds: String = "trackCommandLineBuilds"
        static let excludedProjects: String = "excludedProjects"
        static let disableAnimations: String = "disableAnimations"
        static let pulseMenuBar: String = "pulseMenuBar"
        static let notifyOnBuildEnd: String = "notifyOnBuildEnd"
        static let notifyAllBuilds: String = "notifyAllBuilds"
        static let notifyMinimumDuration: String = "notifyMinimumDuration"
    }

    private init() {
        let rawDisplay: String? = defaults.string(forKey: Keys.menuBarDisplay)
        menuBarDisplay = rawDisplay.flatMap(MenuBarDisplay.init(rawValue:)) ?? .todayTotal
        sourceFilter = defaults.string(forKey: Keys.sourceFilter).flatMap(SourceFilter.init(rawValue:)) ?? .all
        trackCommandLineBuilds = defaults.object(forKey: Keys.trackCommandLineBuilds) as? Bool ?? true
        let excluded: [String] = defaults.stringArray(forKey: Keys.excludedProjects) ?? []
        excludedProjects = Set(excluded)
        disableAnimations = defaults.bool(forKey: Keys.disableAnimations)
        pulseMenuBar = defaults.bool(forKey: Keys.pulseMenuBar)
        notifyOnBuildEnd = defaults.bool(forKey: Keys.notifyOnBuildEnd)
        let storedDuration: Double = defaults.object(forKey: Keys.notifyMinimumDuration) as? Double ?? BuildNotifier.defaultThreshold
        if storedDuration == 0 {
            // Stored by the earlier picker UI where 0 meant "All builds".
            notifyAllBuilds = true
            notifyMinimumDuration = BuildNotifier.defaultThreshold
            defaults.set(true, forKey: Keys.notifyAllBuilds)
            defaults.set(BuildNotifier.defaultThreshold, forKey: Keys.notifyMinimumDuration)
        } else {
            notifyAllBuilds = defaults.bool(forKey: Keys.notifyAllBuilds)
            notifyMinimumDuration = storedDuration
        }
    }

    func isExcluded(_ project: String) -> Bool {
        return excludedProjects.contains(project)
    }

    func setExcluded(_ project: String, _ excluded: Bool) {
        if excluded {
            excludedProjects.insert(project)
        } else {
            excludedProjects.remove(project)
        }
    }
}
