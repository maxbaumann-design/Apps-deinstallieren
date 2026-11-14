#requires -Version 5.1
# Apps deinstallieren: mehrere Programme, Store-Apps und Dienste auswählen und
# nacheinander entfernen - mit einer einzigen Admin-Abfrage und einer Bestätigung.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Data

# --- Einmalige Admin-Anhebung ------------------------------------------------
$identitaet = [Security.Principal.WindowsIdentity]::GetCurrent()
$istAdmin = (New-Object Security.Principal.WindowsPrincipal $identitaet).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $istAdmin) {
    try {
        $exe = (Get-Process -Id $PID).Path
        $argumente = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
        Start-Process -FilePath $exe -ArgumentList $argumente -Verb RunAs
    }
    catch {
        [void][System.Windows.MessageBox]::Show(
            'Ohne Administratorrechte können keine Programme oder Dienste entfernt werden.',
            'Apps deinstallieren', 'OK', 'Warning')
    }
    exit
}

$libOrdner = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libOrdner 'Erkennung.ps1')

$logOrdner = Join-Path $env:LOCALAPPDATA 'AppsDeinstallieren\Logs'
[void](New-Item -ItemType Directory -Path $logOrdner -Force)
$script:LogDatei = Join-Path $logOrdner ("{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

# --- Oberfläche --------------------------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Apps deinstallieren" Width="1040" Height="740" MinWidth="780" MinHeight="540"
        WindowStartupLocation="CenterScreen" FontSize="13">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="130"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,8" LastChildFill="True">
      <Button Name="BtnAktualisieren" DockPanel.Dock="Right" Content="Aktualisieren" Padding="12,4" Margin="6,0,0,0"/>
      <Button Name="BtnKeine" DockPanel.Dock="Right" Content="Keine" Padding="12,4" Margin="6,0,0,0"/>
      <Button Name="BtnAlle" DockPanel.Dock="Right" Content="Alle sichtbaren" Padding="12,4" Margin="6,0,0,0"/>
      <TextBlock DockPanel.Dock="Left" Text="Suche:" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox Name="Suche" VerticalContentAlignment="Center" Padding="4,3"/>
    </DockPanel>

    <TabControl Name="Tabs" Grid.Row="1">
      <TabItem Header="Programme und Apps">
        <DataGrid Name="GridProgramme" AutoGenerateColumns="False" IsReadOnly="True"
                  CanUserAddRows="False" CanUserDeleteRows="False" HeadersVisibility="Column"
                  SelectionMode="Single" GridLinesVisibility="Horizontal"
                  HorizontalGridLinesBrush="#DDDDDD" BorderThickness="0">
          <DataGrid.Columns>
            <DataGridTemplateColumn Width="34" CanUserResize="False">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding Auswahl, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                            HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*"/>
            <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="120"/>
            <DataGridTextColumn Header="Hersteller" Binding="{Binding Hersteller}" Width="190"/>
            <DataGridTextColumn Header="Größe" Binding="{Binding Groesse}" SortMemberPath="GroesseMB" Width="80"/>
            <DataGridTextColumn Header="Typ" Binding="{Binding Typ}" Width="85"/>
            <DataGridTextColumn Header="Still möglich" Binding="{Binding StillText}" Width="170"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem Header="Dienste">
        <DockPanel>
          <CheckBox Name="ChkSystemdienste" DockPanel.Dock="Top" Margin="6"
                    Content="Systemdienste anzeigen (können nur deaktiviert, nicht gelöscht werden)"/>
          <DataGrid Name="GridDienste" AutoGenerateColumns="False" IsReadOnly="True"
                    CanUserAddRows="False" CanUserDeleteRows="False" HeadersVisibility="Column"
                    SelectionMode="Single" GridLinesVisibility="Horizontal"
                    HorizontalGridLinesBrush="#DDDDDD" BorderThickness="0">
            <DataGrid.Columns>
              <DataGridTemplateColumn Width="34" CanUserResize="False">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <CheckBox IsChecked="{Binding Auswahl, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                              HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Dienst" Binding="{Binding Anzeigename}" Width="*"/>
              <DataGridTextColumn Header="Interner Name" Binding="{Binding DienstName}" Width="190"/>
              <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
              <DataGridTextColumn Header="Startart" Binding="{Binding Startart}" Width="100"/>
              <DataGridTemplateColumn Header="Aktion" Width="140" SortMemberPath="Aktion">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <ComboBox SelectedValuePath="Content" IsEnabled="{Binding LoeschenErlaubt}"
                              SelectedValue="{Binding Aktion, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}">
                      <ComboBoxItem Content="Deaktivieren"/>
                      <ComboBoxItem Content="Löschen"/>
                    </ComboBox>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
            </DataGrid.Columns>
          </DataGrid>
        </DockPanel>
      </TabItem>
    </TabControl>

    <Grid Grid.Row="2" Margin="0,8,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="300"/>
      </Grid.ColumnDefinitions>
      <TextBlock Name="Status" Grid.Column="0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <ProgressBar Name="Fortschritt" Grid.Column="1" Height="16" Minimum="0" Maximum="1" Value="0"/>
    </Grid>

    <TextBox Name="Protokoll" Grid.Row="3" IsReadOnly="True" TextWrapping="NoWrap"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas" FontSize="12"/>

    <DockPanel Grid.Row="4" Margin="0,10,0,0" LastChildFill="False">
      <CheckBox Name="ChkSimulieren" DockPanel.Dock="Left" VerticalAlignment="Center"
                Content="Nur simulieren (zeigt die Befehle, entfernt nichts)"/>
      <Button Name="BtnStart" DockPanel.Dock="Right" Content="Ausgewählte entfernen"
              Padding="18,6" FontWeight="SemiBold" Margin="8,0,0,0"/>
      <Button Name="BtnAbbrechen" DockPanel.Dock="Right" Content="Abbrechen" Padding="14,6" IsEnabled="False"/>
    </DockPanel>
  </Grid>
</Window>
'@

$fenster = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Suche', 'BtnAlle', 'BtnKeine', 'BtnAktualisieren', 'Tabs', 'GridProgramme', 'GridDienste',
    'ChkSystemdienste', 'Status', 'Fortschritt', 'Protokoll', 'ChkSimulieren', 'BtnStart', 'BtnAbbrechen') {
    $ui[$n] = $fenster.FindName($n)
}

# --- Datentabellen -----------------------------------------------------------
$dtProg = New-Object System.Data.DataTable
[void]$dtProg.Columns.Add('Id', [int])
[void]$dtProg.Columns.Add('Auswahl', [bool])
foreach ($s in 'Name', 'Version', 'Hersteller', 'Groesse', 'Typ', 'StillText') { [void]$dtProg.Columns.Add($s, [string]) }
[void]$dtProg.Columns.Add('GroesseMB', [double])

$dtDienst = New-Object System.Data.DataTable
[void]$dtDienst.Columns.Add('Id', [int])
[void]$dtDienst.Columns.Add('Auswahl', [bool])
foreach ($s in 'Anzeigename', 'DienstName', 'Status', 'Startart', 'Aktion') { [void]$dtDienst.Columns.Add($s, [string]) }
[void]$dtDienst.Columns.Add('System', [bool])
[void]$dtDienst.Columns.Add('LoeschenErlaubt', [bool])

$ui.GridProgramme.ItemsSource = $dtProg.DefaultView
$ui.GridDienste.ItemsSource = $dtDienst.DefaultView

$script:Programme = @{}   # Id -> Programm-Objekt aus Get-ProgrammListe
$script:Laeuft = $false
$script:Laden = $false
$script:Lauf = $null

# --- Hilfsfunktionen ---------------------------------------------------------
function Write-Protokoll {
    param([string]$Text)
    $zeile = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
    $ui.Protokoll.AppendText($zeile + [Environment]::NewLine)
    $ui.Protokoll.ScrollToEnd()
    try { Add-Content -LiteralPath $script:LogDatei -Value $zeile -Encoding UTF8 } catch { }
}

function ConvertTo-FilterText {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Text.ToCharArray()) {
        if ('[]%*'.IndexOf($c) -ge 0) { [void]$sb.Append('[').Append($c).Append(']') }
        elseif ($c -eq [char]39) { [void]$sb.Append("''") }
        else { [void]$sb.Append($c) }
    }
    $sb.ToString()
}

function Set-Filter {
    $t = ConvertTo-FilterText $ui.Suche.Text.Trim()
    $fProg = ''
    $fDienst = ''
    if ($t) {
        $fProg = "(Name LIKE '%$t%' OR Hersteller LIKE '%$t%')"
        $fDienst = "(Anzeigename LIKE '%$t%' OR DienstName LIKE '%$t%')"
    }
    if (-not $ui.ChkSystemdienste.IsChecked) {
        if ($fDienst) { $fDienst += ' AND ' }
        $fDienst += '(System = false)'
    }
    $dtProg.DefaultView.RowFilter = $fProg
    $dtDienst.DefaultView.RowFilter = $fDienst
}

function Update-Zaehler {
    if ($script:Laeuft -or $script:Laden) { return }
    $p = @($dtProg.Select('Auswahl = true')).Count
    $d = @($dtDienst.Select('Auswahl = true')).Count
    $ui.Status.Text = "Ausgewählt: $p Programme/Apps, $d Dienste"
}

function Update-Listen {
    $fenster.Cursor = [System.Windows.Input.Cursors]::Wait
    $ui.Status.Text = 'Lade Programme und Dienste ...'
    $fenster.Dispatcher.Invoke([Action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
    $script:Laden = $true
    try {
        $dtProg.Clear()
        $dtDienst.Clear()
        $script:Programme = @{}

        $id = 0
        foreach ($p in @(Get-ProgrammListe)) {
            $id++
            $script:Programme[$id] = $p
            $r = $dtProg.NewRow()
            $r['Id'] = $id
            $r['Auswahl'] = $false
            $r['Name'] = [string]$p.Name
            $r['Version'] = [string]$p.Version
            $r['Hersteller'] = [string]$p.Hersteller
            $r['GroesseMB'] = [double]$p.GroesseMB
            if ($p.GroesseMB -gt 0) { $r['Groesse'] = ('{0:N1} MB' -f $p.GroesseMB) } else { $r['Groesse'] = '' }
            $r['Typ'] = [string]$p.Typ
            if ($p.Still) { $r['StillText'] = "Ja ($($p.Art))" } else { $r['StillText'] = 'Nein - wird übersprungen' }
            $dtProg.Rows.Add($r)
        }

        $id = 0
        try { $dienste = @(Get-DienstListe) }
        catch { $dienste = @(); Write-Protokoll "Dienste konnten nicht gelesen werden: $($_.Exception.Message)" }
        foreach ($d in $dienste) {
            $id++
            $r = $dtDienst.NewRow()
            $r['Id'] = $id
            $r['Auswahl'] = $false
            $r['Anzeigename'] = [string]$d.Anzeigename
            $r['DienstName'] = [string]$d.DienstName
            $r['Status'] = [string]$d.Status
            $r['Startart'] = [string]$d.Startart
            $r['Aktion'] = 'Deaktivieren'
            $r['System'] = [bool]$d.System
            $r['LoeschenErlaubt'] = (-not $d.System)
            $dtDienst.Rows.Add($r)
        }
        Write-Protokoll "$($dtProg.Rows.Count) Programme/Apps und $($dtDienst.Rows.Count) Dienste gefunden."
    }
    catch {
        Write-Protokoll "Fehler beim Laden: $($_.Exception.Message)"
    }
    finally {
        $script:Laden = $false
        $fenster.Cursor = $null
        Update-Zaehler
    }
}

function Set-AuswahlSichtbare {
    param([bool]$Wert)
    $tabelle = $dtProg
    if ($ui.Tabs.SelectedIndex -eq 1) { $tabelle = $dtDienst }
    foreach ($zeile in @($tabelle.DefaultView)) { $zeile.Row['Auswahl'] = $Wert }
}

function Set-Bedienbar {
    param([bool]$Frei)
    foreach ($n in 'Suche', 'BtnAlle', 'BtnKeine', 'BtnAktualisieren', 'GridProgramme', 'GridDienste',
        'ChkSystemdienste', 'ChkSimulieren', 'BtnStart') {
        $ui[$n].IsEnabled = $Frei
    }
    $ui.BtnAbbrechen.IsEnabled = (-not $Frei)
}

# --- Hintergrundarbeit -------------------------------------------------------
$arbeitsSkript = @'
param($Aufgaben, $Sync, $LibOrdner, $LogOrdner, $Simulieren)
. (Join-Path $LibOrdner 'Ausfuehrung.ps1')
$i = 0
foreach ($a in $Aufgaben) {
    if ($Sync.Abbruch) {
        $Sync.Meldungen.Enqueue(@{ Art = 'Ergebnis'; Index = $i; Name = $a.Name; Status = 'Abgebrochen'; Detail = ''; Neustart = $false })
        $i++
        continue
    }
    $Sync.Meldungen.Enqueue(@{ Art = 'Start'; Index = $i; Name = $a.Name })
    try { $e = Invoke-Aufgabe -Aufgabe $a -Simulieren $Simulieren -LogOrdner $LogOrdner }
    catch { $e = [pscustomobject]@{ Status = 'Fehler'; Detail = $_.Exception.Message; Neustart = $false } }
    $Sync.Meldungen.Enqueue(@{ Art = 'Ergebnis'; Index = $i; Name = $a.Name; Status = $e.Status; Detail = $e.Detail; Neustart = [bool]$e.Neustart })
    $i++
}
'@

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)

function Start-Lauf {
    param($Aufgaben, [bool]$Simulieren)

    $sync = [hashtable]::Synchronized(@{
            Abbruch   = $false
            Meldungen = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
        })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($arbeitsSkript).AddArgument($Aufgaben).AddArgument($sync).AddArgument($libOrdner).AddArgument($logOrdner).AddArgument($Simulieren)

    $script:Lauf = @{
        Sync       = $sync
        PS         = $ps
        Runspace   = $rs
        Anzahl     = $Aufgaben.Count
        Ergebnisse = New-Object System.Collections.ArrayList
        Simulieren = $Simulieren
        Handle     = $null
    }
    $script:Laeuft = $true
    Set-Bedienbar $false
    $ui.Fortschritt.Maximum = [Math]::Max(1, $Aufgaben.Count)
    $ui.Fortschritt.Value = 0
    if ($Simulieren) { Write-Protokoll "--- Simulation: $($Aufgaben.Count) Einträge ---" }
    else { Write-Protokoll "--- Start: $($Aufgaben.Count) Einträge ---" }

    $script:Lauf.Handle = $ps.BeginInvoke()
    $timer.Start()
}

function Complete-Lauf {
    $lauf = $script:Lauf
    try { [void]$lauf.PS.EndInvoke($lauf.Handle) } catch { Write-Protokoll "Fehler im Ablauf: $($_.Exception.Message)" }
    foreach ($f in @($lauf.PS.Streams.Error)) { Write-Protokoll "Fehler im Ablauf: $f" }
    $lauf.PS.Dispose()
    $lauf.Runspace.Dispose()

    $erg = @($lauf.Ergebnisse)
    $ok = @($erg | Where-Object { @('Entfernt', 'Deaktiviert', 'Gelöscht') -contains $_.Status })
    $manuell = @($erg | Where-Object { $_.Status -eq 'Manuell' })
    $fehler = @($erg | Where-Object { $_.Status -eq 'Fehler' })
    $abgebrochen = @($erg | Where-Object { $_.Status -eq 'Abgebrochen' })
    $simuliert = @($erg | Where-Object { $_.Status -eq 'Simuliert' })
    $neustart = @($erg | Where-Object { $_.Neustart })

    $zeilen = New-Object System.Collections.ArrayList
    if ($lauf.Simulieren) { [void]$zeilen.Add("Simulation beendet - es wurde nichts verändert.") ; [void]$zeilen.Add("Würde ausgeführt: $($simuliert.Count)") }
    else { [void]$zeilen.Add("Erfolgreich: $($ok.Count)") }
    [void]$zeilen.Add("Fehlgeschlagen: $($fehler.Count)")
    [void]$zeilen.Add("Übersprungen (manuell nötig): $($manuell.Count)")
    if ($abgebrochen.Count -gt 0) { [void]$zeilen.Add("Abgebrochen: $($abgebrochen.Count)") }

    if ($fehler.Count -gt 0) {
        [void]$zeilen.Add('')
        [void]$zeilen.Add('Fehlgeschlagen:')
        foreach ($e in ($fehler | Select-Object -First 12)) { [void]$zeilen.Add("  - $($e.Name): $($e.Detail)") }
    }
    if ($manuell.Count -gt 0) {
        [void]$zeilen.Add('')
        [void]$zeilen.Add('Bitte manuell deinstallieren:')
        foreach ($e in ($manuell | Select-Object -First 12)) { [void]$zeilen.Add("  - $($e.Name)") }
    }
    if ($neustart.Count -gt 0) {
        [void]$zeilen.Add('')
        [void]$zeilen.Add('Ein Neustart ist erforderlich, um alles abzuschließen.')
    }
    [void]$zeilen.Add('')
    [void]$zeilen.Add("Protokoll: $script:LogDatei")

    Write-Protokoll '--- Fertig ---'
    $script:Laeuft = $false
    $script:Lauf = $null
    Set-Bedienbar $true
    $ui.Fortschritt.Value = 0

    [void][System.Windows.MessageBox]::Show($fenster, ($zeilen -join [Environment]::NewLine),
        'Apps deinstallieren - Ergebnis', 'OK', 'Information')

    if (-not $lauf.Simulieren) { Update-Listen } else { Update-Zaehler }
}

$timer.add_Tick({
        $lauf = $script:Lauf
        if (-not $lauf) { $timer.Stop(); return }
        $fertig = $lauf.Handle.IsCompleted

        while ($lauf.Sync.Meldungen.Count -gt 0) {
            $m = $lauf.Sync.Meldungen.Dequeue()
            if ($m.Art -eq 'Start') {
                $ui.Status.Text = "($($m.Index + 1) von $($lauf.Anzahl)) $($m.Name) ..."
            }
            else {
                [void]$lauf.Ergebnisse.Add($m)
                $ui.Fortschritt.Value = $lauf.Ergebnisse.Count
                $text = "[$($m.Status)] $($m.Name)"
                if ($m.Detail) { $text += " - $($m.Detail)" }
                Write-Protokoll $text
            }
        }

        if ($fertig) {
            $timer.Stop()
            Complete-Lauf
        }
    })

# --- Ereignisse --------------------------------------------------------------
$ui.Suche.add_TextChanged({ Set-Filter })
$ui.ChkSystemdienste.add_Click({ Set-Filter })
$ui.BtnAlle.add_Click({ Set-AuswahlSichtbare $true })
$ui.BtnKeine.add_Click({ Set-AuswahlSichtbare $false })
$ui.BtnAktualisieren.add_Click({ Update-Listen })
$dtProg.add_ColumnChanged({ Update-Zaehler })
$dtDienst.add_ColumnChanged({ Update-Zaehler })

$ui.BtnAbbrechen.add_Click({
        if ($script:Lauf) {
            $script:Lauf.Sync.Abbruch = $true
            $ui.BtnAbbrechen.IsEnabled = $false
            Write-Protokoll 'Abbruch angefordert - der laufende Eintrag wird noch beendet.'
        }
    })

$ui.BtnStart.add_Click({
        $aufgaben = New-Object System.Collections.ArrayList
        $ohneStill = 0

        foreach ($zeile in $dtProg.Rows) {
            if (-not $zeile['Auswahl']) { continue }
            $p = $script:Programme[[int]$zeile['Id']]
            if (-not $p.Still) { $ohneStill++ }
            [void]$aufgaben.Add(@{
                    Typ       = [string]$p.Typ
                    Name      = [string]$p.Name
                    Still     = [bool]$p.Still
                    Datei     = [string]$p.Datei
                    Argumente = [string]$p.Argumente
                    RegPfad   = [string]$p.RegPfad
                    PaketName = [string]$p.PaketName
                })
        }
        $anzahlProg = $aufgaben.Count

        $loeschen = 0
        foreach ($zeile in $dtDienst.Rows) {
            if (-not $zeile['Auswahl']) { continue }
            $aktion = [string]$zeile['Aktion']
            if (-not [bool]$zeile['LoeschenErlaubt']) { $aktion = 'Deaktivieren' }
            if ($aktion -eq 'Löschen') { $loeschen++ }
            [void]$aufgaben.Add(@{
                    Typ             = 'Dienst'
                    Name            = "Dienst: $($zeile['Anzeigename'])"
                    DienstName      = [string]$zeile['DienstName']
                    Aktion          = $aktion
                    LoeschenErlaubt = [bool]$zeile['LoeschenErlaubt']
                })
        }
        $anzahlDienst = $aufgaben.Count - $anzahlProg

        if ($aufgaben.Count -eq 0) {
            [void][System.Windows.MessageBox]::Show($fenster, 'Es ist nichts ausgewählt.',
                'Apps deinstallieren', 'OK', 'Information')
            return
        }

        $simulieren = [bool]$ui.ChkSimulieren.IsChecked
        if (-not $simulieren) {
            $z = New-Object System.Collections.ArrayList
            [void]$z.Add("$anzahlProg Programme/Apps deinstallieren")
            [void]$z.Add("$anzahlDienst Dienste bearbeiten (davon $loeschen löschen)")
            if ($ohneStill -gt 0) {
                [void]$z.Add("$ohneStill Programme ohne stillen Modus werden übersprungen")
            }
            [void]$z.Add('')
            foreach ($a in ($aufgaben | Select-Object -First 15)) { [void]$z.Add("  - $($a.Name)") }
            if ($aufgaben.Count -gt 15) { [void]$z.Add("  ... und $($aufgaben.Count - 15) weitere") }
            [void]$z.Add('')
            [void]$z.Add('Jetzt ohne weitere Rückfragen ausführen?')

            $antwort = [System.Windows.MessageBox]::Show($fenster, ($z -join [Environment]::NewLine),
                'Apps deinstallieren - Bestätigung', 'YesNo', 'Warning', 'No')
            if ($antwort -ne 'Yes') { return }
        }

        Start-Lauf -Aufgaben $aufgaben -Simulieren $simulieren
    })

$fenster.add_Closing({
        param($absender, $e)
        if ($script:Laeuft) {
            $e.Cancel = $true
            [void][System.Windows.MessageBox]::Show($fenster,
                'Es läuft noch eine Deinstallation. Bitte warten oder zuerst "Abbrechen" wählen.',
                'Apps deinstallieren', 'OK', 'Information')
        }
    })

$fenster.add_ContentRendered({ Set-Filter; Update-Listen })

try {
    [void]$fenster.ShowDialog()
}
catch {
    [void][System.Windows.MessageBox]::Show("Unerwarteter Fehler:`n$($_.Exception.Message)",
        'Apps deinstallieren', 'OK', 'Error')
}
