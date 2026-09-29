# Configurações principais

As configurações completas dos cinco roteadores estão no pacote `routing-lab-project.zip`, na pasta `configs/`. O script `lab_setup_and_run.sh` também gera todas elas automaticamente.

## OSPF — exemplo de R1

```text
router ospf
 ospf router-id 1.1.1.1
 network 10.0.0.0/8 area 0.0.0.0
 passive-interface lan
interface r1r2
 ip ospf hello-interval 1
 ip ospf dead-interval 3
 ip ospf network point-to-point
 ip ospf cost 2
interface r1r3
 ip ospf hello-interval 1
 ip ospf dead-interval 3
 ip ospf network point-to-point
 ip ospf cost 4
```

## eBGP — exemplo de R1

```text
router bgp 65001
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy
 timers bgp 1 3
 network 10.10.1.0/24
 neighbor 10.0.12.2 remote-as 65002
 neighbor 10.0.13.2 remote-as 65003
```

## Endereçamento

| Enlace | Rede |
|---|---|
| R1–R2 | 10.0.12.0/30 |
| R1–R3 | 10.0.13.0/30 |
| R2–R3 | 10.0.23.0/30 |
| R2–R4 | 10.0.24.0/30 |
| R3–R4 | 10.0.34.0/30 |
| R3–R5 | 10.0.35.0/30 |
| R4–R5 | 10.0.45.0/30 |

Cada roteador Rn possui a LAN `10.10.n.0/24`.
