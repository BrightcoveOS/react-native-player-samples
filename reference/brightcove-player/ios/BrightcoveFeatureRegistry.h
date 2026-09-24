#import <Foundation/Foundation.h>

#import "core/BrightcovePlayerFeature.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The features this bridge copy contains. This file is owned by each sample
 * (like README/tsconfig): a sample lists exactly the features whose
 * directories it copied, and nothing else. The reference registers everything.
 */
@interface BrightcoveFeatureRegistry : NSObject

+ (NSArray<id<BrightcovePlayerFeature>> *)installedFeatures;

@end

NS_ASSUME_NONNULL_END
