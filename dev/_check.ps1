Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Select-Object ProcessId, ParentProcessId, CreationDate, CommandLine | Format-List

Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class EW {
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
}
"@
$script:t = @()
$cb = [EW+EnumProc]{ param($h,$l)
  if ([EW]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 200
    [void][EW]::GetWindowText($h,$sb,200)
    $s = $sb.ToString()
    if ($s -match 'Controle de|User Account|Consent|UAC|Aviso|Windows Security|Seguran|Alterar') { [void]$script:t.Add($s) }
  }
  return $true
}
[void][EW]::EnumWindows($cb,[IntPtr]::Zero)
Write-Output ("janelas de consentimento: " + $script:t.Count)
$script:t | ForEach-Object { Write-Output ("  - " + $_) }
