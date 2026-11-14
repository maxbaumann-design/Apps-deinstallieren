# Selbstständiger Test der Erkennungslogik (ohne Zusatzmodule, entfernt nichts).
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Erkennung.ps1

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Erkennung.ps1')

$script:Fehler = 0
$script:Anzahl = 0
function Assert-Gleich {
    param($Erwartet, $Ist, [string]$Name)
    $script:Anzahl++
    if ("$Erwartet" -ceq "$Ist") { Write-Host "  OK      $Name" }
    else {
        $script:Fehler++
        Write-Host "  FEHLER  $Name  (erwartet: '$Erwartet', erhalten: '$Ist')" -ForegroundColor Red
    }
}

function New-Eintrag {
    param([hashtable]$Werte)
    $basis = @{
        KeyName = 'Beispiel'; DisplayName = 'Beispiel'; UninstallString = ''; QuietUninstallString = ''
        ParentKeyName = ''; ReleaseType = ''; SystemComponent = $null; WindowsInstaller = $null
    }
    foreach ($k in $Werte.Keys) { $basis[$k] = $Werte[$k] }
    [pscustomobject]$basis
}

$keinNsis = { param($p) $false }
$istNsis = { param($p) $true }
$guid = '{12345678-ABCD-1234-ABCD-1234567890AB}'

Write-Host 'Split-Befehlszeile'
$t = Split-Befehlszeile '"C:\Program Files\Foo\uninst.exe" /x /y'
Assert-Gleich 'C:\Program Files\Foo\uninst.exe' $t.Datei 'Pfad in Anführungszeichen'
Assert-Gleich '/x /y' $t.Argumente 'Argumente nach Anführungszeichen'
$t = Split-Befehlszeile 'C:\Program Files\Foo\uninst.exe /x'
Assert-Gleich 'C:\Program Files\Foo\uninst.exe' $t.Datei 'Pfad mit Leerzeichen ohne Anführungszeichen'
Assert-Gleich '/x' $t.Argumente 'Argumente ohne Anführungszeichen'
$t = Split-Befehlszeile "MsiExec.exe /I$guid"
Assert-Gleich 'MsiExec.exe' $t.Datei 'MsiExec ohne Pfad'
Assert-Gleich $null (Split-Befehlszeile '   ') 'Leere Befehlszeile'

Write-Host 'Get-StillerBefehl'
$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ KeyName = $guid; WindowsInstaller = 1; UninstallString = "MsiExec.exe /I$guid" }) -NsisPruefung $keinNsis
Assert-Gleich 'MSI' $b.Art 'MSI über WindowsInstaller=1'
Assert-Gleich "/x $guid /qn /norestart" $b.Argumente 'MSI-Argumente'
Assert-Gleich 'msiexec.exe' $b.Datei 'MSI-Programmdatei'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ KeyName = 'Foo'; UninstallString = "MsiExec.exe /X$guid" }) -NsisPruefung $keinNsis
Assert-Gleich 'MSI' $b.Art 'MSI über UninstallString'
Assert-Gleich "/x $guid /qn /norestart" $b.Argumente 'MSI-Argumente aus UninstallString'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ UninstallString = '"C:\Foo\setup.exe" /uninstall'; QuietUninstallString = '"C:\Foo\setup.exe" /uninstall /quiet' }) -NsisPruefung $keinNsis
Assert-Gleich 'Hersteller' $b.Art 'QuietUninstallString wird verwendet'
Assert-Gleich '/uninstall /quiet' $b.Argumente 'QuietUninstallString-Argumente'
Assert-Gleich $true $b.Still 'QuietUninstallString ist still'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ KeyName = 'Foo_is1'; UninstallString = '"C:\Foo\unins000.exe"' }) -NsisPruefung $keinNsis
Assert-Gleich 'Inno Setup' $b.Art 'Inno Setup über Schlüsselname'
Assert-Gleich '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' $b.Argumente 'Inno-Argumente'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ KeyName = 'Foo'; UninstallString = 'C:\Program Files\Foo\unins001.exe' }) -NsisPruefung $keinNsis
Assert-Gleich 'Inno Setup' $b.Art 'Inno Setup über Dateiname'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ UninstallString = '"C:\Foo\uninstall.exe"' }) -NsisPruefung $istNsis
Assert-Gleich 'NSIS' $b.Art 'NSIS erkannt'
Assert-Gleich '/S' $b.Argumente 'NSIS-Argument'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ UninstallString = '"C:\Foo\uninstall.exe" /remove' }) -NsisPruefung $keinNsis
Assert-Gleich $false $b.Still 'Unbekannter Deinstaller ist nicht still'
Assert-Gleich 'Unbekannt' $b.Art 'Unbekannter Deinstaller'

$b = Get-StillerBefehl -Eintrag (New-Eintrag @{ UninstallString = '' }) -NsisPruefung $keinNsis
Assert-Gleich $false $b.Still 'Ohne Deinstallationsbefehl nicht still'

Write-Host 'Test-ProgrammSichtbar'
Assert-Gleich $true (Test-ProgrammSichtbar (New-Eintrag @{ UninstallString = 'C:\x.exe' })) 'Normales Programm sichtbar'
Assert-Gleich $false (Test-ProgrammSichtbar (New-Eintrag @{ DisplayName = ''; UninstallString = 'C:\x.exe' })) 'Ohne Namen ausgeblendet'
Assert-Gleich $false (Test-ProgrammSichtbar (New-Eintrag @{ SystemComponent = 1; UninstallString = 'C:\x.exe' })) 'Systemkomponente ausgeblendet'
Assert-Gleich $false (Test-ProgrammSichtbar (New-Eintrag @{ ParentKeyName = 'Foo'; UninstallString = 'C:\x.exe' })) 'Untereintrag ausgeblendet'
Assert-Gleich $false (Test-ProgrammSichtbar (New-Eintrag @{ ReleaseType = 'Security Update'; UninstallString = 'C:\x.exe' })) 'Update ausgeblendet'
Assert-Gleich $false (Test-ProgrammSichtbar (New-Eintrag @{ })) 'Ohne Deinstallationsbefehl ausgeblendet'
Assert-Gleich $true (Test-ProgrammSichtbar (New-Eintrag @{ WindowsInstaller = 1 })) 'MSI ohne UninstallString sichtbar'

Write-Host 'Test-SystemDienst'
Assert-Gleich $true (Test-SystemDienst -PathName 'C:\Windows\system32\svchost.exe -k netsvcs' -SystemRoot 'C:\Windows') 'svchost ist Systemdienst'
Assert-Gleich $true (Test-SystemDienst -PathName '"C:\WINDOWS\System32\spoolsv.exe"' -SystemRoot 'C:\Windows') 'Gross-/Kleinschreibung egal'
Assert-Gleich $false (Test-SystemDienst -PathName '"C:\Program Files\Foo\foosvc.exe" --run' -SystemRoot 'C:\Windows') 'Fremddienst'
Assert-Gleich $false (Test-SystemDienst -PathName 'C:\Program Files (x86)\Foo Bar\svc.exe' -SystemRoot 'C:\Windows') 'Fremddienst ohne Anführungszeichen'
Assert-Gleich $true (Test-SystemDienst -PathName '' -SystemRoot 'C:\Windows') 'Ohne Pfad vorsichtshalber Systemdienst'

Write-Host ''
if ($script:Fehler -eq 0) { Write-Host "Alle $script:Anzahl Prüfungen bestanden." -ForegroundColor Green; exit 0 }
Write-Host "$script:Fehler von $script:Anzahl Prüfungen fehlgeschlagen." -ForegroundColor Red
exit 1
