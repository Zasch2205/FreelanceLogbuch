import CoreLocation
import Foundation
import UserNotifications

final class ShiftAutomationService: NSObject {
    static let shared = ShiftAutomationService()

    enum InAppDecision {
        case startGrafik
        case startSchnitt
        case endYes
        case no
        case later
    }

    private enum Constants {
        static let categoryStartId = "SHIFT_EVENT_START_CATEGORY"
        static let categoryEndId = "SHIFT_EVENT_END_CATEGORY"
        static let actionStartGrafik = "SHIFT_ACTION_START_GRAFIK"
        static let actionStartSchnitt = "SHIFT_ACTION_START_SCHNITT"
        static let actionEndYes = "SHIFT_ACTION_END_YES"
        static let actionNo = "SHIFT_ACTION_NO"
        static let actionLater = "SHIFT_ACTION_LATER"
        static let regionPrefix = "worklocation-"
        static let defaultRadius: CLLocationDistance = 200
        static let overtimeReminderPrefix = "SHIFT_OVERTIME_REMINDER-"
        static let overtimeReminderHours = [11, 12, 13, 14]
    }

    private enum EventType: String {
        case start
        case end
    }

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let calendarService: ShiftCalendarSyncing = ShiftCalendarService()

    private var isConfigured = false

    func configure() {
        guard isConfigured == false else { return }
        isConfigured = true

        locationManager.delegate = self
        notificationCenter.delegate = self

        registerNotificationActions()
        requestNeededPermissions()
        refreshMonitoring()
        refreshOpenShiftReminders()
    }

    func refreshMonitoring() {
        stopManagedRegions()

        guard let activeLocation = WorkLocationPersistence.load().first(where: { $0.isActive }) else { return }
        startMonitoring(for: activeLocation)
    }

    private func requestNeededPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func registerNotificationActions() {
        let startGrafikAction = UNNotificationAction(
            identifier: Constants.actionStartGrafik,
            title: "Grafik",
            options: [.foreground]
        )
        let startSchnittAction = UNNotificationAction(
            identifier: Constants.actionStartSchnitt,
            title: "Schnitt",
            options: [.foreground]
        )
        let endYesAction = UNNotificationAction(
            identifier: Constants.actionEndYes,
            title: "Ja",
            options: [.foreground]
        )
        let noAction = UNNotificationAction(
            identifier: Constants.actionNo,
            title: "Nein",
            options: []
        )
        let laterAction = UNNotificationAction(
            identifier: Constants.actionLater,
            title: "Später",
            options: []
        )

        let startCategory = UNNotificationCategory(
            identifier: Constants.categoryStartId,
            actions: [startGrafikAction, startSchnittAction, noAction, laterAction],
            intentIdentifiers: []
        )
        let endCategory = UNNotificationCategory(
            identifier: Constants.categoryEndId,
            actions: [endYesAction, noAction, laterAction],
            intentIdentifiers: []
        )

        notificationCenter.setNotificationCategories([startCategory, endCategory])
    }

    private func stopManagedRegions() {
        for region in locationManager.monitoredRegions {
            guard region.identifier.hasPrefix(Constants.regionPrefix) else { continue }
            locationManager.stopMonitoring(for: region)
        }
    }

    private func startMonitoring(for location: WorkLocation) {
        let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let radius = max(100, min(location.radiusMeters, locationManager.maximumRegionMonitoringDistance))

        let region = CLCircularRegion(
            center: center,
            radius: radius == 0 ? Constants.defaultRadius : radius,
            identifier: Constants.regionPrefix + location.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    private func scheduleQuestion(for eventType: EventType, locationName: String, delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = "FreelanceLogbuch"
        content.body = eventType == .start
            ? "\(locationName): Schicht startet jetzt?"
            : "\(locationName): Schicht ist jetzt zu Ende?"
        content.sound = .default
        content.categoryIdentifier = eventType == .start
            ? Constants.categoryStartId
            : Constants.categoryEndId
        content.userInfo = [
            "eventType": eventType.rawValue,
            "locationName": locationName
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    private func openShift() -> Shift? {
        ShiftPersistence.load().first(where: { $0.status == .open })
    }

    private func reminderIdentifiers(for shiftId: UUID) -> [String] {
        Constants.overtimeReminderHours.map { hour in
            "\(Constants.overtimeReminderPrefix)\(shiftId.uuidString)-\(hour)"
        }
    }

    private func cancelOvertimeReminders(for shiftId: UUID) {
        let identifiers = reminderIdentifiers(for: shiftId)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func refreshOpenShiftReminders() {
        guard let shift = openShift() else { return }
        scheduleOvertimeReminders(for: shift)
    }

    private func scheduleOvertimeReminders(for shift: Shift) {
        cancelOvertimeReminders(for: shift.id)

        guard shift.status == .open else { return }
        let locationName = shift.locationName ?? "Arbeitsort"
        let now = Date()

        for hour in Constants.overtimeReminderHours {
            let fireDate = shift.startAt.addingTimeInterval(TimeInterval(hour * 60 * 60))
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "FreelanceLogbuch"
            content.body = "\(locationName): Schicht läuft seit \(hour) Stunden. Ist sie jetzt zu Ende?"
            content.sound = .default
            content.categoryIdentifier = Constants.categoryEndId
            content.userInfo = [
                "eventType": EventType.end.rawValue,
                "locationName": locationName
            ]

            let triggerDelay = fireDate.timeIntervalSinceNow
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerDelay, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Constants.overtimeReminderPrefix)\(shift.id.uuidString)-\(hour)",
                content: content,
                trigger: trigger
            )
            notificationCenter.add(request)
        }
    }

    private func scheduleLater(from content: UNNotificationContent) {
        let newContent = UNMutableNotificationContent()
        newContent.title = content.title
        newContent.body = content.body
        newContent.sound = .default
        if let eventTypeRaw = content.userInfo["eventType"] as? String,
           let eventType = EventType(rawValue: eventTypeRaw) {
            newContent.categoryIdentifier = eventType == .start
                ? Constants.categoryStartId
                : Constants.categoryEndId
        } else {
            newContent.categoryIdentifier = Constants.categoryEndId
        }
        newContent.userInfo = content.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: newContent,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    func handleInAppConfirmation(eventTypeRaw: String, locationName: String, decision: InAppDecision) {
        guard let eventType = EventType(rawValue: eventTypeRaw) else { return }

        switch decision {
        case .startGrafik:
            guard eventType == .start else { return }
            handleConfirmedStart(locationName: locationName, assignmentType: .grafik)

        case .startSchnitt:
            guard eventType == .start else { return }
            handleConfirmedStart(locationName: locationName, assignmentType: .schnitt)

        case .endYes:
            if eventType == .end {
                handleConfirmedEnd()
            }

        case .later:
            scheduleQuestion(for: eventType, locationName: locationName, delay: 10 * 60)

        case .no:
            break
        }
    }

    private func handleConfirmedStart(locationName: String, assignmentType: AssignmentType) {
        var shifts = ShiftPersistence.load()
        guard shifts.contains(where: { $0.status == .open }) == false else { return }

        let newShift = Shift(
            id: UUID(),
            locationName: locationName,
            startAt: Date(),
            endAt: nil,
            status: .open,
            createdBy: .geofence,
            assignmentType: assignmentType,
            note: nil
        )
        shifts.append(newShift)
        ShiftPersistence.save(shifts)
        scheduleOvertimeReminders(for: newShift)
        NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
    }

    private func handleConfirmedEnd() {
        var shifts = ShiftPersistence.load()
        guard let index = shifts.firstIndex(where: { $0.status == .open }) else { return }

        shifts[index].endAt = Date()
        shifts[index].status = .closed
        let closedShift = shifts[index]
        cancelOvertimeReminders(for: closedShift.id)

        ShiftPersistence.save(shifts)
        NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

        Task {
            try? await calendarService.addShiftToCalendar(closedShift)
        }
    }
}

extension ShiftAutomationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        refreshMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard openShift() == nil else { return }

        guard
            let locationId = UUID(uuidString: region.identifier.replacingOccurrences(of: Constants.regionPrefix, with: "")),
            let location = WorkLocationPersistence.load().first(where: { $0.id == locationId })
        else { return }

        scheduleQuestion(for: .start, locationName: location.name)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let shift = openShift() else { return }

        guard
            let locationId = UUID(uuidString: region.identifier.replacingOccurrences(of: Constants.regionPrefix, with: "")),
            let location = WorkLocationPersistence.load().first(where: { $0.id == locationId })
        else { return }

        scheduleQuestion(for: .end, locationName: shift.locationName ?? location.name)
    }
}

extension ShiftAutomationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let eventType = EventType(rawValue: userInfo["eventType"] as? String ?? "")
        let locationName = userInfo["locationName"] as? String ?? "Arbeitsort"

        switch response.actionIdentifier {
        case Constants.actionStartGrafik:
            if eventType == .start {
                handleConfirmedStart(locationName: locationName, assignmentType: .grafik)
            }

        case Constants.actionStartSchnitt:
            if eventType == .start {
                handleConfirmedStart(locationName: locationName, assignmentType: .schnitt)
            }

        case Constants.actionEndYes:
            if eventType == .end {
                handleConfirmedEnd()
            }

        case Constants.actionLater:
            scheduleLater(from: response.notification.request.content)

        case UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(
                name: .shiftConfirmationRequired,
                object: nil,
                userInfo: [
                    "eventType": eventType?.rawValue ?? "",
                    "locationName": locationName
                ]
            )

        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
