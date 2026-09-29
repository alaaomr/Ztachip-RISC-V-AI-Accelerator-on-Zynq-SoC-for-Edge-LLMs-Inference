#include <stdio.h>
#include <stdlib.h>
#include "zuf.h"
#include "gguf.h"

int main(int argc,char *argv[])
{
    GGUF gguf;
    bool forSim;
    ZUF_QUANT quant;

    if(argc != 5) {
        printf("Error: Usage quant [SIM|ZTA] [Q4|Q8] <gguf file> <zuf file>\r\n");
        return -1;
    }
    if(strcmp(argv[1],"SIM")==0) {
        printf("Quantize for simulation \r\n");
        forSim = true;
    }
    else if(strcmp(argv[1],"ZTA")==0) {
        printf("Quantize for ztachip \r\n");
        forSim = false;
    }
    else
    {
        printf("Error: Usage quant [SIM|ZTA] <gguf file> <zuf file>\r\n");
        return -1;
    }
    printf("Quantize model %s quant=%s \r\n",argv[3],argv[2]);
    if(strcmp(argv[2],"Q4")==0)
        quant = ZUF_QUANT_INT4;
    else if(strcmp(argv[2],"Q8")==0)
        quant = ZUF_QUANT_INT8;
    else {
        printf("Invalid quantization");
        return -1;
    }
    if(gguf.Open(argv[3]) != ZtaStatusOk) {
        printf("Error open GGUF file \r\n");
        exit(-1);
    }
    if(gguf.SaveAsZUF(argv[4],forSim,quant) != ZtaStatusOk)
        printf("quantization fail \r\n");
    else
        printf("Quantization complete successfully\r\n");
    return 0;
}
