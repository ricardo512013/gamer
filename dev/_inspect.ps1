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

function Dump-Tree($c, $depth, $maxDepth) {
    if ($depth -gt $maxDepth) { return }
    $pad = '  ' * $depth
    $txt = ''
    try { $txt = $c.Text } catch { }
    if ($txt) { $txt = $txt -replace "`r?`n", ' ' }
    $b = $c.Bounds
    '{0}{1} [{2}x{3} @ {4},{5}] {6}' -f $pad, $c.GetType().Name, $b.Width, $b.Height, $b.X, $b.Y, $txt | Write-Output
    foreach ($ch in $c.Controls) { Dump-Tree $ch ($depth + 1) $maxDepth }
}

'=== SIDEBAR/NAV ==='
$nav = $global:NavFlow
'navFlow: ' + $nav.GetType().Name + ' children=' + $nav.Controls.Count + ' dock=' + $nav.Dock + ' autosize=' + $nav.AutoSize + ' size=' + $nav.Width + 'x' + $nav.Height
foreach ($c in $nav.Controls) { '   navItem: y=' + $c.Top + ' h=' + $c.Height + ' w=' + $c.Width + " text='" + $c.Text + "'" }

'=== HEADER (nivel 1) ==='
$root = $global:Form.Controls[0]
Dump-Tree $global:Form 0 4
