typedef NS_ENUM(NSUInteger, STKLayoutPosition) {
    STKPositionUnknown = 0,
    STKPositionTop     = 1,
    STKPositionBottom  = 2,
    STKPositionLeft    = 3,
    STKPositionRight   = 4
};

typedef struct STKGroupSlot {
    STKLayoutPosition position;
    NSUInteger index;
} STKGroupSlot;

typedef NS_OPTIONS(NSUInteger, STKLocation) {
    STKLocationRegular        = 0,
    STKLocationTouchingTop    = 1 << 0,
    STKLocationTouchingBottom = 1 << 1,
    STKLocationTouchingLeft   = 1 << 2,
    STKLocationTouchingRight  = 1 << 3,
    STKLocationDock           = 1 << 4
};
