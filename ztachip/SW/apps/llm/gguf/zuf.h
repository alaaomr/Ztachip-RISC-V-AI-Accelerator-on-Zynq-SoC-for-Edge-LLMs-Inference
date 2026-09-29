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

// This class implements ZUF file format

#ifndef __ZUF_H_
#define __ZUF_H_

#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <string>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <vector>
#include <string>
#include "../../../base/types.h"

#define ZUF_VERSION 1 // Current supported version

#define ZUF_MAGIC_NUMBER "ZTACHIP!"

typedef struct {
    uint8_t magicNumber[8];
    uint8_t len[4]; // Support small model <4G for now
    uint32_t ver[4]; // Version 
    uint8_t reserved[16];
} ZUF_HEADER;


enum ZUF_TYPE {
    ZUF_TYPE_EOF = 0,
    ZUF_TYPE_UINT32 = 1,
    ZUF_TYPE_FLOAT = 2,
    ZUF_TYPE_BFLOAT = 3,
    ZUF_TYPE_STRING = 4,
    ZUF_TYPE_UINT8 = 5,
    ZUF_TYPE_FP16 = 6,
    ZUF_TYPE_GAP = 64
};

typedef enum {
    ZUF_QUANT_INT4=0,
    ZUF_QUANT_INT8=1
} ZUF_QUANT;

typedef struct {
    enum ZUF_TYPE type;
    uint32_t sz;
    char* key;
    uint32_t lstSize;
    void* data;
    uint32_t dataLen;
} ZUF_CONFIG_ELE;

class ZUF
{
public:
    ZUF();
    ~ZUF();
    ZtaStatus Create(const char* fname);
    ZtaStatus CreateComplete();
    ZtaStatus Open(const char* fname);
    void Close();
    void WriteItemU32(const char* key, uint32_t v);
    void WriteItemFloat(const char* key, float v);
    void WriteItemBfloat(const char* key, float16_t v);
    void WriteItemFP16(const char* key, float16_t v);
    void WriteItemString(const char* key, char* str);
    void WriteItemArrayU32(const char* key, uint32_t arrSize, uint32_t * arr);
    void WriteItemArrayFloat(const char* key, uint32_t arrSize, float* arr);
    void WriteItemArrayBFLOAT(const char* key, uint32_t arrSize, float16_t * arr);
    void WriteItemArrayFP16(const char* key, uint32_t arrSize, float16_t * arr);
    void WriteItemArrayString(const char* key, uint32_t arrSize, char* arr);
    void WriteItemArrayU8(const char* key, uint32_t arrSize, uint8_t* arr);

    bool ReadItemU32(const char* key, uint32_t& v);
    bool ReadItemFloat(const char* key, float& v);
    bool ReadItemBFLOAT(const char* key, float16_t & v);
    bool ReadItemFP16(const char* key, float16_t & v);
    bool ReadItemString(const char* key, char** str);
    bool ReadArrayU8(const char* key, uint32_t & arraySize, uint8_t** array);
    bool ReadArrayFloat(const char* key, uint32_t & arraySize, float** array);
    bool ReadArrayBfloat(const char* key, uint32_t & arraySize, float16_t** array);
    bool ReadArrayFP16(const char* key, uint32_t & arraySize, float16_t** array);
    bool ReadArrayString(const char* key, uint32_t & arraySize, char** array);
    void DumpKeys(int maxKeys);   // debug: print first maxKeys metadata keys
private:
    inline void write(void* buf, size_t bufLen) {
        fwrite(buf, 1, bufLen, m_fp);
        m_wpos += bufLen;
    }
    inline void writeReset() {
        fseek(m_fp,0,SEEK_SET);
        m_wpos = 0;
    }
    bool findKey(const char* key, ZUF_CONFIG_ELE& ele);
    void writeConfig(ZUF_TYPE type, const char* key, uint32_t numItems, void* items);
private:
    FILE* m_fp;
    uint8_t* m_buf;
    uint8_t* m_top;
    size_t m_wpos;
};

#endif
