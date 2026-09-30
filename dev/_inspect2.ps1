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

$global:Form.Show()
$global:Form.Activate()

for ($i = 0; $i -lt 60; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }

Write-Output '=== NAV ITEMS (reflexao) ==='
foreach ($c in $global:NavFlow.Controls) {
    $it = $c
    Write-Output ('  ItemText={0} Active={1} bounds={2},{3} {4}x{5} Visible={6}' -f $it.ItemText, $it.Active, $it.Left, $it.Top, $it.Width, $it.Height, $it.Visible)
}

Write-Output '=== HEADER ACTIONS ==='
foreach ($ch in $global:HeaderActions.Controls) {
    Write-Output ('  {0} text={1} bounds={2},{3} {4}x{5} vis={6}' -f $ch.GetType().Name, $ch.Text, $ch.Left, $ch.Top, $ch.Width, $ch.Height, $ch.Visible)
}
Write-Output '=== CAPTION/OUTROS BOTOES NO HEADER ==='
$hdrPanel = $global:HeaderActions.Parent
foreach ($ch in $hdrPanel.Controls) {
    Write-Output ('  {0} text={1} bounds={2},{3} {4}x{5}' -f $ch.GetType().Name, ($ch.Text -replace "`r?`n",' '), $ch.Left, $ch.Top, $ch.Width, $ch.Height)
    foreach ($g in $ch.Controls) { Write-Output ('     filho: {0} text={1} bounds={2},{3} {4}x{5}' -f $g.GetType().Name, $g.Text, $g.Left, $g.Top, $g.Width, $g.Height) }
}

Write-Output '=== BOTOES DA BARRA DO CONSOLE ==='
function Find-Buttons($c, $depth) {
    if ($depth -gt 6) { return }
    foreach ($ch in $c.Controls) {
        if ($ch.GetType().Name -eq 'PremiumButton') { Write-Output ('  console-btn: text={0} bounds={1},{2} {3}x{4} parent={5}' -f $ch.Text, $ch.Left, $ch.Top, $ch.Width, $ch.Height, $ch.Parent.GetType().Name) }
        Find-Buttons $ch ($depth + 1)
    }
}
Find-Buttons $global:Form 0

Write-Output '=== CAPTURA ==='
Add-Type @"
using System;using System.Runtime.InteropServices;
public class R2{[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RR r);[StructLayout(LayoutKind.Sequential)]public struct RR{public int L,T,Rt,B;}}
"@
$r = New-Object R2+RR
[void][R2]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$out = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\fresh.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("captura: " + $out + " em " + $r.L + "," + $r.T)

$global:Form.Hide()
