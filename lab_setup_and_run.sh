#!/usr/bin/env bash
set -euo pipefail

LAB=/home/vboxuser/routing-lab
RESULTS="$LAB/results"
CONFIGS="$LAB/configs"
PCAPS="$LAB/pcaps"
mkdir -p "$RESULTS" "$CONFIGS" "$PCAPS"
chown frr:frr "$RESULTS"

log() { printf '[LAB] %s\n' "$*"; }

cleanup_topology() {
  for n in r1 r2 r3 r4 r5; do
    if ip netns list | grep -q "^$n "; then
      ip netns pids "$n" 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      ip netns del "$n" 2>/dev/null || true
    fi
  done
  rm -rf /run/frr/lab-r1 /run/frr/lab-r2 /run/frr/lab-r3 /run/frr/lab-r4 /run/frr/lab-r5
  rm -f /run/frr/lab-r*-zserv.api /run/frr/lab-r*-zebra.vty /run/frr/lab-r*-ospfd.vty /run/frr/lab-r*-ripd.vty /run/frr/lab-r*-zebra.pid /run/frr/lab-r*-ospfd.pid /run/frr/lab-r*-ripd.pid
  rm -f /tmp/lab-r*-zebra.pid /tmp/lab-r*-ospfd.pid /tmp/lab-r*-ripd.pid
}

add_link() {
  local a=$1 b=$2 ifa=$3 ifb=$4 ipa=$5 ipb=$6 delay=$7
  ip link add "$ifa" type veth peer name "$ifb"
  ip link set "$ifa" netns "$a"
  ip link set "$ifb" netns "$b"
  ip -n "$a" addr add "$ipa" dev "$ifa"
  ip -n "$b" addr add "$ipb" dev "$ifb"
  ip -n "$a" link set "$ifa" up
  ip -n "$b" link set "$ifb" up
  ip netns exec "$a" tc qdisc add dev "$ifa" root netem delay "${delay}ms"
  ip netns exec "$b" tc qdisc add dev "$ifb" root netem delay "${delay}ms"
}

setup_topology() {
  cleanup_topology
  for i in 1 2 3 4 5; do
    local n="r$i"
    ip netns add "$n"
    ip -n "$n" link set lo up
    ip netns exec "$n" sysctl -qw net.ipv4.ip_forward=1
    ip -n "$n" link add lan type dummy
    ip -n "$n" addr add "10.10.${i}.1/24" dev lan
    ip -n "$n" link set lan up
  done
  add_link r1 r2 r1r2 r2r1 10.0.12.1/30 10.0.12.2/30 2
  add_link r1 r3 r1r3 r3r1 10.0.13.1/30 10.0.13.2/30 4
  add_link r2 r3 r2r3 r3r2 10.0.23.1/30 10.0.23.2/30 1
  add_link r2 r4 r2r4 r4r2 10.0.24.1/30 10.0.24.2/30 8
  add_link r3 r4 r3r4 r4r3 10.0.34.1/30 10.0.34.2/30 3
  add_link r3 r5 r3r5 r5r3 10.0.35.1/30 10.0.35.2/30 7
  add_link r4 r5 r4r5 r5r4 10.0.45.1/30 10.0.45.2/30 2
}

write_zebra_configs() {
  for i in 1 2 3 4 5; do
    local d="/etc/frr/lab-r$i"
    mkdir -p "$d" "/run/frr/lab-r$i"
    chown -R frr:frr "$d" "/run/frr/lab-r$i"
    chmod 775 "/run/frr/lab-r$i"
    cat > "$d/zebra.conf" <<EOF
hostname R$i
password lab
enable password lab
ip forwarding
EOF
  done
}

ospf_interfaces() {
  case "$1" in
    1) echo 'r1r2:2 r1r3:4' ;;
    2) echo 'r2r1:2 r2r3:1 r2r4:8' ;;
    3) echo 'r3r1:4 r3r2:1 r3r4:3 r3r5:7' ;;
    4) echo 'r4r2:8 r4r3:3 r4r5:2' ;;
    5) echo 'r5r3:7 r5r4:2' ;;
  esac
}

write_ospf_configs() {
  write_zebra_configs
  for i in 1 2 3 4 5; do
    local d="/etc/frr/lab-r$i"
    {
      echo "hostname R$i"
      echo 'password lab'
      echo 'enable password lab'
      echo 'router ospf'
      echo " ospf router-id $i.$i.$i.$i"
      echo ' network 10.0.0.0/8 area 0.0.0.0'
      echo ' passive-interface lan'
      echo 'exit'
      for item in $(ospf_interfaces "$i"); do
        local intf=${item%%:*}
        local cost=${item##*:}
        echo "interface $intf"
        echo ' ip ospf hello-interval 1'
        echo ' ip ospf dead-interval 3'
        echo ' ip ospf network point-to-point'
        echo " ip ospf cost $cost"
        echo 'exit'
      done
    } > "$d/ospfd.conf"
    cat "$d/zebra.conf" "$d/ospfd.conf" > "$d/frr.conf"
  done
}

write_rip_configs() {
  write_zebra_configs
  for i in 1 2 3 4 5; do
    local d="/etc/frr/lab-r$i"
    cat > "$d/ripd.conf" <<EOF
hostname R$i
password lab
enable password lab
router rip
 version 2
 timers basic 2 6 6
 network 10.0.0.0/8
 passive-interface lan
 redistribute connected
EOF
    cat "$d/zebra.conf" "$d/ripd.conf" > "$d/frr.conf"
  done
}

bgp_neighbors() {
  case "$1" in
    1) echo '10.0.12.2:65002 10.0.13.2:65003' ;;
    2) echo '10.0.12.1:65001 10.0.23.2:65003 10.0.24.2:65004' ;;
    3) echo '10.0.13.1:65001 10.0.23.1:65002 10.0.34.2:65004 10.0.35.2:65005' ;;
    4) echo '10.0.24.1:65002 10.0.34.1:65003 10.0.45.2:65005' ;;
    5) echo '10.0.35.1:65003 10.0.45.1:65004' ;;
  esac
}

write_bgp_configs() {
  write_zebra_configs
  for i in 1 2 3 4 5; do
    local d="/etc/frr/lab-r$i" as=$((65000+i)) item peer remote
    {
      echo "hostname R$i"
      echo 'password lab'
      echo 'enable password lab'
      echo "router bgp $as"
      echo " bgp router-id $i.$i.$i.$i"
      echo ' no bgp ebgp-requires-policy'
      echo ' timers bgp 1 3'
      echo " network 10.10.$i.0/24"
      for item in $(bgp_neighbors "$i"); do
        peer=${item%%:*}; remote=${item##*:}
        echo " neighbor $peer remote-as $remote"
      done
    } > "$d/bgpd.conf"
    cat "$d/zebra.conf" "$d/bgpd.conf" > "$d/frr.conf"
  done
}

ns_pid() {
  local ns=$1 name=$2 p exe
  for p in $(ip netns pids "$ns"); do
    exe=$(basename "$(readlink "/proc/$p/exe" 2>/dev/null || true)")
    if [[ "$exe" == "$name" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

start_frr() {
  local proto=$1
  touch /etc/frr/zebra.conf "/etc/frr/${proto}d.conf" /etc/frr/frr.conf
  for i in 1 2 3 4 5; do
    ip netns exec "r$i" unshare -m --propagation private bash -c "
      mount --bind /run/frr/lab-r$i /run/frr
      mount --bind /etc/frr/lab-r$i/zebra.conf /etc/frr/zebra.conf
      mount --bind /etc/frr/lab-r$i/${proto}d.conf /etc/frr/${proto}d.conf
      mount --bind /etc/frr/lab-r$i/frr.conf /etc/frr/frr.conf
      chown frr:frr /run/frr
      /usr/lib/frr/zebra -d -u frr -g frr
      sleep 1
      /usr/lib/frr/${proto}d -d -u frr -g frr
      sleep 1
      vtysh -b
      exec sleep infinity
    " > "$RESULTS/r${i}-${proto}-supervisor.log" 2>&1 &
  done
  sleep 4
  for i in 1 2 3 4 5; do
    ns_pid "r$i" zebra >/dev/null
    ns_pid "r$i" "${proto}d" >/dev/null
  done
}

vty_cmd() {
  local ns=$1 cmd=$2 pid
  pid=$(ns_pid "$ns" zebra)
  nsenter -t "$pid" -m -n vtysh -c "$cmd"
}

parse_ping_avg() {
  awk -F'/' '/^rtt/ {print $5}' "$1"
}

capture_control() {
  local mode=$1 filter=$2 iface=$3
  local pcap="$PCAPS/${mode}-control.pcap"
  ip netns exec r1 timeout 6 tcpdump -U -i "$iface" -nn -w "$pcap" "$filter" >/dev/null 2>&1 || true
  local packets bytes
  packets=$(tcpdump -nn -r "$pcap" 2>/dev/null | wc -l)
  bytes=$(tcpdump -nn -r "$pcap" 2>/dev/null | sed -n 's/.*length \([0-9][0-9]*\).*/\1/p' | awk '{s+=$1} END{print s+0}')
  printf '%s,%s\n' "$packets" "$bytes"
}

measure_common() {
  local mode=$1 filter=$2 iface=$3
  local pingfile="$RESULTS/${mode}-ping.txt"
  ip netns exec r1 ping -I 10.10.1.1 -c 12 -i 0.2 -W 1 10.10.5.1 > "$pingfile"
  local rtt
  rtt=$(parse_ping_avg "$pingfile")

  ip netns exec r5 iperf3 -s -B 10.10.5.1 -1 > "$RESULTS/${mode}-iperf-server.txt" 2>&1 &
  sleep 0.5
  ip netns exec r1 iperf3 -B 10.10.1.1 -c 10.10.5.1 -t 3 -J > "$RESULTS/${mode}-iperf.json"
  local mbps
  mbps=$(jq -r '.end.sum_received.bits_per_second/1000000' "$RESULTS/${mode}-iperf.json")

  local route_count
  route_count=$(ip -n r1 -4 route show | wc -l)
  ip -n r1 -4 route show > "$RESULTS/${mode}-r1-routes.txt"
  for i in 1 2 3 4 5; do ip -n "r$i" -4 route show > "$RESULTS/${mode}-r${i}-routes.txt"; done

  local ctrl packets bytes
  ctrl=$(capture_control "$mode" "$filter" "$iface")
  packets=${ctrl%,*}
  bytes=${ctrl#*,}
  printf '%s,%s,%s,%s,%s\n' "$route_count" "$packets" "$bytes" "$rtt" "$mbps"
}

measure_failover() {
  local mode=$1 ns=$2 iface=$3 recompute=${4:-}
  local start end ok=0
  ip -n "$ns" link set "$iface" down
  start=$(date +%s%N)
  if [[ -n "$recompute" ]]; then eval "$recompute"; fi
  for _ in $(seq 1 120); do
    if ip netns exec r1 ping -I 10.10.1.1 -c 1 -W 1 10.10.5.1 >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 0.1
  done
  end=$(date +%s%N)
  local ms=$(( (end-start)/1000000 ))
  printf '%s\n' "$ms" > "$RESULTS/${mode}-convergence-ms.txt"
  printf '%s\n' "$ok" > "$RESULTS/${mode}-recovered.txt"
  ip -n r1 -4 route show > "$RESULTS/${mode}-r1-routes-after-failure.txt"
  ip -n r5 -4 route show > "$RESULTS/${mode}-r5-routes-after-failure.txt"
  printf '%s\n' "$ms"
}

run_ospf() {
  log 'Rodada OSPF'
  setup_topology
  write_ospf_configs
  start_frr ospf
  sleep 8
  vty_cmd r1 'show ip ospf neighbor' > "$RESULTS/ospf-neighbors.txt" 2>&1 || true
  vty_cmd r1 'show ip route ospf' > "$RESULTS/ospf-vty-routes.txt" 2>&1 || true
  local common conv
  common=$(measure_common ospf 'ip proto 89' r1r3)
  conv=$(measure_failover ospf r3 r3r4)
  echo "OSPF,$common,$conv" >> "$RESULTS/metrics.csv"
}

run_rip() {
  log 'Rodada RIPv2'
  setup_topology
  write_rip_configs
  start_frr rip
  sleep 10
  vty_cmd r1 'show ip rip status' > "$RESULTS/rip-status.txt" 2>&1 || true
  vty_cmd r1 'show ip route rip' > "$RESULTS/rip-vty-routes.txt" 2>&1 || true
  local common conv
  common=$(measure_common rip 'udp port 520' r1r3)
  conv=$(measure_failover rip r3 r3r5)
  echo "RIPv2,$common,$conv" >> "$RESULTS/metrics.csv"
}

run_bgp() {
  log 'Rodada eBGP'
  setup_topology
  write_bgp_configs
  start_frr bgp
  sleep 10
  vty_cmd r1 'show bgp summary' > "$RESULTS/bgp-summary.txt" 2>&1 || true
  vty_cmd r1 'show ip route bgp' > "$RESULTS/bgp-vty-routes.txt" 2>&1 || true
  local common conv
  common=$(measure_common bgp 'tcp port 179' r1r3)
  conv=$(measure_failover bgp r3 r3r5)
  echo "eBGP,$common,$conv" >> "$RESULTS/metrics.csv"
}

run_custom() {
  log 'Rodada algoritmo proprio MC-Dijkstra'
  setup_topology
  local t0 t1 common conv
  t0=$(date +%s%N)
  python3 "$LAB/custom_router.py" --lab "$LAB" > "$RESULTS/custom-initial.txt"
  t1=$(date +%s%N)
  echo $(( (t1-t0)/1000000 )) > "$RESULTS/custom-initial-compute-ms.txt"
  common=$(measure_common custom 'ip proto 89 or udp port 520 or tcp port 179' r1r3)
  ip -n r1 link set r1r3 down
  python3 "$LAB/custom_router.py" --lab "$LAB" --down R1-R3 > "$RESULTS/custom-recompute.txt"
  conv=$(sed -n 's/.*compute_install_ms=\([0-9.]*\).*/\1/p' "$RESULTS/custom-recompute.txt")
  if ip netns exec r1 ping -I 10.10.1.1 -c 4 -W 1 10.10.5.1 > "$RESULTS/custom-failure-ping.txt" 2>&1; then echo 1 > "$RESULTS/custom-recovered.txt"; else echo 0 > "$RESULTS/custom-recovered.txt"; fi
  ip -n r1 -4 route show > "$RESULTS/custom-r1-routes-after-failure.txt"
  ip -n r5 -4 route show > "$RESULTS/custom-r5-routes-after-failure.txt"
  echo "$conv" > "$RESULTS/custom-convergence-ms.txt"
  echo "MC-Dijkstra,$common,$conv" >> "$RESULTS/metrics.csv"
}

export_configs() {
  rm -rf "$CONFIGS"/*
  cp -a /etc/frr/lab-r* "$CONFIGS"/
  cp "$LAB/custom_router.py" "$CONFIGS"/
  cat > "$LAB/README.md" <<'EOF'
# Laboratorio de roteamento - 5 roteadores

Plataforma: FRRouting 10.5.1 em namespaces Linux.

Topologia: R1-R2, R1-R3, R2-R3, R2-R4, R3-R4, R3-R5 e R4-R5, com uma rede de acesso 10.10.N.0/24 em cada roteador.

Execucao completa: `sudo bash ~/routing-lab/lab_setup_and_run.sh`.

As rodadas OSPF, eBGP e MC-Dijkstra sao executadas separadamente. O script recria a topologia antes de cada solucao, impedindo execucao simultanea. Ao final, OSPF e deixado ativo para demonstracao.

Resultados: `results/metrics.csv`, tabelas de roteamento, vizinhancas, pings, iperf3, logs e capturas em `pcaps/`.
EOF
}

leave_demo_running() {
  log 'Deixando OSPF ativo para demonstracao'
  setup_topology
  write_ospf_configs
  start_frr ospf
  sleep 8
  ip netns exec r1 ping -I 10.10.1.1 -c 4 10.10.5.1 > "$RESULTS/final-demo-ping.txt"
}

main() {
  systemctl stop frr 2>/dev/null || true
  rm -f "$RESULTS/metrics.csv"
  echo 'solution,route_count_r1,control_packets_6s,control_bytes_6s,rtt_avg_ms,throughput_mbps,convergence_ms' > "$RESULTS/metrics.csv"
  run_ospf
  run_bgp
  run_custom
  export_configs
  leave_demo_running
  chown -R vboxuser:vboxuser "$LAB"
  tar --exclude='routing-lab/routing-lab-artifacts.tar.gz' -C /home/vboxuser -czf /home/vboxuser/routing-lab-artifacts.tar.gz routing-lab
  chown vboxuser:vboxuser /home/vboxuser/routing-lab-artifacts.tar.gz
  log 'CONCLUIDO'
  cat "$RESULTS/metrics.csv"
}

trap 'echo "Falha na linha $LINENO" >&2' ERR
main "$@"
