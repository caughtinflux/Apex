export SDKVERSION = 10.1
export SYSROOT = $(THEOS)/sdks/iPhoneOS10.1.sdk
export TARGET = iphone:clang:10.1:7.0

include theos/makefiles/common.mk

TWEAK_NAME = ApexSBSHook
ApexSBSHook_FILES = SBSHook.m
ApexSBSHook_PRIVATE_FRAMEWORKS = SpringBoardServices

after-install::
	@install.exec "killall -9 searchd"

include $(THEOS_MAKE_PATH)/tweak.mk

