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

static YTReelPlayerViewController *UYTFindReelController(UIViewController *controller) {
    UIViewController *cursor = controller;
    for (NSInteger i = 0; cursor && i < 10; i++) {
        if ([cursor isKindOfClass:NSClassFromString(@"YTReelPlayerViewController")] ||
            [cursor isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")] ||
            [cursor isKindOfClass:NSClassFromString(@"YTReelPlayerViewControllerSub")]) {
            return (YTReelPlayerViewController *)cursor;
        }
        cursor = cursor.parentViewController;
    }
    return nil;
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

    BOOL newVideoObject = UYTObservedVideoObject != video;
    BOOL durationChanged = UYTLastDuration > 0.0 && fabs(UYTLastDuration - duration) > 0.25;
    if (newVideoObject || durationChanged) {
        UYTResetObservation(video, duration, position);
        return;
    }

    CGFloat previous = UYTLastPosition;
    CGFloat remaining = duration - position;
    CGFloat naturalTolerance = MAX(0.15, MIN(0.45, duration * 0.004));

    BOOL naturalEnd = position >= duration * 0.75 && remaining <= naturalTolerance;
    BOOL seekToEnd = previous >= 0.0 && position - previous >= 0.8 &&
                     position >= duration * 0.75 && remaining <= 2.0;
    BOOL loopWrapped = previous >= duration * 0.75 && duration - previous <= 2.0 &&
                       position <= MIN(1.0, duration * 0.20);

    UYTLastPosition = position;
    UYTLastDuration = duration;
    if (!naturalEnd && !seekToEnd && !loopWrapped) return;

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - UYTLastAdvanceUptime < 0.8) return;
    UYTLastAdvanceUptime = now;
    UYTLastPosition = -1.0;

    dispatch_async(dispatch_get_main_queue(), ^{
        [reel reelContentViewRequestsAdvanceToNextVideo:nil];
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
