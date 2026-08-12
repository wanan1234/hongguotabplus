ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HongGuoFullScreen
HongGuoFullScreen_FILES = Tweak.xm
HongGuoFullScreen_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
