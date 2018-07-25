//
//  ViewController.m
//  MultipeerConnectivity
//
//  Created by 张晓民 on 2018/7/25.
//  Copyright © 2018年 张晓民. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>
@interface ViewController ()<MCSessionDelegate,MCBrowserViewControllerDelegate,MCNearbyServiceBrowserDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>
{
    // 会话
    MCSession *_mcSession;
    
    //  表示为一个用户，亦可认为是当前设备
    MCPeerID *_mcPeerID;
    
    // 可以接收，并处理用户请求连接的响应。没有回调，会弹出默认的提示框，并处理连接。
    MCAdvertiserAssistant *_advertiser;
    
    // 用于搜索附近的用户，并可以对搜索到的用户发出邀请加入某个会话中
    MCNearbyServiceBrowser *_brower;
    
    // 附近用户列表
    MCBrowserViewController *_browerViewController;
    
    // 储存连接
    NSMutableArray *_sessionArray;
    
    // 连接会话
    AVCaptureSession *_avCaptureSession;
    // 摄像头设备
    AVCaptureDevice *_videoDevice;
    
    // 肤质检测仪画面
    UIImageView *_detectorCameraView;
    
    // 开启摄像头按钮
    UIButton *_startCamera;
    
    
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self createMC];
    
    _detectorCameraView = [[UIImageView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self.view addSubview:_detectorCameraView];
    
    _startCamera=[UIButton buttonWithType:UIButtonTypeSystem];
    [_startCamera setTitle:@"开启摄像头" forState:UIControlStateNormal];
    _startCamera.frame=CGRectMake([UIScreen mainScreen].bounds.size.width/2-50, [UIScreen mainScreen].bounds.size.height/2-50, 100, 100);
    [_startCamera addTarget:self action:@selector(btnStartCamera) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_startCamera];
}


- (void)viewDidAppear:(BOOL)animated
{
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) btnStartCamera
{
    _startCamera.hidden=YES;
    [self startSkinDetectorCamera];
}

-(void)createMC
{
    // 获取当前设备的名称
    NSString *name = [UIDevice currentDevice].name;
    
    // 用户
    _mcPeerID=[[MCPeerID alloc] initWithDisplayName:name];
    
    // 创建连接
    _mcSession = [[MCSession alloc] initWithPeer:_mcPeerID];
    
    // 设置代理
    _mcSession.delegate=self;
    
    // 设置广播服务
    _advertiser=[[MCAdvertiserAssistant alloc] initWithServiceType:@"panxsoft" discoveryInfo:nil session:_mcSession];
    
    // 开始广播
    [_advertiser start];
    
    // 设置发现服务（接收方）
    _brower=[[MCNearbyServiceBrowser alloc] initWithPeer:_mcPeerID serviceType:@"panxsoft"];
    
    // 设置代理
    _brower.delegate=self;
    [_brower startBrowsingForPeers];
}

/** 配置肤质检测仪
 *
 */
-(void)setupSkinDetectorCamera
{
    // 如果连接会话已经建立则直接返回
    if (_avCaptureSession)
    {
        return;
    }
    
    // 确保摄像头已经得到App的授权
    BOOL cameraAccessAuthorized=[self queryCameraAuthorizationStatusAndNotifyUserIfNotGranted];
    
    //如果摄像头没有得到授权
    if (!cameraAccessAuthorized)
    {
        //TODO:对摄像头进行授权
        return;
    }
    
    // 创建会话
    _avCaptureSession = [[AVCaptureSession alloc] init];
    [_avCaptureSession beginConfiguration];
    
    // 设置预设值,并以VGA获取摄像头的数据
    [_avCaptureSession setSessionPreset:AVCaptureSessionPreset352x288];
    
    // 创建一个摄像头设备
    _videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSLog(@"%@",[_videoDevice localizedName]);
    // 对摄像头设备进行判断
    assert(_videoDevice !=nil);
    
    NSError *error=nil;
    
    // 使用自动曝光、自动白平衡、并设置自动对焦
    if ([_videoDevice lockForConfiguration:&error])
    {
        // 设置曝光
        if ([_videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
        {
            [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        
        // 设置白平衡
        if ([_videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
        {
            [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        }
        
        // 设置自动对焦
        if ([_videoDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
        {
            [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        
        [_videoDevice unlockForConfiguration];
    }
    
    // 创建一个会话输入设备
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    
    if (error)
    {
        NSLog(@"不能初始化AVCaptureDeviceInput");
        assert(0);
    }
    
    // 将输入设备添加到会话中
    [_avCaptureSession addInput:input];
    
    // 创建视频流的输出
    AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    [dataOutput setVideoSettings:[NSDictionary dictionaryWithObject:value forKey:key]];
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_avCaptureSession addOutput:dataOutput];
    
    // 强制使用30FPS的捕获帧率
    if ([_videoDevice lockForConfiguration:&error])
    {
        [_videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice unlockForConfiguration];
    }
    
    [_avCaptureSession commitConfiguration];
}


/** 开启肤质检测仪
 *
 */
- (void)startSkinDetectorCamera
{
    // 检查会话是否开启
    if (_avCaptureSession && [_avCaptureSession isRunning])
    {
        return;
    }
    
    // 检查会话是否为空
    if (_avCaptureSession == nil)
    {
        [self setupSkinDetectorCamera];
    }
    
    // 开始会话
    [_avCaptureSession startRunning];
}

/** 关闭肤质检测
 *
 */
- (void)stopSkinDetectorCamera
{
    if ([_avCaptureSession isRunning])
    {
        //停止会话
        [_avCaptureSession stopRunning];
    }
    
    _avCaptureSession = nil;
    _videoDevice = nil;
}


#pragma mark - AVFoundation
-(BOOL)queryCameraAuthorizationStatusAndNotifyUserIfNotGranted
{
    const NSUInteger numCameras = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
    if(0==numCameras)
    {
        NSLog(@"没有可以使用的摄像头");
        return NO;
    }
    else
    {
        NSLog(@"有%lu个可以使用的摄像头",numCameras);
    }
    AVAuthorizationStatus authStatus=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus != AVAuthorizationStatusAuthorized)
    {
        NSLog(@"没有授权使用摄像头");
        
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted)
            {
                NSLog(@"开启摄像头!");
            }
            else
            {
                NSLog(@"授权失败!");
            }
        }];
    }
    else
    {
        NSLog(@"App已经授权使用摄像头!");
    }
    
    
    return YES;
}


- (void)session:(nonnull MCSession *)session didFinishReceivingResourceWithName:(nonnull NSString *)resourceName fromPeer:(nonnull MCPeerID *)peerID atURL:(nullable NSURL *)localURL withError:(nullable NSError *)error {
    
}

- (void)session:(nonnull MCSession *)session didReceiveData:(nonnull NSData *)data fromPeer:(nonnull MCPeerID *)peerID {
    
//    NSLog(@"收到消息消息了:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        self->_startCamera.hidden=YES;
        self->_detectorCameraView.image=[UIImage imageWithData:data];
    });

    
}

- (void)session:(nonnull MCSession *)session didReceiveStream:(nonnull NSInputStream *)stream withName:(nonnull NSString *)streamName fromPeer:(nonnull MCPeerID *)peerID {
    
}

- (void)session:(nonnull MCSession *)session didStartReceivingResourceWithName:(nonnull NSString *)resourceName fromPeer:(nonnull MCPeerID *)peerID withProgress:(nonnull NSProgress *)progress {
    
}

/**
 * 当检测到连接状态发生改变后进行存储
 * @param session MC流
 * @param peerID 用户
 * @param state 连接状态
 */

- (void)session:(nonnull MCSession *)session peer:(nonnull MCPeerID *)peerID didChangeState:(MCSessionState)state {
    // 判断是否连接
    if (state==MCSessionStateConnected)
    {
        // 保存这个连接
        if (![_sessionArray containsObject:session])
        {
            //如果不存在，则保存
            [_sessionArray addObject:session];
        }
    }
}

/**
 * 选取相应用户
 * @param browserViewController 用户列表
 */
- (void)browserViewControllerDidFinish:(nonnull MCBrowserViewController *)browserViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
    _browerViewController = nil;
    //关闭广播服务，停止其他人发现
    [_advertiser stop];
}

/**
 * 用户列表关闭
 * @param browserViewController 用户列表
 *
 */
- (void)browserViewControllerWasCancelled:(nonnull MCBrowserViewController *)browserViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
    _browerViewController = nil;
    //关闭广播服务，停止其他人发现
    [_advertiser stop];
}

/**
 * 发现附近用户
 * @param browser 搜索附近用户
 * @param peerID 附件用户
 * @param info 详情
 */
- (void)browser:(nonnull MCNearbyServiceBrowser *)browser foundPeer:(nonnull MCPeerID *)peerID withDiscoveryInfo:(nullable NSDictionary<NSString *,NSString *> *)info {
    
    NSLog(@"发现附近用户%@",peerID.displayName);
    if (_browerViewController == nil)
    {
        _browerViewController=[[MCBrowserViewController alloc] initWithServiceType:@"panxsoft" session:_mcSession];
        _browerViewController.delegate=self;
        
        //跳转到发现页面
        [self presentViewController:_browerViewController animated:YES completion:nil];
    }
    
}

/**
 * 附近某个用户消失
 * @param browser 搜索附近用户
 * @param peerID 用户
 */
- (void)browser:(nonnull MCNearbyServiceBrowser *)browser lostPeer:(nonnull MCPeerID *)peerID {
    NSLog(@"附近用户%@离开",peerID.displayName);
}

- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
    
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    
}

- (void)preferredContentSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    
}

//- (CGSize)sizeForChildContentContainer:(nonnull id<UIContentContainer>)container withParentContainerSize:(CGSize)parentSize {
//
//}

- (void)systemLayoutFittingSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    
}

- (void)willTransitionToTraitCollection:(nonnull UITraitCollection *)newCollection withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    
}

- (void)didUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context withAnimationCoordinator:(nonnull UIFocusAnimationCoordinator *)coordinator {
    
}

- (void)setNeedsFocusUpdate {
    
}

//- (BOOL)shouldUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context {
//
//}

- (void)updateFocusIfNeeded {
    
}


- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"%ld",[_mcSession.connectedPeers count]);
    
    UIImage *image=[self imageFromSampleBuffer:sampleBuffer];
    _detectorCameraView.image=image;
    
//    NSString* deviceName=[UIDevice currentDevice].name;
//    [_mcSession sendData:[deviceName dataUsingEncoding:NSUTF8StringEncoding] toPeers:_mcSession.connectedPeers withMode:MCSessionSendDataReliable error:nil];
    
    [_mcSession sendData:UIImageJPEGRepresentation(image, 0.8) toPeers:_mcSession.connectedPeers withMode:MCSessionSendDataReliable error:nil];
    
    
}

#pragma mark - imageFromSampleBuffer
-(UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVImageBufferRef imageBuffer=CMSampleBufferGetImageBuffer(sampleBuffer);
    
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);// 锁定缓存地址
    void *baseAddress=CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow=CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width=CVPixelBufferGetWidth(imageBuffer);
    size_t height=CVPixelBufferGetHeight(imageBuffer);
    
    if (width ==0 || height ==0)
    {
        return nil;
    }
    
    CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context=CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    UIImage *image=[UIImage imageWithCGImage:quartzImage];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(quartzImage);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);// 解锁缓存地址
    
    return image;
    
}


@end
