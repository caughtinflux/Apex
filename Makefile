TARGET = iphone:clang:latest:6.0
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Stacks
Stacks_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.m Tweak.xm
Stacks_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

before-install::
	$(ECHO_NOTHING)echo `date`$(ECHO_END)
