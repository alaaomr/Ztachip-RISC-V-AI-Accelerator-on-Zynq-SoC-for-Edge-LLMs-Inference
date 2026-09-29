#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#include <assert.h>
#include "util.h"
#include "../src/soc.h"

#define ETH_TYPE_ARP 0x0806

#define ETH_TYPE_IP  0x0800

#define ARP_REQUEST 1

#define ARP_REPLY   2

#define IP_PROTO_UDP 17

#define TFTP_PORT 69

#define TFTP_RRQ  1

#define TFTP_DATA 3

#define TFTP_ACK  4

#define TFTP_ERROR 5

#define ETH_HDR 14

#define IP_HDR  20

#define UDP_HDR 8

#define TFTP_BLOCK 512

#define ARP_TIMEOUT 1000

#define ARP_RETRY   3

#define TFTP_TIMEOUT 2000

#define TFTP_RETRY   5

static uint8_t local_mac[6] = {0x00,0x00,0x5E,0x00,0xFA,0xCE};

static uint32_t local_ip = 0x0A0A0A01;

static uint8_t txpacket[100];

static uint8_t rxpacket[600];

// Calculate IP checksum

static uint16_t checksum(uint8_t *buf) {
    uint32_t sum=0;
    for(int i=0;i<20;i+=2)
        sum += (buf[i]<<8) | buf[i+1];
    while(sum>>16) sum=(sum&0xffff)+(sum>>16);
    return ~sum;
}

// Receive ethernet packet
// If packet received is ARP request then respond to it if 
// the request is for my ip address

static int ethRx(uint8_t *pkt, int len) {
    uint8_t arpReply[64];
    uint32_t targetIP;

    len = EthernetLiteReceive(pkt,len);

    if(len < 42) return len;

    if(((pkt[12]<<8)|pkt[13]) != 0x0806)
        return len; // Not an ARP

    uint8_t *arp = pkt + 14;

    uint16_t opcode = (arp[6]<<8) | arp[7];

    if(opcode != 1)
        return len;

    targetIP = (arp[24]<<24)|(arp[25]<<16)|(arp[26]<<8)|arp[27];

    if(targetIP != local_ip)
        return 0;

    memcpy(arpReply, pkt+6, 6);
    memcpy(arpReply+6, local_mac, 6);
    arpReply[12]=0x08;
    arpReply[13]=0x06;

    uint8_t *r = arpReply + 14;

    r[0]=0x00; r[1]=0x01;
    r[2]=0x08; r[3]=0x00;
    r[4]=6;
    r[5]=4;
    r[6]=0x00; r[7]=0x02;

    memcpy(r+8, local_mac, 6);
    r[14]=(local_ip>>24)&0xff;
    r[15]=(local_ip>>16)&0xff;
    r[16]=(local_ip>>8)&0xff;
    r[17]=local_ip&0xff;

    memcpy(r+18, arp+8, 6);
    memcpy(r+24, arp+14, 4);

    EthernetLiteSend(arpReply,42);
    return 0;
}

// Resolve peer IP address using ARP protocol

static bool arpResolve(uint32_t targetIP,uint8_t *targetMAC) {
    uint8_t arpPkt[64];
    uint32_t start;
    int retry=0;

    while(retry<ARP_RETRY) {
        memset(arpPkt,0,sizeof(arpPkt));

        memset(arpPkt,0xff,6);
        memcpy(arpPkt+6,local_mac,6);
        H2N16(ETH_TYPE_ARP,arpPkt+12);

        uint8_t *arp=arpPkt+14;
        H2N16(1,arp+0);
        H2N16(0x0800,arp+2);
        arp[4]=6; arp[5]=4;
        H2N16(ARP_REQUEST,arp+6);

        memcpy(arp+8,local_mac,6);
        H2N(local_ip,arp+14);
        memset(arp+18,0,6);
        H2N(targetIP,arp+24);

        if(EthernetLiteSend(arpPkt,42)==0)
            return false;

        start=TimeGet();
        while((int)TimeGet()-(int)start < ARP_TIMEOUT)
        {
            int len=ethRx(arpPkt,sizeof(arpPkt));
            if(len<42) continue;
            if(((arpPkt[12]<<8)|arpPkt[13])!=ETH_TYPE_ARP) continue;

            uint8_t *r=arpPkt+14;
            if(((r[6]<<8)|r[7])!=ARP_REPLY) continue;
            if(memcmp(r+14,&targetIP,4)!=0) continue;

            memcpy(targetMAC,r+8,6);
            return true;
        }
        retry++;
    }
    return false;
}

// Build and send UDP packet

static int sendUdp(uint8_t *dstMAC,uint32_t dstIP,
                    uint16_t srcPort,uint16_t dstPort,
                    uint8_t *payload,int payloadLen) {
    uint16_t cs;
    int pktLen;

    memcpy(txpacket,dstMAC,6);
    memcpy(txpacket+6,local_mac,6);
    H2N16(ETH_TYPE_IP,txpacket+12);

    uint8_t *ip=txpacket+ETH_HDR;
    ip[0]=0x45;
    ip[1]=0;
    H2N16(IP_HDR+UDP_HDR+payloadLen,ip+2);
    H2N16(0,ip+4);
    H2N16(0,ip+6);
    ip[8]=64;
    ip[9]=IP_PROTO_UDP;
    H2N16(0,ip+10);
    H2N(local_ip,ip+12);
    H2N(dstIP,ip+16);
    cs=checksum(ip);
    H2N16(cs,ip+10);

    uint8_t *udp=ip+IP_HDR;
    H2N16(srcPort,udp+0);
    H2N16(dstPort,udp+2);
    H2N16(UDP_HDR+payloadLen,udp+4);
    H2N16(0,udp+6);

    memcpy(udp+8,payload,payloadLen);

    pktLen=ETH_HDR+IP_HDR+UDP_HDR+payloadLen;
    assert(pktLen < (int)sizeof(txpacket));
    return EthernetLiteSend(txpacket,pktLen);
}

// Initialize NET layer
ZtaStatus NetInit(uint32_t localIP) {
    EthernetLiteInit(local_mac);
    local_ip = localIP;
    return ZtaStatusOk;
}

// Perform file download from TPTP server

size_t NetTftpDownload(uint32_t serverIP,char *fileName,uint8_t *buf,size_t bufSize,bool printProgress) {
    uint8_t serverMAC[6];
    uint8_t rrq[32];
    uint8_t ack[4];
    int rrqLen;
    uint16_t localPort=40000;
    uint16_t serverPort=TFTP_PORT;
    size_t total;
    uint16_t expectedBlock;
    int retry;
    uint32_t start;
    int lastPrintTotal=0;
    bool eof=false;

    if(printProgress)
        printf("\r\n");
    if(!arpResolve(serverIP,serverMAC))
        return 0;

    H2N16(TFTP_RRQ,rrq);
    strcpy((char*)rrq+2,fileName);
    rrqLen=2;
    rrqLen+=strlen(fileName)+1;
    strcpy((char*)rrq+rrqLen,"octet");
    rrqLen+=6;
    assert(rrqLen < (int)sizeof(rrq));

    if(sendUdp(serverMAC,serverIP,localPort,serverPort,rrq,rrqLen)==0)
        return 0;

    total=0;

    expectedBlock=1;

    retry=0;

    start=TimeGet();

    while(1)
    {
        if((int)TimeGet()-(int)start > TFTP_TIMEOUT) {
            if(++retry>TFTP_RETRY)
                return 0;
            if(sendUdp(serverMAC,serverIP,localPort,serverPort,rrq,rrqLen)==0)
                return 0;
            start=TimeGet();
            continue;
        }
        int len=ethRx(rxpacket,sizeof(rxpacket));
        if(len<=0) continue;
        if(((rxpacket[12]<<8)|rxpacket[13])!=ETH_TYPE_IP) continue;
        uint8_t *ip=rxpacket+ETH_HDR;
        if(ip[9]!=IP_PROTO_UDP) continue;
        uint8_t *udp=ip+IP_HDR;
        uint16_t srcPort=(udp[0]<<8)|udp[1];
        uint16_t dstPort=(udp[2]<<8)|udp[3];
        uint16_t udpLen = (udp[4] << 8) | udp[5];
        int udpPayloadLen = udpLen - UDP_HDR;
        if(dstPort!=localPort) continue;
        if(udpLen < UDP_HDR + 4)
            continue;
        uint8_t *tftp=udp+UDP_HDR;
        uint16_t opcode=(tftp[0]<<8)|tftp[1];
        if(opcode==TFTP_DATA) {
            serverPort=srcPort;
            uint16_t block=(tftp[2]<<8)|tftp[3];
            int dataLen = udpPayloadLen - 4;
            if(block==expectedBlock) {
                if(total > bufSize) {
                    // Already running out of buffer. Send ERROR to terminate transfer
                    H2N16(TFTP_ERROR,ack);
                    H2N16(3,ack+2);
                    if(sendUdp(serverMAC,serverIP,localPort,serverPort,ack,4)==0)
                        return 0;
                    return bufSize;
                } else {
                    H2N16(TFTP_ACK,ack);
                    H2N16(block,ack+2);
                    if(sendUdp(serverMAC,serverIP,localPort,serverPort,ack,4)==0) {
                        return 0;
                    }
                    expectedBlock++;
                    start=TimeGet();
                    retry=0;
                }
                if(total < bufSize) {
                    len = (bufSize-total);
                    if(len > dataLen)
                        len = dataLen;
                    memcpy(buf+total,tftp+4,len);
                }
                total+=dataLen;
                if(printProgress) {
                    if(total-lastPrintTotal > 1000000) {
                        printf("%d/%dM\r",total/1000000,bufSize/1000000); // Print every 10M
                        fflush(stdout);
                        lastPrintTotal = total;
                    }
                }
                if(dataLen<TFTP_BLOCK) {
                    if(printProgress)
                        printf("\r\n");
                    return total;
                }
            }
        }
        else if(opcode==TFTP_ERROR) {
            return 0;
        }
    }
}
