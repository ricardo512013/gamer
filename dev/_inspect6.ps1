$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class ZW2{
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]public static extern int GetWindowLong(IntPtr h,int i);
 [DllImport("user32.dll")]public static extern IntPtr GetWindow(IntPtr h,uint c);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$core = Join-Path $global:TIRoot 'src\Core'
$wsp  = Join-Path $global:TIRoot 'src\Workspaces'
foreach ($n in @('00-Controls.ps1','01-Theme.ps1','02-Dialogs.ps1','03-Logging.ps1','04-Async.ps1','05-Shell.ps1')) { . (Join-Path $core $n) }
foreach ($n in @('Dashboard.ps1','Limpeza.ps1','Contas.ps1','Rede.ps1')) { . (Join-Path $wsp $n) }
Start-TIApp
$global:Form.Show(); $global:Form.Activate()
for ($i = 0; $i -lt 25; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }

$ar = New-Object ZW2+R
[void][ZW2]::GetWindowRect([IntPtr]$global:Form.Handle, [ref]$ar)
Write-Output ('nossa janela: ' + $ar.L + ',' + $ar.T + ' ' + ($ar.Rt-$ar.L) + 'x' + ($ar.B-$ar.T))
Write-Output ('exstyle=0x{0:X}' -f [ZW2]::GetWindowLong([IntPtr]$global:Form.Handle, -20))
Write-Output ('style=0x{0:X}' -f [ZW2]::GetWindowLong([IntPtr]$global:Form.Handle, -16))

$script:z = 0
$script:out = @()
$cb = [ZW2+EnumProc]{ param($h,$l)
  $script:z++
  $r = New-Object ZW2+R
  if ([ZW2]::GetWindowRect($h,[ref]$r)) {
    $inter = -not ($r.Rt -le $ar.L -or $r.L -ge $ar.Rt -or $r.B -le $ar.T -or $r.T -ge $ar.B)
    if ($inter) {
      $sb = New-Object System.Text.StringBuilder 200
      [void][ZW2]::GetWindowText($h,$sb,200)
      $p = 0; [void][ZW2]::GetWindowThreadProcessId($h,[ref]$p)
      $vis = [ZW2]::IsWindowVisible($h)
      $script:out += ("z={0} pid={1} vis={2} ex=0x{3:X} rect={4},{5} {6}x{7} '{8}'" -f $script:z, $p, $vis, [ZW2]::GetWindowLong($h,-20), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T), $sb.ToString())
    }
  }
  return $true
}
[void][ZW2]::EnumWindows($cb,[IntPtr]::Zero)
Write-Output '=== janelas que interceptam nosso retangulo (ordem Z: 1=topo) ==='
$script:out

$global:Form.Hide()
