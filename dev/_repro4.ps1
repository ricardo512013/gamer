Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
. '.\src\Core\00-Controls.ps1'
Add-Type @"
using System;using System.Runtime.InteropServices;
public class R5 {
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
}
"@

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(2200, 300)   # monitor 2
$f.Size = New-Object System.Drawing.Size(800, 600)
$f.BackColor = [System.Drawing.Color]::Lime

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = [System.Drawing.Color]::Red
$f.Controls.Add($content)

$flow = New-Object TISuite.TIScrollFlow
$flow.Dock = 'Fill'
$flow.FlowDirection = 'LeftToRight'
$flow.WrapContents = $true
$flow.AutoScroll = $true
$flow.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)
$flow.Padding = New-Object System.Windows.Forms.Padding(24,20,24,24)
$content.Controls.Add($flow)

for ($i = 0; $i -lt 12; $i++) {
    $c = New-Object System.Windows.Forms.Panel
    $c.Size = New-Object System.Drawing.Size(220, 160)
    $c.BackColor = [System.Drawing.Color]::FromArgb(30,41,59)
    $flow.Controls.Add($c)
}
$f.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 1000

$r = New-Object R5+R
[void][R5]::GetWindowRect($f.Handle, [ref]$r)
Write-Output ('window rect = {0},{1} {2}x{3}' -f $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T))

Add-Type -AssemblyName System.Drawing
foreach ($flag in @(2, 0)) {
    $bmp = New-Object System.Drawing.Bitmap(800, 600)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [R5]::PrintWindow($f.Handle, $hdc, [uint32]$flag)
    $g.ReleaseHdc($hdc); $g.Dispose()
    Write-Output ('--- flag={0} ok={1} y=300 x=778..799 ---' -f $flag, $ok)
    for ($x = 778; $x -lt 800; $x++) {
        $c = $bmp.GetPixel($x, 300)
        Write-Output ('x={0} = {1},{2},{3}' -f $x, $c.R, $c.G, $c.B)
    }
    $bmp.Dispose()
}
$f.Close(); $f.Dispose()
Write-Output 'ok'
