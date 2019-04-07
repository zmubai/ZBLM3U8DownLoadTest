###  m3u8缓存本地播放
#### 使用方法
```
//下载
  [[ZBLM3u8Manager shareInstance] downloadVideoWithUrlString:url downloadProgressHandler:^(float progress) {
            //更新进度
            dispatch_async(dispatch_get_main_queue(), ^{
                label.text = [NSString stringWithFormat:@"%0.2f%%",progress * 100];
            });
        } downloadSuccessBlock:^(NSString *localPlayUrlString) {
            //开启http服务
            [[ZBLM3u8Manager shareInstance]  tryStartLocalService];
            dispatch_async(dispatch_get_main_queue(), ^{
                //播放
                [self playWithUrlString:localPlayUrlString];
            });
        }];

```

```
//暂停
 [[ZBLM3u8Manager shareInstance] suspendDownload];
//恢复
[[ZBLM3u8Manager shareInstance] resumeDownload];
```

#### 简单demo
此demo实现并不完善，多线程问题可能会存在死锁。为此又弄了个简单的demo，实现主要功能，并减少不必要的多线程使用，减少死锁问题。

地址：[https://github.com/zmubai/m3u8DownloadSimpleDemo](https://github.com/zmubai/m3u8DownloadSimpleDemo)

