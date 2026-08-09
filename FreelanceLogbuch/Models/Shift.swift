import Foundation

struct Shift: Identifiable, Codable, Equatable {
    let id: UUID
    var locationName: String?
    var startAt: Date
    var endAt: Date?
    var status: Status
    var createdBy: CreatedBy
    var assignmentType: AssignmentType
    var note: String?

    enum Status: String, Codable {
        case open
        case closed
        case cancelled
    }

    enum CreatedBy: String, Codable {
        case geofence
        case manual
    }
}

extension Shift {
    var title: String {
        assignmentType.rawValue + (locationName.map { " · \($0)" } ?? "")
    }

    var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let endAt {
            return "\(formatter.string(from: startAt)) – \(formatter.string(from: endAt))"
        }
        return "Start: \(formatter.string(from: startAt))"
    }

    static var sample: [Shift] {
        [
            Shift(
                id: UUID(),
                locationName: "Studio Berlin",
                startAt: Date().addingTimeInterval(-5_400),
                endAt: Date().addingTimeInterval(-1_800),
                status: .closed,
                createdBy: .geofence,
                assignmentType: .grafik,
                note: "Key Visuals"
            ),
            Shift(
                id: UUID(),
                locationName: "Remote",
                startAt: Date().addingTimeInterval(-900),
                endAt: nil,
                status: .open,
                createdBy: .manual,
                assignmentType: .schnitt,
                note: nil
            )
        ]
    }
}
