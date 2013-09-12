DEBUG = 1
TARGET = iphone:clang:6.1:3.0

include theos/makefiles/common.mk

TWEAK_NAME = Apex
Apex_FILES =  Tweak.xm STKConstants.m STKIconLayout.m STKIconLayoutHandler.m STKStackManager.mm NSOperationQueue+STKMainQueueDispatch.m STKPlaceHolderIcon.xm STKSelectionView.m STKSelectionViewCell.m STKRecognizerDelegate.m STKPreferences.m
Apex_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore
Apex_CFLAGS = -Wall -Werror -O3

include $(THEOS_MAKE_PATH)/tweak.mk


before-all::
	$(ECHO_NOTHING)python ./VersionUpdate.py $(THEOS_PACKAGE_VERSION)$(ECHO_END)
	$(ECHO_NOTHING)touch -t 2012310000 Tweak.xm$(ECHO_END)
	$(ECHO_NOTHING)touch -t 2012310000 PrefBundle/STKPrefsController.m$(ECHO_END)	

SUBPROJECTS += SpotlightHelper
SUBPROJECTS += PrefBundle

include $(THEOS_MAKE_PATH)/aggregate.mk
