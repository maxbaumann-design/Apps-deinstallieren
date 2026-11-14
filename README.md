# Apps deinstallieren

Ein kleines Windows-Werkzeug (Windows 10/11): mehrere Programme, Store-Apps und Dienste ankreuzen und in einem Durchgang entfernen – mit **einer** Admin-Abfrage und **einer** Bestätigung.

Es muss nichts installiert werden. Das Werkzeug nutzt PowerShell und WPF, die in Windows enthalten sind.

## Starten

1. Repository als ZIP herunterladen und entpacken (oder klonen).
2. `Start.cmd` doppelklicken.
3. Die Admin-Abfrage von Windows einmal bestätigen.

## Bedienung

- **Programme und Apps**: gewünschte Einträge ankreuzen. Die Spalte „Still möglich" zeigt, ob das Programm ohne eigene Rückfragen deinstalliert werden kann.
- **Dienste**: ankreuzen und je Dienst **Deaktivieren** (stoppen, startet nicht mehr automatisch – rückgängig machbar) oder **Löschen** wählen.
- **Suche** filtert beide Listen. „Alle sichtbaren" / „Keine" wirken auf den gerade geöffneten Reiter.
- **Nur simulieren**: zeigt im Protokoll, welche Befehle ausgeführt würden, ohne etwas zu verändern. Für den ersten Versuch empfohlen.
- **Ausgewählte entfernen**: eine Zusammenfassung bestätigen, danach läuft alles ohne weitere Rückfragen durch.

Am Ende erscheint ein Bericht: erfolgreich, fehlgeschlagen, übersprungen (manuell nötig), Neustart erforderlich. Es wird nie automatisch neu gestartet.

## Was still deinstalliert werden kann

| Art | Vorgehen |
|---|---|
| MSI-Pakete | `msiexec /x {GUID} /qn /norestart` |
| Vom Hersteller hinterlegter stiller Befehl | wird unverändert verwendet |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| NSIS | `/S` |
| Store-Apps | `Remove-AppxPackage -AllUsers` |

Alles andere wird **übersprungen** und im Bericht unter „Bitte manuell deinstallieren" aufgeführt.

## Sicherheitsnetze

- Windows-eigene Dienste sind standardmäßig ausgeblendet und können nur deaktiviert, nie gelöscht werden.
- Vor dem Löschen eines Dienstes wird sein Registry-Schlüssel als `.reg`-Datei gesichert. Ein Doppelklick auf diese Datei und ein Neustart stellen den Dienst-Eintrag wieder her.
- Systemkomponenten, Windows-Updates und nicht entfernbare Store-Apps erscheinen nicht in der Liste.
- Jeder Eintrag hat ein Zeitlimit von 15 Minuten; ein Fehler bei einem Eintrag hält die übrigen nicht auf.

Protokolle und Dienst-Sicherungen liegen unter `%LOCALAPPDATA%\AppsDeinstallieren\Logs`.

## Bekannte Grenzen

- Wird die Admin-Abfrage mit einem **anderen** Konto bestätigt, fehlen Programme, die nur für das eigene Benutzerkonto installiert wurden.
- Manche Deinstaller melden Erfolg, lassen aber Reste zurück oder ignorieren den stillen Schalter. Solche Fälle stehen im Bericht unter „Fehlgeschlagen".
- Store-Apps werden mit ihrem technischen Paketnamen angezeigt (z. B. `Microsoft.ZuneMusic`).

## Test der Erkennungslogik

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Erkennung.ps1
```

Der Test prüft nur die Regeln zur Befehlserkennung und entfernt nichts.
