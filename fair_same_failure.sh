#!/usr/bin/env bash
set -euo pipefail

LAB=/home/vboxuser/routing-lab
FAIR="$LAB/results/fair-r3-r5"

# Reaproveita somente as funcoes de criacao da topologia e do FRRouting.
source <(sed '/^run_ospf()/,$d' "$LAB/lab_setup_and_run.sh")

mkdir -p "$FAIR"
rm -f "$FAIR/trials.csv" "$FAIR/summary.csv"
echo 'solution,trial,first_success_ms,failed_pings,post_failure_rtt_ms,recovered,route_changed_r1,route_changed_r3' > "$FAIR/trials.csv"

route_line() {
  local ns=$1
  ip -n "$ns" route get 10.10.5.1 2>/dev/null | head -n 1 | sed 's/  */ /g'
}

ping_avg() {
  local ns=$1 out=$2
  ip netns exec "$ns" ping -I 10.10.1.1 -c 5 -i 0.2 -W 1 10.10.5.1 > "$out"
  awk -F'/' '/^rtt/ {print $5}' "$out"
}

trial() {
  local solution=$1 trial_no=$2 down_cmd=${3:-} up_cmd=${4:-}
  local before_r1 before_r3 after_r1 after_r3 start end elapsed failed=0 recovered=0 post_rtt='NA'

  before_r1=$(route_line r1)
  before_r3=$(route_line r3)
  printf '%s\n' "$before_r1" > "$FAIR/${solution}-${trial_no}-r1-before.txt"
  printf '%s\n' "$before_r3" > "$FAIR/${solution}-${trial_no}-r3-before.txt"

  start=$(date +%s%N)
  ip -n r3 link set r3r5 down
  if [[ -n "$down_cmd" ]]; then eval "$down_cmd"; fi

  for _ in $(seq 1 120); do
    if ip netns exec r1 ping -I 10.10.1.1 -c 1 -W 1 10.10.5.1 >/dev/null 2>&1; then
      recovered=1
      break
    fi
    failed=$((failed + 1))
    sleep 0.05
  done
  end=$(date +%s%N)
  elapsed=$(( (end-start)/1000000 ))

  after_r1=$(route_line r1)
  after_r3=$(route_line r3)
  printf '%s\n' "$after_r1" > "$FAIR/${solution}-${trial_no}-r1-after.txt"
  printf '%s\n' "$after_r3" > "$FAIR/${solution}-${trial_no}-r3-after.txt"
  if [[ "$recovered" == 1 ]]; then
    post_rtt=$(ping_avg r1 "$FAIR/${solution}-${trial_no}-post-ping.txt")
  fi

  local changed_r1=0 changed_r3=0
  [[ "$before_r1" != "$after_r1" ]] && changed_r1=1
  [[ "$before_r3" != "$after_r3" ]] && changed_r3=1
  echo "$solution,$trial_no,$elapsed,$failed,$post_rtt,$recovered,$changed_r1,$changed_r3" >> "$FAIR/trials.csv"

  ip -n r3 link set r3r5 up
  if [[ -n "$up_cmd" ]]; then eval "$up_cmd"; fi
  sleep 6
}

run_ospf_fair() {
  setup_topology
  write_ospf_configs
  start_frr ospf
  sleep 8
  vty_cmd r1 'show ip route ospf' > "$FAIR/ospf-routes-before.txt" 2>&1 || true
  for n in 1 2 3; do trial OSPF "$n"; done
}

run_bgp_fair() {
  setup_topology
  write_bgp_configs
  start_frr bgp
  sleep 10
  vty_cmd r1 'show ip route bgp' > "$FAIR/ebgp-routes-before.txt" 2>&1 || true
  for n in 1 2 3; do trial eBGP "$n"; done
}

run_custom_fair() {
  setup_topology
  python3 "$LAB/custom_router.py" --lab "$LAB" > "$FAIR/mc-initial.txt"
  sleep 2
  for n in 1 2 3; do
    trial MC-Dijkstra "$n" \
      "python3 '$LAB/custom_router.py' --lab '$LAB' --down R3-R5 > '$FAIR/mc-${n}-recompute-down.txt'" \
      "python3 '$LAB/custom_router.py' --lab '$LAB' > '$FAIR/mc-${n}-recompute-up.txt'"
  done
}

summarize() {
  echo 'solution,mean_first_success_ms,median_first_success_ms,total_failed_pings,mean_post_failure_rtt_ms,recovery_successes,route_changes_r1,route_changes_r3' > "$FAIR/summary.csv"
  for solution in OSPF eBGP MC-Dijkstra; do
    awk -F, -v s="$solution" '
      NR>1 && $1==s { n++; t[n]=$3+0; sum+=$3; failed+=$4; rtt+=$5; ok+=$6; c1+=$7; c3+=$8 }
      END {
        if (n==0) exit 1
        for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) if (t[i]>t[j]) {x=t[i];t[i]=t[j];t[j]=x}
        med=t[int((n+1)/2)]
        printf "%s,%.2f,%.2f,%d,%.3f,%d,%d,%d\n",s,sum/n,med,failed,rtt/n,ok,c1,c3
      }' "$FAIR/trials.csv" >> "$FAIR/summary.csv"
  done
}

systemctl stop frr 2>/dev/null || true
run_ospf_fair
run_bgp_fair
run_custom_fair
summarize
chown -R vboxuser:vboxuser "$FAIR"

printf '\n=== TESTES INDIVIDUAIS ===\n'
cat "$FAIR/trials.csv"
printf '\n=== RESUMO (MESMA FALHA R3-R5) ===\n'
cat "$FAIR/summary.csv"
