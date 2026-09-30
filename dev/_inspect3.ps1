$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
$core = Join-Path $global:TIRoot 'src\Core'
$wsp  = Join-Path $global:TIRoot 'src\Workspaces'
foreach ($n in @('00-Controls.ps1','01-Theme.ps1','02-Dialogs.ps1','03-Logging.ps1','04-Async.ps1','05-Shell.ps1')) { . (Join-Path $core $n) }
foreach ($n in @('Dashboard.ps1','Limpeza.ps1','Contas.ps1','Rede.ps1')) { . (Join-Path $wsp $n) }
Start-TIApp
$global:Form.Show(); $global:Form.Activate()
for ($i = 0; $i -lt 40; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }

function Walk($c, $path) {
    $t = ''
    try { $t = $c.Text } catch { }
    $it = $null
    try { $it = $c.ItemText } catch { }
    $label = if ($it) { $it } else { $t }
    $b = $c.Bounds
    $screen = $c.PointToScreen([System.Drawing.Point]::Empty)
    $global:Found.Add([pscustomobject]@{ Type=$c.GetType().Name; Label=$label; Path=$path; ScreenX=$screen.X; ScreenY=$screen.Y; W=$b.Width; H=$b.Height; Parent=$c.Parent.GetType().Name })
    foreach ($ch in $c.Controls) { Walk $ch ($path + '/' + $c.GetType().Name) }
}
$global:Found = New-Object System.Collections.ArrayList
Walk $global:Form 'Form'

Write-Output '=== controles com Label/Text = Inicio ==='
$global:Found | Where-Object { $_.Label -match 'Inicio|InÃ­cio' } | ForEach-Object { "  {0} '{1}' screen=({2},{3}) {4}x{5} parent={6} path={7}" -f $_.Type, $_.Label, $_.ScreenX, $_.ScreenY, $_.W, $_.H, $_.Parent, $_.Path }

Write-Output '=== todos os controles na regiao da sidebar (x<240, y 120..340) ==='
$global:Found | Where-Object { $_.ScreenX -ge 0 -and $_.ScreenX -lt 240 -and $_.ScreenY -ge 240 -and $_.ScreenY -lt 520 } | ForEach-Object { "  {0} '{1}' screen=({2},{3}) {4}x{5} parent={6}" -f $_.Type, $_.Label, $_.ScreenX, $_.ScreenY, $_.W, $_.H, $_.Parent }

Write-Output '=== SidebarItem no documento todo ==='
$global:Found | Where-Object { $_.Type -eq 'SidebarItem' } | ForEach-Object { "  '{0}' screen=({1},{2}) parent={3}" -f $_.Label, $_.ScreenX, $_.ScreenY, $_.Parent }

Write-Output '=== PremiumButton "Exportar relatorio" ==='
$global:Found | Where-Object { $_.Label -eq 'Exportar relatorio' } | ForEach-Object { "  screen=({0},{1}) {2}x{3} parent={4}" -f $_.ScreenX, $_.ScreenY, $_.W, $_.H, $_.Parent }

$global:Form.Hide()
