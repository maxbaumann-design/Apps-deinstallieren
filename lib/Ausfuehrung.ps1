# Ausführung: entfernt genau einen Eintrag (Programm, Store-App oder Dienst)
# und meldet das Ergebnis zurück. Wird im Hintergrund vom Hauptfenster aufgerufen.

function New-Ergebnis {
    param([string]$Status, [string]$Detail = '', [bool]$Neustart = $false)
    [pscustomobject]@{ Status = $Status; Detail = $Detail; Neustart = $Neustart }
}

function Wait-EintragEntfernt {
    # Manche Deinstaller arbeiten nach dem Ende ihres ersten Prozesses weiter.
    # Deshalb wird kurz gewartet, bis der Registry-Eintrag verschwunden ist.
    param([string]$RegPfad, [int]$Sekunden = 45)

    if (-not $RegPfad) { return $true }
    $ende = (Get-Date).AddSeconds($Sekunden)
    do {
        if (-not (Test-Path -LiteralPath $RegPfad)) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $ende)
    return $false
}

function Invoke-ProgrammDeinstallation {
    param($Aufgabe, [bool]$Simulieren, [int]$ZeitlimitSek = 900)

    if (-not $Aufgabe.Still) {
        return New-Ergebnis 'Manuell' 'Kein stiller Deinstallationsmodus bekannt'
    }
    $befehl = ("$($Aufgabe.Datei) $($Aufgabe.Argumente)").Trim()
    if ($Simulieren) { return New-Ergebnis 'Simuliert' $befehl }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Aufgabe.Datei
    $psi.Arguments = [string]$Aufgabe.Argumente
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    try { $prozess = [System.Diagnostics.Process]::Start($psi) }
    catch { return New-Ergebnis 'Fehler' "Start fehlgeschlagen: $($_.Exception.Message)" }

    if (-not $prozess.WaitForExit($ZeitlimitSek * 1000)) {
        & taskkill.exe /PID $prozess.Id /T /F 2>&1 | Out-Null
        return New-Ergebnis 'Fehler' "Zeitlimit von $([int]($ZeitlimitSek / 60)) Minuten überschritten, abgebrochen"
    }
    $code = $prozess.ExitCode
    $prozess.Dispose()

    if ($code -eq 1605) { return New-Ergebnis 'Entfernt' 'War bereits entfernt' }

    $neustart = ($code -eq 3010 -or $code -eq 1641)
    $erfolgGemeldet = ($code -eq 0 -or $neustart)
    $wartezeit = 5
    if ($erfolgGemeldet) { $wartezeit = 45 }
    $weg = Wait-EintragEntfernt -RegPfad $Aufgabe.RegPfad -Sekunden $wartezeit

    if ($weg) {
        if ($neustart) { return New-Ergebnis 'Entfernt' 'Neustart erforderlich' $true }
        return New-Ergebnis 'Entfernt' ''
    }
    if ($neustart) {
        return New-Ergebnis 'Entfernt' 'Wird mit dem nächsten Neustart abgeschlossen' $true
    }
    if ($code -eq 0) {
        return New-Ergebnis 'Fehler' 'Deinstaller meldete Erfolg, der Eintrag ist aber noch vorhanden - bitte prüfen'
    }
    return New-Ergebnis 'Fehler' "Deinstaller endete mit Fehlercode $code"
}

function Invoke-StoreAppEntfernung {
    param($Aufgabe, [bool]$Simulieren)

    $name = [string]$Aufgabe.PaketName
    if ($Simulieren) { return New-Ergebnis 'Simuliert' "Remove-AppxPackage -AllUsers ($name)" }

    try {
        $pakete = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
        foreach ($p in $pakete) {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        }
    }
    catch { return New-Ergebnis 'Fehler' $_.Exception.Message }

    # Vorinstallation für neue Benutzerkonten ebenfalls entfernen (falls vorhanden)
    try {
        Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { $_.DisplayName -eq $name } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null }
    }
    catch { }

    $rest = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)
    if ($rest.Count -gt 0) { return New-Ergebnis 'Fehler' 'Paket ist nach dem Entfernen noch vorhanden' }
    return New-Ergebnis 'Entfernt' ''
}

function Invoke-DienstAktion {
    param($Aufgabe, [bool]$Simulieren, [string]$LogOrdner)

    $name = [string]$Aufgabe.DienstName
    $loeschen = ($Aufgabe.Aktion -eq 'Löschen')

    if ($loeschen -and -not $Aufgabe.LoeschenErlaubt) {
        return New-Ergebnis 'Fehler' 'Systemdienste dürfen nur deaktiviert, nicht gelöscht werden'
    }
    if ($Simulieren) {
        if ($loeschen) { return New-Ergebnis 'Simuliert' "Dienst stoppen, sichern und löschen: sc.exe delete $name" }
        return New-Ergebnis 'Simuliert' "Dienst stoppen und deaktivieren: $name"
    }

    try { $dienst = Get-Service -Name $name -ErrorAction Stop }
    catch { return New-Ergebnis 'Fehler' 'Dienst nicht gefunden' }

    if ($loeschen) {
        $sicher = ($name -replace '[^A-Za-z0-9_.-]', '_')
        $datei = Join-Path $LogOrdner ("Dienst_{0}_{1}.reg" -f $sicher, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$name" $datei /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return New-Ergebnis 'Fehler' 'Sicherung des Dienstes fehlgeschlagen - nicht gelöscht'
        }
    }

    if ($dienst.Status -ne 'Stopped') {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    }

    if (-not $loeschen) {
        try { Set-Service -Name $name -StartupType Disabled -ErrorAction Stop }
        catch { return New-Ergebnis 'Fehler' $_.Exception.Message }
        $jetzt = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($jetzt -and $jetzt.Status -ne 'Stopped') {
            return New-Ergebnis 'Deaktiviert' 'Läuft noch bis zum nächsten Neustart' $true
        }
        return New-Ergebnis 'Deaktiviert' ''
    }

    & sc.exe delete $name 2>&1 | Out-Null
    $code = $LASTEXITCODE
    if ($code -eq 0) { return New-Ergebnis 'Gelöscht' "Sicherung: $datei" }
    if ($code -eq 1072) { return New-Ergebnis 'Gelöscht' "Wird mit dem nächsten Neustart entfernt. Sicherung: $datei" $true }
    return New-Ergebnis 'Fehler' "sc.exe delete endete mit Fehlercode $code"
}

function Invoke-Aufgabe {
    param($Aufgabe, [bool]$Simulieren, [string]$LogOrdner)

    switch ($Aufgabe.Typ) {
        'Programm'  { return Invoke-ProgrammDeinstallation -Aufgabe $Aufgabe -Simulieren $Simulieren }
        'Store-App' { return Invoke-StoreAppEntfernung -Aufgabe $Aufgabe -Simulieren $Simulieren }
        'Dienst'    { return Invoke-DienstAktion -Aufgabe $Aufgabe -Simulieren $Simulieren -LogOrdner $LogOrdner }
        default     { return New-Ergebnis 'Fehler' "Unbekannter Typ: $($Aufgabe.Typ)" }
    }
}
