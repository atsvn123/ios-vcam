#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@protocol VCH264DecoderDelegate <NSObject>
- (void)outputFrame:(void *)frameData
  presentationTimeStamp:(int64_t)pts
  presentationDuration:(int64_t)duration;
@end

@interface VCH264Decoder : NSObject

@property (nonatomic, weak) id<VCH264DecoderDelegate> delegate;

- (BOOL)initDecoder:(const uint8_t *)spsData spsSize:(size_t)spsSize
                pps:(const uint8_t *)ppsData ppsSize:(size_t)ppsSize;

- (void)decode:(const uint8_t *)data size:(size_t)size pts:(int32_t)pts;

- (void)endDecode;

- (BOOL)reinitFromSaved;

@end
