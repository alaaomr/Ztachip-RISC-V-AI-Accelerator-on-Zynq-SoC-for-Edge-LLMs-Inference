#!/usr/bin/env python3
"""
Summarize the ZC702 benchmark and compare it to the Jetson TX1 runs.

- reads  results/results_ZC702_SmolLM2-135M.csv   (written by board_benchmark.tcl)
- reads  results/raw_runs_ZC702.txt               -> builds outputs JSON (Jetson schema)
- reads  the teammate's Jetson CSVs (Q4_K_M Instruct + Base) for the comparison
- writes results/outputs_ZC702_SmolLM2-135M.json
- writes results/comparison.md
- prints a summary table to the console

Run:  python3 summarize.py
"""
import csv, json, os, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
RESDIR = os.path.join(HERE, "results")
OURS_CSV = os.path.join(RESDIR, "results_ZC702_SmolLM2-135M.csv")
RAW = os.path.join(RESDIR, "raw_runs_ZC702.txt")
OUT_JSON = os.path.join(RESDIR, "outputs_ZC702_SmolLM2-135M.json")
CMP_MD = os.path.join(RESDIR, "comparison.md")

JBASE = "/home/eslam-elshokafy/Downloads/jetson results-20260620T133521Z-3-001/jetson results"
JETSON = {
    "Jetson TX1  SmolLM2-135M Q4_K_M": os.path.join(JBASE, "smollm quantised/results_TX1_SmolLM2-135M-Instruct-Q4_K_M.csv"),
    "Jetson TX1  SmolLM2-135M Base":   os.path.join(JBASE, "smollm 135 M/results_TX1_SmolLM2-135M-Base.csv"),
}


def load_csv(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            try:
                r["gen_tokens"] = int(float(r["gen_tokens"]))
                r["wall_time_s"] = float(r["wall_time_s"])
                r["tps"] = float(r["tps"])
            except (ValueError, KeyError):
                continue
            rows.append(r)
    return rows


def stats(vals):
    vals = [v for v in vals if v > 0]
    if not vals:
        return (0, 0, 0, 0)
    return (st.mean(vals),
            st.median(vals),
            (st.pstdev(vals) if len(vals) > 1 else 0.0),
            len(vals))


def summarize(rows):
    tps = [r["tps"] for r in rows]
    gen = [r["gen_tokens"] for r in rows]
    m_tps, med_tps, sd_tps, n = stats(tps)
    m_gen = st.mean([g for g in gen if g > 0]) if gen else 0
    return dict(n=n, mean_tps=m_tps, median_tps=med_tps, sd_tps=sd_tps, mean_gen=m_gen)


def per_category(rows):
    cats = {}
    for r in rows:
        cats.setdefault(r["category"], []).append(r["tps"])
    return {c: stats(v)[0] for c, v in sorted(cats.items())}


def build_json_from_raw():
    if not os.path.exists(RAW):
        return
    out = []
    cur = None
    mode = None
    buf = []
    with open(RAW) as f:
        for line in f.read().split("\n"):
            if line.startswith("===RUN\t"):
                _, rep, pid, cat = line.split("\t")
                cur = {"repeat": int(rep), "prompt_id": pid, "category": cat,
                       "prompt": "", "output": ""}
            elif line.startswith("PROMPT\t") and cur is not None:
                cur["prompt"] = line.split("\t", 1)[1]
            elif line == "OUTPUT_BEGIN":
                mode = "out"; buf = []
            elif line == "OUTPUT_END":
                if cur is not None:
                    raw_out = "\n".join(buf).strip()
                    # The firmware echoes the typed prompt back at the start of the
                    # console output. Strip that echo so `output` is only the model's
                    # answer (the clean prompt is kept separately in `prompt`).
                    p = cur["prompt"].strip()
                    idx = raw_out.find(p)
                    if 0 <= idx < len(p) + 20:
                        raw_out = raw_out[idx + len(p):]
                    cur["output"] = raw_out.lstrip("\r\n :").strip()
                    out.append(cur)
                cur = None; mode = None
            elif mode == "out":
                buf.append(line)
    with open(OUT_JSON, "w") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {OUT_JSON}  ({len(out)} runs)")


def main():
    if not os.path.exists(OURS_CSV):
        print(f"ERROR: {OURS_CSV} not found -- run the benchmark first.")
        return
    ours = load_csv(OURS_CSV)
    s = summarize(ours)

    lines = []
    def P(x): print(x); lines.append(x)

    P("# ZC702 ztachip vs Jetson TX1 — SmolLM2-135M\n")
    P(f"**Our run (ZC702 ztachip @93.75 MHz):** {s['n']} runs")
    P(f"- mean throughput : **{s['mean_tps']:.2f} tok/s**  "
      f"(median {s['median_tps']:.2f}, sd {s['sd_tps']:.2f})")
    P(f"- mean gen length : {s['mean_gen']:.0f} tokens\n")

    # memory-bound evidence (PMU columns, if present)
    try:
        stall = [float(r["rd_stall_pct"]) for r in ours if float(r.get("rd_stall_pct", 0)) > 0]
        bpt = [float(r["bytes_per_tok"]) for r in ours if float(r.get("bytes_per_tok", 0)) > 0]
        if stall:
            P(f"- PMU: DDR read-stall **{st.mean(stall):.1f}%** of cycles, "
              f"~{st.mean(bpt)/1e6:.1f} MB read per token  (memory-bound evidence)\n")
    except (KeyError, ValueError):
        pass

    P("## Comparison\n")
    P("| Platform / model | runs | mean tok/s | median | gen tok |")
    P("|---|---|---|---|---|")
    P(f"| **ZC702 ztachip — SmolLM2-135M (Q4 ZUF, repo default)** | {s['n']} | "
      f"**{s['mean_tps']:.2f}** | {s['median_tps']:.2f} | {s['mean_gen']:.0f} |")
    for name, path in JETSON.items():
        if not os.path.exists(path):
            P(f"| {name} | (file missing) | - | - | - |")
            continue
        jr = load_csv(path)
        js = summarize(jr)
        ratio = (js["mean_tps"] / s["mean_tps"]) if s["mean_tps"] else 0
        P(f"| {name} | {js['n']} | {js['mean_tps']:.2f} | "
          f"{js['median_tps']:.2f} | {js['mean_gen']:.0f} |"
          f"  _({ratio:.1f}x ours)_" if ratio else "")

    P("\n## Our throughput by category\n")
    P("| category | mean tok/s |")
    P("|---|---|")
    for c, v in per_category(ours).items():
        P(f"| {c} | {v:.2f} |")

    P("\n_Note: same 30-prompt set and same tps definition (gen_tokens / decode wall-time) "
      "as the Jetson runs. Our tok/s and wall-time come from the on-chip PMU cycle counter "
      "(excludes JTAG-console overhead). Power compared separately._")

    with open(CMP_MD, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\nwrote {CMP_MD}")
    build_json_from_raw()


if __name__ == "__main__":
    main()
