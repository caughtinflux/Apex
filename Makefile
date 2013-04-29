TARGET = iphone:clang
#DEBUG = 1

include theos/makefiles/common.mk

TWEAK_NAME = Acervo
Acervo_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm Tweak.xm
Acervo_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

before-install::
	$(ECHO_NOTHING)echo `date`$(ECHO_END)
