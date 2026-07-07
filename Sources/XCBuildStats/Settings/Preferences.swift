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

    private let defaults: UserDefaults = .standard

    private enum Keys {
        static let menuBarDisplay: String = "menuBarDisplay"
        static let excludedProjects: String = "excludedProjects"
        static let disableAnimations: String = "disableAnimations"
        static let pulseMenuBar: String = "pulseMenuBar"
    }

    private init() {
        let rawDisplay: String? = defaults.string(forKey: Keys.menuBarDisplay)
        menuBarDisplay = rawDisplay.flatMap(MenuBarDisplay.init(rawValue:)) ?? .todayTotal
        let excluded: [String] = defaults.stringArray(forKey: Keys.excludedProjects) ?? []
        excludedProjects = Set(excluded)
        disableAnimations = defaults.bool(forKey: Keys.disableAnimations)
        pulseMenuBar = defaults.bool(forKey: Keys.pulseMenuBar)
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
