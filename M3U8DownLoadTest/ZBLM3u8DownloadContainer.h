//
//  ZBLM3u8DownloadContainer.h
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef void (^ZBLM3u8DownloadCompletaionHandler)(NSString *locaLUrl,NSError *error);
typedef void (^ZBLM3u8DownloadProgressHandler)(float progress);
typedef NSInteger (^ZBLM3u8AnalysisM3u8InfoSuccessBlock)();
@interface ZBLM3u8DownloadContainer : NSObject

@property (nonatomic, strong) ZBLM3u8AnalysisM3u8InfoSuccessBlock analysisM3u8InfoSuccessBlock;

- (void)startDownloadWithUrlString:(NSString *)urlStr  downloadProgressHandler:(ZBLM3u8DownloadProgressHandler)downloadProgressHandler completaionHandler:(ZBLM3u8DownloadCompletaionHandler)completaionHandler;

- (void)resumeDownload;

- (void)suspendDownload;

FOUNDATION_EXPORT NSString * const ZBLM3u8DownloadContainerGreateRootDirErrorDomain;

@end
