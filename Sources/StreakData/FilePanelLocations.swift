import Foundation

public struct FilePanelLocations {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var openDirectory: URL {
        get {
            defaults.url(forKey: "lastOpenDirectory")
                .map { URL(fileURLWithPath: $0.path, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        nonmutating set {
            defaults.set(newValue, forKey: "lastOpenDirectory")
        }
    }

    public var saveDirectory: URL? {
        get {
            defaults.url(forKey: "lastSaveDirectory")
                .map { URL(fileURLWithPath: $0.path, isDirectory: true) }
        }
        nonmutating set {
            defaults.set(newValue, forKey: "lastSaveDirectory")
        }
    }
}
