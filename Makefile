# VCam — Theos root project
# Target : iOS 14.0 – 17.x, rootless (Dopamine) & RootHide (both use /var/jb)
#
# Root project chỉ là aggregate. Hiện có 1 subproject:
#   VCamApp  -> /Applications/VCam.app (UI khung)
# Các tweak dylib (mediaserverd / SpringBoard hooks) sẽ được thêm sau
# dưới dạng SUBPROJECTS riêng khi port chức năng.

export THEOS_PACKAGE_SCHEME = rootless
export TARGET               = iphone:clang:latest:14.0
export ARCHS                = arm64

INSTALL_TARGET_PROCESSES = VCam

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += VCamApp

include $(THEOS_MAKE_PATH)/aggregate.mk
