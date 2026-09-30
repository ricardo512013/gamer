$k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
(Get-ItemProperty -Path $k).PSObject.Properties |
  Where-Object { $_.Name -notlike 'PS*' } |
  ForEach-Object { Write-Output ($_.Name + ' = ' + $_.Value) }
