import Foundation

/// Configuration for tkal
///
/// Uses JSON format stored in ~/.config/tkal/config.json (or $XDG_CONFIG_HOME/tkal/config.json)
struct Config: Codable {
    var enabledCalendars: [String]
    var use24HourTime: Bool

    private static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Use XDG_CONFIG_HOME if set, otherwise use ~/.config
        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdgConfigHome).appendingPathComponent("tkal")
        } else {
            return home.appendingPathComponent(".config/tkal")
        }
    }

    private static var configFile: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    static func load() -> Config? {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: configFile)
            let decoder = JSONDecoder()
            return try decoder.decode(Config.self, from: data)
        } catch {
            print("Error loading config: \(error.localizedDescription)")
            return nil
        }
    }

    func save() {
        do {
            // Create config directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: Config.configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: Config.configFile)
        } catch {
            print("Error saving config: \(error.localizedDescription)")
        }
    }
}
