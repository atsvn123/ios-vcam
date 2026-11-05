#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@class VCLiveEngine;

@interface VCBridge : NSObject

@property (nonatomic, assign) unsigned int cameraWidth;
@property (nonatomic, assign) unsigned int cameraHeight;

+ (instancetype)sharedInstance;

- (void)listen;
- (void)setResolution:(unsigned int)width height:(unsigned int)height;

@end

extern volatile uint8_t g_done;
extern double g_lastResolutionUpdate;
extern BOOL VCamIsEnabled(void);
