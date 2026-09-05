import EventKit
import Foundation

protocol ShiftCalendarSyncing {
    func addShiftToCalendar(_ shift: Shift) async throws
    func upsertShiftInCalendar(_ shift: Shift) async throws
    func cleanupDuplicateShiftEvents(for shifts: [Shift]) async throws -> Int
}

enum ShiftCalendarError: Error {
    case missingEndTime
    case permissionDenied
    case calendarUnavailable
}

final class ShiftCalendarService: ShiftCalendarSyncing {
    private let eventStore = EKEventStore()
    private static let shiftIdentifierPrefix = "FreelanceLogbuch-Shift-ID:"
    private static let shiftEventMapKey = "ShiftCalendarService.shiftEventMap"

    func addShiftToCalendar(_ shift: Shift) async throws {
        try await upsertShiftInCalendar(shift)
    }

    func upsertShiftInCalendar(_ shift: Shift) async throws {
        let latestShift = latestPersistedShiftVersion(for: shift)

        guard let endAt = latestShift.endAt else {
            throw ShiftCalendarError.missingEndTime
        }

        let granted = try await requestCalendarAccess()
        guard granted else {
            throw ShiftCalendarError.permissionDenied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ShiftCalendarError.calendarUnavailable
        }

        let event = existingEvent(for: latestShift, calendar: calendar) ?? EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.startDate = latestShift.startAt
        event.endDate = endAt
        event.title = calendarTitle(for: latestShift)
        event.notes = calendarNotes(for: latestShift)

        try eventStore.save(event, span: .thisEvent)
        storeEventIdentifier(event.eventIdentifier, for: latestShift.id)
    }

    func cleanupDuplicateShiftEvents(for shifts: [Shift]) async throws -> Int {
        let granted = try await requestCalendarAccess()
        guard granted else {
            throw ShiftCalendarError.permissionDenied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ShiftCalendarError.calendarUnavailable
        }

        var deletedCount = 0

        for shift in shifts where shift.endAt != nil {
            let candidates = candidateEvents(for: shift, calendar: calendar)
            guard candidates.count > 1 else { continue }

            guard let primary = primaryEvent(from: candidates, for: shift) else { continue }
            storeEventIdentifier(primary.eventIdentifier, for: shift.id)

            for event in candidates where event.eventIdentifier != primary.eventIdentifier {
                if shouldDeleteAsDuplicate(event: event, primary: primary, shift: shift) {
                    try? eventStore.remove(event, span: .thisEvent, commit: false)
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            try eventStore.commit()
        }

        return deletedCount
    }

    private func calendarTitle(for shift: Shift) -> String {
        "Schicht: \(shift.assignmentType.rawValue)"
    }

    private func calendarNotes(for shift: Shift) -> String {
        var lines: [String] = [
            shiftIdentifierLine(for: shift),
            "Quelle: \(shift.createdBy.rawValue)",
            "Einsatzart: \(shift.assignmentType.rawValue)"
        ]

        if let locationName = shift.locationName, locationName.isEmpty == false {
            lines.append("Arbeitsort: \(locationName)")
        }

        if let note = shift.note, note.isEmpty == false {
            lines.append("Notiz: \(note)")
        }

        return lines.joined(separator: "\n")
    }

    private func shiftIdentifierLine(for shift: Shift) -> String {
        "\(Self.shiftIdentifierPrefix) \(shift.id.uuidString)"
    }

    private func existingEvent(for shift: Shift, calendar: EKCalendar) -> EKEvent? {
        if let mappedEvent = mappedEvent(for: shift.id, calendar: calendar) {
            return mappedEvent
        }

        let candidates = candidateEvents(for: shift, calendar: calendar)
        return primaryEvent(from: candidates, for: shift)
    }

    private func candidateEvents(for shift: Shift, calendar: EKCalendar) -> [EKEvent] {
        guard let endAt = shift.endAt else { return [] }

        let searchStart = shift.startAt.addingTimeInterval(-24 * 60 * 60)
        let searchEnd = endAt.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)
        let matchingTitles = legacyCompatibleTitles(for: shift)
        return events.filter { matchingTitles.contains($0.title) }
    }

    private func primaryEvent(from candidates: [EKEvent], for shift: Shift) -> EKEvent? {
        let identifierLine = shiftIdentifierLine(for: shift)
        if let idMatch = candidates.first(where: { $0.notes?.contains(identifierLine) == true }) {
            return idMatch
        }

        if let sameDayBest = bestSameDayCandidate(from: candidates, for: shift.startAt) {
            return sameDayBest
        }

        return candidates.min {
            abs($0.startDate.timeIntervalSince(shift.startAt)) < abs($1.startDate.timeIntervalSince(shift.startAt))
        }
    }

    private func shouldDeleteAsDuplicate(event: EKEvent, primary: EKEvent, shift: Shift) -> Bool {
        if let taggedShiftId = taggedShiftIdentifier(in: event.notes), taggedShiftId != shift.id.uuidString {
            return false
        }

        return intervalsOverlap(
            startA: event.startDate,
            endA: event.endDate,
            startB: primary.startDate,
            endB: primary.endDate
        )
    }

    private func taggedShiftIdentifier(in notes: String?) -> String? {
        guard let notes, let line = notes.split(separator: "\n").first(where: { $0.contains(Self.shiftIdentifierPrefix) }) else {
            return nil
        }

        return line
            .replacingOccurrences(of: Self.shiftIdentifierPrefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func intervalsOverlap(startA: Date, endA: Date, startB: Date, endB: Date) -> Bool {
        max(startA, startB) < min(endA, endB)
    }

    private func latestPersistedShiftVersion(for shift: Shift) -> Shift {
        guard let persistedShift = ShiftPersistence.load().first(where: { $0.id == shift.id }) else {
            return shift
        }

        if persistedShift.endAt != nil {
            return persistedShift
        }

        return shift
    }

    private func mappedEvent(for shiftId: UUID, calendar: EKCalendar) -> EKEvent? {
        let map = UserDefaults.standard.dictionary(forKey: Self.shiftEventMapKey) as? [String: String] ?? [:]
        guard let eventIdentifier = map[shiftId.uuidString] else { return nil }
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            removeStoredEventIdentifier(for: shiftId)
            return nil
        }

        if event.calendar.calendarIdentifier != calendar.calendarIdentifier {
            return nil
        }
        return event
    }

    private func storeEventIdentifier(_ identifier: String?, for shiftId: UUID) {
        guard let identifier, identifier.isEmpty == false else { return }
        var map = UserDefaults.standard.dictionary(forKey: Self.shiftEventMapKey) as? [String: String] ?? [:]
        map[shiftId.uuidString] = identifier
        UserDefaults.standard.set(map, forKey: Self.shiftEventMapKey)
    }

    private func removeStoredEventIdentifier(for shiftId: UUID) {
        var map = UserDefaults.standard.dictionary(forKey: Self.shiftEventMapKey) as? [String: String] ?? [:]
        map.removeValue(forKey: shiftId.uuidString)
        UserDefaults.standard.set(map, forKey: Self.shiftEventMapKey)
    }

    private func legacyCompatibleTitles(for shift: Shift) -> Set<String> {
        var titles: Set<String> = [calendarTitle(for: shift)]
        titles.insert("FreelanceLogbuch: \(shift.assignmentType.rawValue)")
        if let locationName = shift.locationName, locationName.isEmpty == false {
            titles.insert("FreelanceLogbuch: \(shift.assignmentType.rawValue) · \(locationName)")
        }
        return titles
    }

    private func bestSameDayCandidate(from candidates: [EKEvent], for startDate: Date) -> EKEvent? {
        let calendar = Calendar.current
        let sameDay = candidates.filter { calendar.isDate($0.startDate, inSameDayAs: startDate) }
        guard sameDay.isEmpty == false else { return nil }

        return sameDay.min {
            abs($0.startDate.timeIntervalSince(startDate)) < abs($1.startDate.timeIntervalSince(startDate))
        }
    }

    private func requestCalendarAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess:
                return true
            case .writeOnly, .notDetermined:
                return try await requestFullAccessToEvents()
            case .restricted, .denied:
                return false
            @unknown default:
                return false
            }
        }

        return try await requestLegacyCalendarAccess()
    }

    @available(iOS 17.0, *)
    private func requestFullAccessToEvents() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
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
