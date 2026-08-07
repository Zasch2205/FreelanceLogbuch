import Foundation

enum AssignmentType: String, CaseIterable, Codable, Identifiable {
    case grafik = "Grafik"
    case schnitt = "Schnitt"
    case sonstiges = "Sonstiges"

    var id: String { rawValue }
}
