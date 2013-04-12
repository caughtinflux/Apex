TARGET = iphone:clang:latest:6.0
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Stacks
Stacks_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk
