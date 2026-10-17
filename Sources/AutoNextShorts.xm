#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <math.h>

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";
static NSTimeInterval UYTLastAdvanceUptime = 0.0;
static __weak id UYTObservedVideoObject = nil;
static CGFloat UYTLastPosition = -1.0;
static CGFloat UYTLastDuration = -1.0;

@interface YTSingleVideoTime : NSObject
@property(nonatomic, assign, readonly) CGFloat time;
@end

@interface YTSingleVideoController : NSObject
@property(nonatomic, assign, readonly) CGFloat totalMediaTime;
@end

@interface YTPlayerViewController : UIViewController
@end

@interface YTReelPlayerViewController : UIViewController
- (void)reelContentViewRequestsAdvanceToNextVideo:(id)video;
@end

static BOOL UYTAutoNextEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:UYTAutoNextShortsKey];
}

static BOOL UYTIsReelController(UIViewController *controller) {
    if (!controller) return NO;
    return [controller isKindOfClass:NSClassFromString(@"YTReelPlayerViewController")] ||
           [controller isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")] ||
           [controller isKindOfClass:NSClassFromString(@"YTReelPlayerViewControllerSub")];
}

static YTReelPlayerViewController *UYTFindReelInTree(UIViewController *controller, NSInteger depth) {
    if (!controller || depth > 20) return nil;
    if (UYTIsReelController(controller)) return (YTReelPlayerViewController *)controller;

    UIViewController *presented = controller.presentedViewController;
    YTReelPlayerViewController *found = UYTFindReelInTree(presented, depth + 1);
    if (found) return found;

    for (UIViewController *child in controller.childViewControllers) {
        found = UYTFindReelInTree(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

static YTReelPlayerViewController *UYTFindReelController(UIViewController *controller) {
    UIViewController *cursor = controller;
    for (NSInteger i = 0; cursor && i < 20; i++) {
        if (UYTIsReelController(cursor)) return (YTReelPlayerViewController *)cursor;
        cursor = cursor.parentViewController;
    }

    UIResponder *responder = controller;
    for (NSInteger i = 0; responder && i < 30; i++) {
        if ([responder isKindOfClass:UIViewController.class] &&
            UYTIsReelController((UIViewController *)responder)) {
            return (YTReelPlayerViewController *)responder;
        }
        responder = responder.nextResponder;
    }

    UIWindow *window = controller.viewIfLoaded.window;
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    return UYTFindReelInTree(window.rootViewController, 0);
}

static void UYTResetObservation(id video, CGFloat duration, CGFloat position) {
    UYTObservedVideoObject = video;
    UYTLastDuration = duration;
    UYTLastPosition = position;
}

static void UYTHandleShortTime(YTPlayerViewController *player,
                               YTSingleVideoController *video,
                               YTSingleVideoTime *time) {
    if (!UYTAutoNextEnabled() || !player || !video || !time) return;

    YTReelPlayerViewController *reel = UYTFindReelController(player);
    if (!reel || ![reel respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)]) return;

    CGFloat duration = video.totalMediaTime;
    CGFloat position = time.time;
    if (!isfinite(duration) || !isfinite(position) || duration <= 0.5 || position < 0.0) return;

    BOOL firstSample = UYTLastDuration <= 0.0 || UYTLastPosition < 0.0;
    BOOL durationChanged = UYTLastDuration > 0.0 && fabs(UYTLastDuration - duration) > 0.25;
    BOOL ordinaryBackwardJump = UYTLastPosition >= 0.0 &&
                                position + 1.0 < UYTLastPosition &&
                                !(UYTLastPosition >= duration * 0.75 && position <= MIN(1.0, duration * 0.20));

    if (firstSample || durationChanged || ordinaryBackwardJump) {
        UYTResetObservation(video, duration, position);
        return;
    }

    CGFloat previous = UYTLastPosition;
    CGFloat remaining = duration - position;
    CGFloat naturalTolerance = MAX(0.20, MIN(0.75, duration * 0.008));
    BOOL naturalEnd = position >= duration * 0.70 && remaining <= naturalTolerance;
    BOOL seekToEnd = previous >= 0.0 && position - previous >= 0.8 &&
                     position >= duration * 0.70 && remaining <= 2.0;
    BOOL loopWrapped = previous >= duration * 0.70 && duration - previous <= 2.0 &&
                       position <= MIN(1.0, duration * 0.20);

    UYTObservedVideoObject = video;
    UYTLastPosition = position;
    UYTLastDuration = duration;

    if (!naturalEnd && !seekToEnd && !loopWrapped) return;

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - UYTLastAdvanceUptime < 0.8) return;
    UYTLastAdvanceUptime = now;
    UYTLastPosition = -1.0;

    __weak YTReelPlayerViewController *weakReel = reel;
    dispatch_async(dispatch_get_main_queue(), ^{
        YTReelPlayerViewController *strongReel = weakReel;
        if (strongReel && [strongReel respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)]) {
            [strongReel reelContentViewRequestsAdvanceToNextVideo:nil];
        }
    });
}

%hook YTPlayerViewController

- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    UYTHandleShortTime(self, video, time);
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    UYTHandleShortTime(self, video, time);
}

%end