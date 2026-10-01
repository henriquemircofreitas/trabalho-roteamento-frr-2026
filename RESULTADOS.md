# Resultados experimentais

Os três cenários foram executados separadamente na mesma topologia. Todos alcançaram conectividade de R1 até R5.

| Solução | Rotas em R1 | Controle em 6 s | RTT médio | Taxa TCP |
|---|---:|---:|---:|---:|
| OSPF | 12 | 12 pacotes / 576 bytes | 19,919 ms | 1.518,9 Mbit/s |
| eBGP | 7 | 18 pacotes / 228 bytes | 24,966 ms | 761,9 Mbit/s |
| MC-Dijkstra | 7 | 0 pacotes / 0 bytes | 25,552 ms | 1.233,8 Mbit/s |

## Comparação controlada: mesma falha R3-R5

A queda do enlace R3-R5 foi aplicada três vezes em cada solução. O mesmo destino, a mesma forma de teste e o mesmo intervalo de estabilização foram usados em todas as rodadas.

| Solução | Resposta média | Mediana | Pings sem resposta | Recuperações corretas | O que ocorreu |
|---|---:|---:|---:|---:|---|
| OSPF | 29 ms | 27 ms | 0 | 3 de 3 | A rota ativa já passava por R3-R4 e não mudou. |
| eBGP | 1.212 ms | 1.213 ms | 9 no total | 3 de 3 | R3 trocou o caminho direto R3-R5 pelo caminho via R4. |
| MC-Dijkstra | 184 ms | 184 ms | 0 | 3 de 3 | O programa recalculou as rotas; o caminho ativo já evitava R3-R5. |

### Conclusão

O **OSPF foi a melhor opção para esta rede interna**. Ele apresentou a menor resposta média no teste controlado, não perdeu pings e também obteve o menor RTT e a maior taxa TCP nas medições gerais. O eBGP funcionou corretamente, mas demorou mais porque precisava retirar o caminho pelo enlace que caiu. O MC-Dijkstra também funcionou, porém depende de um programa central para recalcular e instalar as rotas.

Os dados completos de cada repetição estão em `results/fair-r3-r5/`. O teste pode ser executado novamente com `sudo bash ~/routing-lab/fair_same_failure.sh`.

## Evidências incluídas

- Tabelas de roteamento por roteador.
- Vizinhanças OSPF em estado `Full`.
- Sessões eBGP estabelecidas.
- Pings fim a fim e testes iperf3.
- Capturas PCAP do tráfego de controle.
- Rotas antes e depois das falhas.
- Três repetições da mesma falha R3-R5 para cada solução.

Os arquivos brutos estão em `routing-lab-project.zip`. A versão principal para apresentação é `Trabalho_Roteamento_FRRouting.pdf`.
