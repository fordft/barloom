#include "BarloomMenuBarNative.h"
#include <ApplicationServices/ApplicationServices.h>

CGImageRef BRLCopyStatusWindowImage(CGWindowID windowID) {
    // ScreenCaptureKit cannot capture these offscreen status windows. Keep the
    // deprecated public Quartz call isolated here until its replacement supports them.
    // The Swift caller checks consent, window layer, and dimensions before calling.
    const void *windowValue = (const void *)(uintptr_t)windowID;
    CFArrayRef windowIDs = CFArrayCreate(kCFAllocatorDefault, &windowValue, 1, NULL);
    if (windowIDs == NULL) return NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef image = CGWindowListCreateImageFromArray(
        CGRectNull,
        windowIDs,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
    );
#pragma clang diagnostic pop
    CFRelease(windowIDs);
    return image;
}

bool BRLRequestAccessibilityTrust(void) {
    const void *keys[] = { kAXTrustedCheckOptionPrompt };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
                                                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    bool trusted = AXIsProcessTrustedWithOptions(options);
    CFRelease(options);
    return trusted;
}
