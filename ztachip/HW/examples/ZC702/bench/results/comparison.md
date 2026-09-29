# ZC702 ztachip — three-model benchmark (SmolLM2)

Same 30 prompts per model. tok/s & bytes/token from the on-chip PMU.

## Per-model results

| model | runs | mean tok/s | median | sd | gen tok | DDR stall % | MB/token |
|---|---|---|---|---|---|---|---|
| SmolLM2-135M  Q4 (repo default) | 30 | **4.13** | 4.21 | 0.29 | 213 | 42.5 | 103.2 |
| SmolLM2-135M  Q8 | 30 | **3.34** | 3.38 | 0.16 | 203 | 29.9 | 155.9 |
| SmolLM2-360M  Q4 | 30 | **1.90** | 1.89 | 0.04 | 146 | 36.3 | 248.4 |

## Memory-bound evidence

**Cleanest proof — Q4 vs Q8 of the SAME model.** They run the *identical*
network (same layers, dims, and number of multiply-adds per token); the only
difference is weight width, int4 vs int8 = ~1.5x the bytes. A **compute-bound**
design would run them at the **same tok/s**. It does not — moving more bytes
is the only thing that slows Q8 down, so the chip is **memory-bound**.

| model | bytes/token | tok/s | DDR read | rd_active | rd_stall | tps×B/tok |
|---|---|---|---|---|---|---|
| SmolLM2-135M  Q4 (repo default) | 103 MB | 4.13 | 431 MB/s | 59% | 42% | **426 MB/s** |
| SmolLM2-135M  Q8 | 156 MB | 3.34 | 526 MB/s | 71% | 30% | **520 MB/s** |
| SmolLM2-360M  Q4 | 248 MB | 1.90 | 478 MB/s | 65% | 36% | **472 MB/s** |

Notes:
- `rd_active` (DDR read engine busy fraction) is the majority of every run -> the read path, not compute, is the bottleneck.
- Effective bandwidth (tps × bytes/token) is NOT constant: int8's wider, more
  regular reads stall less than int4's 4-bit unpacking, so Q8 reaches a higher
  DDR bandwidth. Net: Q8 moves ~1.5x the bytes but is only ~1.2x slower.
- Peak sustained DDR read observed ~530 MB/s (Q8).

## Jetson TX1 reference (same prompts/definition)

| platform / model | runs | mean tok/s |
|---|---|---|
| Jetson TX1  SmolLM2-135M Q4_K_M | 150 | 14.92 |
| Jetson TX1  SmolLM2-135M Base | 150 | 13.46 |

## SmolLM2-135M  Q4 (repo default) — throughput by category

| category | mean tok/s |
|---|---|
| ENG | 4.03 |
| GEN | 4.29 |
| GEO | 4.25 |
| HIST | 4.32 |
| MATH | 3.86 |
| SCI | 4.05 |
