$bad = 0
foreach ($f in Get-ChildItem 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk\src' -Recurse -Filter *.ps1) {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { $bad++; Write-Output ($f.Name + ': ' + $e[0].Message) }
}
Write-Output ("parse: " + $bad + " arquivo(s) com erro")
