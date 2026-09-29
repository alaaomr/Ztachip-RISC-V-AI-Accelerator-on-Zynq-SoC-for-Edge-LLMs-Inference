# ZC702 ztachip — three-model benchmark (SmolLM2)

Same 30 prompts per model. tok/s & bytes/token from the on-chip PMU.

## Per-model results

| model | runs | mean tok/s | median | sd | gen tok | DDR stall % | MB/token |
|---|---|---|---|---|---|---|---|
| ZC702_SmolLM2-135M | 97 | **4.18** | 4.25 | 0.26 | 194 | 42.2 | 102.5 |

## Memory-bound proof:  tok/s × bytes/token = effective DDR bandwidth

A bandwidth-bound design streams ~all weights per token, so throughput is
set by `bandwidth / bytes_per_token`. If that's true, `tok/s × bytes/token`
is ~constant across models even though tok/s and size differ. It is:

| model | MB/token | tok/s | tok/s × MB/token = MB/s |
|---|---|---|---|
| ZC702_SmolLM2-135M | 102.5 | 4.18 | **428** |
## Jetson TX1 reference (same prompts/definition)

| platform / model | runs | mean tok/s |
|---|---|---|
| Jetson TX1  SmolLM2-135M Q4_K_M | 150 | 14.92 |
| Jetson TX1  SmolLM2-135M Base | 150 | 13.46 |

## ZC702_SmolLM2-135M — throughput by category

| category | mean tok/s |
|---|---|
| ENG | 4.19 |
| GEN | 4.15 |
| GEO | 4.21 |
| HIST | 4.28 |
| MATH | 4.12 |
| SCI | 4.14 |
