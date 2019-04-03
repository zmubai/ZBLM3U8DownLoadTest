//
//  ZBLM3u8Downloader.m
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import "ZBLM3u8Downloader.h"
#import "AFNetworking.h"
#import "ZBLM3u8FileDownloadInfo.h"
#import "ZBLM3u8FileManager.h"

@interface ZBLM3u8Downloader ()
@property (nonatomic, strong) dispatch_semaphore_t tsSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, strong) dispatch_queue_t downloadQueue;
@property (nonatomic, strong) AFURLSessionManager *sessionManager;
@property (nonatomic, strong) NSMutableArray <ZBLM3u8FileDownloadInfo*> *fileDownloadInfos;
@property (nonatomic, assign) BOOL suspend;
@property (nonatomic, assign) BOOL resumming;
@property (nonatomic, copy) ZBLM3u8DownloaderCompletaionHandler completaionHandler;
@end
/*控制下载  控制下载并发  保存下载文件，通知下载完成 暂停任务 重新开启任务*/

NSString * const ZBLM3u8DownloaderErrorDomain = @"error.m3u8.downloader";

@implementation ZBLM3u8Downloader
- (instancetype)initWithfileDownloadInfos:(NSMutableArray <ZBLM3u8FileDownloadInfo*> *) fileDownloadInfos maxConcurrenceDownloadTaskCount:(NSInteger)maxConcurrenceDownloadTaskCount completaionHandler:(ZBLM3u8DownloaderCompletaionHandler) completaionHandler downloadQueue:(dispatch_queue_t) downloadQueue
{
    self = [super init];
    if (self) {
        _fileDownloadInfos = fileDownloadInfos;
        _completaionHandler = completaionHandler ;
        _tsSemaphore = dispatch_semaphore_create(maxConcurrenceDownloadTaskCount);
        _lock = dispatch_semaphore_create(1);
        _suspend = NO;
        _resumming = NO;
        if (downloadQueue) {
            _downloadQueue = downloadQueue;
        }
        else
        {
            _downloadQueue = dispatch_queue_create("m3u8.download.queue", DISPATCH_QUEUE_CONCURRENT);
        }
    }
    return self;
}

- (void)dealloc
{
    
}

- (void)_lock
{
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
}

- (void)_unlock
{
    dispatch_semaphore_signal(_lock);
}

- (void)startDownload
{
    //因为这是外部调用的方法，这里要放到异步线程中避免并发控制中的等待堵塞外部线程
    dispatch_async(self.downloadQueue, ^{
        if (!_fileDownloadInfos.count) {
            _completaionHandler(nil);
            return;
        }
        NSLog(@"downloadInfoCount:%ld",(long)_fileDownloadInfos.count);

        if(self.suspend) return;
        [_fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            //控制切片并发
            if(self.suspend) return;
            dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
            if(self.suspend)
            {
                dispatch_semaphore_signal(self.tsSemaphore);
                return;
            }
            [self _lock];
            if ([ZBLM3u8FileManager exitItemWithPath:obj.filePath]) {
                obj.success = YES;
                [self verifyDownloadCountAndCallbackByDownloadSuccess:YES];
            }
            else
            {
                [self createDownloadTaskWithDownloadInfo:obj];
            }
            [self _unlock];
        }];

    });
}

- (void)createDownloadTaskWithDownloadInfo:(ZBLM3u8FileDownloadInfo*)downloadInfo
{
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:downloadInfo.downloadUrl]];
    __block NSData *data = nil;
    downloadInfo.downloadTask = [self.sessionManager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {


        NSLog(@"%@:%0.2lf%%\n",downloadInfo.downloadUrl, (float)downloadProgress.completedUnitCount / (float)downloadProgress.totalUnitCount * 100);
        
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        
        data = [NSData dataWithContentsOfURL:targetPath];
        
        
        return nil;
        
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        if (!error) {
            ///只以成功的来计算
            [self downloadSuccessTosaveData:data downloadInfo:downloadInfo];
        }
        else
        {
            NSLog(@"\n\nfile download failed:%@ \n\nerror:%@\n\n",downloadInfo.filePath,error);
            [self _lock];
            downloadInfo.failed = YES;
            [self verifyDownloadCountAndCallbackByDownloadSuccess:NO];
            [self _unlock];
        }
        
    }];
    [downloadInfo.downloadTask resume];
}

- (void)downloadSuccessTosaveData:(NSData *)data downloadInfo:(ZBLM3u8FileDownloadInfo *) downloadInfo
{
    [[ZBLM3u8FileManager shareInstance] saveDate:data ToFile:downloadInfo.filePath completaionHandler:^(NSError *error) {
        if (!error) {
            [self _lock];
            downloadInfo.success = YES;
            [self verifyDownloadCountAndCallbackByDownloadSuccess:YES];
            [self _unlock];
        }
        else
        {
            NSLog(@"save downloadFail failed:%@ \nerror:%@",downloadInfo.filePath,error);
            [self _lock];
            downloadInfo.failed = YES;
            [self verifyDownloadCountAndCallbackByDownloadSuccess:NO];
            [self _unlock];
        }
    }];
    
}

//信号量的释放
- (void)verifyDownloadCountAndCallbackByDownloadSuccess:(BOOL) isSuccess
{
    dispatch_semaphore_signal(self.tsSemaphore);
    NSInteger successCount = 0;
    NSInteger failCount = 0;
    for (ZBLM3u8FileDownloadInfo *di in _fileDownloadInfos) {
        if (di.success == YES) {
            successCount ++;
        }
        else if(di.failed == YES)
        {
            failCount ++;
        }
    }
    if (isSuccess) {
        if (_downloadProgressHandler) {
            _downloadProgressHandler(successCount / (float)_fileDownloadInfos.count);
        }
        if (successCount == _fileDownloadInfos.count) {
            ///完成下载
            _completaionHandler(nil);
            ///取消多余的下载
            [_sessionManager invalidateSessionCancelingTasks:YES];
            _sessionManager = nil;
            return;
        }
    }
    if (failCount > 0 &&
        successCount + failCount == _fileDownloadInfos.count) {
        NSError *error = [[NSError alloc]initWithDomain:ZBLM3u8DownloaderErrorDomain code:NSURLErrorUnknown userInfo:nil];
        _completaionHandler(error);
    }
}

- (void)resumeDownload
{
    dispatch_barrier_async(self.downloadQueue, ^{
            //恢复挂起的任务、重新创建发起失败的任务、没有创建任务的创建任务、已经创建没有发起的发起任务
            if (self.resumming) {
                return;
            }
            _resumming = YES;
            _suspend = NO;
            [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (self.suspend) {
                    return;
                }
                if (!obj.success) {
                    if ([ZBLM3u8FileManager exitItemWithPath:obj.filePath]) {
                        [self _lock];
                        obj.success = YES;
                        [self verifyDownloadCountAndCallbackByDownloadSuccess:YES];
                        [self _unlock];
                    }
                    else
                    {
                        dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
                        if (self.suspend) {
                            dispatch_semaphore_signal(self.tsSemaphore);
                            return;
                        }
                        [self _lock];
                        NSLog(@"reCreate task");
                        [self createDownloadTaskWithDownloadInfo:obj];
                        [self _unlock];
                    }
                }
            }];
            _resumming = NO;
    });
}

- (void)suspendDownload
{
    self.suspend = YES;/*必须提供能中断信号量的等待的功能*/
    dispatch_barrier_async(self.downloadQueue, ^{
        //设置变量中断流程，没创建的任务停止创建、已经创建的任务停止发起、已经开始的任务挂起、等待中的任务取消
            [self.sessionManager invalidateSessionCancelingTasks:YES];
            self.sessionManager = nil;
    });
}

#pragma mark -
- (AFURLSessionManager *)sessionManager
{
    if (!_sessionManager) {
        _sessionManager = [[AFURLSessionManager alloc]initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        _sessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    }
    return _sessionManager;
}

@end
