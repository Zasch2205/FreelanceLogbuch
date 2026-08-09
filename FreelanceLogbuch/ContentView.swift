import CoreLocation
import Contacts
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var shifts: [Shift] = ShiftPersistence.load()
    @State private var isShowingSettings = false
    @State private var workLocations: [WorkLocation] = []

    @AppStorage("freelancerName") private var freelancerName: String = ""
    @State private var showNotificationConfirmation = false
    @State private var pendingEventTypeRaw: String = ""
    @State private var pendingLocationName: String = ""
    @State private var statusBannerText: String?

    init() {
        Self.configureNavigationBarAppearance()
    }

    private var activeLocation: WorkLocation? {
        workLocations.first(where: { $0.isActive })
    }

    private var sortedShifts: [Shift] {
        shifts.sorted { $0.startAt > $1.startAt }
    }

    private var latestShifts: [Shift] {
        Array(sortedShifts.prefix(2))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    Text("Freelance Logbuch")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.28))
                        .shadow(color: .black.opacity(0.38), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    List {
                        if freelancerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            Section {
                                GlassPanel {
                                    Text(freelancerName)
                                        .font(.subheadline)
                                }
                            } header: {
                                AppSectionHeader("Freelancer")
                            }
                            .listRowBackground(Color.clear)
                        }

                        if let activeLocation {
                            Section {
                                GlassPanel {
                                    Text(activeLocation.name)
                                        .font(.subheadline)
                                }
                            } header: {
                                AppSectionHeader("Aktiver Arbeitsort")
                            }
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            if latestShifts.isEmpty {
                                GlassPanel {
                                    Text("Noch keine Schichten vorhanden")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                GlassPanel {
                                    VStack(spacing: 0) {
                                        ForEach(Array(latestShifts.enumerated()), id: \.element.id) { index, shift in
                                            ShiftRowView(shift: shift)

                                            if index < latestShifts.count - 1 {
                                                Divider()
                                                    .overlay(Color.white.opacity(0.35))
                                            }
                                        }
                                    }
                                }
                            }

                            GlassPanel {
                                NavigationLink {
                                    AllShiftsView(shifts: $shifts, activeLocationName: activeLocation?.name)
                                } label: {
                                    Label("Alle Schichten anzeigen", systemImage: "list.bullet")
                                }
                            }
                        } header: {
                            AppSectionHeader("Letzte Schichten")
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .listRowSeparator(.hidden)
                }
            }
            .tint(AppTheme.accentBlue)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityLabel("Settings öffnen")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(workLocations: $workLocations)
            }
            .onAppear {
                workLocations = WorkLocationPersistence.load()
                shifts = ShiftPersistence.load()
                ShiftAutomationService.shared.refreshMonitoring()
            }
            .onChange(of: shifts) { _, updatedShifts in
                ShiftPersistence.save(updatedShifts)
            }
            .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
                shifts = ShiftPersistence.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shiftConfirmationRequired)) { notification in
                guard
                    let userInfo = notification.userInfo,
                    let eventType = userInfo["eventType"] as? String,
                    let locationName = userInfo["locationName"] as? String,
                    eventType.isEmpty == false
                else { return }

                pendingEventTypeRaw = eventType
                pendingLocationName = locationName
                showNotificationConfirmation = true
            }
            .alert(notificationAlertTitle, isPresented: $showNotificationConfirmation) {
                Button("Ja") {
                    ShiftAutomationService.shared.handleInAppConfirmation(
                        eventTypeRaw: pendingEventTypeRaw,
                        locationName: pendingLocationName,
                        decision: .yes
                    )
                    showStatusBanner(
                        pendingEventTypeRaw == "start" ? "Schicht gestartet" : "Schicht beendet"
                    )
                }
                Button("Später") {
                    ShiftAutomationService.shared.handleInAppConfirmation(
                        eventTypeRaw: pendingEventTypeRaw,
                        locationName: pendingLocationName,
                        decision: .later
                    )
                }
                Button("Nein", role: .cancel) {
                    ShiftAutomationService.shared.handleInAppConfirmation(
                        eventTypeRaw: pendingEventTypeRaw,
                        locationName: pendingLocationName,
                        decision: .no
                    )
                }
            } message: {
                Text(notificationAlertMessage)
            }
            .overlay(alignment: .top) {
                if let statusBannerText {
                    Text(statusBannerText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: statusBannerText)
        }
    }

    private var notificationAlertTitle: String {
        pendingEventTypeRaw == "start" ? "Schicht starten?" : "Schicht beenden?"
    }

    private var notificationAlertMessage: String {
        if pendingLocationName.isEmpty {
            return "Bitte bestätige die Schicht-Aktion."
        }
        return "Arbeitsort: \(pendingLocationName)"
    }

    private func showStatusBanner(_ text: String) {
        statusBannerText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            statusBannerText = nil
        }
    }

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(red: 0.90, green: 0.97, blue: 1.0, alpha: 1.0)
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.90, green: 0.97, blue: 1.0, alpha: 1.0)
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
}

private struct ShiftRowView: View {
    let shift: Shift

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shift.title)
                .font(.headline)
            Text(shift.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AllShiftsView: View {
    @Binding var shifts: [Shift]
    let activeLocationName: String?

    @State private var exportError = false
    @State private var isShowingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isShowingAddShift = false
    @State private var noActiveLocationAlert = false

    private var sortedShifts: [Shift] {
        shifts.sorted { $0.startAt > $1.startAt }
    }

    var body: some View {
        ZStack {
            AppBackground()

            List {
                if sortedShifts.isEmpty {
                    GlassPanel {
                        Text("Noch keine Schichten vorhanden")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedShifts) { shift in
                        ShiftRowView(shift: shift)
                            .listRowBackground(AppTheme.tableRowBackground)
                    }
                    .onDelete(perform: deleteShifts)
                }

                Section {
                    GlassPanel {
                        Button {
                            exportAndShare()
                        } label: {
                            Label("CSV exportieren & teilen", systemImage: "square.and.arrow.up")
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    AppSectionHeader("Export")
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowSeparator(.visible)
        }
        .navigationTitle("Alle Schichten")
        .tint(AppTheme.accentBlue)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .disabled(sortedShifts.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if activeLocationName == nil {
                        noActiveLocationAlert = true
                    } else {
                        isShowingAddShift = true
                    }
                } label: {
                    Label("Datensatz hinzufügen", systemImage: "plus")
                }
            }
        }
        .alert("Export fehlgeschlagen", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Die CSV-Datei konnte nicht erstellt werden.")
        }
        .alert("Kein aktiver Arbeitsort", isPresented: $noActiveLocationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte zuerst in den Settings einen aktiven Arbeitsort setzen.")
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ActivityView(items: shareItems)
        }
        .sheet(isPresented: $isShowingAddShift) {
            AddManualShiftView(activeLocationName: activeLocationName) { date in
                addManualShift(startAt: date.startAt, endAt: date.endAt, assignmentType: date.assignmentType)
            }
        }
    }

    private func exportAndShare() {
        guard let exportURL = ShiftCSVExporter.createCSVFile(for: sortedShifts) else {
            exportError = true
            return
        }
        shareItems = [exportURL]
        isShowingShareSheet = true
    }

    private func deleteShifts(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sortedShifts[$0].id }
        shifts.removeAll { idsToDelete.contains($0.id) }
    }

    private func addManualShift(startAt: Date, endAt: Date, assignmentType: AssignmentType) {
        let newShift = Shift(
            id: UUID(),
            locationName: activeLocationName,
            startAt: startAt,
            endAt: endAt,
            status: .closed,
            createdBy: .manual,
            assignmentType: assignmentType,
            note: nil
        )
        shifts.append(newShift)
    }
}

private struct AddManualShiftView: View {
    @Environment(\.dismiss) private var dismiss

    let activeLocationName: String?
    let onSave: ((startAt: Date, endAt: Date, assignmentType: AssignmentType)) -> Void

    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(8 * 60 * 60)
    @State private var assignmentType: AssignmentType = .grafik

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Form {
                    Section {
                        Text(activeLocationName ?? "Nicht gesetzt")
                    } header: {
                        AppSectionHeader("Arbeitsort")
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        DatePicker("Startzeit", selection: $startAt)
                        DatePicker("Endezeit", selection: $endAt)
                    } header: {
                        AppSectionHeader("Datum und Uhrzeit")
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        Picker("Einsatzart", selection: $assignmentType) {
                            Text("Grafik").tag(AssignmentType.grafik)
                            Text("Schnitt").tag(AssignmentType.schnitt)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        AppSectionHeader("Einsatzart")
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Datensatz hinzufügen")
            .tint(AppTheme.accentBlue)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: startAt) { _, newValue in
                endAt = newValue.addingTimeInterval(8 * 60 * 60)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        onSave((startAt: startAt, endAt: endAt, assignmentType: assignmentType))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

private struct AppSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
            .textCase(nil)
            .padding(.top, 4)
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient

            IconMotifBackdrop()
                .opacity(0.36)
                .blendMode(.screen)

            IconMotifBackdrop()
                .scaleEffect(1.10)
                .blur(radius: 10)
                .opacity(0.30)
                .blendMode(.screen)

            IconMotifBackdrop()
                .scaleEffect(1.2)
                .blur(radius: 24)
                .opacity(0.18)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

private struct IconMotifBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 110)
                    .fill(Color(red: 0.62, green: 0.86, blue: 1.0).opacity(0.38))
                    .frame(width: w * 0.92, height: h * 0.26)
                    .offset(y: h * 0.24)

                RoundedRectangle(cornerRadius: 56)
                    .fill(Color(red: 0.76, green: 0.92, blue: 1.0).opacity(0.42))
                    .frame(width: w * 0.62, height: h * 0.16)
                    .rotationEffect(.degrees(-12))
                    .offset(x: w * 0.08, y: h * 0.02)

                RoundedRectangle(cornerRadius: 30)
                    .fill(Color(red: 0.60, green: 0.80, blue: 1.0).opacity(0.40))
                    .frame(width: w * 0.52, height: h * 0.14)
                    .offset(x: -w * 0.05, y: h * 0.10)

                RoundedRectangle(cornerRadius: 130)
                    .fill(Color(red: 0.75, green: 0.90, blue: 1.0).opacity(0.32))
                    .frame(width: w * 0.72, height: h * 0.22)
                    .rotationEffect(.degrees(-18))
                    .offset(x: w * 0.14, y: -h * 0.16)

                Capsule()
                    .fill(Color(red: 0.70, green: 0.88, blue: 1.0).opacity(0.42))
                    .frame(width: w * 0.30, height: h * 0.032)
                    .offset(x: 0, y: h * 0.25)
            }
            .frame(width: w, height: h)
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Binding var workLocations: [WorkLocation]

    @AppStorage("freelancerName") private var freelancerName: String = ""

    @State private var addressInput: String = ""
    @State private var errorMessage: String?
    @State private var isGeocoding = false

    private var activeLocation: WorkLocation? {
        workLocations.first(where: { $0.isActive })
    }

    private var mapRegion: MapCameraPosition {
        guard let coordinate = activeLocation?.coordinate else { return .automatic }
        return .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Form {
                    Section {
                        GlassPanel {
                            TextField("Name", text: $freelancerName)
                                .textInputAutocapitalization(.words)
                        }
                    } header: {
                        AppSectionHeader("Freelancer")
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Adresse eingeben", text: $addressInput, axis: .vertical)
                                    .textInputAutocapitalization(.words)

                                Button {
                                    Task {
                                        await addAddressAsLocation()
                                    }
                                } label: {
                                    if isGeocoding {
                                        ProgressView()
                                    } else {
                                        Text("Adresse übernehmen")
                                    }
                                }
                                .disabled(addressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeocoding)

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        AppSectionHeader("Neuen Ort hinzufügen")
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        if workLocations.isEmpty {
                            GlassPanel {
                                Text("Noch kein Arbeitsort hinterlegt")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(workLocations) { location in
                                GlassPanel {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.name)
                                                .font(.body)
                                            Text("Radius: \(Int(location.radiusMeters)) m")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(location.isActive ? "Aktiv" : "Als aktiv setzen") {
                                            setActiveLocation(location.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .tint(location.isActive ? .green : AppTheme.accentBlue)
                                    }
                                }
                            }
                            .onDelete(perform: deleteLocations)
                        }
                    } header: {
                        AppSectionHeader("Arbeitsorte")
                    }
                    .listRowBackground(Color.clear)

                    if let activeLocation {
                        Section {
                            GlassPanel {
                                VStack(alignment: .leading, spacing: 10) {
                                    Map(position: .constant(mapRegion)) {
                                        Marker("Arbeitsort", coordinate: activeLocation.coordinate)
                                    }
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Button("In Apple Maps öffnen") {
                                        openInAppleMaps(location: activeLocation)
                                    }
                                }
                            }
                        } header: {
                            AppSectionHeader("Aktiver Ort auf Karte")
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        NavigationLink {
                            AppInfoView()
                        } label: {
                            Label("Info", systemImage: "info.circle")
                        }
                    } header: {
                        AppSectionHeader("Über")
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Settings")
            .tint(AppTheme.accentBlue)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(workLocations.isEmpty)
                }
            }
        }
    }

    private func addAddressAsLocation() async {
        let trimmedAddress = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAddress.isEmpty == false else { return }

        isGeocoding = true
        errorMessage = nil

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(trimmedAddress)
            guard let placemark = placemarks.first, let coordinate = placemark.location?.coordinate else {
                errorMessage = "Adresse konnte nicht gefunden werden."
                isGeocoding = false
                return
            }

            let normalizedAddress = normalizedAddressName(from: placemark, fallback: trimmedAddress)

            let alreadyExists = workLocations.contains {
                $0.name.caseInsensitiveCompare(normalizedAddress) == .orderedSame
            }
            if alreadyExists {
                errorMessage = "Diese Adresse ist bereits vorhanden."
                isGeocoding = false
                return
            }

            let shouldBeActive = workLocations.contains(where: { $0.isActive }) == false
            let newLocation = WorkLocation(
                id: UUID(),
                name: normalizedAddress,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radiusMeters: 200,
                isActive: shouldBeActive
            )

            workLocations.append(newLocation)
            saveWorkLocations()

            addressInput = ""
            isGeocoding = false
        } catch {
            errorMessage = "Geocoding fehlgeschlagen. Bitte Adresse prüfen."
            isGeocoding = false
        }
    }

    private func setActiveLocation(_ id: UUID) {
        workLocations = workLocations.map { location in
            var updated = location
            updated.isActive = updated.id == id
            return updated
        }
        saveWorkLocations()
    }

    private func deleteLocations(at offsets: IndexSet) {
        workLocations.remove(atOffsets: offsets)

        if workLocations.contains(where: { $0.isActive }) == false, let firstId = workLocations.first?.id {
            setActiveLocation(firstId)
            return
        }

        saveWorkLocations()
    }

    private func saveWorkLocations() {
        WorkLocationPersistence.save(workLocations)
        ShiftAutomationService.shared.refreshMonitoring()
    }

    private func openInAppleMaps(location: WorkLocation) {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "q", value: location.name)
        ]

        guard let url = components?.url else { return }
        openURL(url)
    }

    private func normalizedAddressName(from placemark: CLPlacemark, fallback: String) -> String {
        if let postalAddress = placemark.postalAddress {
            let formatted = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if formatted.isEmpty == false {
                return formatted
            }
        }

        let parts: [String?] = [
            placemark.name,
            placemark.locality,
            placemark.country
        ]

        let compact = parts.compactMap { (value: String?) -> String? in
            guard let unwrapped = value else { return nil }
            let trimmed = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if compact.isEmpty == false {
            return compact.joined(separator: ", ")
        }

        return fallback
    }
}

private struct AppInfoView: View {
    @Environment(\.openURL) private var openURL

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(shortVersion) (Build \(build))"
    }

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("(c) 2026 Sascha Molina")
                            Button("Feedback an s.molina@gmx.de") {
                                if let mailURL = URL(string: "mailto:s.molina@gmx.de") {
                                    openURL(mailURL)
                                }
                            }
                            Text("Version: \(versionText)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                    }
                } header: {
                    AppSectionHeader("Info")
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink("Impressum") {
                        LegalImprintView()
                    }
                    NavigationLink("Datenschutz") {
                        LegalPrivacyView()
                    }
                } header: {
                    AppSectionHeader("Recht")
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
        }
        .navigationTitle("Info")
        .tint(AppTheme.accentBlue)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct LegalImprintView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Angaben gemäß § 5 DDG")
                                .font(.headline)

                            Text("Sascha Molina")
                            Text("Lerchenweg 25")
                            Text("22885 Barsbüttel")
                            Text("Deutschland")

                            Text("E-Mail: s.molina@gmx.de")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Impressum")
        .tint(AppTheme.accentBlue)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct LegalPrivacyView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Datenschutzhinweise")
                                .font(.headline)

                            Text("Diese App verarbeitet Standortdaten zur Erkennung von Schichtstart/-ende über Geofencing.")
                            Text("Schichtdaten werden lokal auf dem Gerät gespeichert.")
                            Text("Für den optionalen Kalendereintrag wird nach Kalenderzugriff gefragt.")
                            Text("Benachrichtigungen werden lokal auf dem Gerät erstellt.")

                            Text("Hinweis: Bitte vor Veröffentlichung eine vollständige, rechtlich geprüfte Datenschutzerklärung ergänzen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Datenschutz")
        .tint(AppTheme.accentBlue)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private enum AppTheme {
    static let accentBlue = Color(red: 0.09, green: 0.52, blue: 0.98)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.20, blue: 0.52),
            Color(red: 0.06, green: 0.37, blue: 0.84),
            Color(red: 0.15, green: 0.62, blue: 0.99)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tableRowBackground = Color.white.opacity(0.2)
}

private enum ShiftCSVExporter {
    static func createCSVFile(for shifts: [Shift]) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]

        let header = "Datum,Start,Ende,DauerMinuten,Ort,Einsatzart,Quelle,Notiz"
        let rows = shifts.map { shift -> String in
            let startDate = shift.startAt
            let endDate = shift.endAt

            let dateOnly = DateFormatter.localizedString(from: startDate, dateStyle: .short, timeStyle: .none)
            let startOnly = DateFormatter.localizedString(from: startDate, dateStyle: .none, timeStyle: .short)
            let endOnly = endDate.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""

            let durationMinutes: Int
            if let endDate {
                durationMinutes = Int(endDate.timeIntervalSince(startDate) / 60)
            } else {
                durationMinutes = 0
            }

            let fields: [String] = [
                dateOnly,
                startOnly,
                endOnly,
                String(durationMinutes),
                shift.locationName ?? "",
                shift.assignmentType.rawValue,
                shift.createdBy.rawValue,
                shift.note ?? ""
            ]

            return fields
                .map { field in
                    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(escaped)\""
                }
                .joined(separator: ",")
        }

        let csv = ([header] + rows).joined(separator: "\n")

        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("freelancelogbuch-export-\(timestamp).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}

#Preview {
    ContentView()
}
