Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class MH {
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$p = Get-Process powershell -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowTitle -like 'TI Suite*' } | Select-Object -First 1
if (-not $p) { Write-Output 'app nao encontrado'; exit 1 }
Write-Output ('pid=' + $p.Id + ' titulo=' + $p.MainWindowTitle)
$r = New-Object MH+R
[void][MH]::GetWindowRect($p.MainWindowHandle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$bmp.Save("$dir\real_now.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ('capturado ' + $w + 'x' + $h + ' em ' + (Get-Date -Format 'HH:mm:ss'))
$log = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log'
Write-Output ('exceptions.log len=' + (Get-Item $log).Length)
