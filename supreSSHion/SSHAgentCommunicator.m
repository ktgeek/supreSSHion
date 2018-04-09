//
//  SSHAgentCommunicator.m
//  supreSSHion
//
// MIT License
//
// Copyright (c) 2018 Keith Garner
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

#define SSH_AGENT_SUCCESS 0x6
#define SSH_AGENT_REMOVE_ALL_IDENTITIES 0x13

@interface SSHAgentCommunicator ()
- (int)getConnectedSocket;
@end

@implementation SSHAgentCommunicator
- (id)initWithSocketPath:(NSString *)socketPath {
    if ((self = [super init])) {
        _sshAgentSocketPath = socketPath;
    }

    return self;
}

- (int)getConnectedSocket {
    struct sockaddr_un socketInfo;
    socketInfo.sun_family = AF_UNIX;
    [_sshAgentSocketPath getCString:socketInfo.sun_path maxLength:104 encoding:NSASCIIStringEncoding];
    socketInfo.sun_len = SUN_LEN(&socketInfo);

    int ssh_agent_socket = socket(PF_UNIX, SOCK_STREAM, 0);
    connect(ssh_agent_socket, (struct sockaddr *)&socketInfo, socketInfo.sun_len);

    return ssh_agent_socket;
}

- (void)removeKeys {
    int socket = self.getConnectedSocket;

    // Per ssh communication, uint32 of message length (in our case the one byte following) and
    // then the message type which is SSH_AGENTC_REMOVE_ALL_IDENTITIES
    int8_t buffer[5];
    uint32_t messageLength = htonl(1);
    memcpy(buffer, &messageLength, 4);
    buffer[4] = SSH_AGENT_REMOVE_ALL_IDENTITIES;
    send(socket, buffer, 5, 0);

    recv(socket, buffer, 5, MSG_WAITALL);

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
@end
