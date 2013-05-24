TARGET = iphone:clang
DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Acervos
Acervos_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm STKRecognizerDelegate.m STKPreferences.m Tweak.xm
Acervos_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore
Acervos_CFLAGS = -Wall -Werror

include $(THEOS_MAKE_PATH)/tweak.mk


before-all::
	$(ECHO_NOTHING)python ./VersionUpdate.py $(THEOS_PACKAGE_VERSION)$(ECHO_END)
	touch -t 2012310000 STKConstants.h

before-install::
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo Install time: `date`$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
