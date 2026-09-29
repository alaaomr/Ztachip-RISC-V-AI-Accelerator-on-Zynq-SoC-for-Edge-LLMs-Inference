#include <stdlib.h>
#include <stdio.h>
#include "../base/ztalib.h"
#include "../base/config.h"
#include "../apps/gdi/gdi.h"
#include "soc.h"
#include "../base/net.h"

extern "C"
{
extern int main(void);
extern void irqCallback(void);
}

// __dso_handle is function pointer to do any cleanup of global object when 
// program exit.
// But this is a baremetal embedded system so we never have a program exit
// except when doing a reboot
// Set __dso_handle to zero

void *__dso_handle=0;

extern int test(void);

extern int vision_ai(void);

extern int chat();

extern void test_llm();

extern "C" void test_dma();

// Individual LLM kernel self-tests (defined non-static in test_llm.cpp) — called
// directly below so we can print a progress line before each and see exactly
// which kernel runs/stops. Each prints "<NAME> ok=N bad=0" when it verifies.
extern void test_llm_residual();
extern void test_llm_SwiGLU();
extern void test_llm_rms();
extern void test_llm_rope();
extern void test_llm_softmax();
extern void test_llm_k_max();
extern void test_llm_cosine();
extern void test_llm_sine();
extern void test_llm_quantize();
extern void test_llm_matmul_q4();
extern void test_llm_matmul_q8();

//-----------------------------------------
// Application main entry
// 2 execution cases: vision example or test suites.
//-----------------------------------------

int main() {
#if defined(ZTACHIP_UNIT_TEST) || defined(ZTACHIP_KERNEL_TEST)
   // DIAGNOSTIC: ping the mailbox the instant we reach main(), BEFORE any init.
   // Writing the console only needs DDR (already up). If this line appears but the
   // banner below doesn't, the hang is inside ztaInit/GdiInit/NetInit; if even this
   // doesn't appear, the hang is before main() (a global constructor / crt).
   printf("\r\n[BOOT] reached main() — starting init...\r\n");
#endif
   ztaInit();
   GdiInit();
   NetInit(0x0a0a0a63); // My local IP=10.10.10.99

#if defined(ZTACHIP_UNIT_TEST) || defined(ZTACHIP_KERNEL_TEST)
   // On-silicon KERNEL self-test: verify each ztachip LLM kernel against the
   // reference C implementation. Banner prints immediately (so the host sees the
   // mailbox come alive = boot confirmed), then a progress line before each kernel
   // and that kernel's own "<NAME> ok=N bad=0" result. bad=0 on every line = PASS.
   // NOTE: the vision test() and test_dma() are intentionally NOT run here — this
   // build targets the LLM kernel verification (the "9-LED" self-test).
   printf("[INIT] done — starting kernel self-test\r\n");
   printf("===== ZTACHIP ON-SILICON KERNEL SELF-TEST =====\r\n");
   printf("each '<kernel> ok=N bad=0' line = that kernel verified vs reference C\r\n");
   printf("-----------------------------------------------\r\n");
#ifdef FPU_ENABLED
   printf(">> residual    ...\r\n"); test_llm_residual();
   printf(">> SwiGLU      ...\r\n"); test_llm_SwiGLU();
   printf(">> rms         ...\r\n"); test_llm_rms();
   printf(">> rope        ...\r\n"); test_llm_rope();
   printf(">> softmax     ...\r\n"); test_llm_softmax();
   printf(">> k_max       ...\r\n"); test_llm_k_max();
   printf(">> cosine      ...\r\n"); test_llm_cosine();
   printf(">> sine        ...\r\n"); test_llm_sine();
   printf(">> quantize    ...\r\n"); test_llm_quantize();
   printf(">> matmul_q4   ...\r\n"); test_llm_matmul_q4();
   printf(">> matmul_q8   ...\r\n"); test_llm_matmul_q8();
#endif
   printf("-----------------------------------------------\r\n");
   printf("===== KERNEL SELF-TEST COMPLETE — all kernels above with bad=0 PASSED =====\r\n");
   for(;;){}   // done: hold here (host capture auto-stops on idle)
#endif

#ifdef ZTACHIP_LLM_TEST
   // Run chatbot with smollm2-135M LLM model
   for(;;) {
      chat();
   }
#endif

   // Run various vision tests
   //   - object detection
   //   - image classfication
   //   - optical flow
   //   - Harris-Corner point-of-interests
   //   - Edge detection
   DisplayInit(DISPLAY_WIDTH,DISPLAY_HEIGHT);
   CameraInit(WEBCAM_WIDTH,WEBCAM_HEIGHT);
   for(;;) {
      vision_ai();
   }
   return 0;
}

void irqCallback() {
}
