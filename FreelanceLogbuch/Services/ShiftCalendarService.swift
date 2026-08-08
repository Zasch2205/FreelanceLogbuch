import EventKit
import Foundation

protocol ShiftCalendarSyncing {
    func addShiftToCalendar(_ shift: Shift) async throws
}

enum ShiftCalendarError: Error {
    case missingEndTime
    case permissionDenied
    case calendarUnavailable
}

final class ShiftCalendarService: ShiftCalendarSyncing {
    private let eventStore = EKEventStore()

    func addShiftToCalendar(_ shift: Shift) async throws {
        guard let endAt = shift.endAt else {
            throw ShiftCalendarError.missingEndTime
        }

        let granted = try await requestCalendarAccess()
        guard granted else {
            throw ShiftCalendarError.permissionDenied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ShiftCalendarError.calendarUnavailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.startDate = shift.startAt
        event.endDate = endAt
        event.title = calendarTitle(for: shift)
        event.notes = calendarNotes(for: shift)

        try eventStore.save(event, span: .thisEvent)
    }

    private func calendarTitle(for shift: Shift) -> String {
        if let locationName = shift.locationName, locationName.isEmpty == false {
            return "FreelanceLogbuch: \(shift.assignmentType.rawValue) · \(locationName)"
        }
        return "FreelanceLogbuch: \(shift.assignmentType.rawValue)"
    }

    private func calendarNotes(for shift: Shift) -> String {
        var lines: [String] = [
            "Quelle: \(shift.createdBy.rawValue)",
            "Einsatzart: \(shift.assignmentType.rawValue)"
        ]

        if let note = shift.note, note.isEmpty == false {
            lines.append("Notiz: \(note)")
        }

        return lines.joined(separator: "\n")
    }

    private func requestCalendarAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestWriteOnlyAccessToEvents { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }

        return try await requestLegacyCalendarAccess()
    }

    @available(iOS, introduced: 6.0, deprecated: 17.0)
    private func requestLegacyCalendarAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
