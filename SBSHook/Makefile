include theos/makefiles/common.mk

TWEAK_NAME = ApexSBSHook
ApexSBSHook_FILES = SBSHook.m
ApexSBSHook_PRIVATE_FRAMEWORKS = SpringBoardServices
ApexSBSHook_LDFLAGS += -Wl,-segalign,4000

after-install::
	@install.exec "killall -9 searchd"

include $(THEOS_MAKE_PATH)/tweak.mk

