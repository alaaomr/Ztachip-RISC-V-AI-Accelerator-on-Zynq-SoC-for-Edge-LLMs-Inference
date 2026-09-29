# Section 2.1 — Prezi Storyboard
### "LLMs & Why Decode Is the Problem"

**THE SPINE (one sentence the whole section proves):**
> LLM *decode* is **memory-bound** → that single fact is *why* we built custom hardware
> and *why* we picked a tiny model.

Every frame below should feel like it's pushing toward that conclusion. Keep text
minimal — diagrams + equations + 3-word labels. You narrate the rest.

---

## PREZI CANVAS MAP (spatial layout, not slides)

Prezi's superpower is *zoom + spatial memory*. Don't make a linear slide deck.
Lay it out as a journey on one big canvas:

```
   ┌────────────────────────  PART 0: FOUNDATIONS  ────────────────────────┐
   │  P1 What is    P2 Text→     P3 Parameters    P4 Train vs   P5 The      │
   │  an LLM?  ──►  Tokens→  ──► = stored     ──► Inference ──► Transformer │
   │  (next-token   Vectors      knowledge       (learn once,  (stacked    │
   │   predictor)                (foreshadows     run forever)  decoders)   │
   │                             the mem wall)                    │         │
   └──────────────────────────────────────────────────────────────┼────────┘
                                                                   │ flows into
                     ┌─────────────────────────────┐               ▼
                     │   [HUB]  LLM INFERENCE       │   ← arrive zoomed-out here
                     │   "Two phases, one problem"  │
                     └──────────────┬──────────────┘
                                    │ zoom in
              ┌─────────────────────┴─────────────────────┐
              │                                             │
        (1) PREFILL  ───── KV Cache ─────►  (2) DECODE      │
        compute-bound                      memory-bound  ◄──┘ the villain
              │                                  │
              │ zoom into decode internals       │ zoom into "why slow"
              ▼                                   ▼
        (3) Decoder Layer            (5) THE MEMORY WALL
        Embed→Attn+FFN→Head          compute↗↗  vs  bandwidth↗
              │                                   │
        (4) Attention = QKV                       ▼
        softmax(QKᵀ/√dk)V            (6) FUNNEL → SmolLM2-135M
                                         (our choice, 141 MB)
```

Suggested zoom order = the frame numbers below. End by zooming **back out** to the
hub so the audience sees the whole story collapse into one idea.

---

## FRAME-BY-FRAME

# ════════ PART 0 — FOUNDATIONS (prerequisites) ════════
> Goal of Part 0: by the end, the audience already "feels" the memory problem
> *before* you name it. Keep each frame to ONE idea, ONE picture.

### ★ P1 — What is an LLM?  *(the single most important prerequisite)*
An LLM does exactly ONE thing: **predict the next token.** Show it literally.

```
   "The cat sat on the ___"  ──►  [ LLM ]  ──►   mat   ████████ 0.62
                                                 floor ███      0.18
                                                 roof  ██       0.09
                                                 ...   ▏        0.01
```
- Headline: **An LLM is a next-token probability machine. That's it.**
- It outputs a probability over the whole vocabulary; pick the top one, append, repeat.
- This one idea makes autoregression (Frame 2) feel obvious later.
- **Transition:** the chosen token "mat" flies into the sentence → zoom to P2.

---

### P2 — Text → Tokens → Vectors  *(how words become math)*
```
  "unbelievable" ─►[TOKENIZER]─► ["un","believ","able"] ─►[EMBEDDING]─► [0.2,-1.3, 0.9, ...]
        text            split into pieces                    each token = a vector of numbers
```
- Two steps: **tokenize** (split text into ~word pieces) → **embed** (each token → a vector).
- Killer one-liner: **"Meaning becomes geometry."**
  classic: `king − man + woman ≈ queen`  (vectors that are *close* mean *similar things*)
- **Transition:** zoom into one vector → P3.

---

### ★ P3 — Parameters = stored knowledge  *(secretly sets up the memory wall)*
```
   LLM = a giant function with BILLIONS of tunable numbers ("weights")

        SmolLM2-135M  =  135,000,000 parameters
                         ▲
        every weight must be STORED in memory and READ for each token
```
- Headline: **The model's "knowledge" = millions/billions of stored numbers.**
- Plant the seed (don't explain yet): *"Reading all these numbers, every token, is the
  bottleneck we'll meet in a minute."* → this pays off at Frame 5 (Memory Wall).
- Tie to your project: 135M params → 141 MB at INT4 → must fit in DDR3.
- **Transition:** pan to P4.

---

### P4 — Train once, run forever  *(bridge into Prefill/Decode)*
```
   TRAINING                       INFERENCE
   (once · weeks · many GPUs)     (every single request)
   learn the numbers     ──────►  use the frozen numbers
        🔒 weights get frozen          │
                                        └─► this is where OUR project lives
```
- Headline: **Training learns the weights. Inference uses them. We only do inference.**
- Critical hand-off line: *"Inference itself splits into two phases..."* → this is the
  exact sentence that opens the HUB and Frame 1.
- **Transition:** zoom to P5.

---

### P5 — The Transformer  *(name the architecture, then move on)*
```
   text ─► [ DECODER LAYER ] ─► [ DECODER LAYER ] ─► ... ─► next token
              (× N identical)
              each = Attention + FFN
```
- Headline: **Every modern LLM = a stack of identical decoder layers.**
- Don't open the layer yet — that's Frame 3. Just establish the silhouette.
- SmolLM2-135M = **30 layers**, hidden size **2048** (numbers you reuse in Frame 6).
- **Transition:** zoom OUT to the HUB (Frame 0) — foundations done, story begins.

# ════════ PART 1 — THE STORY ════════

### ★ FRAME 0 — HUB / Title (zoomed-out anchor)
- Big center text: **LLM INFERENCE**
- Subtitle: *Two phases. One bottleneck.*
- Tiny preview of the Prefill→Decode split faded in the background.
- **Transition:** zoom IN to Frame 1.

---

### ★ FRAME 1 — The Two Phases  *(HERO DIAGRAM — spend time here)*
This is the most important visual in your whole section.

```
   INPUT TOKENS (all at once)              OUTPUT TOKENS (one at a time)
   ┌──┬──┬──┬──┬──┐                          ┌──┐ ┌──┐ ┌──┐
   │t1│t2│t3│t4│t5│   ══►  KV CACHE  ══►     │o1│→│o2│→│o3│→ ...
   └──┴──┴──┴──┴──┘                          └──┘ └──┘ └──┘
      PREFILL                                   DECODE
   ▣ parallel                                ▣ sequential
   ▣ COMPUTE-bound  (blue)                   ▣ MEMORY-bound  (red)
   "like training"                           "the real problem"
```
- Color code hard: **Prefill = blue (compute)**, **Decode = red (memory)**. Keep
  these two colors consistent for the ENTIRE talk.
- KV Cache = the bridge between them; note "size grows with input+output length."
- One-line callout: *"Prefill & Decode can even run on different servers."*
- **Transition:** the red Decode box pulses → zoom into it (Frame 2).

---

### ★ FRAME 2 — Autoregressive Loop  *(animation = Prezi gold)*
A *looping* diagram is perfect for Prezi's spin/zoom — use it.

```
        ┌─────────────────────────────┐
        │                             ▼
   "The" ──►[ MODEL ]──► "cat" ──►[ MODEL ]──► "sat" ──► ...
        ▲                             │
        └──────── feed output back ───┘
```
- Headline: **auto** = self · **regressive** = depends on previous
- Punchline under it: **"One token at a time → can't parallelize → memory-bound."**
- This frame *justifies* why Decode (red) is the bottleneck. That's its only job.
- **Transition:** zoom into the [MODEL] box → Frame 3.

---

### FRAME 3 — Inside a Decoder Layer  *(zoom-in, keep light)*
```
  text ─► [EMBEDDING] ─► [DECODER LAYER × N] ─► [LM HEAD] ─► next token
                              │
                ┌────────────┴────────────┐
                │  ATTENTION   +   FFN     │
                │ "gather from   "think    │
                │  others"       alone"    │
                └─────────────────────────┘
```
- Attention = *latency-sensitive* (many quick comparisons).
- FFN = *weight-intensive* (massive stored data) ← tie this back to "memory."
- **Transition:** zoom into the ATTENTION half → Frame 4.

---

### FRAME 4 — Attention = Q, K, V  *(one equation, one example)*
```
   Q = "what am I looking for?"
   K = "what do I offer?"        ─►  score = Q·Kᵀ ─► softmax ─► × V ─► context
   V = "my actual content"
```
- **The ONE equation to show (big, centered):**

  Attention = softmax( QKᵀ / √dₖ ) · V

- Intuition callout (this lands with audiences):
  *"The bank was closed because the river flooded"* → **"bank"** attends to
  **"river"** → it means *land*, not money.
- Optional tiny steps strip (don't dwell): Embed → LayerNorm → Q,K,V → QKᵀ → ÷√dₖ → softmax → ×V
- **Transition:** zoom back OUT to the red Decode box, then pan to Frame 5.

---

### ★ FRAME 5 — The Memory Wall  *(the "aha", graph-driven)*
A 2-line graph is far stronger than the bullet list in the thesis.

```
   performance
     ▲
     │          compute  ↗↗↗↗↗  (fast growth)
     │        ↗↗↗
     │     ↗↗↗            ┌─ THE GAP = "Memory Wall"
     │   ↗↗   ___________ memory bandwidth ──── (slow growth)
     │ ↗  ____/
     └───────────────────────────────────────► time
```
- Caption: **Decode lives in the memory-bound regime → it starves waiting for data.**
- Then the memory tradeoff as a 3-row mini-table (icons > words):

  | Type | Speed | Density | Cost |
  |------|-------|---------|------|
  | SRAM | ⚡⚡⚡ fast | low | 💲💲💲 |
  | DRAM | ⚡ slower | high | 💲 |
  | HBM  | ⚡⚡ hi-BW | high | 💲💲💲 |

- One line: *"No GPU/TPU was designed solely for decode."* ← this is your bridge to
  the whole hardware thesis.
- **Transition:** zoom out, then funnel-pan down to Frame 6.

---

### ★ FRAME 6 — Why a Tiny Model  *(funnel diagram = strong closer)*
```
        ┌───────────────────────────────────────┐
        │  Many capable LLMs (7B, 13B ...)       │
        └───────────────────┬───────────────────┘
              constraint 1:  1 GB DDR3 on ZC702
              constraint 2:  64-bit AXI @ 93.75 MHz
              constraint 3:  decoder-only + GQA runtime
                            ▼
                   ┌─────────────────┐
                   │  SmolLM2-135M   │   141 MB @ INT4
                   │  ✓ fits         │   30 layers, hidden 2048
                   │  ✓ all kernels  │   (Qwen2.5-0.5B = upgrade path,
                   │  ✓ compressible │    blocked by missing bias tensors)
                   └─────────────────┘
```
- Funnel shape visually = "everything narrows to our one model." Very satisfying.
- Keep the big comparison table (Mistral/TinyLlama/Phi-2...) as an OPTIONAL deep-zoom
  side node — only zoom in if asked. Don't put it on the main path.
- **Transition:** zoom ALL the way back out to the HUB (Frame 0).

---

### ★ FRAME 7 — Collapse back to the spine
- Land on the HUB again, now with the one-sentence spine revealed in full:
  **"Decode is memory-bound → that's why we built custom hardware & chose SmolLM2."**
- This hand-off line literally sets up Section 2.2 (your hardware architectures).

---

## WHAT TO DROP / COMPRESS (so it stays impressive, not bloated)
- **FLOPS (2.1.2):** one sentence on Frame 5 only — "FLOPS = compute power; but decode
  isn't compute-limited." Don't give it a frame.
- **MoE (2.1.4):** demote to a single OPTIONAL side-node off Frame 3 ("a scaling trick:
  many experts, use a few"). You did NOT use MoE in SmolLM2 — don't let it eat time.
- **LLM Challenges list of 6 (2.1.5):** turn into a 6-icon ring, 5 seconds, then move on.
- **Latency challenge (2.1.6):** fold the two key terms (time-to-first-token,
  time-to-completion) into one callout on Frame 2's autoregressive loop.

## DESIGN RULES (for "impressive")
1. **Two colors, all talk:** blue = compute/Prefill, red = memory/Decode. Nothing else.
2. **≤ 7 words of text per frame.** If it's a sentence, it's narration, not a slide.
3. **One equation total** (attention). More math = lost audience.
4. **Motion with meaning:** loop-spin for autoregression, zoom-in for "inside",
   zoom-out for "the big picture." Never move just to move.
5. **End where you began** (hub) — the zoom-out is the emotional payoff.

## EQUATIONS TO TYPESET (only these)
- Attention:  `softmax(QKᵀ / √dₖ) · V`
- (optional, Frame 4 strip) `Q = xW_Q,  K = xW_K,  V = xW_V`
- Skip the MoE router softmax unless you keep the MoE side-node.
