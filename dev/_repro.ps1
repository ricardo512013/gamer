Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
. '.\src\Core\00-Controls.ps1'

Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class RE {
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
 public static List<string> Rows = new List<string>();
}
"@

function Dump-Kids($h, $label) {
    [RE]::Rows.Clear()
    [void][RE]::EnumChildWindows($h, [RE+EnumProc]{ param($x,$l)
        $r = New-Object RE+R
        if ([RE]::GetWindowRect($x,[ref]$r)) {
            $sb = New-Object System.Text.StringBuilder 200
            [void][RE]::GetClassName($x,$sb,200)
            [void][RE]::Rows.Add(('  cls={0} vis={1} rect={2},{3} {4}x{5}' -f $sb, [RE]::IsWindowVisible($x), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T)))
        }
        return $true }, [IntPtr]::Zero)
    Write-Output ($label + ' (' + [RE]::Rows.Count + '):')
    [RE]::Rows | ForEach-Object { Write-Output $_ }
}

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(50, 50)
$f.Size = New-Object System.Drawing.Size(800, 600)
$f.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)

$content = New-Object System.Windows.Forms.Panel   # BackColor default F0F0F0 (igual app real)
$content.Dock = 'Fill'
$f.Controls.Add($content)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 64
$header.BackColor = [System.Drawing.Color]::Transparent
$content.Controls.Add($header)

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
Start-Sleep -Milliseconds 300
[System.Windows.Forms.Application]::DoEvents()
Write-Output ('flow.Handle=0x{0:X}  form.Handle=0x{1:X}' -f $flow.Handle, $f.Handle)
Write-Output ('flow.VerticalScroll.Visible=' + $flow.VerticalScroll.Visible)
Dump-Kids $flow.Handle '--- filhos do FLOW (pos OnLayout +300ms) ---'
Start-Sleep -Milliseconds 1500   # deixa o timer de 120ms rodar
Dump-Kids $flow.Handle '--- filhos do FLOW (apos 1.5s com timer) ---'
Write-Output ('flow.VerticalScroll.Visible=' + $flow.VerticalScroll.Visible)

# captura a faixa direita do form
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(800, 600)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
Add-Type @"
using System;using System.Runtime.InteropServices;
public class PWR { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f); }
"@
[void][PWR]::PrintWindow($f.Handle, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\repro_strip.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output '--- pixel linha y=300, x=775..799 ---'
for ($x = 775; $x -lt 800; $x++) {
    $c = $bmp.GetPixel($x, 300)
    Write-Output ('x={0} = {1},{2},{3}' -f $x, $c.R, $c.G, $c.B)
}
$bmp.Dispose()
$f.Close()
$f.Dispose()
Write-Output 'repro concluido'
