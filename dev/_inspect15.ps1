$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $global:TIRoot 'src\Core\00-Controls.ps1')
. (Join-Path $global:TIRoot 'src\Core\01-Theme.ps1')
. (Join-Path $global:TIRoot 'src\Core\02-Dialogs.ps1')
. (Join-Path $global:TIRoot 'src\Core\03-Logging.ps1')
. (Join-Path $global:TIRoot 'src\Core\04-Async.ps1')
foreach ($n in @('Dashboard','Limpeza','Contas','Rede')) { . (Join-Path $global:TIRoot ('src\Workspaces\' + $n + '.ps1')) }
foreach ($t in @('TISuite.SidebarItem','TISuite.PremiumButton','TISuite.ToggleSwitch','TISuite.FlatProgress','TISuite.ArcSpinner','TISuite.RoundPanel')) {
  $c = [Activator]::CreateInstance([type]$t)
  $bc = $c.BackColor
  $isT = ($bc.ToArgb() -eq [System.Drawing.Color]::Transparent.ToArgb())
  Write-Output ("{0}: BackColor={1} transparent={2}" -f $t, $bc.ToArgb().ToString('X8'), $isT)
  $c.Dispose()
}
Write-Output '--- excecoes recentes ---'
$log = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log'
if (Test-Path $log) { Get-Content $log -Tail 15 } else { 'sem exceptions.log' }
