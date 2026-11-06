// Tweak.x — MobileSubstrate entry point for vcamera.dylib
// Injects into mediaserverd (iOS 14-16) and lskdd (iOS 17+)

#import <Foundation/Foundation.h>
#import <substrate.h>
#import <pthread.h>
#import <unistd.h>
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

static void *hookRetryThreadEntry(void *arg) {
    @autoreleasepool {
        // mediaserverd can load BW classes after tweak constructors run. Retry
        // until both hooks install; one-second idle checks have negligible cost.
        while (VCamIsEnabled() && !mediaServerHooksInstalled()) {
            installMediaServerHooks();
            usleep(1000000);
        }
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
        // Construct engine before any camera frame can reach the hook. The
        // hook uses existingInstance to avoid allocation on the media thread.
        [VCLiveEngine sharedInstance];
        installMediaServerHooks();
        pthread_t hookRetryThread;
        pthread_create(&hookRetryThread, NULL, hookRetryThreadEntry, NULL);
        pthread_detach(hookRetryThread);
        pthread_create(&g_listenThread, NULL, listenThreadEntry, NULL);
    }
}
