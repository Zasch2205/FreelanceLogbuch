import Foundation

final class ShiftStore {
    enum EndTrigger {
        case manual
        case locationExit
    }

    private(set) var shifts: [Shift] = []
    private let calendarService: ShiftCalendarSyncing

    init(calendarService: ShiftCalendarSyncing = ShiftCalendarService()) {
        self.calendarService = calendarService
    }

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

    func endOpenShift(
        at date: Date = Date(),
        trigger: EndTrigger = .manual,
        wasConfirmedByUser: Bool = false
    ) {
        guard let index = shifts.firstIndex(where: { $0.status == .open }) else { return }

        shifts[index].endAt = date
        shifts[index].status = .closed

        let shouldSyncToCalendar = trigger == .locationExit && wasConfirmedByUser
        guard shouldSyncToCalendar else { return }

        let closedShift = shifts[index]
        Task {
            try? await calendarService.addShiftToCalendar(closedShift)
        }
    }
}
