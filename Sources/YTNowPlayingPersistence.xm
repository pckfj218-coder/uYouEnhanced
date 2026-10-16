#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString *const YTNPDefaultsKey = @"YTNP.LastNowPlayingInfo.v1";
static NSDictionary *YTNPLastInfo = nil;
static BOOL YTNPInternallyRestoring = NO;

static NSDictionary *YTNPSanitizeInfo(NSDictionary *info) {
    if (![info isKindOfClass:[NSDictionary class]] || info.count == 0) return nil;
    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    [info enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        if ([obj isKindOfClass:[NSString class]] ||
            [obj isKindOfClass:[NSNumber class]] ||
            [obj isKindOfClass:[NSDate class]] ||
            [obj isKindOfClass:[NSData class]]) {
            safe[key] = obj;
        } else if ([obj isKindOfClass:[NSURL class]]) {
            safe[key] = [(NSURL *)obj absoluteString];
        }
    }];
    return safe.count ? [safe copy] : nil;
}

static void YTNPSaveInfo(NSDictionary *info) {
    NSDictionary *safe = YTNPSanitizeInfo(info);
    if (!safe) return;
    YTNPLastInfo = safe;
    [[NSUserDefaults standardUserDefaults] setObject:safe forKey:YTNPDefaultsKey];
}

static NSDictionary *YTNPLoadInfo(void) {
    if (YTNPLastInfo.count) return YTNPLastInfo;
    id saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:YTNPDefaultsKey];
    if ([saved isKindOfClass:[NSDictionary class]] && [saved count]) {
        YTNPLastInfo = saved;
    }
    return YTNPLastInfo;
}

static void YTNPRestoreIfNeeded(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
        if (center.nowPlayingInfo.count) {
            YTNPSaveInfo(center.nowPlayingInfo);
            return;
        }
        NSDictionary *saved = YTNPLoadInfo();
        if (!saved.count) return;
        YTNPInternallyRestoring = YES;
        center.nowPlayingInfo = saved;
        center.playbackState = MPNowPlayingPlaybackStatePaused;
        YTNPInternallyRestoring = NO;
    });
}

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (YTNPInternallyRestoring) {
        %orig(info);
        return;
    }
    if (info.count) {
        YTNPSaveInfo(info);
        %orig(info);
        return;
    }
    NSDictionary *saved = YTNPLoadInfo();
    if (saved.count) {
        %orig(saved);
        self.playbackState = MPNowPlayingPlaybackStatePaused;
        return;
    }
    %orig(info);
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)state {
    if (!YTNPInternallyRestoring && state == MPNowPlayingPlaybackStateStopped && [YTNPLoadInfo() count]) {
        %orig(MPNowPlayingPlaybackStatePaused);
        return;
    }
    %orig(state);
}

%end

%ctor {
    @autoreleasepool {
        YTNPLoadInfo();
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            YTNPRestoreIfNeeded();
        }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            YTNPRestoreIfNeeded();
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            YTNPRestoreIfNeeded();
        }];
        YTNPRestoreIfNeeded();
    }
}
