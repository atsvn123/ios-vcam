// Tweak.x — MobileSubstrate entry point for vcamera.dylib
// Injects into mediaserverd (iOS 14-16) and lskdd (iOS 17+)

#import <Foundation/Foundation.h>
#import <substrate.h>
#import <pthread.h>
#import "VCBridge.h"
#import "VCLiveEngine.h"
#import "VCMediaServerHooks.h"

static pthread_t g_listenThread;

static void *listenThreadEntry(void *arg) {
    @autoreleasepool {
        VCBridge *bridge = [VCBridge sharedInstance];
        [bridge listen];
    }
    return NULL;
}

static void vcamCleanup(void) {
    g_done = 1;
    if (g_listenThread) {
        pthread_cancel(g_listenThread);
        g_listenThread = 0;
    }
}

__attribute__((constructor))
static void vcamEntry(void) {
    @autoreleasepool {
        NSString *pn = [[[NSProcessInfo processInfo] processName] lowercaseString];
        BOOL isMediaHost = ([pn rangeOfString:@"mediaserverd"].location != NSNotFound) ||
                           ([pn rangeOfString:@"lskdd"].location != NSNotFound);
        if (!isMediaHost) return;

        atexit(vcamCleanup);
        [VCLiveEngine sharedInstance];
        installMediaServerHooks();
        pthread_create(&g_listenThread, NULL, listenThreadEntry, NULL);
    }
}
