$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SXR2 {
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

function Shot($name, $scale) {
    $r = New-Object SXR2+R
    [void][SXR2]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
    $w = $r.Rt - $r.L; $h = $r.B - $r.T
    $sw = [int]($w * $scale); $sh = [int]($h * $scale)
    $bmp = New-Object System.Drawing.Bitmap($sw, $sh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    if ($scale -eq 1.0) { $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h))) }
    else { $g.DrawImage((New-Object System.Drawing.Bitmap(($tmp = $null))), 0, 0) }
    $g.Dispose(); $bmp.Dispose()
}
# shot A e B: duas capturas iguais com 1s de intervalo
foreach ($n in @('capA','capB')) {
    $r = New-Object SXR2+R
    [void][SXR2]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$r)
    $w = $r.Rt - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    $bmp.Save("C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\$n.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Start-Sleep -Milliseconds 1000
    Write-Output "shot $n ok"
}
# comparar pixels da regiao da sidebar entre A e B
$a = [System.Drawing.Bitmap]::FromFile('C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\capA.png')
$b = [System.Drawing.Bitmap]::FromFile('C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\capB.png')
$diff = 0
for ($y = 150; $y -lt 340; $y += 2) {
    for ($x = 0; $x -lt 230; $x += 2) {
        if ($a.GetPixel($x,$y).ToArgb() -ne $b.GetPixel($x,$y).ToArgb()) { $diff++ }
    }
}
Write-Output ("pixeis diferentes entre A e B na sidebar: " + $diff)
$a.Dispose(); $b.Dispose()
$global:Form.Hide()
