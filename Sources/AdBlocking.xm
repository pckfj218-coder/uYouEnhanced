#import <objc/runtime.h>
#import <objc/message.h>

#import "uYouPlus.h"
#import "UYTLog.h"

static NSString *const UYTShortsAdSkipKey = @"shortsAdSkip_enabled";

__attribute__((constructor)) static void UYTRegisterShortsAdSkipDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"removeYouTubeAds": @YES,
        @"autoNextShorts_enabled": @YES,
        @"shortsAdSkip_enabled": @YES,
    }];
}

static BOOL UYTShortsAdSkipEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:UYTShortsAdSkipKey];
}

%group uYouAdBlockingWorkaroundLite
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return YES; }
%end
%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%new(@@:)
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}
%new(@@:)
- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end
%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end
%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end
%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end
%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return nil; }
%end
%hook YTDataUtils
+ (id)spamSignalsDictionary { return nil; }
+ (id)spamSignalsDictionaryWithoutIDFA { return nil; }
%end
%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad {}
%end
%end

%group uYouAdBlockingWorkaround
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return YES; }
%end
%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%new(@@:)
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}
%new(@@:)
- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end
%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end
%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end
%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end
%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return nil; }
%end
%hook YTDataUtils
+ (id)spamSignalsDictionary { return nil; }
+ (id)spamSignalsDictionaryWithoutIDFA { return nil; }
%end
%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end
%hook MDXSession
- (void)adPlaying:(id)ad {}
%end
%hook MDXSessionImpl
- (void)adPlaying:(id)ad {}
%end
// YTLite-compatible policy: do not mutate the active Shorts/Reels carousel.
// Ads are suppressed upstream through player/Innertube response hooks below.
%hook YTIElementRenderer
- (NSData *)elementData {
    if (self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData)
        return nil;
    NSString *description = [self description];
    NSArray *ads = @[
        @"brand_promo",
        @"product_carousel",
        @"product_engagement_panel",
        @"product_item",
        @"text_search_ad",
        @"text_image_button_layout",
        @"carousel_headered_layout",
        @"carousel_footered_layout",
        @"square_image_layout",
        @"landscape_image_wide_button_layout",
        @"feed_ad_metadata"
    ];
    if ([ads containsObject:description])
        return [NSData data];
    return %orig;
}
%end
%hook YTSectionListViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    NSMutableArray<YTISectionListSupportedRenderers *> *contentsArray = model.contentsArray;
    NSIndexSet *removeIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTISectionListSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
        YTIItemSectionRenderer *sectionRenderer = renderers.itemSectionRenderer;
        YTIItemSectionSupportedRenderers *firstObject = [sectionRenderer.contentsArray firstObject];
        return firstObject.hasPromotedVideoRenderer ||
               firstObject.hasCompactPromotedVideoRenderer ||
               firstObject.hasPromotedVideoInlineMutedRenderer;
    }];
    [contentsArray removeObjectsAtIndexes:removeIndexes];
    %orig;
}
%end
static BOOL UYTRuntimeNameMatches(NSString *name) {
    if (!name.length) return NO;
    NSArray<NSString *> *needles = @[
        @"Reel", @"Shorts", @"Infinite", @"PlayerResponse", @"ElementRenderer",
        @"Feed", @"Ad", @"Promo", @"Sponsored", @"VideoDataSource"
    ];
    for (NSString *needle in needles) {
        if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
    return NO;
}

static BOOL UYTRuntimeSelectorMatches(NSString *name) {
    if (!name.length) return NO;
    NSArray<NSString *> *needles = @[
        @"reel", @"short", @"model", @"entry", @"content", @"item", @"feed",
        @"dataSource", @"render", @"ad", @"promo", @"sponsor", @"videoType"
    ];
    for (NSString *needle in needles) {
        if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
    return NO;
}

static void UYTWriteRuntimeShortsClassDump(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!documents.length) documents = NSTemporaryDirectory();
    NSString *path = [documents stringByAppendingPathComponent:@"UYT_RUNTIME_CLASSES.log"];

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    classCount = objc_getClassList(classes, classCount);

    NSMutableString *output = [NSMutableString stringWithFormat:@"generated=%@ classCount=%d\n",
                               [[NSDate date] descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]],
                               classCount];
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);
        if (!UYTRuntimeNameMatches(className)) continue;
        [output appendFormat:@"\nCLASS %@ SUPER %@\n", className, NSStringFromClass(class_getSuperclass(cls)) ?: @""];

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int j = 0; j < methodCount; j++) {
            NSString *selectorName = NSStringFromSelector(method_getName(methods[j]));
            if (UYTRuntimeSelectorMatches(selectorName))
                [output appendFormat:@"  -[%@ %@] types=%s\n", className, selectorName, method_getTypeEncoding(methods[j]) ?: ""];
        }
        free(methods);

        Class meta = object_getClass(cls);
        methodCount = 0;
        methods = class_copyMethodList(meta, &methodCount);
        for (unsigned int j = 0; j < methodCount; j++) {
            NSString *selectorName = NSStringFromSelector(method_getName(methods[j]));
            if (UYTRuntimeSelectorMatches(selectorName))
                [output appendFormat:@"  +[%@ %@] types=%s\n", className, selectorName, method_getTypeEncoding(methods[j]) ?: ""];
        }
        free(methods);
    }
    free(classes);

    NSError *error = nil;
    BOOL ok = [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    UYTDebugInfo(@"UYT_RUNTIME_DUMP ok=%d path=%@ bytes=%lu error=%@", ok, path, (unsigned long)[output lengthOfBytesUsingEncoding:NSUTF8StringEncoding], error);
}

__attribute__((constructor)) static void UYTScheduleRuntimeShortsClassDump(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UYTWriteRuntimeShortsClassDump();
    });
}
static NSString *UYTAdProbeLogPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (!documents.length) documents = NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:@"UYT_ADPROBE.log"];
}

static void UYTAppendAdProbeLine(NSString *line) {
    if (!line.length) return;
    NSString *record = [line stringByAppendingString:@"\n"];
    NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    NSString *path = UYTAdProbeLogPath();
    @synchronized([NSFileManager defaultManager]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static void UYTProbeShortsModel(NSString *source, id model) {
    NSString *timestamp = [[NSDate date] descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    if (!model) {
        UYTAppendAdProbeLine([NSString stringWithFormat:@"%@ source=%@ model=nil", timestamp, source]);
        return;
    }
    NSInteger videoType = -1;
    if ([model respondsToSelector:@selector(videoType)])
        videoType = ((YTReelModel *)model).videoType;
    NSString *description = [model description] ?: @"";
    NSString *customData = @"";
    if ([model isKindOfClass:%c(YTReelNonVideoContentModel)])
        customData = [[[(YTReelNonVideoContentModel *)model renderer].customData description] copy] ?: @"";
    NSString *line = [NSString stringWithFormat:@"%@ source=%@ class=%@ videoType=%ld custom=%@ desc=%@",
                      timestamp, source, NSStringFromClass([model class]), (long)videoType, customData, description];
    UYTAppendAdProbeLine(line);
    UYTDebugInfo(@"UYT_ADPROBE %@", line);
}
static BOOL UYTIsVideoShortsAdModel(YTReelContentModel *model) {
    if (!model) return NO;
    return [model respondsToSelector:@selector(videoType)] && ((YTReelModel *)model).videoType == 3;
}

static BOOL UYTIsNonVideoShortsAdModel(YTReelContentModel *model) {
    if (!model || ![model isKindOfClass:%c(YTReelNonVideoContentModel)]) return NO;
    NSString *description = [[[(YTReelNonVideoContentModel *)model renderer].customData description] copy];
    return [description containsString:@"YTIReelNonVideoAdsCustomData_reelNonVideoAdsCustomData"];
}

static BOOL UYTIsAnyShortsAdModel(YTReelContentModel *model) {
    return UYTIsVideoShortsAdModel(model) || UYTIsNonVideoShortsAdModel(model);
}

%hook YTReelDataSource
- (YTReelContentModel *)makeContentModelForEntry:(id)entry {
    YTReelContentModel *model = %orig;
    UYTProbeShortsModel(@"YTReelDataSource.makeContentModelForEntry", model);
    return UYTIsVideoShortsAdModel(model) ? nil : model;
}
%end

%hook YTReelInfinitePlaybackDataSource
- (YTReelContentModel *)makeContentModelForEntry:(id)entry {
    YTReelContentModel *model = %orig;
    UYTProbeShortsModel(@"YTReelInfinitePlaybackDataSource.makeContentModelForEntry", model);
    return UYTIsAnyShortsAdModel(model) ? nil : model;
}

- (NSMutableOrderedSet *)reels {
    NSMutableOrderedSet *originalReels = %orig;`n    for (id model in originalReels) UYTProbeShortsModel(@"YTReelInfinitePlaybackDataSource.reels", model);
    if (![originalReels isKindOfClass:[NSMutableOrderedSet class]])
        return originalReels;

    NSMutableOrderedSet *filteredReels = [originalReels mutableCopy];
    NSIndexSet *adIndexes = [filteredReels indexesOfObjectsPassingTest:^BOOL(YTReelContentModel *model, NSUInteger idx, BOOL *stop) {
        return UYTIsAnyShortsAdModel(model);
    }];
    if (adIndexes.count > 0)
        [filteredReels removeObjectsAtIndexes:adIndexes];
    return filteredReels;
}
%end
static UIViewController *UYTFindShortsAdvanceController(UIViewController *controller) {
    if (!controller) return nil;
    if ([controller respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)])
        return controller;
    UIViewController *presented = UYTFindShortsAdvanceController(controller.presentedViewController);
    if (presented) return presented;
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *match = UYTFindShortsAdvanceController(child);
        if (match) return match;
    }
    return nil;
}

static UIViewController *UYTActiveShortsAdvanceController(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in windowScene.windows) {
            UIViewController *match = UYTFindShortsAdvanceController(window.rootViewController);
            if (match) return match;
        }
    }
    return nil;
}

static const void *kUYTShortsAdAdvancePending = &kUYTShortsAdAdvancePending;

static void UYTAdvancePastShortsAdView(UIView *view, NSInteger attempt) {
    if (!UYTShortsAdSkipEnabled()) return;
    if (!view) return;

    if (attempt == 1) {
        if ([objc_getAssociatedObject(view, kUYTShortsAdAdvancePending) boolValue]) return;
        objc_setAssociatedObject(view, kUYTShortsAdAdvancePending, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UYTDebugInfo(@"UYT_SHORTS_AD_SKIP_REQUEST class=%@", NSStringFromClass([view class]));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = UYTActiveShortsAdvanceController();
        if (controller) {
            UYTDebugInfo(@"UYT_SHORTS_AD_SKIP_V7 class=%@ reel=%@ attempt=%ld", NSStringFromClass([view class]), NSStringFromClass([controller class]), (long)attempt);
            ((void (*)(id, SEL, id))objc_msgSend)(controller, @selector(reelContentViewRequestsAdvanceToNextVideo:), nil);
            return;
        }

        if (attempt < 10) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UYTAdvancePastShortsAdView(view, attempt + 1);
            });
        } else {
            objc_setAssociatedObject(view, kUYTShortsAdAdvancePending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UYTDebugInfo(@"UYT_SHORTS_AD_SKIP_V7_FAILED class=%@ attempts=%ld", NSStringFromClass([view class]), (long)attempt);
        }
    });
}
%hook YTShortsAdsContentView
- (id)initWithFrame:(CGRect)frame reelModel:(id)reelModel ghostViewManager:(id)ghostViewManager parentResponder:(id)parentResponder {
    id result = %orig;
    if (result) {
        UIView *adView = (UIView *)(id)result;
        UYTDebugInfo(@"UYT_SHORTS_AD_VIEW_INIT class=%@", NSStringFromClass([adView class]));
        UYTAdvancePastShortsAdView(adView, 1);
    }
    return result;
}

- (void)didStartRenderingAdsOverlay {
    %orig;
    UIView *adView = (UIView *)(id)self;
    UYTDebugInfo(@"UYT_SHORTS_AD_OVERLAY_STARTED class=%@", NSStringFromClass([adView class]));
    UYTAdvancePastShortsAdView(adView, 1);
}

- (void)setOverlayRendererFromShortsAdsRenderer:(id)renderer {
    %orig;
    UIView *adView = (UIView *)(id)self;
    UYTDebugInfo(@"UYT_SHORTS_AD_RENDERER class=%@ renderer=%@", NSStringFromClass([adView class]), NSStringFromClass([renderer class]));
    UYTAdvancePastShortsAdView(adView, 1);
}
%end
static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)]) {
        YTIShowEngagementPanelEndpoint *endpoint = [command yt_showEngagementPanelEndpoint];
        return [endpoint.identifier.tag isEqualToString:@"PAproduct_list"];
    }
    return NO;
}
%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        YTICommandExecutorCommand *commandExecutorCommand = [onUiReady yt_commandExecutorCommand];
        NSMutableArray <YTICommand *> *commandsArray = commandExecutorCommand.commandsArray;
        [commandsArray removeObjectsAtIndexes:[commandsArray indexesOfObjectsPassingTest:^BOOL(YTICommand *command, NSUInteger idx, BOOL *stop) {
            return isProductList(command);
        }]];
    }
    if (isProductList(onUiReady))
        model.onUiReady = nil;
    %orig;
}
%end
%hook YTMainAppVideoPlayerOverlayViewController

- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_product_in_video"]) return;
    %orig;
}
%end
NSString *getAdString(NSString *description) {
    for (NSString *str in @[
        @"brand_promo",
        @"brand_video_shelf",
        @"carousel_footered_layout",
        @"carousel_headered_layout",
        @"eml.expandable_metadata",
        @"feed_ad_metadata",
        @"full_width_portrait_image_layout",
        @"full_width_square_image_layout",
        @"grid_ads_image_layout",
        @"landscape_image_wide_button_layout",
        @"post_shelf",
        @"product_carousel",
        @"product_engagement_panel",
        @"product_item",
        @"shopping_carousel",
        @"shopping_item_card_list",
        @"statement_banner",
        @"square_image_layout",
        @"text_image_button_layout",
        @"text_search_ad",
        @"video_display_full_layout",
        @"video_display_full_buttoned_layout"
    ])
        if ([description containsString:str]) return str;
    return nil;
}
static BOOL isAdRenderer(YTIElementRenderer *elementRenderer, int kind) {
    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] && elementRenderer.hasCompatibilityOptions && elementRenderer.compatibilityOptions.hasAdLoggingData) {
        UYTDebugInfo(@"YTX adLogging kind=%d renderer=%@", kind, NSStringFromClass([elementRenderer class]));
        return YES;
    }
    NSString *description = [elementRenderer description];
    NSString *adString = getAdString(description);
    if (adString) {
        UYTDebugInfo(@"YTX getAdString kind=%d match=%lu chars renderer=%@", kind, (unsigned long)adString.length, NSStringFromClass([elementRenderer class]));
        return YES;
    }
    return NO;
}
static NSMutableArray <YTIItemSectionRenderer *> *filteredArray(NSArray <YTIItemSectionRenderer *> *array) {
    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)]) {
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            YTIHorizontalListRenderer *horizontalListRenderer = content.horizontalListRenderer;
            NSMutableArray <YTIHorizontalListSupportedRenderers *> *itemsArray = horizontalListRenderer.itemsArray;
            NSIndexSet *removeItemsArrayIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *horizontalListSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = horizontalListSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 4);
            }];
            [itemsArray removeObjectsAtIndexes:removeItemsArrayIndexes];
        }
        if (![sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)])
            return NO;
        NSMutableArray <YTIItemSectionSupportedRenderers *> *contentsArray = sectionRenderer.contentsArray;
        if (contentsArray.count > 1) {
            NSIndexSet *removeContentsArrayIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *sectionSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = sectionSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 3);
            }];
            [contentsArray removeObjectsAtIndexes:removeContentsArrayIndexes];
        }
        YTIItemSectionSupportedRenderers *firstObject = [contentsArray firstObject];
        YTIElementRenderer *elementRenderer = firstObject.elementRenderer;
        return isAdRenderer(elementRenderer, 2);
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (([self.accessibilityIdentifier isEqualToString:@"eml.expandable_metadata.vpp"]))
        [self removeFromSuperview];
}
%end
%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sectionRenderers) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    %orig(
        filteredArray(array)
    );
}
%end
%end

%ctor {
    if (IS_ENABLED(kAdBlockWorkaroundLite)) {
        %init(uYouAdBlockingWorkaroundLite);
    }
    if (IS_ENABLED(kAdBlockWorkaround)) {
        %init(uYouAdBlockingWorkaround);
    }
}

