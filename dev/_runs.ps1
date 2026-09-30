Add-Type -AssemblyName System.Drawing
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$bmp = [System.Drawing.Bitmap]::FromFile("$dir\pw_final.png")
Write-Output ("tamanho: {0}x{1}" -f $bmp.Width, $bmp.Height)
function Show-Runs($b, $fixed, $axis, $from, $to) {
    $runs = New-Object System.Collections.ArrayList
    $prev = $null; $start = $from
    for ($i = $from; $i -lt $to; $i++) {
        $c = if ($axis -eq 'row') { $b.GetPixel($i, $fixed) } else { $b.GetPixel($fixed, $i) }
        $key = '{0},{1},{2}' -f $c.R, $c.G, $c.B
        if ($prev -ne $null -and $key -ne $prev) {
            [void]$runs.Add(('{0}..{1}: {2}' -f $start, ($i-1), $prev))
            $start = $i
        }
        $prev = $key
    }
    [void]$runs.Add(('{0}..{1}: {2}' -f $start, ($to-1), $prev))
    $runs | ForEach-Object { Write-Output $_ }
}
Write-Output '--- linha y=300, x=1100..fim ---'
Show-Runs $bmp 300 'row' 1100 $bmp.Width
Write-Output '--- coluna x=1152, y=0..fim ---'
Show-Runs $bmp 1152 'col' 0 $bmp.Height
$bmp.Dispose()
