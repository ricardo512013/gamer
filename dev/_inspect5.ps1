$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR {
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$core = Join-Path $global:TIRoot 'src\Core'
$wsp  = Join-Path $global:TIRoot 'src\Workspaces'
foreach ($n in @('00-Controls.ps1','01-Theme.ps1','02-Dialogs.ps1','03-Logging.ps1','04-Async.ps1','05-Shell.ps1')) { . (Join-Path $core $n) }
foreach ($n in @('Dashboard.ps1','Limpeza.ps1','Contas.ps1','Rede.ps1')) { . (Join-Path $wsp $n) }
Start-TIApp
$global:Form.Show(); $global:Form.Activate()
for ($i = 0; $i -lt 25; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
Write-Output ('DwmRounded=' + $global:DwmRounded + ' Region=' + $(if ($global:Form.Region) { 'SET' } else { 'null' }) + ' Opacity=' + $global:Form.Opacity)

function Shot($name) {
    $r = New-Object SXR+R
    [void][SXR]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
    $w = $r.Rt - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    $bmp.Save("C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("shot: $name")
}
Shot 'screen_with_region'
$global:Form.Region = $null
$global:Form.Invalidate()
[void][System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 600
Shot 'screen_no_region'
$global:Form.Hide()
