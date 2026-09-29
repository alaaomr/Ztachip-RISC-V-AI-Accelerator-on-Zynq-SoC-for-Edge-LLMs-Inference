//----------------------------------------------------------------------------
// Copyright [2014] [Ztachip Technologies Inc]
//
// Author: Vuong Nguyen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except IN compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to IN writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//------------------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "soc.h"
#include "../base/zta.h"
#include "../base/util.h"

#define NUM_CAMERA_CAPTURE  4

#define NUM_VIDEO_FRAME     4

// Memory mapped of APB bus

#define APB ((volatile unsigned int *)0xC0000000)

static void *buffer_vga[NUM_VIDEO_FRAME];

static void *buffer_camera[NUM_CAMERA_CAPTURE];

static void *curr_camera_capture=0;

static int curr_video=0;

extern unsigned int *vgabuf;

static int camera_last_read=0;

uint8_t *DisplayCanvas=0;


//----------------------------
// Initialize VGA display driver
// The driver configures the Xilinx's VDMA IP
//-----------------------------

ZtaStatus DisplayInit(int w,int h) {
   int r;
   static bool init=false;
   if(init)
      return ZtaStatusOk;
   if(w!=WEBCAM_WIDTH || h!=WEBCAM_HEIGHT)
      return ZtaStatusFail;
   // Configure VGA display output stream
   for(r=0;r < NUM_VIDEO_FRAME;r++) {
      buffer_vga[r]=malloc(WEBCAM_WIDTH*3*(WEBCAM_HEIGHT+2));
      APB[APB_VIDEO_BUFFER+r]=(unsigned int)buffer_vga[r];
   }
   APB[APB_VIDEO_ENABLE]=1;
   DisplayCanvas=(uint8_t *)buffer_vga[curr_video];
   init=true;
   return ZtaStatusOk;
}

//---------------------------------
// Make the current working display buffer returned from DisplayGetBuffer()
// to be the active screen display buffer
//-----------------------------------

ZtaStatus DisplayUpdateBuffer() {
   APB[APB_VIDEO_BUFFER]=(uint32_t)buffer_vga[curr_video];
   curr_video++;
   if(curr_video >= NUM_VIDEO_FRAME)
      curr_video=0;
   DisplayCanvas=(uint8_t *)buffer_vga[curr_video];
   return ZtaStatusOk;
}

//------------------------------------
// Initialize the camera driver
// The driver configures the Xilinx's VDMA IP core
//------------------------------------

ZtaStatus CameraInit(int w,int h) {
   int r;
   static bool init=false;
   if(init)
      return ZtaStatusOk;
   if(w!=WEBCAM_WIDTH || h!=WEBCAM_HEIGHT)
      return ZtaStatusFail;
   curr_camera_capture=malloc(WEBCAM_WIDTH*3*(WEBCAM_HEIGHT+2));
   // Configure camera input stream
   for(r=0;r < NUM_CAMERA_CAPTURE;r++) {
      buffer_camera[r]=malloc(WEBCAM_WIDTH*3*(WEBCAM_HEIGHT+2));
      APB[APB_CAMERA_BUFFER+r]=(unsigned int)buffer_camera[r];
   }
   APB[APB_CAMERA_ENABLE]=1;
   init=true;
   return ZtaStatusOk;
}

// Check if capture from camera is ready

bool CameraCaptureReady() {
   int next_read,curr_read;
   unsigned int vv;
   void *temp;

   next_read=APB[APB_CAMERA_CURR_FRAME];
   if(next_read != camera_last_read) {
      camera_last_read=next_read;
      curr_read=(camera_last_read==0)?(NUM_CAMERA_CAPTURE-1):camera_last_read-1;
      // Swap current camera buffer for the current capture buffer
      temp=buffer_camera[curr_read];
      buffer_camera[curr_read]=curr_camera_capture;
      curr_camera_capture=temp;
      APB[APB_CAMERA_BUFFER+curr_read]=(unsigned int)buffer_camera[curr_read];
      return true;
   }
   else
      return false;
}

//---------------------------------------
// Get latest camera capture if available
//---------------------------------------

uint8_t *CameraGetCapture() {
   return (uint8_t *)curr_camera_capture;
}

//----------------------------------------
// Set LED state (on/off)
//----------------------------------------

void LedSetState(uint32_t ledState) {
   APB[APB_LED]=ledState;
}

//-----------------------------------------
// Get push button current state
//-----------------------------------------

uint32_t PushButtonGetState() {
   return APB[APB_PB];
}

//-----------------------------------------
// DDR mailbox console (read/written over JTAG)
//-----------------------------------------
// The ZC702 has no usable UART pin for the VexRiscv (UART_TXD/RXD = K18/J18
// land on the FMC1 connector, unreachable without a breakout). So the chatbot
// console is bridged through a pair of ring buffers in DDR at MBX_BASE. A host
// xsdb script reads the "out" ring and writes the "in" ring over JTAG.
// VexRiscv caches DDR, so FLUSH_DATA_CACHE() (writeback+invalidate) is used to
// keep the mailbox coherent with the host. Index words are spaced 64 bytes
// apart so the CPU-written and host-written indices never share a cache line.
// Moved 0x20000000 -> 0x30000000 (768MiB) so the model region at 0x10000000 can
// hold models up to ~512MB (e.g. SmolLM2-360M Q4 = 308MB) without colliding with
// the mailbox. ZC702 has 1GB DDR, so 0x30000000 is well within range. The host
// scripts (board_*.tcl) set MBX to the same value.
#define MBX_BASE      0x30000000u
#define MBX_RING      4096u
#define MBX_MAGIC     0x5A544348u            // 'ZTCH' - host waits for this
#define MBX_W(off)    (*((volatile uint32_t*)(MBX_BASE + (off))))
#define MBX_MAGIC_R   MBX_W(0x00)            // CPU writes once at init
#define MBX_OUTHEAD   MBX_W(0x40)            // CPU writes  (output producer)
#define MBX_OUTTAIL   MBX_W(0x80)            // host writes (output consumer)
#define MBX_INHEAD    MBX_W(0xC0)            // host writes (input producer)
#define MBX_INTAIL    MBX_W(0x100)           // CPU writes  (input consumer)
#define MBX_OUTBUF    ((volatile uint8_t*)(MBX_BASE + 0x1000)) // CPU->host
#define MBX_INBUF     ((volatile uint8_t*)(MBX_BASE + 0x2000)) // host->CPU

static int g_mbxInited = 0;
static void mbxEnsureInit() {
   if(!g_mbxInited) {
      MBX_OUTHEAD = 0;
      MBX_OUTTAIL = 0;
      MBX_INHEAD  = 0;
      MBX_INTAIL  = 0;
      MBX_MAGIC_R = MBX_MAGIC;               // signal "console ready" to host
      FLUSH_DATA_CACHE();
      g_mbxInited = 1;
   }
}

//-----------------------------------------
// Read one input char (blocks until host sends one)
//-----------------------------------------

uint8_t UartRead() {
   mbxEnsureInit();
   FLUSH_DATA_CACHE();                        // pull fresh in_head/in_buf from host
   uint32_t tail = MBX_INTAIL;
   while(MBX_INHEAD == tail) {
      FLUSH_DATA_CACHE();                     // spin: refresh in_head until data arrives
   }
   uint8_t ch = MBX_INBUF[tail % MBX_RING];
   MBX_INTAIL = tail + 1;
   FLUSH_DATA_CACHE();                        // publish new in_tail to host
   return ch;
}

//-------------------------------------------
// Write one output char (blocks if host hasn't drained)
//---------------------------------------------

void UartWrite(uint8_t ch) {
   mbxEnsureInit();
   uint32_t head = MBX_OUTHEAD;
   while((head - MBX_OUTTAIL) >= MBX_RING) {
      FLUSH_DATA_CACHE();                     // buffer full: refresh out_tail until host drains
   }
   MBX_OUTBUF[head % MBX_RING] = ch;
   FLUSH_DATA_CACHE();                        // land the data byte in DDR FIRST
   MBX_OUTHEAD = head + 1;
   FLUSH_DATA_CACHE();                        // then publish out_head (host now sees byte+index)
}

//-----------------------------------------------
// Return number of available UART characters for
// reading
//-----------------------------------------------

int UartReadAvailable() {
   mbxEnsureInit();
   FLUSH_DATA_CACHE();                        // fresh in_head from host
   return (int)(MBX_INHEAD - MBX_INTAIL);
}

//-----------------------------------------------
// Return number of spaces available for UART
// transmission FIFO
//-----------------------------------------------

int UartWriteAvailable() {
   mbxEnsureInit();
   FLUSH_DATA_CACHE();                        // fresh out_tail from host
   return (int)(MBX_RING - (MBX_OUTHEAD - MBX_OUTTAIL));
}


//---------------------------------------------------------
// Initialize Ethernet driver
//---------------------------------------------------------

ZtaStatus EthernetLiteInit(uint8_t macAddr[6]) {
   // Always hardcoded for now
   macAddr[0] = 0x00;
   macAddr[1] = 0x00;
   macAddr[2] = 0x5E;
   macAddr[3] = 0x00;
   macAddr[4] = 0xFA;
   macAddr[5] = 0xCE;
   return ZtaStatusOk;
}

//--------------------------------------------------------------
// Simple Ethernet Driver based on Xilinx EthernetLite IP
// Primarily used to download files (such as LLM model) 
// with TFTP 
// This function is blocked until the Ethernet packet can be sent
//--------------------------------------------------------------

int EthernetLiteSend(uint8_t *pkt,int pktLen)
{
   int cnt;
   uint32_t start;
   
   start=TimeGet();
   cnt = (pktLen+3)/4;
   while(APB[APB_ETH_TXPINGCTRL] & 0x1) {
      while((int)TimeGet()-(int)start > 5000)
         return 0;
   }
   for(int i=0;i < cnt;i++,pkt+=4) {
      APB[APB_ETH_TXPINGBUF+i] = *((uint32_t*)pkt);
   }
   APB[APB_ETH_TXPINGLEN] = pktLen;
   APB[APB_ETH_TXPINGCTRL] = 1;
   return pktLen;
}

//-------------------------------------------------------
// Simple Ethernet Driver based on Xilinx EthernetLite IP
// Primarily used to download files (such as LLM model) 
// with TFTP 
// This function is blocked until an Ethernet packet is 
// received
//-------------------------------------------------------

int EthernetLiteReceive(uint8_t *pkt,int pktLen)
{
   static int nextBuf=0;
   int cnt=pktLen/4; 

   if(nextBuf==0 && APB[APB_ETH_RXPINGCTRL] & 0x1)
   {
      for(int i=0;i < cnt;i++,pkt+=4) {
         *((uint32_t*)pkt) = APB[APB_ETH_RXPINGBUF+i];
      }
      APB[APB_ETH_RXPINGCTRL] = 0;
      nextBuf=1;
      return cnt*4;
   }
   if(nextBuf==1 && APB[APB_ETH_RXPONGCTRL] & 0x1)
   {
      for(int i=0;i < cnt;i++,pkt+=4) {
         *((uint32_t*)pkt) = APB[APB_ETH_RXPONGBUF+i];
      }
      APB[APB_ETH_RXPONGCTRL] = 0;
      nextBuf=0;
      return cnt*4;
   }
   return 0;
}



