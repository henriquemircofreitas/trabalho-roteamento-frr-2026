#!/usr/bin/env python3
import argparse
import heapq
import subprocess
import time

ROUTERS = ["R1", "R2", "R3", "R4", "R5"]
LAN = {r: f"10.10.{i}.0/24" for i, r in enumerate(ROUTERS, 1)}

# a, b, a_ip, b_ip, a_if, b_if, delay_ms, capacity_mbps, reliability
EDGES = [
    ("R1", "R2", "10.0.12.1", "10.0.12.2", "r1r2", "r2r1", 2, 100, 0.99),
    ("R1", "R3", "10.0.13.1", "10.0.13.2", "r1r3", "r3r1", 4, 100, 0.97),
    ("R2", "R3", "10.0.23.1", "10.0.23.2", "r2r3", "r3r2", 1, 50, 0.98),
    ("R2", "R4", "10.0.24.1", "10.0.24.2", "r2r4", "r4r2", 8, 100, 0.98),
    ("R3", "R4", "10.0.34.1", "10.0.34.2", "r3r4", "r4r3", 3, 100, 0.90),
    ("R3", "R5", "10.0.35.1", "10.0.35.2", "r3r5", "r5r3", 7, 100, 0.70),
    ("R4", "R5", "10.0.45.1", "10.0.45.2", "r4r5", "r5r4", 2, 100, 0.99),
]


def score(delay, capacity, reliability):
    return delay + 100.0 / capacity + 25.0 * (1.0 - reliability)


def build_graph(down):
    graph = {r: [] for r in ROUTERS}
    for a, b, aip, bip, aif, bif, delay, cap, rel in EDGES:
        if down and {a, b} == set(down.split("-")):
            continue
        w = score(delay, cap, rel)
        graph[a].append((b, w, bip, aif))
        graph[b].append((a, w, aip, bif))
    return graph


def shortest(graph, src):
    dist = {r: float("inf") for r in ROUTERS}
    first = {}
    dist[src] = 0.0
    q = [(0.0, src, None, None, [src])]
    paths = {}
    while q:
        d, u, nh, dev, path = heapq.heappop(q)
        if d != dist[u]:
            continue
        paths[u] = path
        first[u] = (nh, dev)
        for v, w, next_ip, out_dev in graph[u]:
            nd = d + w
            if nd < dist[v]:
                dist[v] = nd
                fnh = next_ip if u == src else nh
                fdev = out_dev if u == src else dev
                heapq.heappush(q, (nd, v, fnh, fdev, path + [v]))
    return dist, first, paths


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser(description="Roteamento proprio MC-Dijkstra")
    ap.add_argument("--lab", required=True)
    ap.add_argument("--down", default="")
    args = ap.parse_args()
    graph = build_graph(args.down)
    started = time.perf_counter_ns()
    updates = 0
    for src in ROUTERS:
        dist, first, paths = shortest(graph, src)
        ns = src.lower()
        for dst in ROUTERS:
            if dst == src or dst not in paths:
                continue
            nh, dev = first[dst]
            metric = max(1, int(round(dist[dst] * 10)))
            # A metrica faz parte da chave da rota no kernel Linux. Sem limpar
            # o prefixo, uma recomputacao pode manter a rota antiga com menor
            # metrica e causar black-hole depois de uma falha de enlace.
            subprocess.run(
                ["ip", "netns", "exec", ns, "ip", "route", "flush", LAN[dst]],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            run(["ip", "netns", "exec", ns, "ip", "route", "add", LAN[dst], "via", nh, "dev", dev, "metric", str(metric)])
            updates += 1
            print(f"{src} -> {LAN[dst]} via {nh} dev {dev} score={dist[dst]:.2f} path={'-'.join(paths[dst])}")
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    print(f"updates={updates} compute_install_ms={elapsed_ms:.3f} down={args.down or 'none'}")


if __name__ == "__main__":
    main()
