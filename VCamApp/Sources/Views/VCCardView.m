#import "VCCardView.h"
#import "VCTheme.h"

@implementation VCCardView

- (instancetype)initWithTitle:(NSString *)title dotColor:(UIColor *)dotColor {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [VCTheme card];
        self.layer.cornerRadius = [VCTheme cornerRadius];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [VCTheme cardBorder].CGColor;

        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = dotColor;
        dot.layer.cornerRadius = 4.0;
        dot.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title.uppercaseString;
        _titleLabel.font = [VCTheme sectionTitleFont];
        _titleLabel.textColor = [VCTheme textSecondary];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [VCTheme captionFont];
        _detailLabel.textColor = [VCTheme textSecondary];
        _detailLabel.textAlignment = NSTextAlignmentRight;
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _contentStack = [[UIStackView alloc] init];
        _contentStack.axis = UILayoutConstraintAxisVertical;
        _contentStack.spacing = 12.0;
        _contentStack.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:dot];
        [self addSubview:_titleLabel];
        [self addSubview:_detailLabel];
        [self addSubview:_contentStack];

        CGFloat p = 14.0;
        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:p],
            [dot.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],

            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:p],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],

            [_detailLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-p],

            [_contentStack.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:12],
            [_contentStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:p],
            [_contentStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-p],
            [_contentStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-p],
        ]];
    }
    return self;
}

- (void)addArrangedSubview:(UIView *)view {
    [_contentStack addArrangedSubview:view];
}

@end
