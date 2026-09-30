
$err = $null
$tok = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'E:/Piaget CleanDesk/src/Workspaces/Limpeza.ps1',
    ([ref]$tok),
    ([ref]$err)
) | Out-Null
if ($err -and $err.Count -gt 0) {
    Write-Host "ERROS:"
    $err | ForEach-Object { Write-Host "  $($_.Message) (Linha $($_.Extent.StartLineNumber))" }
    exit 1
} else {
    Write-Host "SINTAXE OK"
    exit 0
}
