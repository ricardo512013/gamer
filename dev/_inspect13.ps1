$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class CW2 {
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
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

# handles WinForms
$wf = New-Object 'System.Collections.Generic.HashSet[string]'
function Collect($c) {
  foreach ($ch in $c.Controls) {
    if ($ch.IsHandleCreated) { [void]$wf.Add($ch.Handle.ToString()) }
    if ($ch.HasChildren) { Collect $ch }
  }
}
Collect $global:Form
Write-Output ("controles WinForms com handle: " + $wf.Count)

$script:nat = New-Object System.Collections.ArrayList
$cb = [CW2+EnumProc]{ param($ch,$l)
  [void]$script:nat.Add($ch)
  return $true
}
[void][CW2]::EnumChildWindows([IntPtr]$global:Form.Handle,$cb,[IntPtr]::Zero)
Write-Output ("janelas nativas filhas: " + $script:nat.Count)

$rb = New-Object CW2+R; [void][CW2]::GetWindowRect([IntPtr]$global:Form.Handle,[ref]$rb)
Write-Output '--- ORFAOS (nativas sem controle WinForms correspondente) ---'
$orphans = 0
foreach ($h in $script:nat) {
  if (-not $wf.Contains($h.ToString())) {
    $orphans++
    $sb = New-Object System.Text.StringBuilder 120
    [void][CW2]::GetClassName($h,$sb,120)
    $r = New-Object CW2+R; [void][CW2]::GetWindowRect($h,[ref]$r)
    Write-Output ("ORFAO cls=" + $sb.ToString() + " vis=" + [CW2]::IsWindowVisible($h) + " rel=" + ($r.L-$rb.L) + "," + ($r.T-$rb.T) + " " + ($r.Rt-$r.L) + "x" + ($r.B-$r.T))
  }
}
Write-Output ("total orfaos: $orphans")
$global:Form.Hide()
