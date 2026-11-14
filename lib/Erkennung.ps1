# Erkennung: Programme, Store-Apps und Dienste auflisten und den stillen
# Deinstallationsbefehl ermitteln. Enthält keine Oberfläche und entfernt nichts.

$script:GuidMuster = '\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}'

function Split-Befehlszeile {
    # Zerlegt eine Befehlszeile aus der Registry in Programmdatei und Argumente.
    param([string]$Befehl)

    $b = [Environment]::ExpandEnvironmentVariables(("$Befehl").Trim())
    if (-not $b) { return $null }

    $datei = $null
    $argumente = ''
    if ($b -match '^"([^"]+)"\s*(.*)$') {
        $datei = $Matches[1]; $argumente = $Matches[2]
    }
    elseif ($b -match '^(.+?\.exe)(?=\s|$)\s*(.*)$') {
        # Pfad ohne Anführungszeichen, darf Leerzeichen enthalten
        $datei = $Matches[1]; $argumente = $Matches[2]
    }
    elseif ($b -match '^(\S+)\s*(.*)$') {
        $datei = $Matches[1]; $argumente = $Matches[2]
    }
    else { return $null }

    [pscustomobject]@{ Datei = $datei.Trim(); Argumente = $argumente.Trim() }
}

function Test-NsisDatei {
    # Erkennt NSIS-Deinstaller an der Kennung "Nullsoft" in der Programmdatei.
    param([string]$Pfad)
    try {
        if (-not $Pfad -or -not (Test-Path -LiteralPath $Pfad -PathType Leaf)) { return $false }
        $fs = [System.IO.File]::Open($Pfad, 'Open', 'Read', 'ReadWrite')
        try {
            $laenge = [int][Math]::Min([long]$fs.Length, [long]2MB)
            $puffer = New-Object byte[] $laenge
            $gelesen = $fs.Read($puffer, 0, $laenge)
        }
        finally { $fs.Dispose() }
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($puffer, 0, $gelesen)
        return ($text.IndexOf('Nullsoft', [StringComparison]::Ordinal) -ge 0)
    }
    catch { return $false }
}

function New-BefehlErgebnis {
    param([bool]$Still, [string]$Art, [string]$Datei = '', [string]$Argumente = '')
    [pscustomobject]@{ Still = $Still; Art = $Art; Datei = $Datei; Argumente = $Argumente }
}

function Get-StillerBefehl {
    # Liefert zu einem Registry-Eintrag den Befehl für eine Deinstallation ohne Rückfragen.
    # Still = $false bedeutet: kein stiller Modus bekannt, Eintrag wird übersprungen.
    param(
        [Parameter(Mandatory = $true)]$Eintrag,
        [scriptblock]$NsisPruefung = { param($p) Test-NsisDatei -Pfad $p }
    )

    $schluessel = [string]$Eintrag.KeyName
    $normal = [string]$Eintrag.UninstallString
    $leise = [string]$Eintrag.QuietUninstallString

    # 1. MSI
    $guid = $null
    if ($Eintrag.WindowsInstaller -eq 1 -and $schluessel -match "^$script:GuidMuster$") {
        $guid = $schluessel
    }
    elseif ($normal -match 'msiexec' -and $normal -match $script:GuidMuster) {
        $guid = $Matches[0]
    }
    if ($guid) {
        return New-BefehlErgebnis -Still $true -Art 'MSI' -Datei 'msiexec.exe' -Argumente "/x $guid /qn /norestart"
    }

    # 2. Vom Hersteller hinterlegter stiller Befehl
    if (-not [string]::IsNullOrWhiteSpace($leise)) {
        $t = Split-Befehlszeile $leise
        if ($t) { return New-BefehlErgebnis -Still $true -Art 'Hersteller' -Datei $t.Datei -Argumente $t.Argumente }
    }

    $t = Split-Befehlszeile $normal
    if (-not $t) { return New-BefehlErgebnis -Still $false -Art 'Unbekannt' }
    $dateiname = ($t.Datei -split '[\\/]')[-1]

    # 3. Inno Setup
    if ($schluessel -like '*_is1' -or $dateiname -match '^unins\d{3}\.exe$') {
        $a = ("$($t.Argumente) /VERYSILENT /SUPPRESSMSGBOXES /NORESTART").Trim()
        return New-BefehlErgebnis -Still $true -Art 'Inno Setup' -Datei $t.Datei -Argumente $a
    }

    # 4. NSIS
    if (& $NsisPruefung $t.Datei) {
        $a = ("$($t.Argumente) /S").Trim()
        return New-BefehlErgebnis -Still $true -Art 'NSIS' -Datei $t.Datei -Argumente $a
    }

    return New-BefehlErgebnis -Still $false -Art 'Unbekannt' -Datei $t.Datei -Argumente $t.Argumente
}

function Test-ProgrammSichtbar {
    # Blendet Systemkomponenten, Updates und Einträge ohne Deinstallationsbefehl aus.
    param([Parameter(Mandatory = $true)]$Eintrag)

    if ([string]::IsNullOrWhiteSpace([string]$Eintrag.DisplayName)) { return $false }
    if ($Eintrag.SystemComponent -eq 1) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Eintrag.ParentKeyName)) { return $false }
    if (@('Update', 'Hotfix', 'Security Update') -contains [string]$Eintrag.ReleaseType) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Eintrag.UninstallString) -and
        [string]::IsNullOrWhiteSpace([string]$Eintrag.QuietUninstallString) -and
        $Eintrag.WindowsInstaller -ne 1) { return $false }
    return $true
}

function Test-StoreAppSichtbar {
    param([Parameter(Mandatory = $true)]$Paket)

    if ($Paket.IsFramework) { return $false }
    if ($Paket.IsResourcePackage) { return $false }
    if ($Paket.NonRemovable) { return $false }
    if ("$($Paket.SignatureKind)" -eq 'System') { return $false }
    return $true
}

function Test-SystemDienst {
    # Dienste, deren Programmdatei im Windows-Ordner liegt, gelten als Systemdienste.
    param([string]$PathName, [string]$SystemRoot = $env:SystemRoot)

    if ([string]::IsNullOrWhiteSpace($PathName)) { return $true }
    $t = Split-Befehlszeile $PathName
    if (-not $t) { return $true }
    $datei = $t.Datei
    if ($datei -match '^\\SystemRoot\\' -or $datei -match '^system32\\') { return $true }
    if ([string]::IsNullOrWhiteSpace($SystemRoot)) { return $false }
    $wurzel = $SystemRoot.TrimEnd('\') + '\'
    return $datei.StartsWith($wurzel, [StringComparison]::OrdinalIgnoreCase)
}

function Get-RegistryProgramme {
    $wurzeln = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $gesehen = @{}
    foreach ($wurzel in $wurzeln) {
        if (-not (Test-Path -LiteralPath $wurzel)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $wurzel -ErrorAction SilentlyContinue)) {
            try {
                $e = [pscustomobject]@{
                    KeyName              = $key.PSChildName
                    RegPfad              = $key.PSPath
                    DisplayName          = [string]$key.GetValue('DisplayName')
                    DisplayVersion       = [string]$key.GetValue('DisplayVersion')
                    Publisher            = [string]$key.GetValue('Publisher')
                    UninstallString      = [string]$key.GetValue('UninstallString')
                    QuietUninstallString = [string]$key.GetValue('QuietUninstallString')
                    ParentKeyName        = [string]$key.GetValue('ParentKeyName')
                    ReleaseType          = [string]$key.GetValue('ReleaseType')
                    SystemComponent      = $key.GetValue('SystemComponent')
                    WindowsInstaller     = $key.GetValue('WindowsInstaller')
                    EstimatedSize        = $key.GetValue('EstimatedSize')
                }
            }
            catch { continue }

            if (-not (Test-ProgrammSichtbar $e)) { continue }

            $marke = "$($e.DisplayName)|$($e.DisplayVersion)|$($e.UninstallString)"
            if ($gesehen.ContainsKey($marke)) { continue }
            $gesehen[$marke] = $true

            $befehl = Get-StillerBefehl -Eintrag $e
            $mb = 0.0
            try { if ($e.EstimatedSize) { $mb = [Math]::Round([double]$e.EstimatedSize / 1024, 1) } } catch { $mb = 0.0 }

            [pscustomobject]@{
                Name       = $e.DisplayName.Trim()
                Version    = $e.DisplayVersion
                Hersteller = $e.Publisher
                GroesseMB  = $mb
                Typ        = 'Programm'
                Art        = $befehl.Art
                Still      = $befehl.Still
                Datei      = $befehl.Datei
                Argumente  = $befehl.Argumente
                RegPfad    = $e.RegPfad
                PaketName  = ''
            }
        }
    }
}

function Get-StoreApps {
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return }
    $pakete = @()
    try { $pakete = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
    catch {
        try { $pakete = @(Get-AppxPackage -ErrorAction Stop) } catch { return }
    }

    $sichtbar = @($pakete | Where-Object { Test-StoreAppSichtbar $_ })
    foreach ($gruppe in @($sichtbar | Group-Object -Property Name)) {
        $p = $gruppe.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        $hersteller = ''
        if ("$($p.Publisher)" -match 'CN=([^,]+)') {
            $hersteller = $Matches[1]
            if ($hersteller -match '^[0-9A-Fa-f]{8}-') { $hersteller = '' }
        }
        [pscustomobject]@{
            Name       = [string]$p.Name
            Version    = [string]$p.Version
            Hersteller = $hersteller
            GroesseMB  = 0.0
            Typ        = 'Store-App'
            Art        = 'Store-App'
            Still      = $true
            Datei      = ''
            Argumente  = ''
            RegPfad    = ''
            PaketName  = [string]$p.Name
        }
    }
}

function Get-ProgrammListe {
    $alle = @(Get-RegistryProgramme) + @(Get-StoreApps)
    $alle | Sort-Object -Property Name
}

function Get-DienstListe {
    $statusText = @{ Running = 'Läuft'; Stopped = 'Beendet'; Paused = 'Angehalten' }
    $startText = @{ Auto = 'Automatisch'; Manual = 'Manuell'; Disabled = 'Deaktiviert'; Boot = 'Boot'; System = 'System' }

    $dienste = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
    $liste = foreach ($d in $dienste) {
        $status = [string]$d.State
        if ($statusText.ContainsKey($status)) { $status = $statusText[$status] }
        $start = [string]$d.StartMode
        if ($startText.ContainsKey($start)) { $start = $startText[$start] }
        $anzeige = [string]$d.DisplayName
        if ([string]::IsNullOrWhiteSpace($anzeige)) { $anzeige = [string]$d.Name }

        [pscustomobject]@{
            DienstName  = [string]$d.Name
            Anzeigename = $anzeige
            Status      = $status
            Startart    = $start
            Pfad        = [string]$d.PathName
            System      = (Test-SystemDienst -PathName ([string]$d.PathName))
        }
    }
    $liste | Sort-Object -Property Anzeigename
}
