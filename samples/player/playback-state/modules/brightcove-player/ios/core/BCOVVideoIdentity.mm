#import "BCOVVideoIdentity.h"

NSString *const BCOVVideoRequestGenerationKey = @"com.brightcove.reactnativeplayer.requestGeneration";

BOOL BCOVVideoIsCurrentRequest(BCOVVideo *video, NSUInteger requestGeneration)
{
  if (video == nil) {
    return NO;
  }

  // The tag is the sole authority and the rule is fail-closed: every loader
  // this repository ships stamps it, so a video without one names nothing this
  // view loaded and is rejected — including a video that merely matches the
  // videoId prop (an untagged loader must never silently gain event
  // forwarding).
  NSNumber *generation = video.properties[BCOVVideoRequestGenerationKey];
  return [generation isKindOfClass:NSNumber.class] &&
      generation.unsignedIntegerValue == requestGeneration;
}
