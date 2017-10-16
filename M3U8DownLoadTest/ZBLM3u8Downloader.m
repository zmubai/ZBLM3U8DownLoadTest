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
@property (nonatomic, assign) NSInteger successCount;
@property (nonatomic, assign) NSInteger failCount;
@property (nonatomic, assign, getter = isSuspend) BOOL suspend;
@property (nonatomic, assign, getter = isResumming) BOOL resumming;
@property (nonatomic, copy) ZBLM3u8DownloaderCompletaionHandler completaionHandler;
@end
/*控制下载  控制下载并发  保存下载文件，通知下载完成 暂停任务 重新开启任务*/

NSString * const ZBLM3u8DownloaderErrorDomain = @"error.m3u8.downloader";

@implementation ZBLM3u8Downloader
- (instancetype)initWithfileDownloadInfos:(NSMutableArray <ZBLM3u8FileDownloadInfo*> *) fileDownloadInfos maxConcurrenceDownloadTaskCount:(NSInteger)maxConcurrenceDownloadTaskCount completaionHandler:(ZBLM3u8DownloaderCompletaionHandler) completaionHandler downloadQueue:(dispatch_queue_t) downloadQueue
{
    self = [super init];
    if (self) {
        _successCount = 0;
        _failCount = 0;
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
        
        [_fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            //控制切片并发
            dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
            if ([ZBLM3u8FileManager exitItemWithPath:obj.filePath]) {
                obj.success = YES;
                [self verifyDownloadCountAndCallbackByDownloadSuccess:YES];
            }
            else
            {
                //如果接受到中断信号，中断下载流程释放信号并返回
                if (self.suspend) {
                    obj.beStopCreateTask = YES;
                    dispatch_semaphore_signal(self.tsSemaphore);
                    NSLog(@"suspend and return! don not createDownloadTask!");
                    return ;
                }
                else
                {
                    //真正的创建下载任务
                    [self createDownloadTaskWithIndex:idx];
                }
            }
        }];
    });
}

- (void)createDownloadTaskWithIndex:(NSInteger)index
{
    ZBLM3u8FileDownloadInfo *downloadInfo = _fileDownloadInfos[index];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:downloadInfo.downloadUrl]];
    __block NSData *data = nil;
    downloadInfo.downloadTask = [self.sessionManager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {
        
        NSLog(@"%@:%0.2lf%%\n",@(index), (float)downloadProgress.completedUnitCount / (float)downloadProgress.totalUnitCount * 100);
        
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        
        data = [NSData dataWithContentsOfURL:targetPath];
        
        
        return nil;
        
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        if (!error) {
            [self downloadSuccessTosaveData:data downloadInfo:downloadInfo];
        }
        else
        {
            NSLog(@"\n\nfile download failed:%@ \n\nerror:%@\n\n",downloadInfo.filePath,error);
            [self verifyDownloadCountAndCallbackByDownloadSuccess:NO];
        }
        
    }];
    if (self.suspend) {
        downloadInfo.beStopResumeTask = YES;
        dispatch_semaphore_signal(self.tsSemaphore);
        return;
    }
    else
    {
        NSLog(@"resume task;");
        [downloadInfo.downloadTask resume];
    }
}

- (void)downloadSuccessTosaveData:(NSData *)data downloadInfo:(ZBLM3u8FileDownloadInfo *) downloadInfo
{
    [[ZBLM3u8FileManager shareInstance] saveDate:data ToFile:downloadInfo.filePath completaionHandler:^(NSError *error) {
        if (!error) {
            downloadInfo.success = YES;
            [self verifyDownloadCountAndCallbackByDownloadSuccess:YES];
        }
        else
        {
            NSLog(@"save downloadFail failed:%@ \nerror:%@",downloadInfo.filePath,error);
            [self verifyDownloadCountAndCallbackByDownloadSuccess:NO];
        }
    }];
    
}

//信号量的释放
- (void)verifyDownloadCountAndCallbackByDownloadSuccess:(BOOL) isSuccess
{
    dispatch_semaphore_signal(self.tsSemaphore);
    [self _lock];
    if (isSuccess) {
        _successCount ++;
        if (_downloadProgressHandler) {
            _downloadProgressHandler(_successCount / (float)_fileDownloadInfos.count);
        }
        if (_successCount == _fileDownloadInfos.count) {
            _completaionHandler(nil);
            [self _unlock];
            return;
        }
    }
    else
    {
        _failCount ++;
    }
    
    if (_failCount > 0 &&
        _successCount + _failCount == _fileDownloadInfos.count) {
        NSInteger fc = 0;
        for (ZBLM3u8FileDownloadInfo *di in _fileDownloadInfos) {
            if (di.isSuccess == NO) {
                fc ++;
            }
        }
        NSLog(@"fc : %ld, failC:%ld",(long)fc,(long)_failCount);
        NSError *error = [[NSError alloc]initWithDomain:ZBLM3u8DownloaderErrorDomain code:NSURLErrorUnknown userInfo:nil];
        _completaionHandler(error);
    }
    [self _unlock];
}

- (void)resumeDownload
{
    //恢复挂起的任务、重新创建发起失败的任务、没有创建任务的创建任务、已经创建没有发起的发起任务
    self.suspend = NO;
    [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.downloadTask.state == NSURLSessionTaskStateSuspended && !obj.beStopResumeTask) {
            NSLog(@"resume SuspendedTask");
            if (!self.suspend) {
                [obj.downloadTask resume];
            }
        }
    }];
    dispatch_async(self.downloadQueue, ^{
        if (self.isResumming) {
            return;
        }
        _resumming = YES;
        [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.downloadTask.error && obj.downloadTask.state == NSURLSessionTaskStateCompleted)
            {
                dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
                if (self.suspend) {
                    dispatch_semaphore_signal(self.tsSemaphore);
                    *stop = YES;
                    return ;
                }
                _failCount --;
                NSParameterAssert(_failCount >= 0);
                NSLog(@"reCreate errorTask");
                [self createDownloadTaskWithIndex:idx];
            }
        }];
        
        [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if(obj.isBeStopResumeTask)
            {
                dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
                if (self.suspend) {
                    dispatch_semaphore_signal(self.tsSemaphore);
                    *stop = YES;
                    return ;
                }
                obj.beStopResumeTask = NO;
                NSParameterAssert(obj.downloadTask);
                NSLog(@"self.suspend = %d",self.suspend);
                NSLog(@"resume beStopResumeTask");
                [obj.downloadTask resume];
            }
        }];
        
        [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.isBeStopCreateTask)
            {
                dispatch_semaphore_wait(self.tsSemaphore, DISPATCH_TIME_FOREVER);
                if (self.suspend) {
                    dispatch_semaphore_signal(self.tsSemaphore);
                    *stop = YES;
                    return ;
                }
                obj.beStopCreateTask = NO;
                NSLog(@"self.suspend = %d",self.suspend);
                NSLog(@"reGreate beStopCreateTask");
                [self createDownloadTaskWithIndex:idx];
            }
        }];
        _resumming = NO;
    });
}



- (void)suspendDownload
{
    //设置变量中断流程，没创建的任务停止创建、已经创建的任务停止发起、已经开始的任务挂起、等待中的任务取消
    self.suspend = YES;
    __block NSInteger suspendCount = 0;
    __block NSInteger cancelCount = 0;
    [self.fileDownloadInfos enumerateObjectsUsingBlock:^(ZBLM3u8FileDownloadInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.downloadTask) {
            switch (obj.downloadTask.state) {
                case NSURLSessionTaskStateRunning:
                {
                    
                    if (obj.downloadTask.countOfBytesReceived <= 0) {
                        cancelCount ++;
                        [obj.downloadTask cancel];
                        NSLog(@"running :cannel obj.index = %ld",(long)idx);
                    }
                    else
                    {
                        suspendCount ++;
                        [obj.downloadTask suspend];
                        NSLog(@"running :suspend obj.index = %ld",(long)idx);
                    }
                }
                    break;
                case NSURLSessionTaskStateSuspended:
                    //                    cancelCount ++;
                    //                    [obj.downloadTask cancel];
                    break;
                default:
                    break;
            }
        }
    }];
    NSLog(@"suspendCount:%d,cancelCount:%d,infosCount:%d",suspendCount,cancelCount,_fileDownloadInfos.count);
    NSLog(@"self.suspend = %d",self.suspend);
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

- (void)setSuspend:(BOOL)suspend
{
    _suspend = suspend;
}

@end
