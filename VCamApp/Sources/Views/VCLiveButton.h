#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Nút lớn khởi động / dừng VCam.
/// Tắt: gradient thương hiệu, chữ "LIVE". Bật: viền xanh, chấm nhấp nháy, chữ "ĐANG LIVE".
@interface VCLiveButton : UIControl

@property (nonatomic, getter=isLive) BOOL live;
- (void)setLive:(BOOL)live animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
