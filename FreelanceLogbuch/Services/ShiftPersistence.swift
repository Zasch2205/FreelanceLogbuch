import Foundation

extension Notification.Name {
    static let shiftsDidChange = Notification.Name("shiftsDidChange")
    static let shiftConfirmationRequired = Notification.Name("shiftConfirmationRequired")
}

enum ShiftPersistence {
    private static let key = "shiftsJSON"

    static func load() -> [Shift] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let shifts = try? JSONDecoder().decode([Shift].self, from: data)
        else {
            return Shift.sample
        }
        return shifts
    }

    static func save(_ shifts: [Shift]) {
        guard let data = try? JSONEncoder().encode(shifts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
