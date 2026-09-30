Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
. '.\src\Core\00-Controls.ps1'
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class R4 {
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
}
"@

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(50, 50)
$f.Size = New-Object System.Drawing.Size(800, 600)
$f.BackColor = [System.Drawing.Color]::Lime      # FORM = verde

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = [System.Drawing.Color]::Red  # CONTENT = vermelho
$f.Controls.Add($content)

$flow = New-Object TISuite.TIScrollFlow
$flow.Dock = 'Fill'
$flow.FlowDirection = 'LeftToRight'
$flow.WrapContents = $true
$flow.AutoScroll = $true
$flow.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)
$flow.Padding = New-Object System.Windows.Forms.Padding(24,20,24,24)
$flow.Add_Layout({ try { $this.VerticalScroll.Visible = $false } catch {} })
$content.Controls.Add($flow)

for ($i = 0; $i -lt 12; $i++) {
    $c = New-Object System.Windows.Forms.Panel
    $c.Size = New-Object System.Drawing.Size(220, 160)
    $c.BackColor = [System.Drawing.Color]::FromArgb(30,41,59)
    $flow.Controls.Add($c)
}
$f.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800
[System.Windows.Forms.Application]::DoEvents()

Write-Output ('form.Bounds=' + $f.Bounds + ' client=' + $f.ClientSize)
Write-Output ('content.Bounds=' + $content.Bounds + ' content.BackColor=' + $content.BackColor)
Write-Output ('flow.Bounds=' + $flow.Bounds)
$style = [R4]::GetWindowLong($f.Handle, -16)   # GWL_STYLE
Write-Output ('form GWL_STYLE=0x{0:X8} WS_VSCROLL={1} WS_HSCROLL={2} WS_CAPTION={3}' -f $style, (($style -band 0x00200000) -ne 0), (($style -band 0x00100000) -ne 0), (($style -band 0x00C00000) -ne 0))

$rows = New-Object System.Collections.ArrayList
[void][R4]::EnumChildWindows($f.Handle, [R4+EnumProc]{ param($h,$l)
    $r = New-Object R4+R
    if ([R4]::GetWindowRect($h,[ref]$r)) {
        $sb = New-Object System.Text.StringBuilder 200
        [void][R4]::GetClassName($h,$sb,200)
        [void]$script:rows.Add(('  h=0x{0:X} cls={1} vis={2} rect={3},{4} {5}x{6}' -f $h.ToInt64(), $sb, [R4]::IsWindowVisible($h), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T)))
    }
    return $true }, [IntPtr]::Zero)
Write-Output ('descendants do form: ' + $rows.Count)
$rows | ForEach-Object { Write-Output $_ }

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(800, 600)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][R4]::PrintWindow($f.Handle, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
Write-Output '--- strip x=780..799 y=300 (form=lime, content=red, flow=dark) ---'
for ($x = 780; $x -lt 800; $x++) {
    $c = $bmp.GetPixel($x, 300)
    Write-Output ('x={0} = {1},{2},{3}' -f $x, $c.R, $c.G, $c.B)
}
Write-Output '--- header y=30, x=780..799 ---'
for ($x = 780; $x -lt 800; $x++) {
    $c = $bmp.GetPixel($x, 30)
    Write-Output ('x={0} = {1},{2},{3}' -f $x, $c.R, $c.G, $c.B)
}
$bmp.Dispose()
$f.Close(); $f.Dispose()
Write-Output 'ok'
