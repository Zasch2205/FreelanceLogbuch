import CoreLocation
import Contacts
import MapKit
import SwiftUI

struct ContentView: View {
    @State private var shifts: [Shift] = Shift.sample
    @State private var isShowingSettings = false
    @State private var workLocations: [WorkLocation] = []

    @AppStorage("freelancerName") private var freelancerName: String = ""

    private var activeLocation: WorkLocation? {
        workLocations.first(where: { $0.isActive })
    }

    var body: some View {
        NavigationStack {
            List {
                if freelancerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Section("Freelancer") {
                        Text(freelancerName)
                            .font(.subheadline)
                    }
                }

                if let activeLocation {
                    Section("Aktiver Arbeitsort") {
                        Text(activeLocation.name)
                            .font(.subheadline)
                    }
                }

                Section("Schichten") {
                    ForEach(shifts) { shift in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shift.title)
                                .font(.headline)
                            Text(shift.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("FreelanceLogbuch")
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
            Form {
                Section("Freelancer") {
                    TextField("Name", text: $freelancerName)
                        .textInputAutocapitalization(.words)
                }

                Section("Neuen Ort hinzufügen") {
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

                Section("Arbeitsorte") {
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
                                .tint(location.isActive ? .green : .blue)
                            }
                        }
                        .onDelete(perform: deleteLocations)
                    }
                }

                if let activeLocation {
                    Section("Aktiver Ort auf Karte") {
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
            }
            .navigationTitle("Settings")
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

#Preview {
    ContentView()
}
