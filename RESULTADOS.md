# Resultados experimentais

Os três cenários foram executados separadamente na mesma topologia. Todos alcançaram conectividade R1→R5 e recuperaram após a falha de enlace testada.

| Solução | Rotas em R1 | Controle em 6 s | RTT médio | Taxa TCP | Convergência |
|---|---:|---:|---:|---:|---:|
| OSPF | 12 | 12 pacotes / 576 bytes | 19,919 ms | 1.518,9 Mbit/s | 32 ms |
| eBGP | 7 | 18 pacotes / 228 bytes | 24,966 ms | 761,9 Mbit/s | 262 ms |
| MC-Dijkstra | 7 | 0 pacotes / 0 bytes | 25,552 ms | 1.233,8 Mbit/s | 61,471 ms |

## Evidências incluídas

- Tabelas de roteamento por roteador.
- Vizinhanças OSPF em estado `Full`.
- Sessões eBGP estabelecidas.
- Pings fim a fim e testes iperf3.
- Capturas PCAP do tráfego de controle.
- Rotas antes e depois das falhas.

Os arquivos brutos estão em `routing-lab-project.zip`. A análise completa, gráficos e capturas da VM estão em `Trabalho_Roteamento_FRRouting.pdf`.
