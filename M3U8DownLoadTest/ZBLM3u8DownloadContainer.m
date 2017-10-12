//
//  ZBLM3u8DownloadContainer.m
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import "ZBLM3u8DownloadContainer.h"
#import "ZBLM3u8Analysiser.h"
#import "ZBLM3u8Downloader.h"
#import "ZBLM3u8Info.h"
#import "ZBLM3u8FileDownloadInfo.h"
#import "ZBLM3u8FileManager.h"
#import "ZBLM3u8Setting.h"


NSString * const ZBLM3u8DownloadContainerGreateRootDirErrorDomain = @"error.m3u8.container.createRootDir";

/*发起解析，发起下载，中断恢复控制...*/
@interface ZBLM3u8DownloadContainer()
@property (nonatomic, strong) ZBLM3u8Info *m3u8Info;
@property (nonatomic, strong) ZBLM3u8Downloader *downloader;
@property (nonatomic, copy) NSString *m3u8OriUrl;
@property (nonatomic, assign) NSInteger maxConcurrenceDownloadTaskCount;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, copy) ZBLM3u8DownloadCompletaionHandler completaionHandler;
@property (nonatomic, assign,getter=isSuspend) BOOL suspend;
@property (nonatomic, assign) BOOL isExitRootDir;
@property (nonatomic, strong) ZBLM3u8DownloadProgressHandler downloadProgressHandler;
@end

@implementation ZBLM3u8DownloadContainer
- (instancetype)init
{
    self = [super init];
    if (self) {
        _lock = dispatch_semaphore_create(1);
        _suspend = NO;
        _maxConcurrenceDownloadTaskCount = 1;
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

- (void)startDownloadWithUrlString:(NSString *)urlStr  downloadProgressHandler:(ZBLM3u8DownloadProgressHandler)downloadProgressHandler completaionHandler:(ZBLM3u8DownloadCompletaionHandler)completaionHandler
{
    [self _lock];
    if (!_m3u8OriUrl) {
        _m3u8OriUrl = urlStr;
    }
    if (!_completaionHandler) {
        _completaionHandler = completaionHandler;
    }
    if (!_downloadProgressHandler) {
        _downloadProgressHandler = downloadProgressHandler;
    }
    if(![self tryCreateRootDir])
    {
        _completaionHandler(nil,[[NSError alloc]initWithDomain:ZBLM3u8DownloadContainerGreateRootDirErrorDomain code:NSURLErrorCannotCreateFile userInfo:nil]);
        [self _unlock];
        return;
    }
    if (_suspend) {
        [self _unlock];
        return;
    }
    
    [ZBLM3u8Analysiser analysisWithUrlString:urlStr completaionHandler:^(ZBLM3u8Info *m3u8Info, NSError *error) {
        if (!error) {
            self.m3u8Info = m3u8Info;
            [self _unlock];
            
            if (self.analysisM3u8InfoSuccessBlock) {
               self.maxConcurrenceDownloadTaskCount = self.analysisM3u8InfoSuccessBlock();
            }
            if (_suspend) {
                return;
            }
            [self downloadAction];
        }
        else
        {
            [self _unlock];
            _completaionHandler(nil,error);
            NSLog(@"error:%@",error.description);
        }
    }];
}

- (BOOL)tryCreateRootDir
{
    return  [ZBLM3u8FileManager tryGreateDir:[[ZBLM3u8Setting commonDirPrefix]  stringByAppendingPathComponent:[ZBLM3u8Setting uuidWithUrl:_m3u8OriUrl]]];
}

- (void)downloadAction
{
    if (!_downloader) {
        [self _lock];
        if (_downloader) {
            [self _unlock];
            return;
        }
        __weak __typeof(self) weakself = self;
        _downloader = [[ZBLM3u8Downloader alloc]initWithfileDownloadInfos:[self fileDownloadInfos] maxConcurrenceDownloadTaskCount:_maxConcurrenceDownloadTaskCount completaionHandler:^(NSError *error) {
            if (!error) {
                [weakself saveM3u8File];
            }
            else
            {
                weakself.completaionHandler(nil,error);
            }
        } downloadQueue:nil];
        if (_downloadProgressHandler) {
            [_downloader setDownloadProgressHandler:^(float progress){
                weakself.downloadProgressHandler(progress);
            }];
        }
        [self _unlock];
        
        [_downloader startDownload];
    }
}

- (NSMutableArray <ZBLM3u8FileDownloadInfo*> *)fileDownloadInfos
{
    NSMutableArray <ZBLM3u8FileDownloadInfo*> *fileDownloadInfos = @[].mutableCopy;
    if (_m3u8Info.keyUri.length > 0) {
        _m3u8Info.keyLocalUri = [NSString stringWithFormat:@"%@/%@/%@",
                                 [ZBLM3u8Setting localHost],
                                 [ZBLM3u8Setting uuidWithUrl:_m3u8OriUrl],
                                 [ZBLM3u8Setting keyFileName]];
        
        ZBLM3u8FileDownloadInfo *downloadKeyInfo = [ZBLM3u8FileDownloadInfo new];
        downloadKeyInfo.downloadUrl = _m3u8Info.keyUri;
        downloadKeyInfo.filePath = [[ZBLM3u8Setting fullCommonDirPrefixWithUrl:_m3u8OriUrl]stringByAppendingPathComponent:[ZBLM3u8Setting keyFileName]];
        [fileDownloadInfos addObject:downloadKeyInfo];
    }
    
    for (ZBLM3u8TsInfo *tsInfo in _m3u8Info.tsInfos) {
        tsInfo.localUrlString = [NSString stringWithFormat:@"%@/%@/%@",
                                 [ZBLM3u8Setting localHost],
                                 [ZBLM3u8Setting uuidWithUrl:_m3u8OriUrl],
                                 [ZBLM3u8Setting tsFileWithIdentify:@(tsInfo.index).stringValue]];
        
        ZBLM3u8FileDownloadInfo *downloadInfo = [ZBLM3u8FileDownloadInfo new];
        downloadInfo.downloadUrl = tsInfo.oriUrlString;
        downloadInfo.filePath = [[ZBLM3u8Setting fullCommonDirPrefixWithUrl:_m3u8OriUrl]stringByAppendingPathComponent:[ZBLM3u8Setting tsFileWithIdentify:@(tsInfo.index).stringValue]];
        [fileDownloadInfos addObject:downloadInfo];
    }
    
    return fileDownloadInfos;
}

- (void)saveM3u8File
{
    __weak __typeof(self) weakself = self;
    NSString *m3u8info = [ZBLM3u8Analysiser synthesisLocalM3u8Withm3u8Info:self.m3u8Info];
    [[ZBLM3u8FileManager shareInstance] saveDate:[m3u8info dataUsingEncoding:NSUTF8StringEncoding] ToFile:[[ZBLM3u8Setting fullCommonDirPrefixWithUrl:_m3u8OriUrl] stringByAppendingPathComponent:[ZBLM3u8Setting m3u8InfoFileName]] completaionHandler:^(NSError *error) {
        if (!error) {
            weakself.completaionHandler([NSString stringWithFormat:@"%@/%@/%@",[ZBLM3u8Setting localHost],[ZBLM3u8Setting uuidWithUrl:_m3u8OriUrl],[ZBLM3u8Setting m3u8InfoFileName]],nil);
        }
        else
        {
            weakself.completaionHandler(nil,error);
        }
        
    }];
}

//通过suspend变量 控制执行的步骤
- (void)resumeDownload
{
    _suspend = NO;
    
    //任何步骤都没有开启，等待上层发起
    if (!_m3u8OriUrl) {
        return;
    }
    
    //解析失败，重新开始
    [self _lock];
    if (_m3u8OriUrl && !_m3u8Info) {
        [self _unlock];
        [self startDownloadWithUrlString:_m3u8OriUrl downloadProgressHandler:_downloadProgressHandler completaionHandler:_completaionHandler];
        return;
    }
    [self _unlock];
    
    //解析成功但下载被中断了， 发起下载
    if (!_downloader) {
        [self downloadAction];
    }
    else
    {
        //否则告诉下载器恢复下载
       [_downloader resumeDownload];
    }
}

- (void)suspendDownload
{
    //设置变量，中断流程
    _suspend = YES;
    
    //告诉下层中断下载
    [_downloader suspendDownload];
}

@end
