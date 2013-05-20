TARGET = iphone:clang
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Acervos
Acervos_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm STKRecognizerDelegate.m STKPreferences.m Tweak.xm
Acervos_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore
Acervos_CFLAGS = -Wall -Werror -DkPackageVersion=\"$(THEOS_PACKAGE_VERSION)\"

include $(THEOS_MAKE_PATH)/tweak.mk

before-install::
	$(ECHO_NOTHING)echo `date`$(ECHO_END)
