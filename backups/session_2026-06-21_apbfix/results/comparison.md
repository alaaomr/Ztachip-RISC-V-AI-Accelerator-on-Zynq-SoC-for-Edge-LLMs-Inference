# ZC702 ztachip vs Jetson TX1 — SmolLM2-135M

**Our run (ZC702 ztachip @93.75 MHz):** 97 runs
- mean throughput : **4.18 tok/s**  (median 4.25, sd 0.26)
- mean gen length : 194 tokens

- PMU: DDR read-stall **42.2%** of cycles, ~102.5 MB read per token  (memory-bound evidence)

## Comparison

| Platform / model | runs | mean tok/s | median | gen tok |
|---|---|---|---|---|
| **ZC702 ztachip — SmolLM2-135M (Q4 ZUF, repo default)** | 97 | **4.18** | 4.25 | 194 |
| Jetson TX1  SmolLM2-135M Q4_K_M | 150 | 14.92 | 15.65 | 145 |  _(3.6x ours)_
| Jetson TX1  SmolLM2-135M Base | 150 | 13.46 | 15.19 | 125 |  _(3.2x ours)_

## Our throughput by category

| category | mean tok/s |
|---|---|
| ENG | 4.19 |
| GEN | 4.15 |
| GEO | 4.21 |
| HIST | 4.28 |
| MATH | 4.12 |
| SCI | 4.14 |

_Note: same 30-prompt set and same tps definition (gen_tokens / decode wall-time) as the Jetson runs. Our tok/s and wall-time come from the on-chip PMU cycle counter (excludes JTAG-console overhead). Power compared separately._
