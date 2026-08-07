# FreelanceLogbuch – MVP-Architektur (iOS)

## 1) Ziel des MVP
FreelanceLogbuch erfasst Arbeitszeiten für Freelancer möglichst automatisch über Geofencing und zuverlässig über Nutzerbestätigung.

**Kernprinzip:**
- Standort-Event löst eine Frage aus (`Schicht gestartet?` / `Schicht beendet?`).
- Erst nach Bestätigung wird ein valider Zeiteintrag erzeugt oder abgeschlossen.
- Zusätzlich gibt es eine **manuelle Erfassung/Korrektur**.

## 2) MVP-Funktionsumfang
- 1–3 Arbeitsorte (Geofences) konfigurierbar
- Eintritt in Geofence → Notification: `Schicht gestartet?`
- Austritt aus Geofence → Notification: `Schicht beendet?`
- Aktionen in Notification: `Ja`, `Nein`, `Später`
- Nach Start-Bestätigung zusätzliche Frage zur Einsatzart: `Grafik`, `Schnitt` oder `Sonstiges`
- Liste aller Schichten mit Start/Ende, Dauer, Ort
- Manuelle Schicht anlegen/ändern/löschen
- Monats-Export als CSV (Share Sheet) inkl. Einsatzart

## 3) iOS-Technik (empfohlen)
- **SwiftUI App**
- **Core Location Region Monitoring** für Ein-/Austritt je Arbeitsort
- **UNUserNotificationCenter** mit Action Buttons
- **Persistenz lokal, offline-first** (SwiftData oder Core Data/SQLite)
- Hintergrundverhalten über iOS-Region-Events (keine dauerhaft aktive App nötig)

## 4) Datenmodell (MVP)

### `WorkLocation`
- `id: UUID`
- `name: String`
- `latitude: Double`
- `longitude: Double`
- `radiusMeters: Double` (z. B. 150–250 m)
- `isActive: Bool`

### `Shift`
- `id: UUID`
- `locationId: UUID?` (optional, falls manuell ohne Ort)
- `startAt: Date`
- `endAt: Date?`
- `status: String` (`open`, `closed`, `cancelled`)
- `createdBy: String` (`geofence`, `manual`)
- `confirmedStart: Bool`
- `confirmedEnd: Bool`
- `note: String?`
- `assignmentType: String` (`Grafik`, `Schnitt`, `Sonstiges`)
- `createdAt: Date`
- `updatedAt: Date`

### `LocationEvent` (optional im MVP, aber hilfreich)
- `id: UUID`
- `locationId: UUID`
- `eventType: String` (`enter`, `exit`)
- `eventAt: Date`
- `decision: String?` (`yes`, `no`, `later`)

## 5) Event-Flow
1. App registriert aktive Arbeitsorte als Geofence.
2. iOS meldet `enter` oder `exit`.
3. App erzeugt lokale Notification mit passender Frage.
4. Nutzeraktion:
   - `Ja` bei `enter` → Zusatzfrage zur Einsatzart (`Grafik`/`Schnitt`/`Sonstiges`) und danach neue `Shift` mit `startAt`, `status=open` und `assignmentType`
   - `Ja` bei `exit` → offene `Shift` wird mit `endAt` geschlossen
   - `Nein` → Event verworfen, optional protokolliert
   - `Später` → erneute Erinnerung nach konfigurierbarer Zeit (z. B. 10 min)
5. UI aktualisiert Schichtliste und Summen.

## 6) Regeln für saubere Buchungen
- Maximal **eine offene Schicht** gleichzeitig
- Bei `enter` mit bereits offener Schicht: keine neue Schicht, stattdessen Hinweis/Log
- Bei `exit` ohne offene Schicht: keine Endbuchung, optional Hinweis/Log
- Alle Zeiten in lokaler Zeitzone anzeigen, intern als absolute Zeit speichern
- Manuelle Korrekturen jederzeit möglich, aber `createdBy` erhalten

## 7) Berechtigungen & UX-Hinweise
- Location Permission: `When In Use` → danach Upgrade-Pfad zu `Always` erklären
- Notifications Permission für Fragen/Erinnerungen
- In den Einstellungen klar erklären:
  - warum `Always Location` benötigt wird
  - dass iOS-Events verzögert eintreffen können
  - dass Bestätigung für rechtssichere Erfassung nötig ist

## 8) Warum keine Numbers/Excel als Primärspeicher?
- Schwach bei Integrität, Konfliktlösung und Offline-Robustheit
- Schlechter für Statuslogik (offene/geschlossene Schicht)
- Besser: robuste lokale Datenbank + **Export** nach CSV/Excel

## 9) MVP-Screens
1. **Heute/Liste**: Schichten, offene Schicht, Tages-/Monatssumme, Einsatzart anzeigen und nach Einsatzart filtern (`Grafik`/`Schnitt`/`Sonstiges`)
2. **Schicht manuell**: Start, Ende, Ort, Einsatzart, Notiz
3. **Orte**: Ort hinzufügen, Radius, Aktiv/Inaktiv
4. **Export**: Monat wählen, CSV teilen
5. **Einstellungen**: Rechte, Erinnerungsintervall, Hilfe

## 10) Umsetzungsreihenfolge
1. Datenmodell + lokale Persistenz
2. Manuelle Schichtanlage (UI + Validierungen)
3. Geofence-Registrierung für Orte
4. Notifications mit `Ja/Nein/Später`
5. Schichtliste + Summen
6. CSV-Export
7. Feinschliff (Fehlerfälle, Berechtigungs-Onboarding)

## 11) CSV-Export (MVP)
- Export pro Monat als UTF-8 CSV über Share Sheet
- Eine Zeile pro Schicht
- Empfohlene Spaltenreihenfolge:
  - `Datum`
  - `Start`
  - `Ende`
  - `DauerMinuten`
  - `Ort`
  - `Einsatzart` (`Grafik`/`Schnitt`/`Sonstiges`)
  - `Quelle` (`geofence`/`manual`)
  - `Notiz`
