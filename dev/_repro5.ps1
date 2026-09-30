Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
. '.\src\Core\00-Controls.ps1'

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(100, 100)
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

$flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Public
$t = [System.Windows.Forms.ScrollableControl]
foreach ($name in @('vscroll','hscroll','displayRect','displayRectStarted','autoScroll')) {
    $fi = $t.GetField($name, $flags)
    if ($null -eq $fi) { Write-Output ("campo {0}: INEXISTENTE" -f $name); continue }
    $val = $fi.GetValue($flow)
    if ($val -is [System.Windows.Forms.Control]) {
        Write-Output ("campo {0}: Control tipo={1} hasHandle={2} visible={3} parentNull={4} bounds={5}" -f $name, $val.GetType().Name, $val.IsHandleCreated, $val.Visible, ($null -eq $val.Parent), $val.Bounds)
        if ($val.IsHandleCreated) {
            Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class R6 {
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
}
"@
            $sb = New-Object System.Text.StringBuilder 200
            [void][R6]::GetClassName($val.Handle, $sb, 200)
            $par = [R6]::GetParent($val.Handle)
            $r = New-Object R6+R; [void][R6]::GetWindowRect($val.Handle, [ref]$r)
            Write-Output ("   hwnd=0x{0:X} class={1} parent=0x{2:X} winVisible={3} rect={4},{5} {6}x{7}" -f $val.Handle.ToInt64(), $sb, $par.ToInt64(), [R6]::IsWindowVisible($val.Handle), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T))
        }
    } elseif ($val -is [System.Drawing.Rectangle]) {
        Write-Output ("campo {0}: Rectangle {1}" -f $name, $val)
    } else {
        Write-Output ("campo {0}: {1}" -f $name, $val)
    }
}
# VerticalScroll wrapper
$vs = $flow.VerticalScroll
Write-Output ('VerticalScroll.Visible=' + $vs.Visible + ' Value=' + $vs.Value + ' Maximum=' + $vs.Maximum + ' LargeChange=' + $vs.LargeChange)
$f.Close(); $f.Dispose()
Write-Output 'ok'
