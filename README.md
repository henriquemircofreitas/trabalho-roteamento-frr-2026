# Laboratório comparativo de roteamento com FRRouting

Projeto reproduzível com cinco roteadores virtuais em namespaces Linux, sete enlaces redundantes e uma rede de acesso por roteador. Compara OSPF, eBGP e um algoritmo próprio MC-Dijkstra. Cada solução é executada isoladamente: a topologia é recriada antes de cada rodada.

## Ambiente

- Ubuntu 26.04 em VirtualBox
- FRRouting 10.5.1
- Linux network namespaces + pares veth
- `tc netem` para atrasos controlados
- `iperf3`, `ping`, `tcpdump` e `jq` para medições

## Topologia

Enlaces: R1-R2, R1-R3, R2-R3, R2-R4, R3-R4, R3-R5 e R4-R5. As LANs são `10.10.N.0/24`, onde N é o número do roteador. Os enlaces ponto a ponto usam `10.0.XY.0/30`.

## Execução

```bash
chmod +x lab_setup_and_run.sh custom_router.py
sudo ./lab_setup_and_run.sh
```

O script executa OSPF, eBGP e MC-Dijkstra em sequência, coleta métricas e deixa OSPF ativo para a demonstração final.

## Estrutura

- `lab_setup_and_run.sh`: cria a topologia, gera configurações, executa testes e coleta resultados.
- `custom_router.py`: MC-Dijkstra com custo de atraso, capacidade e confiabilidade.
- `configs/`: configurações FRRouting por roteador e cópia do algoritmo.
- `results/`: tabelas de rotas, pings, testes iperf3, convergência e resumos dos protocolos.
- `pcaps/`: capturas de tráfego de controle de cada cenário.

## Resultado principal

Consulte `results/metrics.csv`. Todos os três cenários alcançaram conectividade fim a fim e recuperaram após a falha testada. O relatório PDF traz gráficos, interpretação e evidências.

## Reprodutibilidade e segurança

Execute em VM/laboratório. O script remove somente os namespaces `r1` a `r5` que ele próprio cria e as pastas FRRouting específicas deste laboratório.
