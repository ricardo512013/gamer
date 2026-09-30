$proc = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like 'TI Suite*' } | Select-Object -First 1
if (-not $proc) {
    $env:TI_SUITE_QUIET = '1'
    $proc = Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\flaviosantos\Desktop\Piaget CleanDesk\TI-Suite.ps1" -NoElevate' -PassThru
    for ($i = 0; $i -lt 80 -and -not $proc.MainWindowTitle; $i++) { Start-Sleep -Milliseconds 500; $proc.Refresh() }
    if (-not $proc.MainWindowTitle) { Write-Output 'nao abriu'; exit 1 }
    Start-Sleep -Seconds 10  # aguarda dados carregar (barra aparece apos layout com scroll)
} else {
    Start-Sleep -Seconds 2
}
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class EB2 {
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetParent(IntPtr h);
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
$script:rows = New-Object System.Collections.ArrayList
$cb = [EB2+EnumProc]{ param($h,$l)
  $r = New-Object EB2+R
  if ([EB2]::GetWindowRect($h,[ref]$r)) {
    $sb = New-Object System.Text.StringBuilder 120
    [void][EB2]::GetClassName($h,$sb,120)
    $cls = $sb.ToString()
    if ($r.L -gt 1120 -or ($r.L -gt 200 -and $cls -match 'Scroll|slider|track')) {
      $par = [EB2]::GetParent($h)
      [void]$script:rows.Add(('cls={0} vis={1} rect={2},{3} {4}x{5} parent=0x{6:X}' -f $cls, [EB2]::IsWindowVisible($h), $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T), $par.ToInt64()))
    }
  }
  return $true
}
[void][EB2]::EnumChildWindows($proc.MainWindowHandle,$cb,[IntPtr]::Zero)
Write-Output ('windows de rolagem: ' + $script:rows.Count + ' (app pid=' + $proc.Id + ')')
$script:rows | ForEach-Object { Write-Output $_ }
