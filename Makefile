TARGET = iphone:clang
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Stacks
Stacks_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm Tweak.xm
Stacks_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

before-install::
	$(ECHO_NOTHING)echo `date`$(ECHO_END)
