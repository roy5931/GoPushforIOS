//
//  ViewController.m
//  GoPushforIOS
//
//  Created by Roy on 14-3-4.
//  Copyright (c) 2014年 Roy. All rights reserved.
//

#import "ViewController.h"


@interface ViewController ()
@property (nonatomic,retain) UILabel *textlabel;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    _textlabel = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, 300, 40)];
    [_textlabel setCenter:self.view.center];
    [_textlabel setTextAlignment:NSTextAlignmentCenter];
    [self.view addSubview:_textlabel];
    
    
    NNGoPush *goPush = [[NNGoPush alloc]initWithHost:@"42.96.200.187" port:8090 key:@"jtxrvju5d7kssf5xxpx8rragzeqc" expire:30 delegate:self];
    [goPush start];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



- (void)onOpen{
    [_textlabel setText:@"onOpen"];
}

- (void)onClose{
    [_textlabel setText:@"onClose"];
}

- (void)onOnlineMessage:(NNPushMessage *)message{
    [_textlabel setText:[@"online:" stringByAppendingString:message.msg]];
}

- (void)onOfflineMessages:(NSArray *)messages{
    if (messages&&messages.count>0) {
        [_textlabel setText:[@"offline:" stringByAppendingString:[messages[0] valueForKey:@"msg"]]];
    }
}

@end
