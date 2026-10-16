#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const UYTAutoNextShortsKey = @"autoNextShorts_enabled";
static BOOL UYTAutoNextBusy = NO;

static UIViewController *UYTTopViewController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    UIViewController *vc = window.rootViewController;
    while (YES) {
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

static BOOL UYTContainsShortsController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *name = NSStringFromClass(vc.class).lowercaseString;
    if ([name containsString:@"shorts"] || [name containsString:@"reel"]) return YES;
    for (UIViewController *child in vc.childViewControllers) {
        if (UYTContainsShortsController(child)) return YES;
    }
    return NO;
}

static UICollectionView *UYTFindPagingCollectionView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *cv = (UICollectionView *)view;
        if (!cv.hidden && cv.window && cv.bounds.size.height > 200.0) return cv;
    }
    for (UIView *subview in view.subviews) {
        UICollectionView *found = UYTFindPagingCollectionView(subview);
        if (found) return found;
    }
    return nil;
}

static void UYTAdvanceToNextShort(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:UYTAutoNextShortsKey]) return;
    if (UYTAutoNextBusy) return;

    UIViewController *top = UYTTopViewController();
    if (!UYTContainsShortsController(top)) return;

    UICollectionView *cv = UYTFindPagingCollectionView(top.view);
    if (!cv) return;

    NSArray<NSIndexPath *> *visible = [cv.indexPathsForVisibleItems sortedArrayUsingSelector:@selector(compare:)];
    NSIndexPath *current = visible.firstObject;
    if (!current) return;

    NSInteger sections = [cv numberOfSections];
    NSInteger nextSection = current.section;
    NSInteger nextItem = current.item + 1;
    if (nextItem >= [cv numberOfItemsInSection:nextSection]) {
        nextSection += 1;
        nextItem = 0;
    }
    if (nextSection >= sections || [cv numberOfItemsInSection:nextSection] == 0) return;

    NSIndexPath *next = [NSIndexPath indexPathForItem:nextItem inSection:nextSection];
    UYTAutoNextBusy = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [cv scrollToItemAtIndexPath:next
                        atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                animated:YES];
        } @catch (__unused NSException *exception) {
            CGPoint offset = cv.contentOffset;
            offset.y += MAX(cv.bounds.size.height, 1.0);
            [cv setContentOffset:offset animated:YES];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ UYTAutoNextBusy = NO; });
    });
}

__attribute__((constructor)) static void UYTAutoNextShortsInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
                        UYTAdvanceToNextShort();
                    }];
    });
}
