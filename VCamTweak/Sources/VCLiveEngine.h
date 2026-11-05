#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "../include/VideoToolboxPrivate.h"

@interface VCLiveEngine : NSObject

@property (nonatomic, assign) BOOL bLive;
@property (nonatomic, assign) int cameraTarget;

+ (instancetype)sharedInstance;
+ (instancetype)existingInstance;

- (BOOL)getLive;
- (void)setLive:(BOOL)live;
- (void)setLiveUserIntent:(BOOL)intent;

- (void)setMediaType:(int)type;
- (void)setMediaPath:(NSString *)path;
- (void)setMediaFitMode:(int)mode;
- (void)setPerformanceFPS:(int)fps;

- (void)setYUVSampleBuffer:(CMSampleBufferRef)sbuf;

- (CMSampleBufferRef)modifyImageBuffer:(CMSampleBufferRef)sampleBuffer;
- (BOOL)blackoutImageBuffer:(CMSampleBufferRef)sampleBuffer;
- (BOOL)shouldInjectForCameraPosition:(int)position;

@end
