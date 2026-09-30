$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR4 {
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

$r = New-Object SXR4+R
[void][SXR4]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
Write-Output ("rect=" + $r.L + "," + $r.T + " " + ($r.Rt-$r.L) + "x" + ($r.B-$r.T))

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bm = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
$g = [System.Drawing.Graphics]::FromImage($bm)
$g.CopyFromScreen($vs.X, $vs.Y, 0, 0, $bm.Size)
$g.Dispose()
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$bm.Save("$dir\desktop9.png", [System.Drawing.Imaging.ImageFormat]::Png)

# recorte em volta da janela
$px = [Math]::Max(0, $r.L - 40); $py = [Math]::Max(0, $r.T - 40)
$pw = [Math]::Min($vs.Width - ($px - $vs.X), ($r.Rt - $r.L) + 80)
$ph = [Math]::Min($vs.Height - ($py - $vs.Y), ($r.B - $r.T) + 80)
$rect = New-Object System.Drawing.Rectangle($px - $vs.X, $py - $vs.Y, $pw, $ph)
$crop = $bm.Clone($rect, $bm.PixelFormat)
$crop.Save("$dir\desktop9_app.png", [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $bm.Dispose()
$global:Form.Hide()
Write-Output 'ok'
