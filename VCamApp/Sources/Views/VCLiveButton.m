#import "VCLiveButton.h"
#import "VCTheme.h"

@implementation VCLiveButton {
    CAGradientLayer *_gradient;
    UIView *_dot;
    UILabel *_title;
    UILabel *_subtitle;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = [VCTheme cornerRadius];
        self.clipsToBounds = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _gradient = [CAGradientLayer layer];
        _gradient.colors = [VCTheme brandGradientColors];
        _gradient.startPoint = CGPointMake(0, 0.5);
        _gradient.endPoint = CGPointMake(1, 0.5);
        [self.layer insertSublayer:_gradient atIndex:0];

        _dot = [[UIView alloc] init];
        _dot.layer.cornerRadius = 6.0;
        _dot.userInteractionEnabled = NO;
        _dot.translatesAutoresizingMaskIntoConstraints = NO;

        _title = [[UILabel alloc] init];
        _title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
        _title.userInteractionEnabled = NO;

        _subtitle = [[UILabel alloc] init];
        _subtitle.font = [VCTheme captionFont];
        _subtitle.userInteractionEnabled = NO;

        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[ _title, _subtitle ]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.alignment = UIStackViewAlignmentCenter;
        texts.spacing = 2;
        texts.userInteractionEnabled = NO;

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ _dot, texts ]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 12;
        row.userInteractionEnabled = NO;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];

        [NSLayoutConstraint activateConstraints:@[
            [_dot.widthAnchor constraintEqualToConstant:12],
            [_dot.heightAnchor constraintEqualToConstant:12],
            [row.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:72],
        ]];

        [self applyState];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gradient.frame = self.bounds;
    [CATransaction commit];
}

- (void)setLive:(BOOL)live { [self setLive:live animated:NO]; }

- (void)setLive:(BOOL)live animated:(BOOL)animated {
    _live = live;
    if (animated) {
        [UIView transitionWithView:self duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ [self applyState]; } completion:nil];
    } else {
        [self applyState];
    }
}

- (void)applyState {
    [_dot.layer removeAnimationForKey:@"pulse"];
    if (_live) {
        _gradient.hidden = YES;
        self.backgroundColor = [VCTheme card];
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = [VCTheme liveGreen].CGColor;
        _dot.backgroundColor = [VCTheme liveGreen];
        _title.text = @"ĐANG LIVE";
        _title.textColor = [VCTheme liveGreen];
        _subtitle.text = @"Chạm để dừng VCam";
        _subtitle.textColor = [VCTheme textSecondary];

        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1.0;
        pulse.toValue = @0.25;
        pulse.duration = 0.8;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [_dot.layer addAnimation:pulse forKey:@"pulse"];
        self.accessibilityLabel = @"Đang live. Chạm để dừng VCam";
    } else {
        _gradient.hidden = NO;
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 0;
        _dot.backgroundColor = [UIColor whiteColor];
        _title.text = @"LIVE";
        _title.textColor = [UIColor whiteColor];
        _subtitle.text = @"Khởi động VCam";
        _subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        self.accessibilityLabel = @"Live. Khởi động VCam";
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.85 : 1.0;
    }];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Animation bị gỡ khi view rời window (đổi tab); gắn lại khi quay về.
    if (self.window) [self applyState];
}

@end
