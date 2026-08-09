# Release- und Versionierungsstrategie (FreelanceLogbuch)

## Begriffe

- **Marketing Version** (`MARKETING_VERSION`): Sichtbare App-Version für Nutzer:innen (z. B. `1.0`, `1.1`, `2.0`)
- **Build Number** (`CURRENT_PROJECT_VERSION`): Interne laufende Nummer für Uploads (z. B. `1`, `2`, `3`)

Anzeige in iOS/TestFlight typischerweise: `1.0 (3)`.

---

## Regeln

### 1) Wann Build Number erhöhen?

**Immer**, wenn ein neues Archive/TestFlight/App-Store-Upload erstellt wird.

Beispiele:
- Bugfix neu hochladen ohne neue sichtbare Version: `1.0 (2)` → `1.0 (3)`
- Neuer Test-Build am selben Tag: Build +1

### 2) Wann Marketing Version erhöhen?

Wenn sich aus Nutzersicht etwas am Release ändert.

- **Minor erhöhen** (`1.0` → `1.1`): neue Funktionen, merkbare UI/UX-Verbesserungen
- **Patch erhöhen** (optional, wenn verwendet; z. B. `1.1.0` → `1.1.1`): kleine Bugfix-Releases
- **Major erhöhen** (`1.x` → `2.0`): größere funktionale Sprünge, grundlegende Änderungen

---

## Empfohlenes Schema für dieses Projekt

Einfach und ausreichend:

- Marketing Version: `MAJOR.MINOR` (z. B. `1.0`, `1.1`, `1.2`)
- Build Number: fortlaufend integer (`1`, `2`, `3`, ...)

Beispielverlauf:
- `1.0 (1)` initial
- `1.0 (2)` nächster TestFlight-Build
- `1.1 (1)` erstes Feature-Release nach 1.0
- `1.1 (2)` Fix-Build

---

## Release-Checkliste

Vor Upload:

1. Version setzen
   - Bei Feature-Release: `MARKETING_VERSION` erhöhen
   - Immer: `CURRENT_PROJECT_VERSION` erhöhen
2. Build lokal prüfen (`BUILD SUCCEEDED`)
3. Kernflows manuell testen (Start/Ende, Export, Geofence-Dialoge)
4. Rechtliches prüfen (Impressum/Datenschutz aktuell)
5. Archive erstellen und hochladen

---

## Hinweise

- Build Number darf in App Store Connect **nie rückwärts** gehen.
- Wenn ein Upload abgelehnt wurde und du neu hochlädst: gleiche Marketing Version möglich, aber Build Number muss höher sein.
- Für konsistente Releases immer denselben Ablauf verwenden (diese Datei).
