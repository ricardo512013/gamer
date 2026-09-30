$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $global:TIRoot 'src\Core\00-Controls.ps1')

$item = New-Object TISuite.SidebarItem
$item.Size = New-Object System.Drawing.Size(219, 42)
$item.ItemText = 'Teste'
$item.Glyph = [string][char]0xE80F
$bmp = New-Object System.Drawing.Bitmap(219, 42)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.Dispose()
$item.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, 219, 42)))
$bg = $bmp.GetPixel(150, 35)
Write-Output ("fundo apos DrawToBitmap (150,35): " + $bg.ToArgb().ToString('X8'))
$bg2 = $bmp.GetPixel(15, 21)
Write-Output ("fundo (15,21): " + $bg2.ToArgb().ToString('X8'))
$bmp.Save("$dir\isolated.png", [System.Drawing.Imaging.ImageFormat]::Png) 2>$null
$dir = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode'
$bmp.Save("$dir\isolated.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$item.Dispose()

# e o Painel padrao: BackColor padrao pinta?
$p = New-Object System.Windows.Forms.Panel
$p.Size = New-Object System.Drawing.Size(50, 50)
$bmp = New-Object System.Drawing.Bitmap(50, 50)
$p.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, 50, 50)))
Write-Output ("painel padrao fundo: " + $bmp.GetPixel(25, 25).ToArgb().ToString('X8'))
$bmp.Dispose(); $p.Dispose()
