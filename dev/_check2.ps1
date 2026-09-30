Get-ChildItem 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags' -Recurse -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty Name
$s = New-Object -ComObject WScript.Shell
$lnk = 'C:\Users\flaviosantos\Desktop\TI Suite.lnk'
if (Test-Path $lnk) {
    $l = $s.CreateShortcut($lnk)
    Write-Output ('target=' + $l.TargetPath)
    Write-Output ('args=' + $l.Arguments)
    Write-Output ('workdir=' + $l.WorkingDirectory)
} else {
    Write-Output 'atalho nao encontrado'
}
