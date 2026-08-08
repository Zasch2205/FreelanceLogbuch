import CoreLocation
import Contacts
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var shifts: [Shift] = Shift.sample
    @State private var isShowingSettings = false
    @State private var workLocations: [WorkLocation] = []

    @AppStorage("freelancerName") private var freelancerName: String = ""

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
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

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
            .navigationTitle("FreelanceLogbuch")
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
            }
        }
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
            AppTheme.backgroundGradient
                .ignoresSafeArea()

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
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

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
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
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
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section {
                        TextField("Name", text: $freelancerName)
                            .textInputAutocapitalization(.words)
                    } header: {
                        AppSectionHeader("Freelancer")
                    }
                    .listRowBackground(Color.clear)

                    Section {
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
                    } header: {
                        AppSectionHeader("Neuen Ort hinzufügen")
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        if workLocations.isEmpty {
                            Text("Noch kein Arbeitsort hinterlegt")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(workLocations) { location in
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
                            .onDelete(perform: deleteLocations)
                        }
                    } header: {
                        AppSectionHeader("Arbeitsorte")
                    }
                    .listRowBackground(Color.clear)

                    if let activeLocation {
                        Section {
                            Map(position: .constant(mapRegion)) {
                                Marker("Arbeitsort", coordinate: activeLocation.coordinate)
                            }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button("In Apple Maps öffnen") {
                                openInAppleMaps(location: activeLocation)
                            }
                        } header: {
                            AppSectionHeader("Aktiver Ort auf Karte")
                        }
                        .listRowBackground(Color.clear)
                    }
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
            WorkLocationPersistence.save(workLocations)

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
        WorkLocationPersistence.save(workLocations)
    }

    private func deleteLocations(at offsets: IndexSet) {
        workLocations.remove(atOffsets: offsets)

        if workLocations.contains(where: { $0.isActive }) == false, let firstId = workLocations.first?.id {
            setActiveLocation(firstId)
            return
        }

        WorkLocationPersistence.save(workLocations)
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

private enum WorkLocationPersistence {
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
