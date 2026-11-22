# Remove o Monitor de Internet deste PC.
#
# Uso, no PowerShell:
#   powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MonitorInternet\desinstalar.ps1"
# ou, sem nada instalado localmente:
#   irm https://raw.githubusercontent.com/dariokrugerjunior/monitor-internet/main/desinstalar.ps1 | iex
#
# Para manter os registros (pasta logs), rode com -ManterRegistros.

param([switch]$ManterRegistros)

$destino = Join-Path $env:LOCALAPPDATA 'MonitorInternet'

Write-Host ''
Write-Host '== Desinstalando o Monitor de Internet ==' -ForegroundColor Cyan

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*monitor-internet.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host '  Monitor encerrado.' }

$atalhoInicio = Join-Path ([Environment]::GetFolderPath('Startup')) 'Monitor de internet.lnk'
$pastaMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Monitor de internet'
if (Test-Path $atalhoInicio) { Remove-Item $atalhoInicio -Force; Write-Host '  Removido da Inicializacao do Windows.' }
if (Test-Path $pastaMenu) { Remove-Item $pastaMenu -Recurse -Force; Write-Host '  Removido do Menu Iniciar.' }

if (Test-Path $destino) {
    if ($ManterRegistros) {
        Get-ChildItem $destino -File | Remove-Item -Force
        Write-Host "  Scripts removidos. Registros mantidos em: $destino\logs"
    } else {
        Remove-Item $destino -Recurse -Force
        Write-Host '  Arquivos e registros removidos.'
    }
}

Write-Host ''
Write-Host 'Monitor de Internet desinstalado.' -ForegroundColor Green
