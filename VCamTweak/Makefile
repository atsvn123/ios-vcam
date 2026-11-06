include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vcamera

vcamera_FILES = $(wildcard Sources/*.m Sources/*.mm Sources/*.x)

vcamera_CFLAGS = \
	-fobjc-arc \
	-Iinclude \
	-DVCAM_DIAGNOSTICS_ENABLED=0 \
	-Wno-error \
	-Wno-unused-variable \
	-Wno-unused-function

vcamera_FRAMEWORKS = \
	Foundation CoreMedia CoreVideo VideoToolbox AVFoundation \
	CoreImage ImageIO QuartzCore IOSurface CoreGraphics

vcamera_LDFLAGS = \
	-framework CydiaSubstrate \
	-Wl,-x

vcamera_INSTALL_PATH = /var/jb/Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
