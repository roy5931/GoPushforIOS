//
//  NNGoPush.h
//  NuanNuan2
//
//  Created by Roy on 14-3-4.
//
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"

@class NNPushMessage;

@protocol NNGoPushDelegate
@required
@optional
-(void)onOpen;
-(void)onOnlineMessage:(NNPushMessage *)message;
-(void)onOfflineMessages:(NSArray *)messages;
-(void)onError:(NSError *)e WithMessage:(NSString *)message;
-(void)onClose;
@end


@interface NNGoPush : NSObject <GCDAsyncSocketDelegate>{
    
}

@property (nonatomic, retain) GCDAsyncSocket *asyncSocket;
@property (nonatomic, retain) NSString *host;
@property (nonatomic) int port;
@property (nonatomic, retain) NSString *key;
@property (nonatomic) long expire;
@property (nonatomic) long mid;
@property (nonatomic) long pmid;
@property (nonatomic) long mmid;
@property (nonatomic) long mpmid;

@property(assign) id<NNGoPushDelegate> goPushDelegate;
@property (nonatomic, retain) NSTimer *heartBeatTask;

@property (nonatomic) BOOL isGetNode;
@property (nonatomic) BOOL isHandshake;
@property (nonatomic) BOOL isDesotry;

@property (nonatomic) BOOL nextMsg;
@property (nonatomic) long nextLength;

- (id)initWithHost:(NSString *)host
                port:(int)port
                 key:(NSString *)key
            expire:(long)expire
          delegate:(id)delegate;

- (void)start;

- (void)ignoreMessage:(NNPushMessage *)message;
    
@end



@interface NNPushMessage : NSObject

@property (nonatomic, retain) NSString *msg;
@property (nonatomic) long mid;
@property (nonatomic) long gid;

- (id)initWithMsg:(NSString *)msg Mid:(long)mid Gid:(int)gid;
@end
