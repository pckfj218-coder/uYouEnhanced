#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <math.h>

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";
static NSTimeInterval UYTLastAdvanceUptime = 0.0;
static NSString *UYTLastAdvancedVideoID = nil;
static NSString *UYTObservedVideoID = nil;
static CGFloat UYTLastObservedPosition = -1.0;

@interface YTSingleVideoTime : NSObject
@property(nonatomic, assign, readonly) CGFloat time;
@end

@interface YTSingleVideoController : NSObject
@property(nonatomic, assign, readonly) CGFloat totalMediaTime;
@end

@interface YTPlayerViewController : UIViewController
@property(nonatomic, readonly) NSString *contentVideoID;
@end

@interface YTReelPlayerViewController : UIViewController
- (void)reelContentViewRequestsAdvanceToNextVideo:(id)video;
@end

static BOOL UYTAutoNextEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:UYTAutoNextShortsKey];
}

static YTReelPlayerViewController *UYTFindReelController(UIViewController *controller) {
    UIViewController *cursor = controller;
    for (NSInteger i = 0; cursor && i < 8; i++) {
        if ([cursor isKindOfClass:NSClassFromString(@"YTReelPlayerViewController")] ||
            [cursor isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")] ||
            [cursor isKindOfClass:NSClassFromString(@"YTReelPlayerViewControllerSub")]) {
            return (YTReelPlayerViewController *)cursor;
        }
        cursor = cursor.parentViewController;
    }
    return nil;
}

static void UYTAdvanceToNextShort(YTPlayerViewController *player,
                                  YTSingleVideoController *video,
                                  YTSingleVideoTime *time) {
    if (!UYTAutoNextEnabled() || !player || !video || !time) return;

    YTReelPlayerViewController *reel = UYTFindReelController(player.parentViewController);
    if (!reel || ![reel respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)]) return;

    CGFloat duration = video.totalMediaTime;
    CGFloat position = time.time;
    if (!isfinite(duration) || !isfinite(position) || duration <= 0.5 || position < 0.0) return;

    NSString *videoID = nil;
    @try { videoID = player.contentVideoID; } @catch (__unused NSException *e) {}

    if ((videoID.length > 0 && ![videoID isEqualToString:UYTObservedVideoID]) ||
        (videoID.length == 0 && position < 0.5 && UYTLastObservedPosition > 1.0)) {
        UYTObservedVideoID = [videoID copy];
        UYTLastObservedPosition = -1.0;
    }

    CGFloat previous = UYTLastObservedPosition;
    CGFloat remaining = duration - position;
    CGFloat naturalTolerance = MAX(0.12, MIN(0.35, duration * 0.003));

    // Normal completion: preserve the original narrow end window.
    BOOL naturalEnd = position >= duration * 0.80 && remaining <= naturalTolerance;

    // Manual seek: if playback jumps forward into the last two seconds, advance immediately.
    BOOL forwardSeekToEnd = previous >= 0.0 &&
                            position - previous >= 1.0 &&
                            position >= duration * 0.80 &&
                            remaining <= 2.0;

    // Loop fallback: YouTube may reset to zero before an end-window callback is delivered.
    BOOL loopWrapped = previous >= duration * 0.80 &&
                       duration - previous <= 2.0 &&
                       position <= MIN(1.0, duration * 0.20);

    UYTLastObservedPosition = position;
    if (!naturalEnd && !forwardSeekToEnd && !loopWrapped) return;

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - UYTLastAdvanceUptime < 1.5) return;
    if (videoID.length > 0 && [videoID isEqualToString:UYTLastAdvancedVideoID] &&
        now - UYTLastAdvanceUptime < 5.0) return;

    UYTLastAdvanceUptime = now;
    UYTLastAdvancedVideoID = [videoID copy];
    UYTLastObservedPosition = -1.0;

    dispatch_async(dispatch_get_main_queue(), ^{
        [reel reelContentViewRequestsAdvanceToNextVideo:nil];
    });
}

%hook YTPlayerViewController

- (void)singleVideo:(YTSingleVideoController *)video
currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    UYTAdvanceToNextShort(self, video, time);
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video
            currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    UYTAdvanceToNextShort(self, video, time);
}

%end
