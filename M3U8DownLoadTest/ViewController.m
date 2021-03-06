//
//  ViewController.m
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import "ViewController.h"
#import "ZBLM3u8Manager.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()
@property (strong, nonatomic) AVPlayer *player;

@property (strong, nonatomic) AVPlayerItem *playerItem;

@property (strong, nonatomic) AVPlayerLayer *playerLayer;

@property (strong, nonatomic) UIView *playerView;

@property (strong, nonatomic) AVPlayerViewController *playerVC;
@property (strong, nonatomic) UIScrollView *scrollView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.scrollView = [[UIScrollView alloc]initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, self.view.bounds.size.height - 100)];
    [self.view addSubview:self.scrollView];
    
    UIButton *suspendBt = [UIButton buttonWithType:UIButtonTypeSystem];
    suspendBt.frame = CGRectMake(15, 50, 60, 40);
    [suspendBt setTitle:@"suspend" forState:UIControlStateNormal];
    [suspendBt addTarget:self action:@selector(suspend) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:suspendBt];
    
    UIButton *resumeBt = [UIButton buttonWithType:UIButtonTypeSystem];
    resumeBt.frame = CGRectMake(80, 50, 60, 40);
    [resumeBt setTitle:@"resume" forState:UIControlStateNormal];
    [resumeBt addTarget:self action:@selector(resume) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:resumeBt];
    
    UIScrollView *progressView = [[UIScrollView alloc]initWithFrame:CGRectMake(0, 90, self.view.bounds.size.width, 40)];
    progressView.backgroundColor = [UIColor grayColor];
    [self.view addSubview:progressView];
    /*
     一些免费的m3u8链接【格式可能不兼容，需要分析处理】
     https://bitmovin.com/mpeg-dash-hls-examples-sample-streams/
     */

    NSArray *urlArr = @[@"https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_360_1000000.m3u8",
                        @"https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_540_1500000.m3u8",
                        @"https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_720_3000000.m3u8",
                        @"https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_1080_5000000.m3u8"
                        ].mutableCopy;
    
    self.scrollView.contentSize = CGSizeMake(self.view. bounds.size.width, self.view.frame.size.width * 9.0 / 16.0 * urlArr.count);
    CGFloat width = 80.0f;
    progressView.contentSize = CGSizeMake(10 + width * urlArr.count, 0);
    
    for (NSInteger i = 0; i < urlArr.count ; i ++) {
        NSString *url = urlArr[i];
        __block  UILabel *label = [UILabel new];
        label.frame = CGRectMake(10 + width*i, 5, width, 40);
        [progressView addSubview:label];
        [[ZBLM3u8Manager shareInstance] downloadVideoWithUrlString:url downloadProgressHandler:^(float progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                label.text = [NSString stringWithFormat:@"%0.2f%%",progress * 100];
            });
        } downloadSuccessBlock:^(NSString *localPlayUrlString) {
            [[ZBLM3u8Manager shareInstance]  tryStartLocalService];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self playWithUrlString:localPlayUrlString];
            });
        }];
    }
}

- (void)suspend
{
    [[ZBLM3u8Manager shareInstance] suspendDownload];
}

- (void)resume
{
    [[ZBLM3u8Manager shareInstance] resumeDownload];
}

static int avCount = 0;
- (void)playWithUrlString:(NSString *)urlStr
{
    self.playerItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:urlStr]];
    self.player = [[AVPlayer alloc] initWithPlayerItem:self.playerItem];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.width * 9.0 / 16.0);
    self.playerView = [[UIView alloc] initWithFrame:CGRectMake(0, 20 + avCount * CGRectGetHeight(self.playerLayer.frame), CGRectGetWidth(self.playerLayer.frame), CGRectGetHeight(self.playerLayer.frame))];
    self.playerView.backgroundColor = [UIColor blackColor];
    [self.playerView.layer addSublayer:self.playerLayer];
    [self.scrollView addSubview:self.playerView];
    [self.player play];
    avCount ++;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
