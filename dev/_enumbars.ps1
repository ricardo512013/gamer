Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class EB {
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetParent(IntPtr h);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$p = Get-Process powershell -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowTitle -like 'TI Suite*' } | Select-Object -First 1
if (-not $p) { Write-Output 'app nao encontrado'; exit 1 }
$root = $p.MainWindowHandle
$script:rows = New-Object System.Collections.ArrayList
$cb = [EB+EnumProc]{ param($h,$l)
  $r = New-Object EB+R
  if ([EB]::GetWindowRect($h,[ref]$r)) {
    if ($r.L -gt 1120 -and $r.Rt -lt 1200) {
      $sb = New-Object System.Text.StringBuilder 120
      [void][EB]::GetClassName($h,$sb,120)
      $par = [EB]::GetParent($h)
      [void]$script:rows.Add(('cls={0} vis={1} rect={2},{3} {4}x{5} parent=0x{6:X}' -f $sb.ToString(), [EB]::IsWindowVisible($h), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T), $par.ToInt64()))
    }
  }
  return $true
}
[void][EB]::EnumChildWindows($root,$cb,[IntPtr]::Zero)
Write-Output ('janelas filhas na borda direita: ' + $script:rows.Count)
$script:rows | ForEach-Object { Write-Output $_ }
