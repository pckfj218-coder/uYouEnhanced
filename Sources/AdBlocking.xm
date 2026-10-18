
#import "uYouPlus.h"
#import "UYTLog.h"

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

