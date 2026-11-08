# VCam — Theos root project
# Target : iOS 16.0 – 17.x, rootless (Dopamine) & RootHide (both use /var/jb)
#
# Root project chỉ là aggregate. Subprojects:
#   VCamApp   -> /Applications/VCam.app (UI)
#   VCamTweak -> /Library/MobileSubstrate/DynamicLibraries/vcamera.dylib (camera injection)

export THEOS_PACKAGE_SCHEME = rootless
export TARGET               = iphone:clang:latest:16.0
export ARCHS                = arm64

INSTALL_TARGET_PROCESSES = VCam

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += VCamApp
SUBPROJECTS += VCamTweak

include $(THEOS_MAKE_PATH)/aggregate.mk
