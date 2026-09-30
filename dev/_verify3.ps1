Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class PW3 {
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
# mata instancias anteriores do app
Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowTitle -like 'TI Suite*') { Stop-Process -Id $_.Id -Force }
}
Start-Sleep -Seconds 1
$env:TI_SUITE_QUIET = '1'
$proc = Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\flaviosantos\Desktop\Piaget CleanDesk\TI-Suite.ps1" -NoElevate' -PassThru
for ($i = 0; $i -lt 80 -and -not $proc.MainWindowTitle; $i++) { Start-Sleep -Milliseconds 500; $proc.Refresh() }
if (-not $proc.MainWindowTitle) { Write-Output 'APP NAO ABRIU'; exit 1 }
Write-Output ('app pid=' + $proc.Id + ' titulo=' + $proc.MainWindowTitle)
Start-Sleep -Seconds 14  # dados carregam ~6s + folga

$r = New-Object PW3+RECT
[void][PW3]::GetWindowRect($proc.MainWindowHandle, [ref]$r)
Write-Output ('window rect screen: {0},{1} {2}x{3}' -f $r.L, $r.T, ($r.R-$r.L), ($r.B-$r.T))

Add-Type -AssemblyName System.Drawing
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$hdc = [System.Drawing.Graphics]::FromImage($bmp)
$gh = $hdc.GetHdc()
$ok = [PW3]::PrintWindow($proc.MainWindowHandle, $gh, 2)
$hdc.ReleaseHdc($gh); $hdc.Dispose()
$out = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\pw_v3.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

function Show-Runs($b, $fixed, $axis, $from, $to) {
    $prev = $null; $start = $from
    for ($i = $from; $i -lt $to; $i++) {
        $c = if ($axis -eq 'row') { $b.GetPixel($i, $fixed) } else { $b.GetPixel($fixed, $i) }
        $key = '{0},{1},{2}' -f $c.R, $c.G, $c.B
        if ($prev -ne $null -and $key -ne $prev) { Write-Output ('{0}..{1}: {2}' -f $start, ($i-1), $prev); $start = $i }
        $prev = $key
    }
    Write-Output ('{0}..{1}: {2}' -f $start, ($to-1), $prev)
}
Write-Output ('PrintWindow ok=' + $ok + ' imagem=' + $bmp.Width + 'x' + $bmp.Height)
Write-Output '--- linha y=300, x=1135..1160 ---'
Show-Runs $bmp 300 'row' 1135 ([Math]::Min(1160, $bmp.Width))
Write-Output '--- coluna x=1151, y=60..520 (so cores distintas) ---'
$prev = $null; $start = 60
for ($i = 60; $i -lt [Math]::Min(520, $bmp.Height); $i++) {
    $c = $bmp.GetPixel(1151, $i)
    $key = '{0},{1},{2}' -f $c.R, $c.G, $c.B
    if ($prev -ne $null -and $key -ne $prev) { Write-Output ('{0}..{1}: {2}' -f $start, ($i-1), $prev); $start = $i }
    $prev = $key
}
Write-Output ('{0}..519: {1}' -f $start, $prev)
$bmp.Dispose()
