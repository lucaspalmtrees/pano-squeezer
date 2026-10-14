# SPEC: Verlustfreie Desqueeze-App für anamorphe DNG-Fotos (macOS)

> **So benutzt du diese Datei**
> 1. Auf dem Mac einen leeren Ordner für das Projekt anlegen und diese Datei als `SPEC.md` hineinlegen.
> 2. Unten die Tabelle «Vorab festlegen» ausfüllen.
> 3. Claude Code in diesem Ordner starten und schreiben: **«Lies SPEC.md und starte mit Phase 0.»**
>
> Alles ab hier richtet sich an Claude Code.

---

## Vorab festlegen

| Punkt | Wert |
|---|---|
| App-Name | `pano-squeezer` |
| Bundle-ID | `com.lucarieser.pano-squeezer` |
| GitHub-Benutzer / Repo-Name | `lucaspalmtrees` / `pano-squeezer` (bereits angelegt, aktuell privat) |
| Spendenlink | `TODO` (Ko-fi, Buy Me a Coffee oder GitHub Sponsors) |
| UI-Sprache v1 | Englisch (Deutsch als spätere Lokalisierung) |
| Lizenz | MIT |

Wenn hier noch `TODO` steht: zuerst nachfragen, nicht raten.

---

## 1. Ziel

Eine kleine, minimalistische, native macOS-App: Ordner mit anamorph aufgenommenen DNG-Fotos hineinziehen, Squeeze-Faktor wählen, «Convert» klicken. Die App schreibt entzerrte Kopien in einen Unterordner.

**Die Bilddaten bleiben bitgenau unverändert.** Die App rechnet keine Pixel um, sondern setzt nur den DNG-Tag `DefaultScale`. Lightroom und Camera Raw wenden ihn beim Rendern an und zeigen das Bild im richtigen Seitenverhältnis.

**Kontext zum Entwickler:**
- Ich bin Programmier-Einsteiger (etwas Python, wenig Git-Erfahrung). Wenn ich selbst etwas tun muss (Terminal, GitHub, Lightroom), erkläre es Schritt für Schritt.
- Hardware: MacBook Pro M1 Pro.
- Testkameras: Leica M10 und Leica Q2. Beide speichern RAW direkt als DNG (Dateiendung `.DNG` in Grossbuchstaben).
- Das Projekt wird als Open Source auf GitHub veröffentlicht, mit freiwilligem Spendenlink.

---

## 2. Nicht verhandelbar

1. **Originale werden nie verändert.** Quelldateien nur lesend öffnen.
2. **Keine Bilddaten verändern.** Die Ausgabedatei enthält alle Bytes des Originals an derselben Position. Geändert wird genau ein 4-Byte-Zeiger, alles Neue wird ans Dateiende angehängt. Das wird nach jedem Schreiben geprüft (siehe 4.5). Schlägt die Prüfung fehl: Ausgabedatei löschen, Fehler melden.
3. **Keine Netzwerkzugriffe, keine Telemetrie.** Einzige Ausnahme: Spenden- und GitHub-Link öffnen den Browser, wenn der Nutzer sie anklickt.
4. **Keine externen Abhängigkeiten zur Laufzeit.** Kein exiftool, kein Python. Nur Swift und Apple-Frameworks. (exiftool ist nur in Tests erlaubt.)

---

## 3. Funktionen v1

Ein einziges Fenster, ca. 440 × 400 pt, ruhig und minimalistisch, SF Symbols, Light und Dark Mode.

**Eingabe**
- Drop-Zone: Ordner oder einzelne DNGs per Drag & Drop. Alternativ Klick auf die Zone öffnet eine Dateiauswahl (Ordner und Dateien erlaubt).
- Nach dem Ablegen: Ordnername, Anzahl gefundener DNGs, Anzahl ignorierter Dateien.
- Checkbox «Include subfolders» (Standard: aus).
- DNG-Erkennung: Endung `.dng` ohne Rücksicht auf Gross-/Kleinschreibung **und** gültiger TIFF-Header. Versteckte Dateien und macOS-Hilfsdateien wie `._L1000123.DNG` (entstehen auf exFAT-SD-Karten) ignorieren.
- Bereits erzeugte Ausgabeordner (siehe unten) beim Scannen überspringen, damit nichts doppelt verarbeitet wird.

**Einstellungen**
- Dropdown Squeeze-Faktor: `1.25×`, `1.33×`, `1.5×`, `1.6×`, `1.8×`, `2.0×`, `Custom…`
  - Custom: Zahlenfeld, erlaubt 1.01 bis 4.00, max. 2 Nachkommastellen, Punkt und Komma als Dezimaltrenner.
  - Standard: 1.33×. Letzte Wahl merken (`@AppStorage`).
- Richtung: Segmented Control «Horizontal» (Standard) / «Vertical». Tooltip: «Vertical: lens mounted rotated by 90°». Hinweis: Hochformatfotos brauchen trotzdem «Horizontal», weil sich das Objektiv mit der Kamera dreht.
- Zielort: «Same folder» (Standard, Unterordner im Quellordner) oder «Choose…» (eigener Ordner, z.B. wenn die Quelle eine SD-Karte ist).

**Umwandeln**
- Button «Convert», deaktiviert, solange nichts abgelegt ist.
- Fortschritt: Balken, «12 / 48» und aktueller Dateiname. Button «Cancel» bricht sauber ab und löscht die halbfertige Datei.
- Die Oberfläche bleibt während der Verarbeitung bedienbar (Arbeit im Hintergrund, `async`).

**Ausgabe**
- Unterordner `Desqueezed 1.33x` bzw. `Desqueezed 1.33x vertical`. Bei «Include subfolders» wird die Ordnerstruktur darin gespiegelt.
- Gleiche Dateinamen wie das Original. Existiert die Zieldatei schon: überspringen und melden, nie überschreiben.
- Erstellungs- und Änderungsdatum vom Original übernehmen.

**Ergebnis**
- Zusammenfassung: «45 converted · 2 skipped · 1 failed», aufklappbare Liste mit Grund pro Datei, Button «Show in Finder».
- Nach erfolgreicher Umwandlung dezent eine Zeile «☕ Support this project» mit Spendenlink. Kein Popup, kein Nerven.
- About-Fenster: Version, Lizenz, GitHub-Link, Spendenlink.

**Überspringen mit Grund**
- Raw-IFD hat bereits `DefaultScale` ungleich 1/1: «already desqueezed (x × y)».
- Kein oder mehr als ein Raw-IFD gefunden.
- BigTIFF oder Datei grösser als 4 GB.
- Beschädigte oder unlesbare Datei.

---

## 4. Technik: DNG-Logik (Kern der App)

### 4.1 Hintergrund
- DNG basiert auf TIFF 6.0.
- Tag `DefaultScale`: ID `0xC61E` (50718), Typ RATIONAL (5), Count 2, Werte `[horizontal, vertikal]`.
- Er gehört ins **Raw-IFD**: das IFD mit `NewSubFileType` (`0x00FE`) = 0. Das kann IFD0 sein oder ein SubIFD. Nicht annehmen, sondern suchen.
- Werte:
  - Horizontal mit Faktor f: `(f, 1)`
  - Vertikal: `(1, f)`
  - Als Bruch gespeichert: f × 100 / 100, gekürzt (1.33 → 133/100, 1.5 → 3/2, 2.0 → 2/1).
- Lightroom Classic, Lightroom Desktop/Web und Camera Raw berücksichtigen den Tag. Lightroom auf iPhone/iPad ignoriert ihn (bekannter Bug). Finder und Quick Look zeigen die eingebettete Vorschau weiterhin gestaucht.

### 4.2 Lesen (Parser)
- Header: `II*\0` (little endian) oder `MM\0*` (big endian). Magic 43 (BigTIFF) ablehnen. Offset zu IFD0 in Bytes 4–7.
- IFD-Aufbau: UInt16 Anzahl Einträge, dann n × 12 Bytes (`tag` u16, `type` u16, `count` u32, `value/offset` u32), danach u32 Offset zum nächsten IFD.
- Werte bis 4 Bytes stehen direkt im Value-Feld (linksbündig), grössere über Offset.
- Typgrössen: BYTE, ASCII, SBYTE, UNDEFINED = 1; SHORT, SSHORT = 2; LONG, SLONG, FLOAT, IFD (13) = 4; RATIONAL, SRATIONAL, DOUBLE = 8.
- Die IFD-Kette ab IFD0 durchlaufen, dazu alle SubIFDs (Tag `0x014A`, Typ LONG oder IFD) rekursiv. EXIF- und GPS-IFDs werden nicht gebraucht.
- Für jedes IFD merken: seinen Offset, seine Einträge und **wo der Zeiger auf dieses IFD steht**. Möglich sind:
  - Header (Byte 4)
  - Next-Feld des vorherigen IFD
  - Value-Feld des SubIFDs-Eintrags (bei Count 1)
  - Element im SubIFD-Array (bei Count > 1)
- Robust gegen kaputte Dateien: alle Offsets gegen die Dateigrösse prüfen, Zyklen erkennen, Anzahl IFDs und Einträge begrenzen (z.B. max. 1000 Einträge pro IFD). Nie abstürzen, sondern einen Fehler zurückgeben.
- Nur Header und IFDs lesen (`FileHandle` mit `seek`), nie die ganze Datei in den Speicher laden. DNGs können 50–100 MB gross sein.

### 4.3 Schreiben (Append-Strategie)
1. Original nach `<Ziel>/.<name>.partial` kopieren (`FileManager.copyItem`). Auf APFS ist das meist ein Klon: sofort fertig und belegt kaum Platz.
2. Neues IFD bauen:
   - Alle Einträge des Raw-IFD unverändert übernehmen, inklusive ihrer Offsets. Diese zeigen weiterhin auf die Originaldaten.
   - Den Eintrag `DefaultScale` hinzufügen. Falls er mit 1/1 schon existiert, ersetzen.
   - Einträge aufsteigend nach Tag sortieren (TIFF-Pflicht).
   - Next-IFD-Offset vom alten IFD übernehmen.
3. Am Dateiende anhängen, in der Bytereihenfolge der Datei, jeweils auf gerade Position aufgefüllt (Word-Alignment):
   - zuerst die 16 Bytes Wert für `DefaultScale` (2 × RATIONAL)
   - dann das neue IFD
4. Den einen Zeiger, der auf das alte Raw-IFD zeigte, auf das neue IFD umbiegen (genau 4 Bytes überschreiben).
5. Das alte IFD bleibt als ungenutzte Bytes stehen.
6. Prüfen (4.5), danach Datumsangaben vom Original setzen und atomar auf den endgültigen Namen umbenennen.

**Warum so:** Leica-MakerNotes und andere Herstellerdaten können absolute Offsets enthalten. Würde man Daten verschieben, gingen sie kaputt. Die Append-Strategie verschiebt nichts.

### 4.4 Faktor-Eingabe
Eine Funktion parst und validiert den Faktor (Strings wie «1.33», «1,5», «2») und gibt den gekürzten Bruch zurück. Ungültige Eingaben ergeben einen klaren Fehler.

### 4.5 Prüfung nach jedem Schreiben (Pflicht)
- Ausgabe neu parsen: Das Raw-IFD hat `DefaultScale` mit dem erwarteten Wert, alle anderen Einträge sind identisch mit dem Original.
- Byte-Vergleich: `Ausgabe[0 ..< Originalgrösse]` ist identisch mit dem Original, ausser genau den 4 Zeiger-Bytes. Die Dateigrösse entspricht Original plus angehängten Bytes. Vergleich in Blöcken (z.B. 4 MB), nicht alles in den Speicher.
- Bei Fehler: `.partial` löschen, Datei als «failed» mit Grund melden.

---

## 5. Projektstruktur

```
Package.swift
Sources/
  <AppName>Core/       # reine Logik, nur Foundation → läuft auch unter Linux
  <appname>-cli/       # Testwerkzeug: <appname>-cli --factor 1.33 [--vertical] --out <dir> <dateien|ordner…>
  <AppName>/           # SwiftUI-App, nur macOS
Tests/<AppName>CoreTests/
Resources/             # Info.plist-Vorlage, AppIcon
scripts/
  build-app.sh         # Universal Binary (arm64 + x86_64), .app zusammenbauen, ad-hoc signieren
  make-icon.sh         # Icon aus Vorlage erzeugen (iconutil)
.github/workflows/ci.yml
.github/workflows/release.yml
.github/FUNDING.yml
README.md  LICENSE  CHANGELOG.md  CLAUDE.md  .gitignore
```

- **Swift Package Manager statt Xcode-Projekt** (reine Textdateien, gut versionierbar). Mindestversion macOS 14.
- App-Code in `#if os(macOS)` packen und für andere Plattformen einen Stub-`main` vorsehen, damit `swift build` und `swift test` auch unter Linux laufen (falls Claude Code in der Cloud arbeitet).
- Die `.app` braucht eine `Info.plist` mit `CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion`, `CFBundleIconFile`, `NSHighResolutionCapable`.
- Icon: einfach und eigenständig, z.B. ein Oval, das zum Kreis wird. Keine fremden Marken oder Logos.

**Voraussetzungen auf dem Mac** (in Phase 0 prüfen und mir erklären, was fehlt):
- Xcode Command Line Tools (`xcode-select --install`). Falls `swift test` damit nicht läuft (XCTest fehlt dort teilweise): volles Xcode installieren oder Tests nur im CI laufen lassen.
- Homebrew, `gh` (GitHub CLI) und für Tests `exiftool`.

---

## 6. Tests

**Unit-Tests** mit synthetischen Mini-TIFF/DNG-Dateien, die im Test erzeugt und nicht eingecheckt werden:
- little endian und big endian
- Raw-Bild in IFD0, in einem SubIFD (Count 1) und in einem SubIFD-Array (Count > 1)
- `DefaultScale` fehlt, ist 1/1 oder ist ungleich 1/1 (→ überspringen)
- kaputte Dateien: Offset ausserhalb der Datei, Zyklus, abgeschnittene Datei → sauberer Fehler, kein Absturz
- Faktor-Parsing inklusive Grenzwerte und Komma
- Byte-Invariante aus 4.5

**Integrationstest mit echten DNGs**
- Im CI öffentliche Beispiel-DNGs herunterladen, z.B. Leica M10 und Q2 von raw.pixls.us. Nur Dateien mit Lizenz CC0 verwenden; ältere Dateien dort haben teils eine strengere Lizenz.
- Mit exiftool prüfen:
  - `exiftool -a -G1 -DefaultScale out.dng` zeigt den Wert im Raw-IFD.
  - `exiftool -validate -warning -a` liefert für die Ausgabe keine neuen Warnungen gegenüber dem Original.

**Eigene Fotos**
- Lokal in `testdata/local/` ablegen und diesen Ordner in `.gitignore` eintragen.
- **Nie eigene Fotos committen.** DNGs enthalten die Seriennummer der Kamera und eventuell GPS-Daten.

**Manueller Abnahmetest (mache ich selbst, bitte anleiten)**
- Ausgabe in Lightroom Classic importieren: Das Bild erscheint entzerrt, der Export hat das richtige Seitenverhältnis.
- Tipp: Beim Import «Standard»-Vorschauen wählen, denn die eingebetteten Vorschauen sind noch gestaucht.

---

## 7. Build und Release (GitHub Actions)

- **`ci.yml`:** Bei Push und Pull Request auf einem macOS-Runner `swift build`, `swift test` und den Integrationstest ausführen (`brew install exiftool`).
- **`release.yml`:** Bei Tag `v*`:
  - Tests ausführen
  - `scripts/build-app.sh` laufen lassen (Release, Universal Binary)
  - ad-hoc signieren (`codesign --force --sign -`)
  - zippen mit `ditto -c -k --keepParent`, optional zusätzlich DMG (`hdiutil`)
  - als GitHub Release hochladen, Release-Notes aus `CHANGELOG.md`
- Das Repo ist aktuell privat. Vor dem ersten Release mich daran erinnern, es auf öffentlich zu stellen (Settings → Danger Zone → Change visibility). In privaten Repos verbrauchen macOS-Builds das Gratis-Kontingent von GitHub Actions schnell, und der «Sponsor»-Knopf erscheint nur bei öffentlichen Repos.
- In v1 keine Apple-Developer-Signatur. Das README erklärt den ersten Start: Systemeinstellungen → Datenschutz & Sicherheit → «Dennoch öffnen».
- Developer-ID-Signierung und Notarisierung über Secrets vorbereiten, aber deaktiviert lassen, falls später ein Apple-Developer-Account dazukommt.
- `FUNDING.yml` mit dem Spendenlink anlegen, damit auf GitHub der «Sponsor»-Knopf erscheint.

---

## 8. README (Englisch)

Inhalt:
- 1 Satz, was die App macht, plus Screenshot oder GIF
- Warum verlustfrei (kurz: `DefaultScale`, keine Pixel verändert)
- Download und erster Start (Gatekeeper-Hinweis)
- Benutzung in 3 Schritten
- Lightroom-Tipps (Import mit Standard-Vorschauen)
- Einschränkungen: nur DNG, Lightroom auf iPhone/iPad, Finder-Vorschau, andere Programme
- Unterstützte Faktoren und Richtung
- Spenden
- Lizenz
- Hinweis: «Not affiliated with Adobe or Leica.»

---

## 9. Vorgehen in Phasen

Arbeite in Phasen. **Nach jeder Phase:** kurz zusammenfassen, was fertig ist und wie ich es ausprobieren kann, committen und auf mein OK warten.

- **Phase 0 – Setup:**
  - Voraussetzungen prüfen
  - Das Repo `github.com/lucaspalmtrees/pano-squeezer` existiert bereits: klonen bzw. als Remote verbinden, **nicht neu anlegen**. Vorher prüfen, was schon drin ist, und nichts davon überschreiben, ohne zu fragen. (Falls `gh` fehlt oder ich nicht angemeldet bin: Schritte erklären.)
  - `.gitignore`, `LICENSE`, README-Gerüst, `Package.swift`
  - `CLAUDE.md` mit den wichtigsten Regeln aus dieser Datei
- **Phase 1 – Kern:** Parser, Writer und Prüfung inklusive Unit-Tests.
- **Phase 2 – CLI:** Kommandozeilen-Tool und Integrationstest mit echten DNGs und exiftool.
- **Phase 3 – App:** Oberfläche nach Abschnitt 3.
- **Phase 4 – Auslieferung:** Build-Skript, Icon, CI- und Release-Workflow, erstes Release `v0.1.0`.
- **Phase 5 – Feinschliff:** README mit Screenshot, `CHANGELOG.md`, `FUNDING.yml`.

---

## 10. Später (nicht in v1)

- Deutsche Lokalisierung
- Eingebettete Vorschau neu erzeugen, damit auch Finder und Quick Look entzerrt anzeigen
- Andere RAW-Formate (ARW, NEF, CR3) vorher in DNG umwandeln, z.B. mit DNGLab (Lizenz prüfen)
- JPG/HEIC: echtes Strecken der Pixel (nicht verlustfrei, in der App klar kennzeichnen)
- Plugin für Lightroom Classic
- Signierte und notarisierte Version

---

## 11. Arbeitsregeln für Claude Code

- Bei Unklarheiten fragen statt raten, besonders bei allem, was Dateien verändern könnte.
- Originaldateien nie mit Schreibrechten öffnen. In Tests nur mit Kopien arbeiten.
- Kleine, verständliche Commits mit klaren Commit-Messages.
- Code einfach halten und dort kommentieren, wo die DNG-/TIFF-Struktur nicht offensichtlich ist.
- Wenn ich etwas selbst tun muss (Tools installieren, GitHub-Login, Lightroom-Test), Schritt für Schritt erklären.
