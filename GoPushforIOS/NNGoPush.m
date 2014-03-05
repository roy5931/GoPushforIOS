//
//  NNGoPush.m
//  NuanNuan2
//
//  Created by Roy on 14-3-4.
//
//

#import "NNGoPush.h"
#import "JsonKit.h"
#import "AFNetworking.h"

#define KS_NET_STATE_OK 0

#define KS_NET_EXCEPTION_SUBSCRIBE_CODE -1
#define KS_NET_EXCEPTION_OFFLINE_CODE -2
#define KS_NET_EXCEPTION_SOCKET_READ_CODE -3
#define KS_NET_EXCEPTION_SOCKET_WRITE_CODE -4
#define KS_NET_EXCEPTION_SOCKET_INIT_CODE -5

#define KS_NET_JSON_KEY_RET @"ret"
#define KS_NET_JSON_KEY_MSG @"msg"
#define KS_NET_JSON_KEY_DATA @"data"
#define KS_NET_JSON_KEY_SERVER @"server"

#define KS_NET_JSON_KEY_MESSAGES @"msgs"
#define KS_NET_JSON_KEY_PMESSAGES @"pmsgs"

#define KS_NET_JSON_KEY_MESSAGE_MSG @"msg"
#define KS_NET_JSON_KEY_MESSAGE_MID @"mid"
#define KS_NET_JSON_KEY_MESSAGE_GID @"gid"

#define KS_NET_KEY_ADDRESS @"address"
#define KS_NET_KEY_PORT @"port"

#define KS_NET_SOCKET_CONNECTION_ACTION @"socket_connection_action"

#define KS_NET_MESSAGE_OBTAIN_DATA_OK 2
#define KS_NET_MESSAGE_DISCONNECT 1

#define KS_NET_MESSAGE_PRIVATE_GID 0

#define TAG_DEFAULT 0
#define TAG_RESPONSE_HEARTBEAT 1
#define TAG_RESPONSE_HEADER 2
#define TAG_RESPONSE_LENGTH 3
#define TAG_RESPONSE_MSG 4


@implementation NNGoPush



- (id)initWithHost:(NSString *)host port:(int)port key:(NSString *)key expire:(long)expire delegate:(id)delegate{
    self.host = host;
    self.port = port;
    self.key = key;
    self.expire = expire;
    self.goPushDelegate = delegate;
    long mid = ((NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"mid"]).longValue;
    long pmid = ((NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"pmid"]).longValue;
    self.mid = mid;
    self.pmid = pmid;
    self.mmid = mid;
    self.mpmid = pmid;
    return self;
}

- (void)start{
    NSString *string = [NSString stringWithFormat:@"http://%@:%d/server/get?key=%@&expire=%ld&proto=2",_host,_port,_key,_expire];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:string]];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Success: %@", operation.responseString);
        NSString *JSON = operation.responseString;
        
        // 初始化socket
        [self initSocket:[self getNodeHostAndPort:JSON]];
        
        
        // 协议已经握手，打开
        if (_goPushDelegate) {
            [_goPushDelegate onOpen];
        }
        // 如果有离线消息
        [self getOfflineMessage:^(NSArray *messages) {
            if (messages != NULL) {
                if (_goPushDelegate) {
                    [_goPushDelegate onOfflineMessages:messages];
                }
            }
        }];
        
        
        // 准备定时心跳任务
        _heartBeatTask = [NSTimer scheduledTimerWithTimeInterval:_expire target:self selector:@selector(heartBeat) userInfo:nil repeats:YES];
        
        [self readline];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failure: %@", error);
    }];
    [operation start];
}

- (void)initSocket:(NSArray *)node{
    //    try {
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    _asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:mainQueue];
    NSError *error = NULL;
    [_asyncSocket connectToHost:node[0] onPort:((NSNumber *)node[1]).intValue withTimeout:_expire*2 error:&error];
    
    // 发送请求协议头
    [self sendHeader];
}

- (void)destory{
    if (_isDesotry) {
        return;
    }
    _isDesotry = true;
    if (_goPushDelegate) {
        [_goPushDelegate onClose];
    }
    if (_asyncSocket&&[_asyncSocket isConnected]&&_asyncSocket) {
        [_asyncSocket disconnectAfterReadingAndWriting];
        [_asyncSocket release];
    }
    if (_heartBeatTask&&[_heartBeatTask isValid]) {
        [_heartBeatTask invalidate];
    }
}

- (NSArray *)getNodeHostAndPort:(NSString *)domain{
    //    @try {
    NSDictionary *dic = [domain objectFromJSONString];
    //        JSONObject data = new JSONObject(HttpUtils.get(domain));
    // 判断协议
    int ret = ((NSNumber *)dic[KS_NET_JSON_KEY_RET]).intValue;
    //        int ret = data.getInt(Constant.KS_NET_JSON_KEY_RET);
    if (ret == KS_NET_STATE_OK) {
        NSDictionary *jot = dic[KS_NET_JSON_KEY_DATA];
        NSString *server = jot[KS_NET_JSON_KEY_SERVER];
        NSArray *result = [server componentsSeparatedByString:@":"];
        // 已经获取节点
        _isGetNode = YES;
        return result;
    }
    return NULL;
}

- (void)sendHeader{
    NSString *expireStr = [NSString stringWithFormat:@"%ld",_expire];
    NSString *protocol = [NSString stringWithFormat:@"*3\r\n$3\r\nsub\r\n$%lu\r\n%@\r\n$%lu\r\n%@\r\n",(unsigned long)_key.length,_key,(unsigned long)expireStr.length,expireStr];
    
    // 发送请求协议
    [self send:protocol tag:TAG_RESPONSE_HEADER];
}

- (void)send:(NSString *)message tag:(long)tag{
    NSAssert(_asyncSocket!=NULL, @"asyncSocket could not be NULL!");
    [_asyncSocket writeData:[message dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:tag];
}

- (void)readline{
    NSAssert(_asyncSocket!=NULL, @"asyncSocket could not be NULL!");
    NSData *term = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    [_asyncSocket readDataToData:term withTimeout:-1 tag:TAG_DEFAULT];
}

- (void)handleLine:(NSString *)line{
    if (_nextMsg) {
        _nextMsg = NO;
        _nextLength = 0;
        NSDictionary *jot = [line objectFromJSONString];
        NNPushMessage *pushMessage = [[[NNPushMessage alloc]initWithMsg:jot[KS_NET_JSON_KEY_MESSAGE_MSG]
                                                                    Mid:((NSNumber *)jot[KS_NET_JSON_KEY_MESSAGE_MID]).longValue
                                                                    Gid:((NSNumber *)jot[KS_NET_JSON_KEY_MESSAGE_GID]).intValue]autorelease];
        // 过滤重复数据，（获取离线消息之后的头几条在线消息可能会重复）
        // 注意之后不需要更新mmid和pmid了，之后服务端是绝对的顺序以及无重复返回消息，只有离线读完读在线的过程可能会重复。为了保险还是加上
        if (pushMessage.gid == KS_NET_MESSAGE_PRIVATE_GID) {
            if (pushMessage.mid <= _mmid)
            return;
            else
            _mmid = pushMessage.mid;
        } else {
            if (pushMessage.mid <= _mpmid)
            return;
            else
            _mpmid = pushMessage.mid;
        }
        if (_goPushDelegate) {
            [_goPushDelegate onOnlineMessage:pushMessage];
        }
    } else if ([line hasPrefix:@"+"]) {
        // 初始心跳
        _isHandshake = true;
    } else if ([line hasPrefix:@"-"]) {
        // 协议错误
        NSLog(@"comet节点握手协议错误:%@",line);
    } else if ([line hasPrefix:@"$"]) {
        _nextMsg = YES;
        _nextLength = [[line substringFromIndex:1] longLongValue];
    }
}

- (void)getOfflineMessage:(void(^)(NSArray *))messages{
    NSString *string = [NSString stringWithFormat:@"http://%@:%d/msg/get?key=%@&mid=%ld&pmid=%ld",_host,_port,_key,_mid,_pmid];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:string]];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Success: %@", operation.responseString);
        
        NSString *offlineMessage = operation.responseString;
        NSDictionary *jot = [offlineMessage objectFromJSONString];
        // 协议错误
        int ret = ((NSNumber *)jot[KS_NET_JSON_KEY_RET]).intValue;
        if (ret != KS_NET_STATE_OK) {
            NSLog(@"获取离线消息协议返回码错误: %d",ret);
        }
        // 有data数据
        if (![jot[KS_NET_JSON_KEY_DATA] isKindOfClass:[NSNull class]]){
            NSMutableArray *res = [NSMutableArray array];
            int pl = 0;
            // 获取私信列表
            NSDictionary *data = jot[KS_NET_JSON_KEY_DATA];
            // 有msgs数据
            if (![data[KS_NET_JSON_KEY_MESSAGES] isKindOfClass:[NSNull class]]) {
                NSArray *array = (NSArray *)data[KS_NET_JSON_KEY_MESSAGES];
                for (int i = 0; i < array.count; i++) {
                    NSString *message = (NSString *)array[i];
                    NSDictionary *mDic = [message objectFromJSONString];
                    NNPushMessage *pushMessage = [[[NNPushMessage alloc]initWithMsg:mDic[KS_NET_JSON_KEY_MESSAGE_MSG]
                                                                                Mid:((NSNumber *)mDic[KS_NET_JSON_KEY_MESSAGE_MID]).longValue
                                                                                Gid:0]autorelease];
                    [res addObject:pushMessage];
                }
                
                // 更新最大私信ID
                pl = (int)res.count;
                if (pl > 0)
                _mmid = ((NNPushMessage *)res[pl-1]).mid;
            }
            // 获取公信列表
            // 有msgs数据
            if (![data[KS_NET_JSON_KEY_PMESSAGES] isKindOfClass:[NSNull class]]) {
                NSArray *array = (NSArray *)data[KS_NET_JSON_KEY_PMESSAGES];
                for (int i = 0; i < array.count; i++) {
                    NSString *message = (NSString *)array[i];
                    NSDictionary *mDic = [message objectFromJSONString];
                    NNPushMessage *pushMessage = [[[NNPushMessage alloc]initWithMsg:mDic[KS_NET_JSON_KEY_MESSAGE_MSG]
                                                                                Mid:((NSNumber *)mDic[KS_NET_JSON_KEY_MESSAGE_MID]).longValue
                                                                                Gid:1]autorelease];
                    [res addObject:pushMessage];
                }
                // 更新最大公信ID
                if (res.count > pl)
                _mpmid = ((NNPushMessage *)res[res.count - 1]).mid;
            }
            if (messages) {
                messages(res);
            }
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failure: %@", error);
    }];
    [operation start];
}

- (BOOL)isGetNode{
    return _isGetNode;
}

- (BOOL)isHandshake{
    return _isHandshake;
}

- (void)heartBeat{
    [self send:@"h" tag:TAG_RESPONSE_HEARTBEAT];
    NSLog(@"heartBeat");
}


- (void)ignoreMessage:(NNPushMessage *)message{
    if (message.gid == KS_NET_MESSAGE_PRIVATE_GID) {
        long mid = ((NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"mid"]).longValue;
        if (message.mid>mid) {
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithLong:message.mid] forKey:@"mid"];
        }
    }
    else {
        long pmid = ((NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"pmid"]).longValue;
        if (message.mid>pmid) {
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithLong:message.mid] forKey:@"pmid"];
        }
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Socket Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	NSLog(@"socket:%p didConnectToHost:%@ port:%hu", sock, host, port);
    //	self.viewController.label.text = @"Connected";
	
    //	NSLog(@"localHost :%@ port:%hu", [sock localHost], [sock localPort]);
	
#if USE_SECURE_CONNECTION
	{
		// Connected to secure server (HTTPS)
        
#if ENABLE_BACKGROUNDING && !TARGET_IPHONE_SIMULATOR
		{
			// Backgrounding doesn't seem to be supported on the simulator yet
			
			[sock performBlock:^{
				if ([sock enableBackgroundingOnSocket])
                NSLog(@"Enabled backgrounding on socket");
				else
                DDLogWarn(@"Enabling backgrounding failed!");
			}];
		}
#endif
		
		// Configure SSL/TLS settings
		NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:3];
		
		// If you simply want to ensure that the remote host's certificate is valid,
		// then you can use an empty dictionary.
		
		// If you know the name of the remote host, then you should specify the name here.
		//
		// NOTE:
		// You should understand the security implications if you do not specify the peer name.
		// Please see the documentation for the startTLS method in GCDAsyncSocket.h for a full discussion.
		
		[settings setObject:@"www.paypal.com"
					 forKey:(NSString *)kCFStreamSSLPeerName];
		
		// To connect to a test server, with a self-signed certificate, use settings similar to this:
		
        //	// Allow expired certificates
        //	[settings setObject:[NSNumber numberWithBool:YES]
        //				 forKey:(NSString *)kCFStreamSSLAllowsExpiredCertificates];
        //
        //	// Allow self-signed certificates
        //	[settings setObject:[NSNumber numberWithBool:YES]
        //				 forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];
        //
        //	// In fact, don't even validate the certificate chain
        //	[settings setObject:[NSNumber numberWithBool:NO]
        //				 forKey:(NSString *)kCFStreamSSLValidatesCertificateChain];
		
		NSLog(@"Starting TLS with settings:\n%@", settings);
		
		[sock startTLS:settings];
		
		// You can also pass nil to the startTLS method, which is the same as passing an empty dictionary.
		// Again, you should understand the security implications of doing so.
		// Please see the documentation for the startTLS method in GCDAsyncSocket.h for a full discussion.
		
	}
#else
	{
		// Connected to normal server (HTTP)
		
#if ENABLE_BACKGROUNDING && !TARGET_IPHONE_SIMULATOR
		{
			// Backgrounding doesn't seem to be supported on the simulator yet
			
			[sock performBlock:^{
				if ([sock enableBackgroundingOnSocket])
                NSLog(@"Enabled backgrounding on socket");
				else
                DDLogWarn(@"Enabling backgrounding failed!");
			}];
		}
#endif
	}
#endif
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock
{
	NSLog(@"socketDidSecure:%p", sock);
    //	self.viewController.label.text = @"Connected + Secure";
	
    //	NSString *requestStr = [NSString stringWithFormat:@"GET / HTTP/1.1\r\nHost: %@\r\n\r\n", HOST];
    //	NSData *requestData = [requestStr dataUsingEncoding:NSUTF8StringEncoding];
    //
    //	[sock writeData:requestData withTimeout:-1 tag:0];
    //	[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	NSLog(@"socket:%p didWriteDataWithTag:%ld", sock, tag);
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	NSLog(@"socket:%p didReadData:withTag:%ld", sock, tag);
	
	NSString *httpResponse = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]autorelease];
    
    NSLog(@"HTTP Response:\n%@", httpResponse);
    
    [self handleLine:httpResponse];
    
    [self readline];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	NSLog(@"socketDidDisconnect:%p withError: %@", sock, err);
    //	self.viewController.label.text = @"Disconnected";
}

@end


@implementation NNPushMessage

- (id)initWithMsg:(NSString *)msg Mid:(long)mid Gid:(int)gid{
    self.msg = msg;
    self.mid = mid;
    self.gid = gid;
    return self;
}

@end
