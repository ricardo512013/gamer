$env:TI_SUITE_QUIET = '1'
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$logPath = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log'
$baseLen = if (Test-Path $logPath) { (Get-Item $logPath).Length } else { 0 }
Write-Output ('exceptions.log baseline len=' + $baseLen)
$proc = Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\flaviosantos\Desktop\Piaget CleanDesk\TI-Suite.ps1" -NoElevate' -PassThru
Write-Output ("pid=" + $proc.Id)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SQ {
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern IntPtr FindWindow(string c,string n);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 80 -and $h -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 500
  $proc.Refresh()
  if (-not $proc.HasExited -and $proc.MainWindowTitle -like 'TI Suite*') { $h = $proc.MainWindowHandle }
}
if ($h -eq [IntPtr]::Zero) { Write-Output 'JANELA NAO ENCONTROU'; exit 1 }
Write-Output 'janela encontrada'

function Shot($name) {
  $r = New-Object SQ+R
  [void][SQ]::GetWindowRect($h, [ref]$r)
  $w = $r.Rt - $r.L; $ht = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
  $g.Dispose()
  $bmp.Save("$dir\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output ("shot $name " + (Get-Date -Format 'HH:mm:ss.fff'))
}

Start-Sleep -Seconds 4;  Shot 'real_t04'
Start-Sleep -Seconds 8;  Shot 'real_t12'
Start-Sleep -Seconds 15; Shot 'real_t27'
Start-Sleep -Seconds 20; Shot 'real_t47'
$cpu1 = $proc.TotalProcessorTime
Start-Sleep -Seconds 5
$proc.Refresh()
$cpu2 = $proc.TotalProcessorTime
Write-Output ("cpu5s=" + [Math]::Round(($cpu2 - $cpu1).TotalMilliseconds) + "ms  running=" + (-not $proc.HasExited))
$len = if (Test-Path $logPath) { (Get-Item $logPath).Length } else { 0 }
Write-Output ('exceptions.log novo tamanho=' + $len + ' (delta=' + ($len - $baseLen) + ')')
