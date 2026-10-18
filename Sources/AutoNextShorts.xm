#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";

__attribute__((constructor)) static void UYTRegisterAutoNextShortsDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"autoNextShorts_enabled": @YES
    }];
}
static const void *kUYTIdentity = &kUYTIdentity;
static const void *kUYTLastTime = &kUYTLastTime;
static const void *kUYTDuration = &kUYTDuration;
static const void *kUYTNearEnd = &kUYTNearEnd;
static const void *kUYTTriggered = &kUYTTriggered;
static const void *kUYTLastAdvance = &kUYTLastAdvance;

@interface YTSingleVideoTime : NSObject
@property(nonatomic, readonly) CGFloat time;
@end

@interface YTSingleVideoController : NSObject
@property(nonatomic, readonly) CGFloat totalMediaTime;
@end

@interface YTPlayerViewController : UIViewController
@property(nonatomic, readonly, copy) NSString *contentVideoID;
@property(nonatomic, readonly) YTSingleVideoController *activeVideo;
@end

static BOOL UYTAutoNextEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:UYTAutoNextShortsKey];
}

static BOOL UYTIsReelController(id object) {
    if (!object) return NO;
    NSString *name = NSStringFromClass([object class]);
    return [name containsString:@"ReelPlayerViewController"] ||
           [name containsString:@"ShortsPlayerViewController"];
}

static id UYTFindReelInTree(UIViewController *root, YTPlayerViewController *player, NSInteger depth) {
    if (!root || depth > 24) return nil;
    if (UYTIsReelController(root)) {
        SEL playerSelector = NSSelectorFromString(@"player");
        if (![root respondsToSelector:playerSelector] ||
            ((id (*)(id, SEL))objc_msgSend)(root, playerSelector) == player) {
            return root;
        }
    }
    id presented = UYTFindReelInTree(root.presentedViewController, player, depth + 1);
    if (presented) return presented;
    for (UIViewController *child in root.childViewControllers) {
        id found = UYTFindReelInTree(child, player, depth + 1);
        if (found) return found;
    }
    return nil;
}

static id UYTFindReel(YTPlayerViewController *player) {
    UIViewController *node = player;
    for (NSInteger i = 0; node && i < 24; i++) {
        if (UYTIsReelController(node)) return node;
        node = node.parentViewController ?: node.navigationController;
    }

    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    for (UIWindow *window in windows.reverseObjectEnumerator) {
        id found = UYTFindReelInTree(window.rootViewController, player, 0);
        if (found) return found;
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        id found = UYTFindReelInTree(window.rootViewController, player, 0);
        if (found) return found;
    }
    return nil;
}

static NSString *UYTCurrentIdentity(YTPlayerViewController *player,
                                    YTSingleVideoController *video,
                                    CGFloat duration) {
    NSString *videoID = player.contentVideoID ?: @"";
    if (videoID.length > 0) return videoID;
    return [NSString stringWithFormat:@"%p|%.3f", video, duration];
}

static void UYTResetPlayerState(YTPlayerViewController *player,
                                NSString *identity,
                                CGFloat current,
                                CGFloat duration) {
    objc_setAssociatedObject(player, kUYTIdentity, identity, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(player, kUYTLastTime, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kUYTDuration, @(duration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kUYTNearEnd, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kUYTTriggered, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void UYTAdvance(YTPlayerViewController *player,
                       YTSingleVideoController *video) {
    if ([objc_getAssociatedObject(player, kUYTTriggered) boolValue]) return;
    id reel = UYTFindReel(player);
    SEL selector = NSSelectorFromString(@"reelContentViewRequestsAdvanceToNextVideo:");
    if (!reel || ![reel respondsToSelector:selector]) return;

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval lastAdvance = [objc_getAssociatedObject(player, kUYTLastAdvance) doubleValue];
    if (now - lastAdvance < 0.8) return;

    objc_setAssociatedObject(player, kUYTLastAdvance, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kUYTTriggered, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakReel = reel;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongReel = weakReel;
        if (strongReel && [strongReel respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(strongReel, selector, video);
        }
    });
}

static void UYTObserve(YTPlayerViewController *player,
                       YTSingleVideoController *video,
                       YTSingleVideoTime *timeObject) {
    if (!UYTAutoNextEnabled() || !player || !video || !timeObject) return;
    if (!UYTFindReel(player)) return;

    CGFloat current = timeObject.time;
    CGFloat duration = video.totalMediaTime;
    if (!isfinite(current) || !isfinite(duration) || duration < 1.0 || current < 0.0) return;

    NSString *identity = UYTCurrentIdentity(player, video, duration);
    NSString *oldIdentity = objc_getAssociatedObject(player, kUYTIdentity);
    CGFloat last = [objc_getAssociatedObject(player, kUYTLastTime) doubleValue];
    CGFloat oldDuration = [objc_getAssociatedObject(player, kUYTDuration) doubleValue];
    BOOL triggered = [objc_getAssociatedObject(player, kUYTTriggered) boolValue];     BOOL restartedAfterTriggered = triggered &&                                    last > MAX(duration - 1.75, duration * 0.955) &&                                    current < MIN(1.35, duration * 0.10);     BOOL resumedFromStaleTriggeredState = triggered &&                                           last >= 0.0 &&                                           current > last + 0.35 &&                                           current < duration * 0.90;     BOOL newItem = ![oldIdentity isEqualToString:identity] ||                    (oldDuration > 0.0 && fabs(oldDuration - duration) > 0.75) ||                    restartedAfterTriggered ||                    resumedFromStaleTriggeredState;     if (newItem) {         UYTResetPlayerState(player, identity, current, duration);         return;     } BOOL nearEnd = current >= MAX(duration - 0.85, duration * 0.982);
    BOOL wrappedAfterEnd = [objc_getAssociatedObject(player, kUYTNearEnd) boolValue] &&
                           last > MAX(duration - 1.75, duration * 0.955) &&
                           current < MIN(1.35, duration * 0.10);
    BOOL seekToEnd = last >= 0.0 && current - last >= 0.8 &&
                     current >= duration * 0.75 && duration - current <= 2.0;

    if (nearEnd) {
        objc_setAssociatedObject(player, kUYTNearEnd, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(player, kUYTLastTime, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kUYTDuration, @(duration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (nearEnd || wrappedAfterEnd || seekToEnd) {
        UYTAdvance(player, video);
    }
}

%hook YTPlayerViewController

- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)timeObject {
    %orig;
    UYTObserve(self, video, timeObject);
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)timeObject {
    %orig;
    UYTObserve(self, video, timeObject);
}

%end