Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
. '.\src\Core\00-Controls.ps1'
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class R2 {
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string cls, string title);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
}
"@

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(50, 50)
$f.Size = New-Object System.Drawing.Size(800, 600)
$f.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
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

Write-Output ('flow.Controls count = ' + $flow.Controls.Count)
foreach ($ch in $flow.Controls) {
    Write-Output ('  managed: ' + $ch.GetType().FullName + ' vis=' + $ch.Visible + ' bounds=' + $ch.Bounds + ' hasHandle=' + $ch.IsHandleCreated)
}
$vs = $flow.VerticalScroll
Write-Output ('VerticalScroll type=' + $vs.GetType().FullName + ' vis=' + $vs.Visible + ' hasHandle=' + $vs.IsHandleCreated + ' bounds=' + $vs.Bounds)
if ($vs.IsHandleCreated) {
    $sb = New-Object System.Text.StringBuilder 200
    [void][R2]::GetClassName($vs.Handle, $sb, 200)
    $par = [R2]::GetParent($vs.Handle)
    $r = New-Object R2+R; [void][R2]::GetWindowRect($vs.Handle, [ref]$r)
    Write-Output ('  VSCROLLBAR hwnd=0x{0:X} class={1} parent=0x{2:X} vis={3} rect={4},{5} {6}x{7}' -f `
        $vs.Handle.ToInt64(), $sb, $par.ToInt64(), [R2]::IsWindowVisible($vs.Handle), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T))
}
# EnumChildWindows direto
$rows = New-Object System.Collections.ArrayList
Add-Type @"
using System;using System.Collections.Generic;using System.Runtime.InteropServices;
public class R3 {
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
}
"@
[void][R3]::EnumChildWindows($flow.Handle, [R3+EnumProc]{ param($h,$l)
    $sb = New-Object System.Text.StringBuilder 200
    [void][R3]::GetClassName($h,$sb,200)
    $p = [R3]::GetParent($h)
    [void]$script:rows.Add(('    native: h=0x{0:X} class={1} parent=0x{2:X}' -f $h.ToInt64(), $sb, $p.ToInt64()))
    return $true }, [IntPtr]::Zero)
Write-Output ('EnumChildWindows(flow) = ' + $rows.Count)
$rows | ForEach-Object { Write-Output $_ }
$f.Close(); $f.Dispose()
Write-Output 'ok'
