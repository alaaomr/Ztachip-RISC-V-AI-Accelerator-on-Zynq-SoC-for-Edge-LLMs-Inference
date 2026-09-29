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

// This file implements ZUF file format

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <time.h>
#include <math.h>
#include <string.h>
#include <fcntl.h>
#include <stdint.h>
#ifndef __WIN32__
#include <unistd.h>
#endif
#ifdef __WIN32__
#include <io.h>
#include <fcntl.h>
#endif
#include <sys/stat.h>
#include <vector>
#include <string>
#include "../../../base/util.h"
#include "../../../base/net.h"
#include "../../../base/types.h"
#include "zuf.h"
#include "gguf.h"

#define BYTE_ALIGNMENT 16 // Tensor begins at byte alignment address
 
#ifndef __WIN32__
#define _open open
#define _read read
#define _write write
#define _close close
#endif

// Constructor

ZUF::ZUF() {
    m_fp = 0;
    m_top = 0;
    m_buf = 0;
}

// Destructor

ZUF::~ZUF() {
    if(m_fp)
        fclose(m_fp);
    if (m_buf)
        free(m_buf);
}

// Open and create a ZUF file

ZtaStatus ZUF::Create(const char *fname) {
    ZUF_HEADER h;
    m_fp = fopen(fname,"wb");
    if(!m_fp)
        return ZtaStatusFail;
    m_wpos = 0;
    memset(&h,0,sizeof(h));
    write(&h,sizeof(ZUF_HEADER));
    return ZtaStatusOk;
}

// Done. Close the file

ZtaStatus ZUF::CreateComplete() {
    if (m_fp) {
        ZUF_HEADER h;
        uint8_t type=ZUF_TYPE_EOF;
        write(&type, 1);
        memset(&h,0,sizeof(h));
        memcpy(h.magicNumber,ZUF_MAGIC_NUMBER,sizeof(h.magicNumber));
        H2N(ZUF_VERSION,h.ver);
        H2N((uint32_t)m_wpos,h.len); // Handle small model only
        writeReset();
        write(&h,sizeof(ZUF_HEADER));       
        fclose(m_fp);
        m_fp = 0;
    }
    return ZtaStatusOk;
}

// Open an existing ZUF file

ZtaStatus ZUF::Open(const char* fname) {
#ifndef QUANTIZER
    int fd;
    size_t sz,sz2;
    struct stat fileStat;
    uint8_t* p;
    ZUF_HEADER h;
    uint32_t size;
    uint32_t ver;

    if (m_buf)
        free(m_buf);
#ifdef __WIN32__
    m_buf = 0;
    m_top = 0;
    fd = _open(fname, O_RDONLY);
    if (fd < 0)
        return ZtaStatusFail;
    fstat(fd, &fileStat);
    sz = fileStat.st_size;
    m_buf = (uint8_t*)malloc(sz+2*BYTE_ALIGNMENT);
    m_top = (uint8_t *)((((size_t)m_buf+BYTE_ALIGNMENT-1)/BYTE_ALIGNMENT)*BYTE_ALIGNMENT);
    p = (uint8_t*)m_top;

    sz2 = _read(fd, p, sz);
    m_top += sizeof(ZUF_HEADER);
    _close(fd);
#else
    // Model is pre-loaded into DDR at ZUF_DDR_BASE_ADDR by the JTAG/XSCT loader
    // before the RISC-V starts. Read directly from that address — no copy needed.
#define ZUF_DDR_BASE_ADDR ((uint8_t*)0x10000000)
    printf("Reading model from DDR at 0x10000000 (JTAG pre-loaded)...\r\n");
    ZUF_HEADER *ddr_h = (ZUF_HEADER*)ZUF_DDR_BASE_ADDR;
    if(memcmp(ddr_h->magicNumber, ZUF_MAGIC_NUMBER, sizeof(ddr_h->magicNumber)) != 0) {
        printf("ZUF magic not found at 0x10000000. Model not pre-loaded via JTAG?\r\n");
        return ZtaStatusFail;
    }
    N2H(ddr_h->ver, ver);
    if(ver != ZUF_VERSION) {
        printf("Incompatible ZUF version. Regenerate ZUF file.\r\n");
        return ZtaStatusFail;
    }
    N2H(ddr_h->len, size);
    printf("Model found at DDR: size=%d bytes\r\n", (int)size);
    m_buf = 0;  // no heap allocation — pointing directly into DDR
    m_top = ZUF_DDR_BASE_ADDR + sizeof(ZUF_HEADER);
#endif
#endif
    return ZtaStatusOk;
}

// Close ZUF file

void ZUF::Close() {
    if (m_buf)
        free(m_buf);
    m_buf = 0; 
}

// Write a configuration item

void ZUF::writeConfig(ZUF_TYPE type,const char *key,uint32_t numItems,void *items) {
    uint8_t byte;
    uint32_t totalLen;
    uint32_t gap;
    uint32_t itemsLen;
    uint32_t strLen;
    char* p;

    totalLen = sizeof(uint8_t) +  // type 
                sizeof(uint32_t) +  // len
                (uint32_t)strlen(key) + 1 +  // key (null terminated)
                sizeof(uint32_t) + // numItems
                sizeof(uint8_t); // gap
    gap = (uint32_t)(((((m_wpos+totalLen)+BYTE_ALIGNMENT-1)/BYTE_ALIGNMENT)*BYTE_ALIGNMENT)-(m_wpos+totalLen));
    switch (type) {
        case ZUF_TYPE_UINT32:
            itemsLen = sizeof(uint32_t)*numItems;
            break;
        case ZUF_TYPE_FLOAT:
            itemsLen = sizeof(float) * numItems;
            break;
        case ZUF_TYPE_BFLOAT:
        case ZUF_TYPE_FP16:
            itemsLen = sizeof(float16_t) * numItems;
            break;
        case ZUF_TYPE_STRING:
            itemsLen = 0;
            p = (char *)items;
            for (uint32_t i = 0; i < numItems; i++) {
                strLen = (uint32_t)strlen(p)+1;
                itemsLen += strLen;
                p += strLen;
            }
            break;
        case ZUF_TYPE_UINT8:
            itemsLen = numItems;
            break;
        default:
            assert(0);
    }
    totalLen += gap + itemsLen;
    byte = (uint8_t)type;
    write(&byte, sizeof(byte));
    write(&totalLen, sizeof(totalLen));
    write((char *)key, strlen(key)+1);
    write(&numItems, sizeof(numItems));
    byte = ZUF_TYPE_GAP + gap;
    write(&byte, sizeof(byte));
    byte = 0;
    for (uint32_t i=0; i < gap; i++)
        write(&byte, 1);
    assert((m_wpos/BYTE_ALIGNMENT)*BYTE_ALIGNMENT == m_wpos);
    write(items, itemsLen);
}

// Write a configuration item which is a UINT32 number

void ZUF::WriteItemU32(const char *key,uint32_t v) {
    writeConfig(ZUF_TYPE_UINT32, key, 1, &v);
}

// Write a configuration item which is a float number

void ZUF::WriteItemFloat(const char* key, float v) {
    writeConfig(ZUF_TYPE_FLOAT, key, 1, &v);
}

// Write a configuration item which is a BFLOAT

void ZUF::WriteItemBfloat(const char* key, float16_t v) {
    writeConfig(ZUF_TYPE_BFLOAT, key, 1, &v);
}

// Write a configuration item which is a FLOAT16

void ZUF::WriteItemFP16(const char* key, float16_t v) {
    writeConfig(ZUF_TYPE_FP16, key, 1, &v);
}

// Write a configuration item which is a string

void ZUF::WriteItemString(const char* key, char *str) {
    writeConfig(ZUF_TYPE_STRING, key, 1, str);
}

// Write a configuration item which is an array of UINT32

void ZUF::WriteItemArrayU32(const char* key, uint32_t arrSize, uint32_t *arr) {
    writeConfig(ZUF_TYPE_UINT32, key, arrSize, arr);
}

// Write a configuration item which is an array of float numbers

void ZUF::WriteItemArrayFloat(const char* key, uint32_t arrSize, float* arr) {
    writeConfig(ZUF_TYPE_FLOAT, key, arrSize, arr);
}

// Write a configuration item which is an array of BFLOAT

void ZUF::WriteItemArrayBFLOAT(const char* key, uint32_t arrSize, float16_t* arr) {
    writeConfig(ZUF_TYPE_BFLOAT, key, arrSize, arr);
}

// Write a configuration item which is an array of FLOAT16

void ZUF::WriteItemArrayFP16(const char* key, uint32_t arrSize, float16_t* arr) {
    writeConfig(ZUF_TYPE_FP16, key, arrSize, arr);
}

// Write a configuration item which is an array of strings

void ZUF::WriteItemArrayString(const char* key, uint32_t arrSize, char* arr) {
    writeConfig(ZUF_TYPE_STRING, key, arrSize, arr);
}

// Write a configuration item which is an array of UINT8

void ZUF::WriteItemArrayU8(const char* key, uint32_t arrSize, uint8_t* arr) {
    writeConfig(ZUF_TYPE_UINT8, key, arrSize, arr);
}

// Debug: walk the element list from m_top and print the first maxKeys keys.
// Proves the walk terminates (prints EOF) and reveals the real metadata key
// names so we can compare against what llm::Open() asks for.

void ZUF::DumpKeys(int maxKeys) {
    uint8_t *item = m_top;
    static const char *tn[] = {"EOF","U32","FLT","BFL","STR","U8 ","FP16"};
    printf("--- ZUF key dump (first %d) ---\r\n", maxKeys);
    for (int n = 0; n < maxKeys; n++) {
        uint8_t *p = item;
        enum ZUF_TYPE type = (enum ZUF_TYPE)*p; p++;
        if (type == ZUF_TYPE_EOF) { printf("  [%d] EOF\r\n", n); return; }
        uint32_t sz; memcpy(&sz, p, 4); p += 4;
        char *key = (char *)p;
        const char *ts = (type <= ZUF_TYPE_FP16) ? tn[type] : "???";
        printf("  [%d] type=%s sz=%u key='%s'\r\n", n, ts, (unsigned)sz, key);
        fflush(stdout);
        if (sz == 0) { printf("  !! sz==0, aborting walk\r\n"); return; }
        item = item + sz;
    }
    printf("--- (dump truncated at %d) ---\r\n", maxKeys);
    fflush(stdout);
}

// Find a configuration item based on key value

bool ZUF::findKey(const char* key,ZUF_CONFIG_ELE &ele) {
    uint8_t* p;
    uint8_t* item;
    uint32_t remain;
    uint32_t gap;
    uint32_t keyLen = (uint32_t)strlen(key) + 1;
    static int fk_dbg = 0;
    int d = (fk_dbg++ < 1);   // trace only the FIRST findKey call
    int steps = 0;
    if (d) { printf("    [fk] start m_top=%p keyLen=%u key='%s'\r\n",(void*)m_top,(unsigned)keyLen,key); fflush(stdout); }

    item = m_top;
    for (;;) {
        p = item;
        ele.type = (enum ZUF_TYPE)*p;
        p++;
        if (ele.type == ZUF_TYPE_EOF) {
            if (d) { printf("    [fk] EOF at step %d\r\n",steps); fflush(stdout); }
            return false;
        }
        memcpy(&ele.sz,p,sizeof(ele.sz));
        p += 4;
        if (d && steps < 12) { printf("    [fk] step %d item=%p type=%d sz=%u storedkey='%s'\r\n",steps,(void*)item,(int)ele.type,(unsigned)ele.sz,(char*)(item+5)); fflush(stdout); }
        if (ele.sz == 0) { if(d){printf("    [fk] sz==0 ABORT (would loop forever)\r\n");fflush(stdout);} return false; }
        remain = ele.sz - 1 - 4;
        ele.key = (char *)p;
        p += keyLen;
        remain -= keyLen;
        steps++;
        // Manual byte-by-byte compare. The optimized libc strcmp can issue a
        // word-aligned load and ele.key is at an UNALIGNED DDR address (e.g.
        // 0x..31) -> the VexRiscv soft-CPU has no misaligned-load support and
        // traps silently. Byte loads can never misalign.
        {
            const unsigned char *a = (const unsigned char*)ele.key;
            const unsigned char *b = (const unsigned char*)key;
            while (*a && (*a == *b)) { a++; b++; }
            int cmp = (int)(*a) - (int)(*b);
            if (d) { printf("    [fk] cmp=%d at step %d\r\n",cmp,steps-1); fflush(stdout); }
            if (cmp != 0) { item = item + ele.sz; continue; }
        }
        if (1) {
            if (d) { printf("    [fk] MATCH at step %d\r\n",steps-1); fflush(stdout); }
            memcpy(&ele.lstSize,p,sizeof(ele.lstSize));
            p += 4;
            remain -= 4;
            gap = (*p - ZUF_TYPE_GAP);
            p += gap+1;
            remain -= gap+1;
            ele.data = p;
            ele.dataLen = remain;
            return true;
        }
        item = item + ele.sz;
    }
    return false;
}

// Read a configuration item which is a UINT32

bool ZUF::ReadItemU32(const char* key, uint32_t& v) {
    ZUF_CONFIG_ELE ele;
    static int riu_dbg = 0;
    int d = (riu_dbg++ < 1);   // trace only the FIRST ReadItemU32 call

    if (d) { printf("   [RIU32] calling findKey('%s')\r\n",key); fflush(stdout); }
    if (!findKey(key, ele)) {
        if (d) { printf("   [RIU32] findKey FALSE\r\n"); fflush(stdout); }
        return false;
    }
    if (d) { printf("   [RIU32] found type=%d lstSize=%u data=%p\r\n",(int)ele.type,(unsigned)ele.lstSize,(void*)ele.data); fflush(stdout); }
    if (ele.type != ZUF_TYPE_UINT32) {
        return false;
    }
    if (ele.lstSize != 1) {
        return false;
    }
    if (d) { printf("   [RIU32] reading *(uint32*)data ...\r\n"); fflush(stdout); }
    v = *((uint32_t*)ele.data);
    if (d) { printf("   [RIU32] got v=%u\r\n",(unsigned)v); fflush(stdout); }
    return true;
}

// Read a configuration item which is a float

bool ZUF::ReadItemFloat(const char* key, float& v) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_FLOAT) {
        return false;
    }
    if (ele.lstSize != 1) {
        return false;
    }
    v = *((float*)ele.data);
    return true;
}

// Read a configuration item which is a BFLOAT

bool ZUF::ReadItemBFLOAT(const char* key, float16_t& v) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_BFLOAT) {
        return false;
    }
    if (ele.lstSize != 1) {
        return false;
    }
    v = *((float16_t*)ele.data);
    return true;
}

// Read a configuration item which is a FP16

bool ZUF::ReadItemFP16(const char* key, float16_t& v) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_FP16) {
        return false;
    }
    if (ele.lstSize != 1) {
        return false;
    }
    v = *((float16_t*)ele.data);
    return true;
}

// Read a configuration item which is a string

bool ZUF::ReadItemString(const char* key,char **str) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_STRING) {
        return false;
    }
    if (ele.lstSize != 1) {
        return false;
    }
    *str = (char *)ele.data;
    return true;
}

// Read a configuration item which is an array of UINT8

bool ZUF::ReadArrayU8(const char *key, uint32_t &arraySize, uint8_t **array) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_UINT8) {
        return false;
    }
    arraySize = ele.dataLen;
    *array = (uint8_t*)ele.data;
    return true;
}

// Read configuration item which is an array of float numbers

bool ZUF::ReadArrayFloat(const char* key, uint32_t& arraySize, float** array) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_FLOAT) {
        return false;
    }
    assert((ele.dataLen%sizeof(float))==0);
    arraySize = ele.dataLen/sizeof(float);
    *array = (float*)ele.data;
    return true;
}

// Read a configuration item which is an array of BFLOAT

bool ZUF::ReadArrayBfloat(const char* key, uint32_t& arraySize, float16_t** array) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_BFLOAT) {
        return false;
    }
    assert((ele.dataLen % sizeof(float16_t)) == 0);
    arraySize = ele.dataLen / sizeof(float16_t);
    *array = (float16_t*)ele.data;
    return true;
}

// Read a configuration item which is an array of FP16

bool ZUF::ReadArrayFP16(const char* key, uint32_t& arraySize, float16_t** array) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_FP16) {
        return false;
    }
    assert((ele.dataLen % sizeof(float16_t)) == 0);
    arraySize = ele.dataLen / sizeof(float16_t);
    *array = (float16_t*)ele.data;
    return true;
}

// Read a configuration item which is an array of strings

bool ZUF::ReadArrayString(const char* key,uint32_t &arraySize,char **array) {
    ZUF_CONFIG_ELE ele;

    if (!findKey(key, ele)) {
        return false;
    }
    if (ele.type != ZUF_TYPE_STRING) {
        return false;
    }
    arraySize = ele.lstSize;
    *array = (char*)ele.data;
    return true;
}
