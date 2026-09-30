$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR7 {
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

$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$r = New-Object SXR7+R
[void][SXR7]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T

$bmpS = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmpS)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$bmpD = New-Object System.Drawing.Bitmap($w, $h)
$global:Form.DrawToBitmap($bmpD, (New-Object System.Drawing.Rectangle(0,0,$w,$h)))

$bmpS.Save("$dir\d_screen.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmpD.Save("$dir\d_draw.png", [System.Drawing.Imaging.ImageFormat]::Png)

# mapa de diferenca
$diff = New-Object System.Drawing.Bitmap($w, $h)
$xs = New-Object System.Collections.ArrayList
$ys = New-Object System.Collections.ArrayList
for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    $ps = $bmpS.GetPixel($x,$y).ToArgb(); $pd = $bmpD.GetPixel($x,$y).ToArgb()
    if ([Math]::Abs((($ps -band 0xFF0000) -shr 16) - (($pd -band 0xFF0000) -shr 16)) -gt 40) {
      $diff.SetPixel($x, $y, [System.Drawing.Color]::Red)
      [void]$xs.Add($x); [void]$ys.Add($y)
    } else {
      $diff.SetPixel($x, $y, $bmpD.GetPixel($x,$y))
    }
  }
}
$diff.Save("$dir\d_map.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("pixels divergentes (vermelho): " + $xs.Count)
if ($xs.Count -gt 0) {
  Write-Output ("bbox: x=" + ($xs | Measure-Object -Minimum).Minimum + ".." + ($xs | Measure-Object -Maximum).Maximum + " y=" + ($ys | Measure-Object -Minimum).Minimum + ".." + ($ys | Measure-Object -Maximum).Maximum)
  # histograma por faixa y de 40px
  $hist = @{}
  for ($i = 0; $i -lt $ys.Count; $i++) { $b = [int][Math]::Floor($ys[$i] / 40) * 40; $hist[$b] = [int]$hist[$b] + 1 }
  $hist.GetEnumerator() | Sort-Object Name | ForEach-Object { "y {0}-{1}: {2}" -f $_.Key, ($_.Key+39), $_.Value }
}
$bmpS.Dispose(); $bmpD.Dispose(); $diff.Dispose()
$global:Form.Hide()
