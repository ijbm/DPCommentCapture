TARGET := iphone:clang:latest:14.5
INSTALL_TARGET_PROCESSES = DPScope

ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DPCommentCapture

DPCommentCapture_FILES = Tweak.x
DPCommentCapture_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DPCommentCapture_FRAMEWORKS = UIKit Foundation
DPCommentCapture_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk
