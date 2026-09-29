//----------------------------------------------------------------------------
// test_llm_main.cpp — Simulation entry point for LLM kernel verification
//
// What it does:
//   Boots RISC-V, initializes ztachip, then runs the FAST LLM kernel tests
//   from SW/src/test_llm.cpp. Each test compares hardware kernel output
//   against the reference C implementation. led_out (APB[0]) increments
//   after each test passes — watch it in the simulator waveform.
//
// Tests included (all small buffers, finish in reasonable sim time):
//   1 → after init
//   2 → test_llm_sine      passed
//   3 → test_llm_cosine    passed
//   4 → test_llm_rope      passed (rotary position embedding)
//   5 → test_llm_rms       passed (RMS normalization)
//   6 → test_llm_residual  passed
//   7 → test_llm_SwiGLU    passed (activation)
//   8 → test_llm_softmax   passed
//   9 → test_llm_k_max     passed (top-K selection)
//   42 → all tests done, looping
//
// Tests SKIPPED in sim (run them on real board instead — too slow in xsim):
//   - test_llm_dot_product / dot_product2 (1023-iteration loops)
//   - test_llm_quantize (medium size)
//   - test_llm_matmul_q4 / q8 (3.5 MB heap, billions of cycles)
//----------------------------------------------------------------------------

#include "../base/ztalib.h"
#include "../src/soc.h"

// LLM tests (declared in SW/src/test_llm.cpp — non-static, callable here)
extern void test_llm_sine();
extern void test_llm_cosine();
extern void test_llm_rope();
extern void test_llm_rms();
extern void test_llm_residual();
extern void test_llm_SwiGLU();
extern void test_llm_softmax();
extern void test_llm_k_max();

// Tests ordered LIGHTEST → HEAVIEST (by tensor-processor go-command count).
// You'll see led_out tick up fast for the early ones, then slow down.
// Stop the sim whenever you've seen enough — each pass proves a real kernel works.
int main()
{
   int led = 1;

   ztaInit();
   APB[APB_LED] = led++;  // led_out = 1: ztachip initialized

   test_llm_residual();    // 5 commands  — lightest
   APB[APB_LED] = led++;   // led_out = 2

   test_llm_SwiGLU();      // 7 commands
   APB[APB_LED] = led++;   // led_out = 3

   test_llm_rms();         // 10 commands
   APB[APB_LED] = led++;   // led_out = 4

   test_llm_rope();        // 14 commands
   APB[APB_LED] = led++;   // led_out = 5

   test_llm_softmax();     // 15 commands
   APB[APB_LED] = led++;   // led_out = 6

   test_llm_k_max();       // medium
   APB[APB_LED] = led++;   // led_out = 7

   test_llm_cosine();      // 15 cmds × 2 iters
   APB[APB_LED] = led++;   // led_out = 8

   test_llm_sine();        // 15 cmds × 2 iters — heaviest
   APB[APB_LED] = led++;   // led_out = 9

   // Signal completion: led_out = 0xA forever
   for(;;) {
      APB[APB_LED] = 0xA;
   }
   return 0;
}

extern "C" void irqCallback() {
}
