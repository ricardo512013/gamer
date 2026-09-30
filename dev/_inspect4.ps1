$ErrorActionPreference = 'Continue'
$global:TIRoot = 'C:\Users\flaviosantos\Desktop\Piaget CleanDesk'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
$core = Join-Path $global:TIRoot 'src\Core'
$wsp  = Join-Path $global:TIRoot 'src\Workspaces'
foreach ($n in @('00-Controls.ps1','01-Theme.ps1','02-Dialogs.ps1','03-Logging.ps1','04-Async.ps1','05-Shell.ps1')) { . (Join-Path $core $n) }
foreach ($n in @('Dashboard.ps1','Limpeza.ps1','Contas.ps1','Rede.ps1')) { . (Join-Path $wsp $n) }
Start-TIApp
$global:Form.Show(); $global:Form.Activate()
for ($i = 0; $i -lt 30; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }

# Renderiza cada SidebarItem isoladamente
$strip = New-Object System.Drawing.Bitmap(240, 190)
$g = [System.Drawing.Graphics]::FromImage($strip)
$g.Clear([System.Drawing.Color]::FromArgb(255,20,30,50))
$y = 4
foreach ($c in $global:NavFlow.Controls) {
    $bmp = New-Object System.Drawing.Bitmap($c.Width, $c.Height)
    $c.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0,0,$c.Width,$c.Height)))
    $g.DrawImage($bmp, 8, $y)
    $bmp.Dispose()
    $y += 46
}
$g.Dispose()
$out1 = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\items_direct.png'
$strip.Save($out1, [System.Drawing.Imaging.ImageFormat]::Png); $strip.Dispose()

# Renderiza o painel da sidebar inteiro
$sbPanel = $global:NavFlow.Parent
$bmp2 = New-Object System.Drawing.Bitmap($sbPanel.Width, $sbPanel.Height)
$sbPanel.DrawToBitmap($bmp2, (New-Object System.Drawing.Rectangle(0,0,$sbPanel.Width,$sbPanel.Height)))
$out2 = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\sidebar_direct.png'
$bmp2.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png); $bmp2.Dispose()

# renderiza form inteiro
$fb = New-Object System.Drawing.Bitmap($global:Form.Width, $global:Form.Height)
$global:Form.DrawToBitmap($fb, (New-Object System.Drawing.Rectangle(0,0,$global:Form.Width,$global:Form.Height)))
$out3 = 'C:\Users\FLAVIO~1\AppData\Local\Temp\opencode\form_direct.png'
$fb.Save($out3, [System.Drawing.Imaging.ImageFormat]::Png); $fb.Dispose()

"ok: $out1 / $out2 / $out3"
$global:Form.Hide()
