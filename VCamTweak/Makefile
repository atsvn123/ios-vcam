include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vcamera

vcamera_FILES = \
	Sources/Tweak.x \
	Sources/VCBridge.m \
	Sources/VCH264Decoder.m \
	Sources/VCLiveEngine.m \
	Sources/VCMediaServerHooks.m \
	Sources/VCServerSocket.m

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

vcamera_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
