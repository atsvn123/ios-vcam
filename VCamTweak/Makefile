TWEAK_NAME = vcamera

vcamera_FILES = $(wildcard Sources/*.m Sources/*.mm Sources/*.x)
vcamera_CFLAGS = -fobjc-arc -Iinclude -DVCAM_DIAGNOSTICS_ENABLED=0
vcamera_FRAMEWORKS = Foundation CoreMedia CoreVideo VideoToolbox AVFoundation CoreImage ImageIO QuartzCore IOSurface CoreGraphics
vcamera_PRIVATE_FRAMEWORKS =
vcamera_LDFLAGS = -lsubstrate
vcamera_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
