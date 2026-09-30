$env:TI_SUITE_QUIET = '1'
$crash = Join-Path $env:LOCALAPPDATA 'TI-Suite\crash.log'
$base = if (Test-Path $crash) { (Get-Item $crash).LastWriteTime } else { $null }
$proc = Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\flaviosantos\Desktop\Piaget CleanDesk\TI-Suite.ps1" -NoElevate' -PassThru -RedirectStandardOutput "$env:TEMP\ti_out.txt" -RedirectStandardError "$env:TEMP\ti_err.txt"
Write-Output ('pid=' + $proc.Id)
Start-Sleep -Seconds 12
$proc.Refresh()
Write-Output ('hasExited=' + $proc.HasExited)
if ($proc.HasExited) { Write-Output ('exitCode=' + $proc.ExitCode) }
$w = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($w) { Write-Output ('titulo=' + $w.MainWindowTitle) }
Write-Output ('crash.log mtime=' + (Get-Item $crash).LastWriteTime + ' (base=' + $base + ')')
Write-Output '--- stdout ---'
Get-Content "$env:TEMP\ti_out.txt" -ErrorAction SilentlyContinue | Select-Object -First 30
Write-Output '--- stderr ---'
Get-Content "$env:TEMP\ti_err.txt" -ErrorAction SilentlyContinue | Select-Object -First 30
if (-not $proc.HasExited) {
    Add-Type @"
using System;using System.Runtime.InteropServices;
public class FW { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n); }
"@
    $h = [FW]::FindWindow($null, 'TI Suite - Ferramentas de suporte')
    Write-Output ('FindWindow=' + $h)
}
