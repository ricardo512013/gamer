$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
$log = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log'
if (Test-Path $log) {
  $c = Get-Content $log
  Write-Output ("total linhas: " + $c.Count)
  # imprime blocos: acha linhas separadoras e mostra comecos de cada bloco com a mensagem
  for ($i = 0; $i -lt $c.Count; $i++) {
    if ($c[$i] -match '^\s*$' -and $i -gt 0 -and $c[$i-1] -match '^-{10,}') {
      $start = $i
      $end = [Math]::Min($c.Count - 1, $i + 4)
      Write-Output ("--- bloco em linha " + $start + " ---")
      $c[$start..$end] | ForEach-Object { if ($_ -and $_ -notmatch '^\s*em ') { Write-Output $_ } }
    }
  }
} else { Write-Output 'sem exceptions.log' }
Write-Output '=== derivacoes das classes ==='
$src = Get-Content (Join-Path $global:TIRoot 'src\Core\00-Controls.ps1') -Raw
[regex]::Matches($src, 'public class (\w+) : (\w+)') | ForEach-Object { $_.Groups[1].Value + ' : ' + $_.Groups[2].Value }
