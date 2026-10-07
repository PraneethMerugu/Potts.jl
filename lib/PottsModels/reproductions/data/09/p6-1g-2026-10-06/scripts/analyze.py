#!/usr/bin/env python3
"""P6.1g analysis (stdlib only): per-replicate summaries, the scan table and the pooled
time-to-single-cluster distribution. Run from the p6-1g-2026-10-06 directory:
    python3 scripts/analyze.py
Inputs: runs/*.tsv (this pass), ../full-2026-10-05/clusters.tsv + timeseries.tsv (P6.1f),
and docs/design/research/model-specs/evidence/09_v-pre5/diagnostic_v-pre5.tsv (D-151 diagnostic).
"""
import csv, glob, math, os, random, statistics as st

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.abspath(os.path.join(HERE, *[".."] * 6))
T_END = 20000
INF = math.inf


def rows(path):
    with open(path) as f:
        return list(csv.DictReader(f, delimiter="\t"))


# ---------- this pass ----------
reps = []
for p in sorted(glob.glob(os.path.join(HERE, "runs", "*.tsv"))):
    r = rows(p)
    by = {int(x["paper_mcs"]): x for x in r}
    ts = sorted(by)
    big = {t: float(by[t]["largest_dark_cluster"]) for t in ts}
    nc = {t: int(by[t]["dark_clusters"]) for t in ts}
    late = [t for t in ts if t >= 500]
    t90 = next((t for t in late if big[t] >= 0.90), INF)      # from 500 on: earlier, the dark cells still percolate (see README)
    t90_any = next((t for t in ts if big[t] >= 0.90), INF)
    t1 = next((t for t in ts if nc[t] == 1), INF)
    reverts = t90 < INF and any(big[t] < 0.90 for t in late if t > t90)
    x0 = r[0]
    reps.append(dict(
        set=x0["group"], n=int(x0["ncells"]), T=float(x0["T"]), Vd=float(x0["V_d"]), Vl=float(x0["V_l"]),
        start_seed=int(x0["start_seed"]), run_seed=int(x0["run_seed"]),
        t90=t90, t90_any=t90_any, t_single=t1, reverts=reverts,
        **{f"largest@{t}": big[t] for t in (10, 100, 1000, 10000, 20000)},
        **{f"clusters@{t}": nc[t] for t in (10, 100, 1000, 10000, 20000)},
        **{f"F_dl@{t}": float(by[t]["F_dl"]) for t in (10, 100, 1000, 10000, 20000)},
        **{f"F_dM@{t}": float(by[t]["F_dM"]) for t in (1000, 10000, 20000)},
        da1000=float(by[1000]["mean_area_light"]) - float(by[1000]["mean_area_dark"]),
        alive=int(by[T_END]["alive_dark"]) + int(by[T_END]["alive_light"]),
        isolated_all=all(x["isolated"] == "true" for x in r),
        wall_s=float(x0["wall_s"]),
        traj={t: big[t] for t in ts}))


def fmt_t(t):
    return ">20000" if t == INF else str(int(t))


cols = ["set", "n", "T", "Vd", "Vl", "start_seed", "run_seed", "t90", "t90_any", "t_single", "reverts",
        "largest@10", "largest@100", "largest@1000", "largest@10000", "largest@20000",
        "clusters@10", "clusters@100", "clusters@1000", "clusters@10000", "clusters@20000",
        "F_dl@10", "F_dl@100", "F_dl@1000", "F_dl@10000", "F_dl@20000", "F_dM@1000", "F_dM@10000", "F_dM@20000",
        "da1000", "alive", "isolated_all", "wall_s"]
with open(os.path.join(HERE, "replicates.tsv"), "w") as f:
    f.write("\t".join(cols) + "\n")
    for r in reps:
        f.write("\t".join(fmt_t(r[c]) if c in ("t90", "t90_any", "t_single") else
                          (f"{r[c]:.4f}" if isinstance(r[c], float) else str(r[c])) for c in cols) + "\n")


# ---------- statistics ----------
def mean_se(v):
    v = list(v)
    m = st.mean(v)
    return m, (st.stdev(v) / math.sqrt(len(v)) if len(v) > 1 else float("nan"))


def frac_se(k, n):
    p = k / n
    return p, math.sqrt(max(p * (1 - p), 0.25 / n) / n)   # floor so 0/n and n/n carry an SE


def quantile_censored(ts, q):
    """ECDF quantile with right-censoring at T_END (all censoring times equal)."""
    s = sorted(ts)
    k = math.ceil(q * len(s)) - 1
    return s[max(k, 0)]


def perm_p(a, b, stat, n=20000, seed=1):
    """two-sided permutation p for the difference in `stat` between groups a and b"""
    rng = random.Random(seed)
    obs = abs(stat(a) - stat(b))
    pool, na, hits = a + b, len(a), 0
    for _ in range(n):
        rng.shuffle(pool)
        hits += abs(stat(pool[:na]) - stat(pool[na:])) >= obs - 1e-12
    return (hits + 1) / (n + 1)


def summary(rs):
    k = len(rs)
    t90 = [r["t90"] for r in rs]
    out = dict(k=k)
    out["largest10k"] = mean_se(r["largest@10000"] for r in rs)
    out["largest20k"] = mean_se(r["largest@20000"] for r in rs)
    out["ge90_10k"] = frac_se(sum(r["largest@10000"] >= 0.9 for r in rs), k)
    out["by5000"] = frac_se(sum(t <= 5000 for t in t90), k)
    out["by10000"] = frac_se(sum(t <= 10000 for t in t90), k)
    out["by20000"] = frac_se(sum(t <= 20000 for t in t90), k)
    out["median"] = quantile_censored(t90, 0.5)
    out["q25"], out["q75"] = quantile_censored(t90, 0.25), quantile_censored(t90, 0.75)
    out["rmean"] = st.mean(min(t, T_END) for t in t90)   # restricted mean, censored at 2×10⁴
    out["Fdl10k"] = mean_se(r["F_dl@10000"] for r in rs)
    out["Fdl"] = {t: mean_se(r[f"F_dl@{t}"] for r in rs) for t in (10, 100, 1000)}
    out["FdM10k"] = mean_se(r["F_dM@10000"] for r in rs)
    out["da"] = mean_se(r["da1000"] for r in rs)
    out["clusters10k"] = mean_se(r["clusters@10000"] for r in rs)
    return out


def pm(ms, d=3):
    return f"{ms[0]:.{d}f} ± {ms[1]:.{d}f}"


base = [r for r in reps if r["set"] == "dist"]
points = [("dist (T = 10, n = 1000, page)", base)]
for T in (5.0, 7.0, 14.0, 20.0):
    points.append((f"(a) T = {T:g}", [r for r in reps if r["set"] == "Tscan" and r["T"] == T]))
points.append(("(b) equal sizes", [r for r in reps if r["set"] == "equalsize"]))
for n in (500, 1500):
    points.append((f"(c) n = {n}", [r for r in reps if r["set"] == "aggsize" and r["n"] == n]))
points.append(("fresh (page, seeds 5001–5020)", [r for r in reps if r["set"] == "fresh"]))
points = [(name, rs) for name, rs in points if rs]

hdr = ["point", "k", "largest@1e4 (mean±SE)", "Δ vs dist (p)", "frac ≥0.90 @1e4", "frac t90≤5000", "Δ vs dist (p)",
       "frac t90≤1e4", "frac t90≤2e4", "t90 median [IQR]", "t90 restricted mean", "largest@2e4", "F_dl@1e4", "Δ vs dist (p)",
       "F_dl@10", "F_dl@100", "F_dl@1e3", "F_dM@1e4", "clusters@1e4", "Δa@1e3 (l−d)"]
lines = ["\t".join(hdr)]
mean = lambda v: sum(v) / len(v)
for name, rs in points:
    s = summary(rs)
    if rs is base:
        d1 = d2 = d3 = "—"
    else:
        a = [r["largest@10000"] for r in rs]; b = [r["largest@10000"] for r in base]
        d1 = f"{mean(a) - mean(b):+.3f} (p={perm_p(a, b, mean):.3f})"
        a = [float(r["t90"] <= 5000) for r in rs]; b = [float(r["t90"] <= 5000) for r in base]
        d2 = f"{mean(a) - mean(b):+.3f} (p={perm_p(a, b, mean):.3f})"
        a = [r["F_dl@10000"] for r in rs]; b = [r["F_dl@10000"] for r in base]
        d3 = f"{mean(a) - mean(b):+.4f} (p={perm_p(a, b, mean):.3f})"
    lines.append("\t".join([name, str(s["k"]), pm(s["largest10k"]), d1, pm(s["ge90_10k"], 2), pm(s["by5000"], 2), d2,
                            pm(s["by10000"], 2), pm(s["by20000"], 2),
                            f"{fmt_t(s['median'])} [{fmt_t(s['q25'])}, {fmt_t(s['q75'])}]", f"{s['rmean']:.0f}",
                            pm(s["largest20k"]), pm(s["Fdl10k"], 4), d3,
                            pm(s["Fdl"][10]), pm(s["Fdl"][100]), pm(s["Fdl"][1000]), pm(s["FdM10k"], 4),
                            pm(s["clusters10k"], 2), pm(s["da"], 2)]))
with open(os.path.join(HERE, "scan.tsv"), "w") as f:
    f.write("\n".join(lines) + "\n")

# ---------- pooled page-parameter distribution ----------
# earlier 22: P6.1f (10; largest only at 10, 10², 10³, 10⁴) and the D-151 diagnostic (12; saves 10³, 2000, …, 2×10⁴)
old = []
full = os.path.join(HERE, "..", "full-2026-10-05")
cl = rows(os.path.join(full, "clusters.tsv"))
ts_ = rows(os.path.join(full, "timeseries.tsv"))
for i in sorted({int(x["replicate"]) for x in cl}):
    big = {int(float(x["paper_mcs"])): float(x["largest_dark_cluster"]) for x in cl if int(x["replicate"]) == i}
    fdl = {int(float(x["paper_mcs"])): float(x["F_dl"]) for x in ts_ if int(x["replicate"]) == i}
    old.append(dict(src="P6.1f", id=i, big=big, fdl10k=fdl[10000], fdl20k=fdl[20000]))
diag = rows(os.path.join(ROOT, "docs/design/research/model-specs/evidence/09_v-pre5/diagnostic_v-pre5.tsv"))
for key in sorted({(x["seed"], x["relaxed"]) for x in diag}):
    sel = [x for x in diag if (x["seed"], x["relaxed"]) == key]
    big = {int(x["t"]): float(x["largest"]) for x in sel}
    fdl = {int(x["t"]): float(x["F_dl"]) for x in sel}
    old.append(dict(src="D-151 diag" + (" relaxed" if key[1] == "true" else ""), id=int(key[0]), big=big,
                    fdl10k=fdl[10000], fdl20k=fdl[20000]))

page_new = [r for r in reps if r["set"] in ("dist", "fresh")]
P = []
for r in page_new:
    P.append(dict(src=r["set"], big10k=r["largest@10000"], by5000=r["t90"] <= 5000, by10k=r["t90"] <= 10000,
                  by20k=r["t90"] <= 20000, t90=r["t90"], fdl10k=r["F_dl@10000"], fdl20k=r["F_dl@20000"]))
for o in old:
    b = o["big"]
    late = sorted(t for t in b if t >= 1000)
    t90 = next((t for t in late if b[t] >= 0.9), INF)
    P.append(dict(src=o["src"], big10k=b[10000],
                  by5000=(t90 <= 5000) if 5000 in b or t90 <= 1000 else (None if b[10000] >= 0.9 else False),
                  by10k=t90 <= 10000, by20k=(t90 <= 20000) if 20000 in b else None,
                  t90=t90 if 5000 in b else None, fdl10k=o["fdl10k"], fdl20k=o["fdl20k"]))

out = []
def frac_of(key, rs):
    v = [r[key] for r in rs if r[key] is not None]
    k = sum(v)
    p, se = frac_se(k, len(v))
    return f"{k}/{len(v)} = {p:.2f} ± {se:.2f}"
for label, rs in (("new page-parameter runs (dist + fresh)", P[:len(page_new)]), ("earlier 22 (P6.1f + D-151 diag)", P[len(page_new):]),
                  ("pooled", P)):
    out.append(f"## {label}: k = {len(rs)}")
    out.append(f"single (≥ 0.90) by 5000: {frac_of('by5000', rs)}")
    out.append(f"single by 10⁴: {frac_of('by10k', rs)}")
    out.append(f"single by 2×10⁴: {frac_of('by20k', rs)}")
    t = [r["t90"] for r in rs if r["t90"] is not None]
    if t:
        out.append(f"t90 over the {len(t)} with saves ≥ every 1000: median {fmt_t(quantile_censored(t, .5))}, "
                   f"IQR [{fmt_t(quantile_censored(t, .25))}, {fmt_t(quantile_censored(t, .75))}], "
                   f"restricted mean (censored at 2×10⁴) {st.mean(min(x, T_END) for x in t):.0f}, "
                   f"mean over those reaching it {st.mean([x for x in t if x < INF]) if any(x < INF for x in t) else float('nan'):.0f}")
    out.append(f"largest@10⁴: mean {pm(mean_se(r['big10k'] for r in rs))}")
    out.append(f"F_dl@10⁴: mean {pm(mean_se(r['fdl10k'] for r in rs), 4)}; min {min(r['fdl10k'] for r in rs):.4f}; "
               f"≤ 0.050: {sum(r['fdl10k'] <= 0.050 for r in rs)}, ≤ 0.040: {sum(r['fdl10k'] <= 0.040 for r in rs)}")
    out.append(f"F_dl@2×10⁴: mean {pm(mean_se(r['fdl20k'] for r in rs), 4)}; min {min(r['fdl20k'] for r in rs):.4f}")
    out.append("")
# resampling: chance that a 10-replicate page ensemble (n = 10, as frozen) reads mean largest@10⁴ ≥ 0.90
rng = random.Random(7)
v = [r["big10k"] for r in P]
hits = sum(mean(rng.choices(v, k=10)) >= 0.90 for _ in range(100000))
out.append(f"bootstrap over the pooled {len(v)}: P(10-replicate mean largest@10⁴ ≥ 0.90) = {hits / 100000:.3f}")
# exchangeability rank of the two published F_dl@10⁴ (0.050 PRE, 0.040 PRL) among the pooled replicates
N = len(P)
k50 = sum(r["fdl10k"] <= 0.050 for r in P); k40 = sum(r["fdl10k"] <= 0.040 for r in P)
out.append(f"F_dl@10⁴ ≤ 0.050 in {k50} of {N}; ≤ 0.040 in {k40} of {N}")
fresh = [r for r in reps if r["set"] == "fresh"]
if fresh:
    for lo in range(0, len(fresh), 10):
        g = fresh[lo:lo + 10]
        out.append(f"fresh seeds {g[0]['start_seed']}–{g[-1]['start_seed']} as a 10-replicate page ensemble: "
                   f"mean largest@10⁴ {mean([r['largest@10000'] for r in g]):.3f} (frozen bound ≥ 0.90)")
with open(os.path.join(HERE, "pooled.txt"), "w") as f:
    f.write("\n".join(out) + "\n")
print("\n".join(lines).replace("\t", " | "))
print()
print("\n".join(out))

# ---------- post hoc, descriptive: light inclusions (runs/incl_*, the dist seeds re-run) ----------
inc = []
for p in sorted(glob.glob(os.path.join(HERE, "runs", "incl_*.tsv"))):
    r = rows(p)
    s = int(r[0]["start_seed"])
    twin = os.path.join(HERE, "runs", f"dist_n1000_T10_V40-40_s{s}.tsv")
    same = None
    if os.path.exists(twin):
        a = rows(twin)
        same = all(x[c] == y[c] for x, y in zip(a, r) for c in ("F_dl", "F_dd", "F_ll", "largest_dark_cluster", "dark_clusters"))
    by = {int(x["paper_mcs"]): x for x in r}
    ts = sorted(by)
    ninc = {t: int(by[t]["light_inclusions"]) for t in ts}
    # last breakthrough: first save from which no light inclusion remains to 2×10⁴
    t_clear = next((t for t in ts if t >= 500 and all(ninc[u] == 0 for u in ts if u >= t)), INF)
    inc.append(dict(seed=s, same=same, t_clear=t_clear, inc1e3=ninc[1000], inc1e4=ninc[10000], inc2e4=ninc[20000],
                    cells1e4=int(by[10000]["light_inclusion_cells"]), big1e4=float(by[10000]["largest_dark_cluster"]),
                    fdl1e4=float(by[10000]["F_dl"]), fdl2e4=float(by[20000]["F_dl"]),
                    big2e4=float(by[20000]["largest_dark_cluster"])))
if inc:
    lines2 = ["start_seed\tsame_as_dist\tt_no_light_inclusion\tinclusions@1e3\tinclusions@1e4\tinclusion_cells@1e4\tinclusions@2e4\tlargest@1e4\tF_dl@1e4\tlargest@2e4\tF_dl@2e4"]
    for d in inc:
        lines2.append("\t".join(map(str, (d["seed"], d["same"], fmt_t(d["t_clear"]), d["inc1e3"], d["inc1e4"], d["cells1e4"], d["inc2e4"],
                                          d["big1e4"], d["fdl1e4"], d["big2e4"], d["fdl2e4"]))))
    with open(os.path.join(HERE, "light_inclusions.tsv"), "w") as f:
        f.write("\n".join(lines2) + "\n")
    o2 = [f"## light inclusions (post hoc, descriptive): k = {len(inc)}; trajectories identical to dist: "
          f"{sum(d['same'] is True for d in inc)}/{sum(d['same'] is not None for d in inc)}"]
    tc = [d["t_clear"] for d in inc]
    o2.append(f"no light inclusion left by 5000: {sum(t <= 5000 for t in tc)}/{len(tc)}; by 10⁴: {sum(t <= 10000 for t in tc)}; "
              f"by 2×10⁴: {sum(t <= 20000 for t in tc)}; median {fmt_t(quantile_censored(tc, .5))}")
    o2.append(f"inclusions at 10³ / 10⁴: mean {mean([d['inc1e3'] for d in inc]):.2f} / {mean([d['inc1e4'] for d in inc]):.2f}")
    for lab, sel in (("one dark cluster (≥ 0.99) and no inclusion @1e4", [d for d in inc if d["big1e4"] >= 0.99 and d["inc1e4"] == 0]),
                     ("one dark cluster (≥ 0.99) with inclusions @1e4", [d for d in inc if d["big1e4"] >= 0.99 and d["inc1e4"] > 0]),
                     ("several dark clusters (< 0.99) @1e4", [d for d in inc if d["big1e4"] < 0.99])):
        if sel:
            o2.append(f"{lab}: k = {len(sel)}, F_dl@1e4 mean {pm(mean_se(d['fdl1e4'] for d in sel), 4) if len(sel) > 1 else round(sel[0]['fdl1e4'], 4)}, "
                      f"range {min(d['fdl1e4'] for d in sel):.4f}–{max(d['fdl1e4'] for d in sel):.4f}")
    with open(os.path.join(HERE, "pooled.txt"), "a") as f:
        f.write("\n" + "\n".join(o2) + "\n")
    print("\n" + "\n".join(o2))
