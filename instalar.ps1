# Instala (ou atualiza) o Monitor de Internet neste PC.
#
# Uso, no PowerShell:
#   irm https://raw.githubusercontent.com/dariokrugerjunior/monitor-internet/main/instalar.ps1 | iex
#
# O que faz:
#   1. Baixa os scripts do GitHub para %LOCALAPPDATA%\MonitorInternet
#   2. Cria um atalho na Inicializacao do Windows (o monitor abre sozinho ao entrar no Windows)
#   3. Cria atalhos no Menu Iniciar ("Monitor de internet" e "Teste de videochamada")
#   4. Inicia o monitor (icone perto do relogio)
# Nao precisa de administrador.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$origem  = 'https://raw.githubusercontent.com/dariokrugerjunior/monitor-internet/main'
$destino = Join-Path $env:LOCALAPPDATA 'MonitorInternet'
$ps      = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arquivos = 'monitor-internet.ps1', 'teste-videochamada.ps1', 'desinstalar.ps1'

Write-Host ''
Write-Host '== Instalando o Monitor de Internet ==' -ForegroundColor Cyan

# Para o monitor, se ja estiver rodando (para poder atualizar os arquivos)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*monitor-internet.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host '  Monitor anterior encerrado.' }

New-Item -ItemType Directory -Force $destino | Out-Null
foreach ($arq in $arquivos) {
    $caminho = Join-Path $destino $arq
    Invoke-WebRequest -Uri "$origem/$arq" -OutFile $caminho -UseBasicParsing
    Unblock-File -Path $caminho
    Write-Host "  Baixado: $arq"
}

function New-Atalho([string]$Caminho, [string]$Argumentos, [string]$Descricao, [int]$Janela = 7) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($Caminho)
    $s.TargetPath = $ps
    $s.Arguments = $Argumentos
    $s.WorkingDirectory = $destino
    $s.WindowStyle = $Janela          # 7 = minimizado, 1 = normal
    $s.Description = $Descricao
    $s.Save()
}

$monitor  = Join-Path $destino 'monitor-internet.ps1'
$teste    = Join-Path $destino 'teste-videochamada.ps1'
$argsMonitor = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitor`""

$pastaInicializar = [Environment]::GetFolderPath('Startup')
$pastaMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Monitor de internet'
New-Item -ItemType Directory -Force $pastaMenu | Out-Null

New-Atalho (Join-Path $pastaInicializar 'Monitor de internet.lnk') $argsMonitor 'Monitor de internet (velocidade, ping e quedas)'
New-Atalho (Join-Path $pastaMenu 'Monitor de internet.lnk') $argsMonitor 'Abrir o monitor de internet'
New-Atalho (Join-Path $pastaMenu 'Teste de videochamada.lnk') "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$teste`"" 'Testar a internet para videochamada' 1
Write-Host '  Atalhos criados (Inicializacao do Windows e Menu Iniciar).'

Start-Process -FilePath $ps -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$monitor`"" -WorkingDirectory $destino -WindowStyle Hidden

Write-Host ''
Write-Host 'Pronto! O monitor esta rodando: veja o icone perto do relogio' -ForegroundColor Green
Write-Host '(se nao aparecer, clique na setinha ^ ao lado do relogio).'
Write-Host "Arquivos e registros: $destino"
Write-Host 'Para desinstalar: Menu Iniciar > pesquise "PowerShell" e rode:'
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$destino\desinstalar.ps1`""
