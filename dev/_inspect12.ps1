$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class CW {
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
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

$h = [IntPtr]$global:Form.Handle
$script:hw = New-Object System.Collections.ArrayList
$cb = [CW+EnumProc]{ param($ch,$l)
  $sb1 = New-Object System.Text.StringBuilder 120
  [void][CW]::GetClassName($ch,$sb1,120)
  $sb2 = New-Object System.Text.StringBuilder 200
  [void][CW]::GetWindowText($ch,$sb2,200)
  $r = New-Object CW+R; [void][CW]::GetWindowRect($ch,[ref]$r)
  $rb = New-Object CW+R; [void][CW]::GetWindowRect([IntPtr]$global:Form.Handle,[ref]$rb)
  $rel = "" + ($r.L - $rb.L) + "," + ($r.T - $rb.T) + " " + ($r.Rt-$r.L) + "x" + ($r.B-$r.T)
  [void]$script:hw.Add(("cls={0} vis={1} rel={2} txt='{3}'" -f $sb1.ToString(), [CW]::IsWindowVisible($ch), $rel, $sb2.ToString()))
  return $true
}
[void][CW]::EnumChildWindows($h,$cb,[IntPtr]::Zero)
Write-Output ("janelas-filhas nativas (EnumChildWindows): " + $script:hw.Count)
$script:hw

# arvore WinForms
function Walk($c, $d) {
  foreach ($ch in $c.Controls) {
    Write-Output (("  " * $d) + $ch.GetType().Name + " '" + $ch.Name + "' " + $ch.Bounds + " vis=" + $ch.Visible + " hwnd=" + $ch.IsHandleCreated)
    if ($ch.HasChildren) { Walk $ch ($d + 1) }
  }
}
Write-Output '--- arvore WinForms ---'
Walk $global:Form 0
$global:Form.Hide()
