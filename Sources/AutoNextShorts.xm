#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";
static BOOL UYTAutoNextBusy = NO;
static NSTimeInterval UYTLastAdvance = 0;
static double UYTLastPosition = -1.0;
static NSString *UYTLastItemToken = nil;

static UIWindow *UYTKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *UYTTopViewController(void) {
    UIViewController *vc = UYTKeyWindow().rootViewController;
    while (vc) {
        if (vc.presentedViewController) { vc = vc.presentedViewController; continue; }
        if ([vc isKindOfClass:UINavigationController.class]) {
            vc = ((UINavigationController *)vc).visibleViewController; continue;
        }
        if ([vc isKindOfClass:UITabBarController.class]) {
            vc = ((UITabBarController *)vc).selectedViewController; continue;
        }
        break;
    }
    return vc;
}

static BOOL UYTControllerTreeIsShorts(UIViewController *vc) {
    if (!vc) return NO;
    NSString *name = NSStringFromClass(vc.class).lowercaseString;
    if ([name containsString:@"shorts"] || [name containsString:@"reel"]) return YES;
    for (UIViewController *child in vc.childViewControllers) {
        if (UYTControllerTreeIsShorts(child)) return YES;
    }
    return NO;
}

static AVPlayer *UYTFindPlayerInLayer(CALayer *layer) {
    if ([layer isKindOfClass:AVPlayerLayer.class]) {
        AVPlayer *player = ((AVPlayerLayer *)layer).player;
        if (player.currentItem) return player;
    }
    for (CALayer *child in layer.sublayers) {
        AVPlayer *player = UYTFindPlayerInLayer(child);
        if (player) return player;
    }
    return nil;
}

static UICollectionView *UYTBestVerticalCollection(UIView *view, UICollectionView *best) {
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *candidate = (UICollectionView *)view;
        UICollectionViewLayout *layout = candidate.collectionViewLayout;
        BOOL vertical = YES;
        if ([layout isKindOfClass:UICollectionViewFlowLayout.class]) {
            vertical = ((UICollectionViewFlowLayout *)layout).scrollDirection == UICollectionViewScrollDirectionVertical;
        }
        if (vertical && candidate.window && !candidate.hidden && candidate.bounds.size.height > 300.0) {
            if (!best || candidate.bounds.size.height * candidate.bounds.size.width > best.bounds.size.height * best.bounds.size.width) {
                best = candidate;
            }
        }
    }
    for (UIView *child in view.subviews) best = UYTBestVerticalCollection(child, best);
    return best;
}

static void UYTAdvanceShort(void) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (UYTAutoNextBusy || now - UYTLastAdvance < 1.5) return;

    UIViewController *top = UYTTopViewController();
    if (!UYTControllerTreeIsShorts(top)) return;
    UICollectionView *cv = UYTBestVerticalCollection(top.view, nil);
    if (!cv) return;

    NSArray<NSIndexPath *> *visible = [cv.indexPathsForVisibleItems sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
        UICollectionViewLayoutAttributes *aa = [cv layoutAttributesForItemAtIndexPath:a];
        UICollectionViewLayoutAttributes *bb = [cv layoutAttributesForItemAtIndexPath:b];
        CGFloat da = fabs(CGRectGetMidY(aa.frame) - CGRectGetMidY(cv.bounds) - cv.contentOffset.y);
        CGFloat db = fabs(CGRectGetMidY(bb.frame) - CGRectGetMidY(cv.bounds) - cv.contentOffset.y);
        return da < db ? NSOrderedAscending : (da > db ? NSOrderedDescending : NSOrderedSame);
    }];
    NSIndexPath *current = visible.firstObject;
    if (!current) return;

    NSInteger section = current.section;
    NSInteger item = current.item + 1;
    while (section < [cv numberOfSections] && item >= [cv numberOfItemsInSection:section]) {
        section += 1;
        item = 0;
    }
    if (section >= [cv numberOfSections]) return;

    NSIndexPath *next = [NSIndexPath indexPathForItem:item inSection:section];
    UYTAutoNextBusy = YES;
    UYTLastAdvance = now;
    [cv scrollToItemAtIndexPath:next atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UYTAutoNextBusy = NO;
        UYTLastPosition = -1.0;
        UYTLastItemToken = nil;
    });
}

static void UYTPollShortsPlayback(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:UYTAutoNextShortsKey]) {
        UYTLastPosition = -1.0;
        UYTLastItemToken = nil;
        return;
    }
    UIViewController *top = UYTTopViewController();
    if (!UYTControllerTreeIsShorts(top)) return;

    AVPlayer *player = UYTFindPlayerInLayer(UYTKeyWindow().layer);
    AVPlayerItem *item = player.currentItem;
    if (!item) return;

    double duration = CMTimeGetSeconds(item.duration);
    double position = CMTimeGetSeconds(player.currentTime);
    if (!isfinite(duration) || !isfinite(position) || duration < 1.0) return;

    NSString *token = [NSString stringWithFormat:@"%p", item];
    if (![token isEqualToString:UYTLastItemToken]) {
        UYTLastItemToken = token;
        UYTLastPosition = position;
        return;
    }

    BOOL nearEnd = duration - position <= 0.22 && position > duration * 0.80;
    BOOL looped = UYTLastPosition > duration * 0.80 && position < duration * 0.20;
    UYTLastPosition = position;
    if (nearEnd || looped) UYTAdvanceShort();
}

__attribute__((constructor)) static void UYTAutoNextShortsInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.20 repeats:YES block:^(__unused NSTimer *timer) {
            UYTPollShortsPlayback();
        }];
    });
}