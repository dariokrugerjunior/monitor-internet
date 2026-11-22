# Teste de conexao para videochamada
# Mede: latencia (ping), jitter, perda de pacotes, download e upload.
# Uso: powershell -ExecutionPolicy Bypass -File .\teste-videochamada.ps1

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'

function Write-Titulo($t) { Write-Host ""; Write-Host "== $t ==" -ForegroundColor Cyan }

# ---------- 1. Latencia, jitter e perda ----------
Write-Titulo "Latencia / Jitter / Perda (40 pings para 1.1.1.1)"
$ping = New-Object System.Net.NetworkInformation.Ping
$tempos = @(); $perdidos = 0; $total = 40
for ($i = 0; $i -lt $total; $i++) {
    try {
        $r = $ping.Send("1.1.1.1", 1000)
        if ($r.Status -eq 'Success') { $tempos += [double]$r.RoundtripTime } else { $perdidos++ }
    } catch { $perdidos++ }
    Start-Sleep -Milliseconds 200
}
if ($tempos.Count -gt 0) {
    $latencia = ($tempos | Measure-Object -Average).Average
    $difs = @(); for ($i = 1; $i -lt $tempos.Count; $i++) { $difs += [math]::Abs($tempos[$i] - $tempos[$i-1]) }
    $jitter = if ($difs.Count) { ($difs | Measure-Object -Average).Average } else { 0 }
} else { $latencia = 9999; $jitter = 9999 }
$perda = 100.0 * $perdidos / $total
"Latencia media : {0:N0} ms" -f $latencia
"Jitter         : {0:N1} ms" -f $jitter
"Perda pacotes  : {0:N1} %" -f $perda

# ---------- 2. Download ----------
Write-Titulo "Download (servidor Cloudflare)"
$wc = New-Object System.Net.WebClient
$downs = @()
foreach ($bytes in 10000000, 25000000, 25000000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $dados = $wc.DownloadData("https://speed.cloudflare.com/__down?bytes=$bytes")
    $sw.Stop()
    $mbps = ($dados.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds
    $downs += $mbps
    "  {0,3} MB em {1:N2}s -> {2:N1} Mbps" -f ($bytes/1e6), $sw.Elapsed.TotalSeconds, $mbps
}
$download = ($downs | Measure-Object -Maximum).Maximum

# ---------- 3. Upload ----------
Write-Titulo "Upload (servidor Cloudflare)"
$ups = @()
foreach ($mb in 5, 10) {
    $corpo = New-Object byte[] ($mb * 1000000)
    (New-Object Random).NextBytes($corpo)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [void]$wc.UploadData("https://speed.cloudflare.com/__up", "POST", $corpo)
    $sw.Stop()
    $mbps = ($corpo.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds
    $ups += $mbps
    "  {0,3} MB em {1:N2}s -> {2:N1} Mbps" -f $mb, $sw.Elapsed.TotalSeconds, $mbps
}
$upload = ($ups | Measure-Object -Maximum).Maximum

# ---------- 4. Veredito ----------
Write-Titulo "Resumo"
"Download: {0:N1} Mbps | Upload: {1:N1} Mbps | Ping: {2:N0} ms | Jitter: {3:N1} ms | Perda: {4:N1}%" -f $download, $upload, $latencia, $jitter, $perda

Write-Titulo "Como ficaria a videochamada"
# Requisitos aproximados (Zoom / Meet / Teams): Mbps de download e upload
$cenarios = @(
    @{ Nome = "So audio";                         Down = 0.1; Up = 0.1 },
    @{ Nome = "Video SD (360p)";                  Down = 0.6; Up = 0.6 },
    @{ Nome = "Video HD (720p) 1 para 1";         Down = 1.5; Up = 1.5 },
    @{ Nome = "Video Full HD (1080p)";            Down = 3.8; Up = 3.8 },
    @{ Nome = "Reuniao em grupo + tela compart."; Down = 4.0; Up = 3.0 }
)
foreach ($c in $cenarios) {
    $ok = ($download -ge $c.Down * 1.5) -and ($upload -ge $c.Up * 1.5)
    $lim = ($download -ge $c.Down) -and ($upload -ge $c.Up)
    if ($ok) { $txt = "OK"; $cor = "Green" } elseif ($lim) { $txt = "NO LIMITE"; $cor = "Yellow" } else { $txt = "RUIM"; $cor = "Red" }
    Write-Host ("  {0,-34} {1}" -f $c.Nome, $txt) -ForegroundColor $cor
}

Write-Host ""
$problemas = @()
if ($latencia -gt 150) { $problemas += "Latencia alta (>150 ms): atraso perceptivel na conversa." }
elseif ($latencia -gt 100) { $problemas += "Latencia moderada (100-150 ms): pode haver leve atraso." }
if ($jitter -gt 30) { $problemas += "Jitter alto (>30 ms): audio picotado e video travando." }
if ($perda -gt 1) { $problemas += "Perda de pacotes (>1%): cortes de audio e imagem congelando." }
if ($problemas.Count -eq 0) {
    Write-Host "Estabilidade: BOA (ping, jitter e perda dentro do ideal)." -ForegroundColor Green
} else {
    Write-Host "Estabilidade: ATENCAO" -ForegroundColor Yellow
    $problemas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
