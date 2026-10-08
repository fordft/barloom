#ifndef BARLOOM_MENU_BAR_NATIVE_H
#define BARLOOM_MENU_BAR_NATIVE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

/// Returns only the requested status window's pixels, including when it is offscreen.
CGImageRef _Nullable BRLCopyStatusWindowImage(CGWindowID windowID) CF_RETURNS_RETAINED;
bool BRLRequestAccessibilityTrust(void);

#endif
