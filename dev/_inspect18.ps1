$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $global:TIRoot 'src\Core\00-Controls.ps1')

foreach ($tn in @('TISuite.ArcSpinner','TISuite.FlatProgress','TISuite.ToggleSwitch','TISuite.PremiumButton')) {
  $c = [Activator]::CreateInstance([type]$tn)
  $c.Size = New-Object System.Drawing.Size(60, 40)
  $bmp = New-Object System.Drawing.Bitmap(60, 40)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Black)
  $g.Dispose()
  $c.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, 60, 40)))
  $px = $bmp.GetPixel(55, 35)
  Write-Output ("{0}: fundo(55,35)={1}" -f $tn, $px.ToArgb().ToString('X8'))
  $bmp.Dispose(); $c.Dispose()
}
