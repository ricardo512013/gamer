$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR3 {
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("dwmapi.dll")]public static extern int DwmSetWindowAttribute(IntPtr h,int a,ref int v,int s);
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

$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'

# 1) desktop inteiro
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bm = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
$g = [System.Drawing.Graphics]::FromImage($bm)
$g.CopyFromScreen($vs.X, $vs.Y, 0, 0, $bm.Size)
$g.Dispose(); $bm.Save("$dir\desktop.png", [System.Drawing.Imaging.ImageFormat]::Png); $bm.Dispose()

# 2) PrintWindow sem flag (WM_PRINT)
$h = [IntPtr]$global:Form.Handle
$r = New-Object SXR3+R
[void][SXR3]::GetWindowRect($h, [ref]$r)
$w = $r.Rt - $r.L; $hgt = $r.B - $r.T
$bm = New-Object System.Drawing.Bitmap($w, $hgt)
$g = [System.Drawing.Graphics]::FromImage($bm)
$hdc = $g.GetHdc()
[void][SXR3]::PrintWindow($h, $hdc, 0)
$g.ReleaseHdc($hdc); $g.Dispose()
$bm.Save("$dir\pw0.png", [System.Drawing.Imaging.ImageFormat]::Png); $bm.Dispose()

# 3) desabilita cantos arredondados DWM + repinta + captura
$on = 0
[void][SXR3]::DwmSetWindowAttribute($h, 33, [ref]$on, 4)
$global:DwmRounded = $false
$global:Form.Invalidate()
for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 60 }
$bm = New-Object System.Drawing.Bitmap($w, $hgt)
$g = [System.Drawing.Graphics]::FromImage($bm)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $hgt)))
$g.Dispose(); $bm.Save("$dir\screen_noround.png", [System.Drawing.Imaging.ImageFormat]::Png); $bm.Dispose()

Write-Output ("rounded_off, region=" + $(if ($global:Form.Region) {'SET'} else {'null'}))
$global:Form.Hide()
