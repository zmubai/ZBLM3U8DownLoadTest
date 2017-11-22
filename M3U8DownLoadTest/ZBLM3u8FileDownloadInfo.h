//
//  ZBLM3u8FileDownloadInfo.h
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/5/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZBLM3u8FileDownloadInfo : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *downloadUrl;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) BOOL fail;
@property (nonatomic, assign) BOOL needBeResume;
@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;
@property (nonatomic, assign, getter=isBeStopCreateTask) BOOL beStopCreateTask;
@property (nonatomic, assign, getter=isBeStopResumeTask) BOOL beStopResumeTask;
@end
