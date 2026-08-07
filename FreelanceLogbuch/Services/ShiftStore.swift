import Foundation

final class ShiftStore {
    private(set) var shifts: [Shift] = []

    func startShift(locationName: String?, assignmentType: AssignmentType, at date: Date = Date(), createdBy: Shift.CreatedBy) {
        guard shifts.contains(where: { $0.status == .open }) == false else { return }

        let newShift = Shift(
            id: UUID(),
            locationName: locationName,
            startAt: date,
            endAt: nil,
            status: .open,
            createdBy: createdBy,
            assignmentType: assignmentType,
            note: nil
        )
        shifts.append(newShift)
    }

    func endOpenShift(at date: Date = Date()) {
        guard let index = shifts.firstIndex(where: { $0.status == .open }) else { return }
        shifts[index].endAt = date
        shifts[index].status = .closed
    }
}
