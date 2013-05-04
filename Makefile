TARGET = iphone:clang
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Acervos
Acervos_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm STKPreferences.m Tweak.xm
Acervos_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

before-install::
	$(ECHO_NOTHING)echo `date`$(ECHO_END)
