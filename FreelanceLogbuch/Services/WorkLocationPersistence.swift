import Foundation

enum WorkLocationPersistence {
    private static let key = "workLocationsJSON"

    static func load() -> [WorkLocation] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let locations = try? JSONDecoder().decode([WorkLocation].self, from: data)
        else {
            return []
        }
        return locations
    }

    static func save(_ locations: [WorkLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
