$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR5 {
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
for ($i = 0; $i -lt 30; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }

$r = New-Object SXR5+R
[void][SXR5]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'

function Cap($name) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose(); $bmp.Save("$dir\$name.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output "cap $name"
}
Cap 'before_full'
$global:Form.Invalidate($true)
[void][System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 500
Cap 'after_full'
# segunda invalidacao (a primeira pode nao ter processado os filhos)
$global:Form.Refresh()
Start-Sleep -Milliseconds 500
Cap 'after_refresh'
$global:Form.Hide()
