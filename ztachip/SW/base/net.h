#ifndef _THIRDPARTY_TFTP_H_

#define _THIRDPARTY_TFTP_H_

#include <stdint.h>

ZtaStatus NetInit(uint32_t localIP);

size_t NetTftpDownload(uint32_t serverIP,char *fileName,uint8_t *buf,size_t bufSize,bool printProgress);

#endif
