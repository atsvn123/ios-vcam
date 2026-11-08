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
- (void)setMediaRotation:(int)degrees;
- (void)setMediaMirror:(BOOL)mirror;

// Orientation of the host camera graph for the frame currently being injected.
// The host rotates the sensor-space buffer itself, so the engine has to
// pre-rotate the media content by the opposite angle to end up upright.
// `degrees` is the rotation the host applies: 0, 90, 180 or 270.
- (void)setHostOrientation:(int)degrees mirrored:(BOOL)mirrored;
- (void)setCurrentCameraPosition:(int)position;

// Manual per-camera tuning, applied on top of the automatic compensation.
- (void)setCameraRotationOffset:(int)degrees forPosition:(int)position;
- (void)setCameraMirror:(BOOL)mirror hasOverride:(BOOL)hasOverride forPosition:(int)position;

// Media file transfer. The tweak runs in mediaserverd and cannot read the
// app's sandbox, so the app streams the file bytes over the socket.
- (void)beginMediaFileTransfer:(int)type totalLength:(int)totalLength;
- (void)beginMediaFileTransfer:(int)type totalLength:(int)totalLength
                     fileExtension:(NSString *)fileExtension;
- (void)appendMediaFileData:(const void *)bytes length:(int)length offset:(int)offset;
- (void)finishMediaFileTransfer;

- (void)setYUVSampleBuffer:(CMSampleBufferRef)sbuf;

- (CMSampleBufferRef)modifyImageBuffer:(CMSampleBufferRef)sampleBuffer;
- (CMSampleBufferRef)modifyImageBuffer:(CMSampleBufferRef)sampleBuffer
                     cameraPosition:(int)cameraPosition;
- (BOOL)blackoutImageBuffer:(CMSampleBufferRef)sampleBuffer;
- (BOOL)shouldInjectForCameraPosition:(int)position;

@end
