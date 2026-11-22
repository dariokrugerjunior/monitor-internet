# Monitor de internet

Scripts em PowerShell para Windows que acompanham a qualidade da internet, pensados para videochamadas.

- **Ícone perto do relógio** com a velocidade máxima (Mbps), colorido pela qualidade da conexão:
  🟢 boa · 🟡 instável ou lenta · 🔴 ruim · **X** sem internet
- **Notificações** quando a internet cai, volta, fica instável ou lenta
- **Diagnóstico da queda**: indica se o problema parece estar no Wi-Fi/roteador ou na operadora
- **Histórico** em CSV (ping a cada segundo e testes de velocidade), útil para reclamar com a operadora
- **Teste rápido para videochamada**: diz se a conexão aguenta áudio, HD, Full HD e reuniões em grupo

## Instalar

Abra o **PowerShell** (não precisa ser administrador) e rode:

```powershell
irm https://raw.githubusercontent.com/dariokrugerjunior/monitor-internet/main/instalar.ps1 | iex
```

O instalador:
- copia os scripts para `%LOCALAPPDATA%\MonitorInternet`;
- faz o monitor abrir sozinho quando você entra no Windows;
- cria atalhos no Menu Iniciar ("Monitor de internet" e "Teste de videochamada");
- inicia o monitor.

Para **atualizar**, rode o mesmo comando de novo.

## Usar

| O que | Como |
|---|---|
| Ver detalhes | Passe o mouse no ícone: velocidade máxima, uso atual, ping, jitter e perda |
| Testar a velocidade agora | Botão direito no ícone > **Testar velocidade agora** |
| Ver o histórico | Botão direito no ícone > **Abrir registros** |
| Parar o monitor | Botão direito no ícone > **Parar monitor** |
| Abrir de novo | Menu Iniciar > **Monitor de internet** |
| Teste para videochamada | Menu Iniciar > **Teste de videochamada** |

Se o ícone não aparecer, clique na setinha `^` ao lado do relógio e arraste-o para a barra de tarefas.

### O que significam as medidas

| Medida | Frequência | Bom para videochamada |
|---|---|---|
| Ping (latência) | a cada segundo | até 100–150 ms |
| Jitter (variação do ping) | a cada segundo | até 30 ms |
| Perda de pacotes | a cada segundo | até 1–3% |
| Velocidade máxima | a cada 30 min, ou pelo menu | 10 Mbps ou mais |

A velocidade máxima não é medida o tempo todo porque o teste ocupa a conexão inteira por 1 a 2 segundos.
O teste é adiado se você estiver usando a internet (numa chamada, por exemplo). Cada teste usa cerca de 35 MB.

### Opções

Edite o atalho (ou rode o script direto) com parâmetros, por exemplo:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MonitorInternet\monitor-internet.ps1" -TesteVelocidadeMin 60 -NumeroNoIcone Ping
```

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `-NumeroNoIcone` | `Capacidade` | `Capacidade` (velocidade máxima), `Uso` (consumo agora) ou `Ping` |
| `-TesteVelocidadeMin` | `30` | Minutos entre testes de velocidade (`0` desliga) |
| `-LimiteVelocidade` | `10` | Mbps de download abaixo dos quais a internet é considerada lenta |
| `-LimiteLatencia` | `150` | Ping (ms) acima do qual a conexão é considerada instável |
| `-LimiteJitter` | `30` | Jitter (ms) acima do qual a conexão é considerada instável |
| `-LimitePerda` | `3` | Perda de pacotes (%) acima da qual a conexão é considerada instável |
| `-TestarNotificacao` | | Só mostra uma notificação de teste |

## Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MonitorInternet\desinstalar.ps1"
```

Use `-ManterRegistros` para guardar a pasta `logs`.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `monitor-internet.ps1` | O monitor (ícone, notificações e registros) |
| `teste-videochamada.ps1` | Teste único de velocidade, ping, jitter e perda, com o veredito para videochamada |
| `instalar.ps1` | Instala ou atualiza a partir deste repositório |
| `desinstalar.ps1` | Remove tudo |

Os testes de velocidade usam os servidores públicos da Cloudflare (`speed.cloudflare.com`), e o ping usa `1.1.1.1` e `8.8.8.8`.
