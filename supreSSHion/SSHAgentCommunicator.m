// MIT License
//
// Copyright (c) 2018-2026 Keith Garner
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "SSHAgentCommunicator.h"
#include <sys/types.h>
#include <sys/un.h>
#include <sys/socket.h>
#import <CommonCrypto/CommonDigest.h>

static uint32_t readUInt32(const uint8_t *buf, size_t offset) {
    uint32_t val;
    memcpy(&val, buf + offset, 4);
    return ntohl(val);
}

static NSString *readNSString(const uint8_t *buf, size_t offset, uint32_t len) {
    return [[NSString alloc] initWithBytes:buf + offset length:len encoding:NSUTF8StringEncoding] ?: @"";
}

#define SSH_AGENT_SUCCESS 0x6
#define SSH_AGENT_FAILURE 0x5
#define SSH_AGENT_IDENTITIES_ANSWER 0xc

#define SSH_AGENTC_REQUEST_IDENTITIES 0xb
#define SSH_AGENTC_REMOVE_ALL_IDENTITIES 0x13

@interface SSHAgentCommunicator ()
- (int)getConnectedSocket;
- (void)sendCommand:(uint8_t)cmd toSocket:(int)sock;
@end

@implementation SSHAgentCommunicator
-(id)init {
    if (self = [super init])  {
        self.sshAgentSocketPath = [[NSProcessInfo processInfo] environment][@"SSH_AUTH_SOCK"];
    }

    return self;
}

- (id)initWithSocketPath:(NSString *)socketPath {
    if (self = [super init]) {
        self.sshAgentSocketPath = socketPath;
    }

    return self;
}

- (int)getConnectedSocket {
    struct sockaddr_un socketInfo;
    socketInfo.sun_family = AF_UNIX;
    [_sshAgentSocketPath getCString:socketInfo.sun_path maxLength:104
                           encoding:NSASCIIStringEncoding];
    socketInfo.sun_len = SUN_LEN(&socketInfo);

    int ssh_agent_socket = socket(PF_UNIX, SOCK_STREAM, 0);
    connect(ssh_agent_socket, (struct sockaddr *)&socketInfo, socketInfo.sun_len);

    return ssh_agent_socket;
}

- (void)sendCommand:(uint8_t)cmd toSocket:(int)sock {
    uint8_t buf[5];
    uint32_t len = htonl(1);
    memcpy(buf, &len, 4);
    buf[4] = cmd;
    send(sock, buf, 5, 0);
}

- (void)removeKeys {
    int socket = self.getConnectedSocket;
    [self sendCommand:SSH_AGENTC_REMOVE_ALL_IDENTITIES toSocket:socket];

    uint8_t buffer[5];

    recv(socket, buffer, 5, MSG_WAITALL);

    uint32_t messageLength;
    memcpy(&messageLength, buffer, 4);
    messageLength = ntohl(messageLength);

    // TODO: Turn this into a generic function if possible/nessessary.
    if ((messageLength != 1) || (buffer[4] != SSH_AGENT_SUCCESS))
    {
        NSLog(@"Failure removing keys from agent");
    }
    else
    {
        NSLog(@"Successfully removed keys");
    }

    close(socket);
}

- (NSArray<NSDictionary<NSString*,NSString*>*>*)getLoadedKeys {
    int socket = self.getConnectedSocket;
    [self sendCommand:SSH_AGENTC_REQUEST_IDENTITIES toSocket:socket];

    uint8_t cmdBuffer[5];
    recv(socket, cmdBuffer, 5, MSG_WAITALL);
    uint32_t messageLength;
    memcpy(&messageLength, cmdBuffer, 4);
    messageLength = ntohl(messageLength);

    if (cmdBuffer[4] != SSH_AGENT_IDENTITIES_ANSWER) {
        NSLog(@"Failure getting list of keys");
        close(socket);
        return @[];
    }

    uint8_t nKeysBuf[4];
    recv(socket, nKeysBuf, 4, MSG_WAITALL);
    uint32_t nKeys = readUInt32(nKeysBuf, 0);

    uint32_t payloadLength = messageLength - 5;
    if (payloadLength == 0) {
        close(socket);
        return @[];
    }

    uint8_t *payload = malloc(payloadLength);
    recv(socket, payload, payloadLength, MSG_WAITALL);
    close(socket);

    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:nKeys];
    size_t offset = 0;

    for (uint32_t i = 0; i < nKeys && offset + 4 <= payloadLength; i++) {
        // Key blob
        uint32_t blobLen = readUInt32(payload, offset);
        offset += 4;
        if (offset + blobLen > payloadLength) break;

        // Fingerprint: SHA256 of the raw key blob
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(payload + offset, blobLen, digest);
        NSData *digestData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
        NSString *b64 = [digestData base64EncodedStringWithOptions:0];
        // Remove trailing '=' padding to match ssh-keygen output
        b64 = [b64 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
        NSString *fingerprint = [@"SHA256:" stringByAppendingString:b64];

        // Key type: first length-prefixed string inside the blob
        uint32_t typeLen = readUInt32(payload, offset);
        NSString *keyType = readNSString(payload, offset + 4, typeLen);

        offset += blobLen;

        // Comment
        if (offset + 4 > payloadLength) break;
        uint32_t commentLen = readUInt32(payload, offset);
        offset += 4;
        if (offset + commentLen > payloadLength) break;
        NSString *comment = readNSString(payload, offset, commentLen);
        offset += commentLen;

        [keys addObject:@{@"type": keyType, @"fingerprint": fingerprint, @"comment": comment}];
    }

    free(payload);
    return keys;
}
@end
