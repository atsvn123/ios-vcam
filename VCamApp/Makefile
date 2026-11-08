# VCam.app — UIKit app khung (Objective-C, ARC)
# Cài vào /var/jb/Applications/VCam.app (rootless)

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VCam

TARGET = 16.0

VCam_FILES = \
	$(wildcard Sources/*.m) \
	$(wildcard Sources/Core/*.m) \
	$(wildcard Sources/Views/*.m) \
	$(wildcard Sources/Controllers/*.m)

VCam_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore Photos PhotosUI

VCam_CFLAGS = \
	-fobjc-arc \
	-I$(CURDIR)/Sources \
	-I$(CURDIR)/Sources/Core \
	-I$(CURDIR)/Sources/Views \
	-I$(CURDIR)/Sources/Controllers

include $(THEOS_MAKE_PATH)/application.mk
