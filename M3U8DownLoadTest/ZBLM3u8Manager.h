//
//  ZBLM3u8Manager.h
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef void (^ZBLM3u8ManagerDownloadSuccessBlock)(NSString *localPlayUrlString);
typedef void (^ZBLM3u8ManagerDownloadProgressHandler)(float progress);
@interface ZBLM3u8Manager : NSObject
+ (instancetype)shareInstance;

- (BOOL)exitLocalVideoWithUrlString:(NSString*) urlStr;

- (NSString *)localPlayUrlWithOriUrlString:(NSString *)urlString;

- (void)downloadVideoWithUrlString:(NSString *)urlStr downloadProgressHandler:(ZBLM3u8ManagerDownloadProgressHandler)downloadProgressHandler downloadSuccessBlock:(ZBLM3u8ManagerDownloadSuccessBlock) downloadSuccessBlock;

- (void)tryStartLocalService;

- (void)tryStopLocalService;

- (void)resumeDownload;
- (void)suspendDownload;
@end
