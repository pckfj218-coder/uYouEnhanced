#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// YTLite-style Shorts completion handling.
// Observe YouTube's own playback-time callbacks and ask the reel controller
// to advance through its internal method instead of searching collection views.

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";
static NSTimeInterval UYTLastAdvanceUptime = 0.0;
static NSString *UYTLastAdvancedVideoID = nil;

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
    if (!isfinite(duration) || !isfinite(position) || duration <= 0.5) return;

    // YouTube Shorts can loop before a generic AVPlayer end notification is emitted.
    // Trigger while still at the end of YouTube's own playback timeline.
    CGFloat remaining = duration - position;
    CGFloat tolerance = MAX(0.12, MIN(0.35, duration * 0.003));
    if (position < duration * 0.80 || remaining > tolerance) return;

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSString *videoID = nil;
    @try { videoID = player.contentVideoID; } @catch (__unused NSException *e) {}

    // Prevent both YouTube time callbacks from advancing the same Short twice.
    if (now - UYTLastAdvanceUptime < 1.5) return;
    if (videoID.length > 0 && [videoID isEqualToString:UYTLastAdvancedVideoID] &&
        now - UYTLastAdvanceUptime < 5.0) return;

    UYTLastAdvanceUptime = now;
    UYTLastAdvancedVideoID = [videoID copy];

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