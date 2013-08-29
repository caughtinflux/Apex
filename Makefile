DEBUG = 1
TARGET = iphone:clang:latest:3.0

include theos/makefiles/common.mk

TWEAK_NAME = Acervos
Acervos_FILES = STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm STKIdentifiedOperation.m STKPlaceHolderIcon.xm STKSelectionView.m STKSelectionViewCell.m STKRecognizerDelegate.m STKPreferences.m Tweak.xm
Acervos_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore
Acervos_CFLAGS = -Wall -Werror

include $(THEOS_MAKE_PATH)/tweak.mk


before-all::
	$(ECHO_NOTHING)python ./VersionUpdate.py $(THEOS_PACKAGE_VERSION)$(ECHO_END)
	$(ECHO_NOTHING)touch -t 2012310000 Tweak.xm$(ECHO_END)

before-install::
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo "Version: `cat STKVersion.h`"$(ECHO_END)
	$(ECHO_NOTHING)echo Install time: `date`$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
	$(ECHO_NOTHING)echo$(ECHO_END)
