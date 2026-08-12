export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HongGuoFullScreen

HongGuoFullScreen_FILES = Tweak.xm
HongGuoFullScreen_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
