#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Card bo góc có tiêu đề (chấm màu + chữ in hoa) và một stack nội dung dọc.
/// Thêm control con bằng -addArrangedSubview:.
@interface VCCardView : UIView

- (instancetype)initWithTitle:(NSString *)title dotColor:(UIColor *)dotColor;

@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *detailLabel;   // chữ phụ bên phải tiêu đề
@property (nonatomic, strong, readonly) UIStackView *contentStack;

- (void)addArrangedSubview:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
