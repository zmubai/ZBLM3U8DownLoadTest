//
//  ZBLM3u8Manager.m
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import "ZBLM3u8Manager.h"
#import "ZBLM3u8FileManager.h"
#import "ZBLM3u8DownloadContainer.h"
#import "HTTPServer.h"
#import "ZBLM3u8Setting.h"
#import "AFNetworkReachabilityManager.h"
/*
 控制中心，策略中心
 */
@interface ZBLM3u8Manager ()
@property (nonatomic, strong) NSMutableDictionary *downloadContainerDictionary;
@property (nonatomic, assign) NSInteger concurrentMovieDownloadCount;
@property (nonatomic, assign) NSInteger concurrentTsDownloadCount;
@property (nonatomic, strong) dispatch_semaphore_t movieSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, strong) dispatch_queue_t downloadQueue;
@property (strong, nonatomic) HTTPServer *httpServer;
@property (nonatomic, assign, getter=isSuspend) BOOL suspend;
@end

@implementation ZBLM3u8Manager
+ (instancetype)shareInstance
{
    static ZBLM3u8Manager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.downloadContainerDictionary = @{}.mutableCopy;
        sharedInstance.concurrentMovieDownloadCount = [ZBLM3u8Setting maxConcurrentMovieDownloadCount];
        sharedInstance.concurrentTsDownloadCount = [ZBLM3u8Setting maxTsFileDownloadCount];
        sharedInstance.movieSemaphore = dispatch_semaphore_create(sharedInstance.concurrentMovieDownloadCount);
        sharedInstance.downloadQueue = dispatch_queue_create("ZBLM3u8Manager.download", DISPATCH_QUEUE_CONCURRENT);
        sharedInstance.lock = dispatch_semaphore_create(1);
        sharedInstance.suspend = NO;
        [sharedInstance controllerDownloadByNetWorkStatus];
    });
    return sharedInstance;
}

#pragma mark - public
- (BOOL)exitLocalVideoWithUrlString:(NSString*) urlStr
{
    return [ZBLM3u8FileManager exitItemWithPath:[[ZBLM3u8Setting commonDirPrefix] stringByAppendingPathComponent:[[ZBLM3u8Setting uuidWithUrl:urlStr] stringByAppendingString:[ZBLM3u8Setting m3u8InfoFileName]]]];
}

- (NSString *)localPlayUrlWithOriUrlString:(NSString *)urlString
{
    return  [NSString stringWithFormat:@"%@/%@/%@",[ZBLM3u8Setting localHost],[ZBLM3u8Setting uuidWithUrl:urlString],[ZBLM3u8Setting m3u8InfoFileName]];
}

#pragma mark - download
- (void)controllerDownloadByNetWorkStatus
{
    __weak __typeof(self) weakSelf = self;
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        switch (status) {
            case AFNetworkReachabilityStatusReachableViaWiFi:
                NSLog(@"manager suspendDownload");
                [weakSelf resumeDownload];
                
                break;
            default:
                
                NSLog(@"manager suspendDownload");
//                [weakSelf suspendDownload];
                break;
        }
    }];
    [[AFNetworkReachabilityManager sharedManager]startMonitoring];
}

- (void)downloadVideoWithUrlString:(NSString *)urlStr downloadProgressHandler:(ZBLM3u8ManagerDownloadProgressHandler)downloadProgressHandler downloadSuccessBlock:(ZBLM3u8ManagerDownloadSuccessBlock) downloadSuccessBlock
{
    dispatch_async(_downloadQueue, ^{
        dispatch_semaphore_wait(_movieSemaphore, DISPATCH_TIME_FOREVER);
        __weak __typeof(self) weakself = self;
        [[self downloadContainerWithUrlString:urlStr] startDownloadWithUrlString:urlStr  downloadProgressHandler:^(float progress) {
            downloadProgressHandler(progress);
        } completaionHandler:^(NSString *locaLUrl, NSError *error) {
            if (!error) {
                [weakself.downloadContainerDictionary removeObjectForKey:[ZBLM3u8Setting uuidWithUrl:urlStr]];
                NSLog(@"下载完成:%@",urlStr);
                downloadSuccessBlock(locaLUrl);
            }
            else
            {
                NSLog(@"下载失败:%@",error);
                [self resumeDownload];
            }
            NSLog(@"%@",weakself.downloadContainerDictionary.allKeys);
            dispatch_semaphore_signal(_movieSemaphore);
        }];
    });
}

//下载中是可以接受 消息的
- (void)resumeDownload
{
    //    if (!_suspend) {
    //        return;
    //    }
    _suspend = NO;
    dispatch_sync(_downloadQueue, ^{
        [self _lock];
        NSArray <ZBLM3u8DownloadContainer *> *containers = _downloadContainerDictionary.allValues;
        [self _unlock];
        for (ZBLM3u8DownloadContainer *dc in containers) {
            [dc resumeDownload];
        }
    });
}

- (void)suspendDownload
{
    if (_suspend) {
        return;
    }
    _suspend = YES;
    dispatch_sync(_downloadQueue, ^{
        [self _lock];
        NSArray <ZBLM3u8DownloadContainer *> *containers = _downloadContainerDictionary.allValues;
        [self _unlock];
        for (ZBLM3u8DownloadContainer *dc in containers) {
            [dc suspendDownload];
        }
    });
}

#pragma mark -
- (ZBLM3u8DownloadContainer *)downloadContainerWithUrlString:(NSString *)urlString
{
    ZBLM3u8DownloadContainer *dc = [_downloadContainerDictionary valueForKey:[ZBLM3u8Setting uuidWithUrl:urlString]];
    if (!dc) {
        dc = [ZBLM3u8DownloadContainer  new];
        __weak __typeof(self) weakself = self;
        [dc setAnalysisM3u8InfoSuccessBlock:^{
            return weakself.concurrentTsDownloadCount;
        }];
        [self _lock];
        [_downloadContainerDictionary setValue:dc forKey:[ZBLM3u8Setting uuidWithUrl:urlString]];
        [self _unlock];
    }
    else
    {
        //判断WIfi
        [dc resumeDownload];
    }
    return dc;
}

#pragma mark - service
- (void)tryStartLocalService
{
    [self _lock];
    if (!self.httpServer) {
        self.httpServer=[[HTTPServer alloc]init];
        [self.httpServer setType:@"_http._tcp."];
        [self.httpServer setPort:[ZBLM3u8Setting port].integerValue];
        [self.httpServer setDocumentRoot:[ZBLM3u8Setting commonDirPrefix]];
        NSError *error;
        if ([self.httpServer start:&error]) {
            NSLog(@"开启HTTP服务器 端口:%hu",[self.httpServer listeningPort]);
        }
        else{
            NSLog(@"服务器启动失败错误为:%@",error);
        }
    }
    else if(!self.httpServer.isRunning)
    {
        [self.httpServer start:nil];
    }
    [self _unlock];
}
- (void)tryStopLocalService
{
    [self.httpServer stop:YES];
}

#pragma mark -
- (void)_lock
{
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
}

- (void)_unlock
{
    dispatch_semaphore_signal(_lock);
}

@end
