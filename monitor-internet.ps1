# Monitor de internet com notificações do Windows
# Fica rodando e:
#   - mostra um ícone perto do relógio com a VELOCIDADE MÁXIMA da internet (Mbps),
#     medida por um teste rápido a cada 30 min, colorido pela qualidade da conexão:
#       verde = boa | amarelo = instável/lenta | vermelho = ruim ou fora do ar
#   - ao passar o mouse, mostra velocidade máxima, uso atual, ping, jitter e perda
#   - mede o ping a cada segundo e avisa quando a internet cai, volta ou fica instável
#   - diz se o problema parece ser no Wi-Fi/roteador ou na operadora
#   - o teste de velocidade é adiado se você estiver usando a internet (ex.: numa chamada)
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\monitor-internet.ps1
#   powershell -ExecutionPolicy Bypass -File .\monitor-internet.ps1 -TestarNotificacao
#   powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File .\monitor-internet.ps1   (sem janela)
#
# Menu (botão direito no ícone): Testar velocidade agora | Abrir registros | Parar monitor
# Registros ficam na pasta "logs" ao lado deste script.

param(
    [string]$Alvo = '1.1.1.1',
    [string]$AlvoReserva = '8.8.8.8',
    [int]$IntervaloMs = 1000,
    [int]$Janela = 30,               # segundos analisados para detectar instabilidade
    [int]$LimiteLatencia = 150,      # ms
    [int]$LimiteJitter = 30,         # ms
    [double]$LimitePerda = 3,        # %
    [double]$LimiteVelocidade = 10,  # Mbps de download abaixo disso = lenta
    [int]$FalhasParaQueda = 3,       # segundos seguidos sem resposta = queda
    [int]$IntervaloAlertaMin = 5,    # minutos mínimos entre alertas de instabilidade
    [int]$TesteVelocidadeMin = 30,   # de quanto em quanto tempo medir a velocidade máxima (0 = nunca)
    [int]$DuracaoMin = 0,            # 0 = roda para sempre
    [ValidateSet('Capacidade', 'Uso', 'Ping')]
    [string]$NumeroNoIcone = 'Capacidade',   # Capacidade = velocidade máxima | Uso = consumo agora | Ping
    [switch]$TestarNotificacao
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Win32 -Name IconeNativo -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Só um monitor por vez (evita dois ícones se ele já foi iniciado com o Windows)
if (-not $TestarNotificacao) {
    $trava = New-Object System.Threading.Mutex($false, 'Local\MonitorDeInternet')
    $temTrava = $false
    try { $temTrava = $trava.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $temTrava = $true }
    if (-not $temTrava) {
        Write-Host 'O monitor de internet já está rodando (veja o ícone perto do relógio).' -ForegroundColor Yellow
        return
    }
}

$pastaLogs = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $pastaLogs | Out-Null
$arqEventos = Join-Path $pastaLogs 'eventos.log'
$arqVelocidade = Join-Path $pastaLogs 'velocidade.csv'

# ---------- Ícone na bandeja + menu ----------
$estado = @{ Parar = $false; TestarAgora = $false }
$icone = New-Object System.Windows.Forms.NotifyIcon
$icone.Icon = [System.Drawing.SystemIcons]::Information
$icone.Text = 'Monitor de internet'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemTeste = $menu.Items.Add('Testar velocidade agora')
$itemTeste.add_Click({ $estado.TestarAgora = $true }.GetNewClosure())
$itemLogs = $menu.Items.Add('Abrir registros')
$itemLogs.add_Click({ Start-Process explorer.exe $pastaLogs }.GetNewClosure())
$itemParar = $menu.Items.Add('Parar monitor')
$itemParar.add_Click({ $estado.Parar = $true }.GetNewClosure())
$icone.ContextMenuStrip = $menu
$icone.Visible = $true

$cores = @{
    Verde    = [System.Drawing.Color]::FromArgb(22, 163, 74)
    Amarelo  = [System.Drawing.Color]::FromArgb(234, 179, 8)
    Vermelho = [System.Drawing.Color]::FromArgb(220, 38, 38)
    Cinza    = [System.Drawing.Color]::FromArgb(107, 114, 128)
}
$iconeAtual = @{ Chave = ''; Handle = [IntPtr]::Zero }

# Desenha o ícone: quadrado colorido com o texto no meio
function Set-IconeStatus([string]$Texto, [string]$Cor, [string]$Dica) {
    if ($Dica.Length -gt 63) { $Dica = $Dica.Substring(0, 63) }   # limite do Windows
    $icone.Text = $Dica

    $chave = "$Texto|$Cor"
    if ($chave -eq $iconeAtual.Chave) { return }

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $fundo = New-Object System.Drawing.SolidBrush $cores[$Cor]
    $g.FillRectangle($fundo, 0, 0, 32, 32)

    $tam = if ($Texto.Length -le 2) { 21 } elseif ($Texto.Length -eq 3) { 15 } else { 11 }
    $fonte = New-Object System.Drawing.Font('Segoe UI', $tam, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $corTexto = if ($Cor -eq 'Amarelo') { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
    $pincel = New-Object System.Drawing.SolidBrush $corTexto
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($Texto, $fonte, $pincel, (New-Object System.Drawing.RectangleF(-2, 1, 36, 32)), $fmt)

    $h = $bmp.GetHicon()
    $icone.Icon = [System.Drawing.Icon]::FromHandle($h)
    if ($iconeAtual.Handle -ne [IntPtr]::Zero) { [void][Win32.IconeNativo]::DestroyIcon($iconeAtual.Handle) }
    $iconeAtual.Handle = $h
    $iconeAtual.Chave = $chave

    $fmt.Dispose(); $pincel.Dispose(); $fonte.Dispose(); $fundo.Dispose(); $g.Dispose(); $bmp.Dispose()
}

function Send-Alerta([string]$Titulo, [string]$Texto, [string]$Tipo = 'Warning') {
    $icone.ShowBalloonTip(10000, $Titulo, $Texto, [System.Windows.Forms.ToolTipIcon]::$Tipo)
    $linha = '{0:yyyy-MM-dd HH:mm:ss}  {1}: {2}' -f (Get-Date), $Titulo, $Texto
    Add-Content -Path $arqEventos -Value $linha -Encoding UTF8
    Write-Host $linha -ForegroundColor Yellow
}

if ($TestarNotificacao) {
    Send-Alerta 'Monitor de internet' 'Notificação de teste: está funcionando!' 'Info'
    Start-Sleep -Seconds 6
    $icone.Dispose()
    return
}

# ---------- Medições ----------
$pinger = New-Object System.Net.NetworkInformation.Ping
function Measure-Ping([string]$Destino) {
    if (-not $Destino) { return $null }
    try {
        $r = $pinger.Send($Destino, 1000)
        if ($r.Status -eq 'Success') { return [int]$r.RoundtripTime }
    } catch {}
    return $null
}

function Get-Gateway {
    try {
        (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Where-Object { $_.NextHop -ne '0.0.0.0' } |
            Sort-Object RouteMetric | Select-Object -First 1).NextHop
    } catch { $null }
}

# Total de bytes recebidos/enviados pelas placas de rede ativas (para medir o uso atual)
function Get-BytesRede {
    $rx = 0.0; $tx = 0.0
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne 'Up') { continue }
        if ($nic.NetworkInterfaceType -eq 'Loopback' -or $nic.NetworkInterfaceType -eq 'Tunnel') { continue }
        try {
            $s = $nic.GetIPStatistics()
            $rx += $s.BytesReceived; $tx += $s.BytesSent
        } catch {}
    }
    return @($rx, $tx)
}

# Teste de velocidade máxima (servidor da Cloudflare): ~25 MB de download e ~10 MB de upload
function Measure-Download([int]$Bytes = 25000000) {
    $req = [Net.HttpWebRequest]::Create("https://speed.cloudflare.com/__down?bytes=$Bytes")
    $req.Timeout = 20000; $req.ReadWriteTimeout = 20000
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $req.GetResponse()
    try {
        $st = $resp.GetResponseStream()
        $buf = New-Object byte[] 262144
        $total = 0
        while (($lidos = $st.Read($buf, 0, $buf.Length)) -gt 0) { $total += $lidos }
    } finally { $resp.Close() }
    $sw.Stop()
    return [double]($total * 8 / 1e6 / $sw.Elapsed.TotalSeconds)
}

function Measure-Upload([int]$Bytes = 10000000) {
    $dados = New-Object byte[] 262144
    (New-Object Random).NextBytes($dados)
    $req = [Net.HttpWebRequest]::Create('https://speed.cloudflare.com/__up')
    $req.Method = 'POST'; $req.ContentType = 'application/octet-stream'
    $req.ContentLength = $Bytes; $req.AllowWriteStreamBuffering = $false
    $req.Timeout = 20000; $req.ReadWriteTimeout = 20000
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $st = $req.GetRequestStream()
    $restante = $Bytes
    while ($restante -gt 0) {
        $n = [math]::Min($dados.Length, $restante)
        $st.Write($dados, 0, $n); $restante -= $n
    }
    $st.Close()
    $req.GetResponse().Close()
    $sw.Stop()
    return [double]($Bytes * 8 / 1e6 / $sw.Elapsed.TotalSeconds)
}

function Format-Mbps([double]$v) {
    if ($v -ge 10) { '{0:N0}' -f $v } else { '{0:N1}' -f $v }
}

# Mbps cabendo em até 3 caracteres no ícone: 0 | 2,5 | 48 | 274 | 1G
function Format-Icone([double]$v) {
    if ($v -lt 0.05) { '0' }
    elseif ($v -lt 10) { '{0:N1}' -f $v }
    elseif ($v -lt 1000) { '{0:N0}' -f $v }
    else { '{0:N0}G' -f ($v / 1000) }
}

$amostras = New-Object System.Collections.Generic.List[object]
$falhasSeguidas = 0
$emQueda = $false
$inicioQueda = $null
$causaQueda = ''
$gwJaRespondeu = $false
$ultimoAlerta = [datetime]::MinValue
$ultimoAlertaLenta = [datetime]::MinValue
$fim = if ($DuracaoMin -gt 0) { (Get-Date).AddMinutes($DuracaoMin) } else { [datetime]::MaxValue }
$gateway = Get-Gateway
$ultimaBuscaGw = Get-Date
$bytesAnt = Get-BytesRede
$tAnt = Get-Date
$down = 0.0; $up = 0.0
$capDown = $null; $capUp = $null; $horaCap = $null
$proximoTeste = if ($TesteVelocidadeMin -gt 0) { (Get-Date).AddSeconds(10) } else { [datetime]::MaxValue }
$n = 0

Set-IconeStatus '...' 'Cinza' 'Monitor de internet: iniciando...'
Write-Host "Monitorando $Alvo (roteador: $gateway). Registros em: $pastaLogs" -ForegroundColor Cyan
Add-Content -Path $arqEventos -Value ('{0:yyyy-MM-dd HH:mm:ss}  Monitor iniciado' -f (Get-Date)) -Encoding UTF8

try {
    while ((Get-Date) -lt $fim -and -not $estado.Parar) {
        $t0 = Get-Date
        $n++

        # ---- Teste de velocidade máxima (periódico ou pelo menu) ----
        if (-not $emQueda -and ($estado.TestarAgora -or $t0 -ge $proximoTeste)) {
            $forcado = $estado.TestarAgora
            $estado.TestarAgora = $false
            if (-not $forcado -and ($down -gt 1 -or $up -gt 1)) {
                # Você está usando a internet (ex.: numa chamada): tenta de novo em 1 minuto
                $proximoTeste = $t0.AddMinutes(1)
            } else {
                $corAgora = if ($iconeAtual.Chave) { $iconeAtual.Chave.Split('|')[1] } else { 'Cinza' }
                Set-IconeStatus '...' $corAgora 'Testando velocidade...'
                [System.Windows.Forms.Application]::DoEvents()
                try {
                    $capDown = Measure-Download
                    $capUp = Measure-Upload
                    $horaCap = Get-Date
                    if (-not (Test-Path $arqVelocidade)) { Add-Content $arqVelocidade 'data_hora;download_mbps;upload_mbps' -Encoding UTF8 }
                    Add-Content $arqVelocidade ('{0:yyyy-MM-dd HH:mm:ss};{1:N1};{2:N1}' -f $horaCap, $capDown, $capUp) -Encoding UTF8
                    Write-Host ('{0:HH:mm:ss}  Velocidade máxima: ↓ {1:N1}  ↑ {2:N1} Mbps' -f $horaCap, $capDown, $capUp) -ForegroundColor Cyan
                    if ($forcado) {
                        Send-Alerta 'Teste de velocidade' ('Download {0} Mbps · Upload {1} Mbps' -f (Format-Mbps $capDown), (Format-Mbps $capUp)) 'Info'
                    } elseif ($capDown -lt $LimiteVelocidade -and ((Get-Date) - $ultimoAlertaLenta).TotalMinutes -ge 60) {
                        Send-Alerta 'Internet lenta' ('Download de só {0} Mbps (upload {1}). Videochamadas podem perder qualidade.' -f (Format-Mbps $capDown), (Format-Mbps $capUp))
                        $ultimoAlertaLenta = Get-Date
                    }
                } catch {
                    Add-Content -Path $arqEventos -Value ('{0:yyyy-MM-dd HH:mm:ss}  Teste de velocidade falhou: {1}' -f (Get-Date), $_.Exception.Message) -Encoding UTF8
                }
                $proximoTeste = (Get-Date).AddMinutes([math]::Max(1, $TesteVelocidadeMin))
                # O teste gera tráfego: não conta como uso do usuário
                $bytesAnt = Get-BytesRede; $tAnt = Get-Date
                $t0 = Get-Date
            }
        }

        if (-not $gateway -or ($t0 - $ultimaBuscaGw).TotalSeconds -ge 60) {
            $gateway = Get-Gateway; $ultimaBuscaGw = $t0
        }

        $ms = Measure-Ping $Alvo
        if ($null -eq $ms) { $ms = Measure-Ping $AlvoReserva }
        $msGw = Measure-Ping $gateway
        if ($null -ne $msGw) { $gwJaRespondeu = $true }
        $ok = $null -ne $ms

        # Uso atual (o que você está baixando/enviando agora)
        $bytesAgora = Get-BytesRede
        $tAgora = Get-Date
        $dt = [math]::Max(0.1, ($tAgora - $tAnt).TotalSeconds)
        $down = [math]::Max([double]0, [double](($bytesAgora[0] - $bytesAnt[0]) * 8 / 1e6 / $dt))
        $up   = [math]::Max([double]0, [double](($bytesAgora[1] - $bytesAnt[1]) * 8 / 1e6 / $dt))
        $bytesAnt = $bytesAgora; $tAnt = $tAgora

        $amostras.Add([pscustomobject]@{ Ok = $ok; Ms = $ms })
        if ($amostras.Count -gt $Janela) { $amostras.RemoveAt(0) }

        # Registro CSV (um arquivo por dia)
        $arqCsv = Join-Path $pastaLogs ('medicoes-{0:yyyy-MM-dd}.csv' -f $t0)
        if (-not (Test-Path $arqCsv)) { Add-Content $arqCsv 'horario;internet_ms;roteador_ms;download_mbps;upload_mbps' -Encoding UTF8 }
        $txtMs = if ($ok) { $ms } else { 'FALHA' }
        $txtGw = if ($null -ne $msGw) { $msGw } else { 'FALHA' }
        Add-Content $arqCsv ('{0:HH:mm:ss};{1};{2};{3:N2};{4:N2}' -f $t0, $txtMs, $txtGw, $down, $up) -Encoding UTF8

        # ---- Queda e retorno ----
        if ($ok) {
            if ($emQueda) {
                $dur = [int]((Get-Date) - $inicioQueda).TotalSeconds
                Send-Alerta 'Internet voltou' "Ficou fora do ar por $dur s ($causaQueda)." 'Info'
                $emQueda = $false
                $ultimoAlerta = Get-Date   # evita alerta de instabilidade logo em seguida
                if ($TesteVelocidadeMin -gt 0) { $proximoTeste = (Get-Date).AddSeconds(15) }   # mede de novo após a volta
            }
            $falhasSeguidas = 0
        } else {
            $falhasSeguidas++
            if ($falhasSeguidas -eq 1) { $primeiraFalha = $t0 }
            if (-not $emQueda -and $falhasSeguidas -ge $FalhasParaQueda) {
                $emQueda = $true
                $inicioQueda = $primeiraFalha
                if (-not $gwJaRespondeu) {
                    $causaQueda = 'causa indeterminada'
                    $detalhe = 'Não foi possível testar o roteador.'
                } elseif ($null -eq $msGw) {
                    $causaQueda = 'Wi-Fi/roteador'
                    $detalhe = 'O roteador também não responde: provável problema no Wi-Fi ou no roteador.'
                } else {
                    $causaQueda = 'operadora'
                    $detalhe = 'O roteador responde: provável problema na operadora.'
                }
                Send-Alerta 'Internet caiu' "Sem resposta há $falhasSeguidas s. $detalhe" 'Error'
            }
        }

        # ---- Qualidade nos últimos segundos (janela móvel) ----
        $boas = @($amostras | Where-Object { $_.Ok } | ForEach-Object { $_.Ms })
        $perda = 100.0 * ($amostras.Count - $boas.Count) / $amostras.Count
        $media = if ($boas.Count) { ($boas | Measure-Object -Average).Average } else { 0 }
        $jitter = 0
        if ($boas.Count -gt 1) {
            $soma = 0
            for ($i = 1; $i -lt $boas.Count; $i++) { $soma += [math]::Abs($boas[$i] - $boas[$i - 1]) }
            $jitter = $soma / ($boas.Count - 1)
        }

        $motivos = @()
        if ($perda -gt $LimitePerda)      { $motivos += ('perda de pacotes {0:N0}%' -f $perda) }
        if ($media -gt $LimiteLatencia)   { $motivos += ('ping {0:N0} ms' -f $media) }
        if ($jitter -gt $LimiteJitter)    { $motivos += ('jitter {0:N0} ms' -f $jitter) }

        if (-not $emQueda -and $amostras.Count -ge $Janela -and $motivos.Count -gt 0 -and
            ((Get-Date) - $ultimoAlerta).TotalMinutes -ge $IntervaloAlertaMin) {
            Send-Alerta 'Internet instável' ("Últimos $Janela s: " + ($motivos -join ', ') + '. Videochamadas podem travar.')
            $ultimoAlerta = Get-Date
        }

        # ---- Atualiza o ícone ----
        $txtMax = if ($null -ne $capDown) { "Máx ↓$(Format-Mbps $capDown) ↑$(Format-Mbps $capUp)" } else { 'Máx ?' }
        $linhaVel = "$txtMax · uso ↓$(Format-Mbps $down) ↑$(Format-Mbps $up)"
        if ($emQueda) {
            Set-IconeStatus 'X' 'Vermelho' "SEM INTERNET há $falhasSeguidas s`n($causaQueda)"
        } elseif (-not $ok) {
            Set-IconeStatus '!' 'Amarelo' "Falha no ping agora`n$linhaVel"
        } else {
            $lenta = $null -ne $capDown -and $capDown -lt $LimiteVelocidade
            $muitoLenta = $null -ne $capDown -and $capDown -lt ($LimiteVelocidade / 2)
            $cor = if ($perda -gt 10 -or $media -gt 2 * $LimiteLatencia -or $jitter -gt 2 * $LimiteJitter -or $muitoLenta) { 'Vermelho' }
                   elseif ($motivos.Count -gt 0 -or $lenta) { 'Amarelo' }
                   else { 'Verde' }
            $numero = switch ($NumeroNoIcone) {
                'Ping'       { [string][math]::Min($ms, 999) }
                'Uso'        { Format-Icone $down }
                default      { if ($null -ne $capDown) { Format-Icone $capDown } else { '...' } }
            }
            $linhaPing = 'Ping {0}ms jit {1:N0}ms perda {2:N0}%' -f $ms, $jitter, $perda
            Set-IconeStatus $numero $cor "$linhaVel`n$linhaPing"
        }

        if ($n % 10 -eq 0) {
            Write-Host ('{0:HH:mm:ss}  ping {1:N0} ms | jitter {2:N1} ms | perda {3:N0}% | {4}' -f (Get-Date), $media, $jitter, $perda, $linhaVel)
        }

        # Mantém o ícone/menu respondendo e espera até o próximo segundo
        [System.Windows.Forms.Application]::DoEvents()
        $resto = $IntervaloMs - ((Get-Date) - $t0).TotalMilliseconds
        while ($resto -gt 0 -and -not $estado.Parar -and -not $estado.TestarAgora) {
            Start-Sleep -Milliseconds ([math]::Min(100, $resto))
            [System.Windows.Forms.Application]::DoEvents()
            $resto = $IntervaloMs - ((Get-Date) - $t0).TotalMilliseconds
        }
    }
} finally {
    Add-Content -Path $arqEventos -Value ('{0:yyyy-MM-dd HH:mm:ss}  Monitor parado' -f (Get-Date)) -Encoding UTF8
    $icone.Visible = $false
    $icone.Dispose()
    if ($iconeAtual.Handle -ne [IntPtr]::Zero) { [void][Win32.IconeNativo]::DestroyIcon($iconeAtual.Handle) }
}
