Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
    $cl = (Get-CimInstance Win32_Process -Filter ("ProcessId=" + $_.Id)).CommandLine
    Write-Output ("pid={0} title='{1}' start={2}" -f $_.Id, $_.MainWindowTitle, $_.StartTime)
    Write-Output ("   cmd=" + $cl)
}
