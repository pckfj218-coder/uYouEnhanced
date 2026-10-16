#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

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

static const void *kYTSIdentity = &kYTSIdentity;
static const void *kYTSLastTime = &kYTSLastTime;
static const void *kYTSDuration = &kYTSDuration;
static const void *kYTSNearEnd = &kYTSNearEnd;
static const void *kYTSTriggered = &kYTSTriggered;

static BOOL YTSIsReelController(id object) {
    if (!object) return NO;
    NSString *name = NSStringFromClass([object class]);
    return [name containsString:@"ReelPlayerViewController"] ||
           [name containsString:@"ShortsPlayerViewController"];
}

static id YTSFindInTree(UIViewController *root, YTPlayerViewController *player) {
    if (!root) return nil;
    if (YTSIsReelController(root)) {
        SEL playerSel = NSSelectorFromString(@"player");
        if (![root respondsToSelector:playerSel] ||
            ((id (*)(id, SEL))objc_msgSend)(root, playerSel) == player) return root;
    }
    for (UIViewController *child in root.childViewControllers) {
        id found = YTSFindInTree(child, player);
        if (found) return found;
    }
    id presented = YTSFindInTree(root.presentedViewController, player);
    return presented;
}

static id YTSFindReel(YTPlayerViewController *player) {
    UIViewController *node = player;
    for (NSInteger i = 0; node && i < 12; i++) {
        if (YTSIsReelController(node)) return node;
        if (node.parentViewController) node = node.parentViewController;
        else if (node.navigationController) node = node.navigationController;
        else break;
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        id found = YTSFindInTree(window.rootViewController, player);
        if (found) return found;
    }
    return nil;
}

static NSString *YTSCurrentIdentity(YTPlayerViewController *player,
                                    YTSingleVideoController *video) {
    return [NSString stringWithFormat:@"%@|%p", player.contentVideoID ?: @"", video];
}

static void YTSAdvance(YTPlayerViewController *player,
                       YTSingleVideoController *video) {
    if ([objc_getAssociatedObject(player, kYTSTriggered) boolValue]) return;
    id reel = YTSFindReel(player);
    SEL selector = NSSelectorFromString(@"reelContentViewRequestsAdvanceToNextVideo:");
    if (!reel || ![reel respondsToSelector:selector]) return;
    objc_setAssociatedObject(player, kYTSTriggered, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, id))objc_msgSend)(reel, selector, video);
    });
}

static void YTSObserve(YTPlayerViewController *player,
                       YTSingleVideoController *video,
                       YTSingleVideoTime *timeObject) {
    if (!player || !video || !timeObject) return;
    if (!YTSFindReel(player)) return;

    CGFloat current = timeObject.time;
    CGFloat duration = video.totalMediaTime;
    if (!isfinite(current) || !isfinite(duration) || duration < 1.0) return;

    NSString *identity = YTSCurrentIdentity(player, video);
    NSString *oldIdentity = objc_getAssociatedObject(player, kYTSIdentity);
    CGFloat last = [objc_getAssociatedObject(player, kYTSLastTime) doubleValue];
    CGFloat oldDuration = [objc_getAssociatedObject(player, kYTSDuration) doubleValue];
    BOOL newItem = ![oldIdentity isEqualToString:identity] ||
                   (oldDuration > 0 && fabs(oldDuration - duration) > 0.75);
    if (newItem) {
        objc_setAssociatedObject(player, kYTSIdentity, identity, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(player, kYTSNearEnd, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(player, kYTSTriggered, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        last = current;
    }

    BOOL nearEnd = current >= MAX(duration - 0.75, duration * 0.985);
    BOOL wrappedAfterEnd = [objc_getAssociatedObject(player, kYTSNearEnd) boolValue] &&
                           last > MAX(duration - 1.5, duration * 0.96) &&
                           current < MIN(1.25, duration * 0.08);
    if (nearEnd) objc_setAssociatedObject(player, kYTSNearEnd, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(player, kYTSLastTime, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(player, kYTSDuration, @(duration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (nearEnd || wrappedAfterEnd) YTSAdvance(player, video);
}

%hook YTPlayerViewController
- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)timeObject {
    %orig;
    YTSObserve(self, video, timeObject);
}
- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)timeObject {
    %orig;
    YTSObserve(self, video, timeObject);
}
%end
