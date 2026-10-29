# Instala ou atualiza o Funilar no Windows com a versão mais nova do GitHub.
#
# Uso (PowerShell):
#   irm https://raw.githubusercontent.com/Pedroedmachado/robervall-app/main/tool/atualizar-funilar.ps1 | iex
#
# O programa fica em %LOCALAPPDATA%\Funilar. Os dados (sinistros, fotos,
# estoque...) ficam em outra pasta (%APPDATA%) e NÃO são mexidos.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # download bem mais rápido
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'Pedroedmachado/robervall-app'
$dest = Join-Path $env:LOCALAPPDATA 'Funilar'
$exe = Join-Path $dest 'funilar.exe'
$verFile = Join-Path $dest 'versao.txt'

Write-Host ''
Write-Host '== Funilar: atualização ==' -ForegroundColor Cyan
Write-Host 'Procurando a versão mais nova...'
$rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'Funilar-atualizador' }
$asset = $rel.assets | Where-Object { $_.name -eq 'Funilar-windows-x64.zip' } | Select-Object -First 1
if (-not $asset) { throw "A versão $($rel.tag_name) não tem o arquivo do Windows." }

$atual = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '' }
if ($atual -eq $rel.tag_name -and (Test-Path $exe)) {
  Write-Host "Você já está na versão mais nova ($atual)." -ForegroundColor Green
  Start-Process $exe
  return
}
if ($atual) { Write-Host "Versão instalada: $atual  ->  nova: $($rel.tag_name)" }
else { Write-Host "Instalando a versão $($rel.tag_name)" }

$zip = Join-Path $env:TEMP 'Funilar-windows-x64.zip'
$tmp = Join-Path $env:TEMP 'Funilar-novo'
Write-Host "Baixando ($([math]::Round($asset.size / 1MB, 1)) MB)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing

# Fecha o Funilar com calma (ele salva ao fechar); força só se não fechar.
$abertos = Get-Process funilar -ErrorAction SilentlyContinue
if ($abertos) {
  Write-Host 'Fechando o Funilar aberto...'
  $abertos | ForEach-Object { [void]$_.CloseMainWindow() }
  Start-Sleep -Seconds 4
  Get-Process funilar -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 1
}

Write-Host 'Instalando...'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip $tmp -Force
if (-not (Test-Path (Join-Path $tmp 'funilar.exe'))) { throw 'O arquivo baixado não tem o funilar.exe.' }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem $dest -Force | Where-Object { $_.Name -ne 'versao.txt' } | Remove-Item -Recurse -Force
Copy-Item (Join-Path $tmp '*') $dest -Recurse -Force
Set-Content -Path $verFile -Value $rel.tag_name
Remove-Item $tmp -Recurse -Force
Remove-Item $zip -Force

# Atalhos na Área de Trabalho e no menu Iniciar
$shell = New-Object -ComObject WScript.Shell
foreach ($pasta in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = $shell.CreateShortcut((Join-Path $pasta 'Funilar.lnk'))
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $dest
  $lnk.IconLocation = "$exe,0"
  $lnk.Description = 'Funilar - orçamentos e sinistros'
  $lnk.Save()
}

Write-Host "Pronto! Funilar $($rel.tag_name) instalado em $dest" -ForegroundColor Green
Start-Process $exe
