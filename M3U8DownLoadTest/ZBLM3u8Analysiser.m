//
//  ZBLM3u8Analysiser.m
//  M3U8DownLoadTest
//
//  Created by zengbailiang on 10/4/17.
//  Copyright © 2017 controling. All rights reserved.
//

#import "ZBLM3u8Analysiser.h"
#import "ZBLM3u8Info.h"
#import "NSString+m3u8.h"
#import "ZBLM3U8Setting.h"
#import "ZBLM3u8FileManager.h"

/*解析m3u8 和组装m3u8*/

NSString * const ZBLM3u8AnalysiserResponeErrorDomain = @"error.m3u8.analysiser.respone";
NSString * const ZBLM3u8AnalysiserAnalysisErrorDomain = @"error.m3u8.analysiser.analysis";

@implementation ZBLM3u8Analysiser

+ (void)analysisWithUrlString:(NSString*)urlStr completaionHandler:(ZBLM3u8AnalysiseCompletaionHandler)completaionHandler
{
    NSLog(@"analysis start");
    NSString *oriM3u8String = [NSString stringWithContentsOfFile:[[ZBLM3u8Setting fullCommonDirPrefixWithUrl:urlStr] stringByAppendingPathComponent:[ZBLM3u8Setting oriM3u8InfoFileName]] encoding:0 error:nil];
    
    __block BOOL happenException = NO;
    if (oriM3u8String.length) {
        NSLog(@"use local oriM3u8Info");
        @try {
            [self analysisWithM3u8String:oriM3u8String completaionHandler:completaionHandler];
        } @catch (NSException *exception) {
            happenException = YES;
            [[ZBLM3u8FileManager shareInstance]removeFileWithPath:[[ZBLM3u8Setting fullCommonDirPrefixWithUrl:urlStr] stringByAppendingPathComponent:[ZBLM3u8Setting oriM3u8InfoFileName]]];
            completaionHandler(nil,[[NSError alloc]initWithDomain:ZBLM3u8AnalysiserAnalysisErrorDomain code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}]);
        } @finally {
            
        }
        if (!happenException) {
            return;
        }
    }
    
    happenException = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *m3u8Str = nil;
        @try {
            NSError *error = nil;
            m3u8Str = [[NSString alloc] initWithContentsOfURL:[NSURL URLWithString:urlStr] usedEncoding:0 error:&error];
            
            if (error)
            {
                completaionHandler(nil,error);
                return ;
            }
            
            
            if (m3u8Str.length == 0)
            {
                completaionHandler(nil,[[NSError alloc]initWithDomain:ZBLM3u8AnalysiserResponeErrorDomain code:NSURLErrorBadServerResponse userInfo:nil]);
                return;
            }
            
            [self analysisWithM3u8String:m3u8Str completaionHandler:completaionHandler];
            
        } @catch (NSException *exception) {
            happenException = YES;
            completaionHandler(nil,[[NSError alloc]initWithDomain:ZBLM3u8AnalysiserAnalysisErrorDomain code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}]);
        } @finally {
            
        }
        
        if (!happenException) {
            [[ZBLM3u8FileManager shareInstance]saveDate:[m3u8Str dataUsingEncoding:NSUTF8StringEncoding] ToFile:[[ZBLM3u8Setting fullCommonDirPrefixWithUrl:urlStr] stringByAppendingPathComponent:[ZBLM3u8Setting oriM3u8InfoFileName]] completaionHandler:nil];
        }
    });
}

+ (void)analysisWithM3u8String:(NSString*)m3u8String completaionHandler:(ZBLM3u8AnalysiseCompletaionHandler)completaionHandler
{
    
    ZBLM3u8Info *info = [ZBLM3u8Info new];
    info.version = [[m3u8String subStringFrom:@"#EXT-X-VERSION:" to:@"#"] removeSpaceAndNewline];
    info.targetduration = [[m3u8String subStringFrom:@"#EXT-X-TARGETDURATION:" to:@"#"] removeSpaceAndNewline];
    info.mediaSequence = [[m3u8String subStringFrom:@"#EXT-X-MEDIA-SEQUENCE:" to:@"#"] removeSpaceAndNewline];
    
    info.keyMethod = [m3u8String subStringFrom:@"#EXT-X-KEY:METHOD=" to:@","];
    info.keyUri = [m3u8String subStringFrom:@"URI=\"" to:@"\""];
    info.keyIv = [[m3u8String subStringFrom:@"IV=" to:@"#"] removeSpaceAndNewline];
    
    NSRange tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
    if (tsRange.location == NSNotFound) {
        completaionHandler(nil,[[NSError alloc]initWithDomain:ZBLM3u8AnalysiserAnalysisErrorDomain code:NSURLErrorUnknown userInfo:@{@"info":@"none downloadUrl for .ts file"}]);
        return;
    }
    NSInteger index = 0;
    NSMutableArray *tsInfos = @[].mutableCopy;
    m3u8String = [m3u8String substringFromIndex:tsRange.location];
    while (tsRange.location != NSNotFound) {
        ZBLM3u8TsInfo *tsInfo = [ZBLM3u8TsInfo new];
        tsInfo.duration = [m3u8String subStringFrom:@"#EXTINF:" to:@","];
        m3u8String = [m3u8String subStringForm:@"," offset:1];
        tsInfo.oriUrlString = [[m3u8String subStringTo:@"#"] removeSpaceAndNewline];
        
        NSRange exRange = [m3u8String rangeOfString:@"#EX"];
        NSRange discontinuityRange = [m3u8String rangeOfString:@"#EXT-X-DISCONTINUITY"];
        if (exRange.location == discontinuityRange.location) {
            tsInfo.hasDiscontiunity = YES;
        }
        tsInfo.index = index ++;
        [tsInfos addObject:tsInfo];
        tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
        if (tsRange.location != NSNotFound) {
            m3u8String = [m3u8String subStringForm:@"#EXTINF:" offset:0];
        }
    }
    NSLog(@"analysis compelte");
    info.tsInfos = tsInfos;
    NSParameterAssert(completaionHandler);
    completaionHandler(info,nil);
}

+ (NSString*)synthesisLocalM3u8Withm3u8Info:(ZBLM3u8Info *)m3u8Info
{
    NSString *newM3u8String = @"";
    
    NSString *header = @"#EXTM3U\n";
    if (m3u8Info.version.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-VERSION:%ld\n",(long)m3u8Info.version.integerValue]];
    }
    if (m3u8Info.targetduration.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%ld\n",(long)m3u8Info.targetduration.integerValue]];
    }
    if (m3u8Info.mediaSequence.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-MEDIA-SEQUENCE:%ld\n",(long)m3u8Info.mediaSequence.integerValue]];
    }
    
    NSString *keyStr = @"";
    if(m3u8Info.keyUri.length)
    {
        keyStr = [NSString stringWithFormat:@"#EXT-X-KEY:METHOD=%@,URI=\"%@\",IV=%@\n",m3u8Info.keyMethod,m3u8Info.keyLocalUri,m3u8Info.keyIv];
    }
    
    __block NSString *body = @"";
    [m3u8Info.tsInfos enumerateObjectsUsingBlock:^(ZBLM3u8TsInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *tsInfo = [NSString stringWithFormat:@"#EXTINF:%.6lf,\n%@\n",obj.duration.floatValue,obj.localUrlString];
        body =  [body stringByAppendingString:tsInfo];
        if (obj.isHasDiscontiunity) body = [body stringByAppendingString:@"#EXT-X-DISCONTINUITY\n"];
    }];
    
    newM3u8String = [[[[newM3u8String stringByAppendingString:header] stringByAppendingString:keyStr] stringByAppendingString:body] stringByAppendingString:@"#EXT-X-ENDLIST"];
    
    return newM3u8String;
}

@end
