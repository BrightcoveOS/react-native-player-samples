#import "BCOVQueueCommandOutcome.h"

BCOVQueueCommandOutcome BCOVNextQueueCommandOutcome(
    NSInteger orderCount,
    NSInteger currentOrderIndex,
    BOOL resolutionInProgress,
    BOOL repeatModeAll)
{
  if (orderCount == 0) {
    return BCOVQueueCommandOutcomePending;
  }
  if (currentOrderIndex < orderCount - 1) {
    return BCOVQueueCommandOutcomeAdvanced;
  }
  if (repeatModeAll && !resolutionInProgress) {
    return BCOVQueueCommandOutcomeAdvanced;
  }
  if (resolutionInProgress) {
    return BCOVQueueCommandOutcomePending;
  }
  return BCOVQueueCommandOutcomeAtEnd;
}

BCOVPreviousQueueCommandOutcomeEnum BCOVPreviousQueueCommandOutcome(
    NSInteger orderCount,
    NSInteger currentOrderIndex,
    BOOL repeatModeAll)
{
  if (currentOrderIndex > 0) {
    return BCOVPreviousQueueCommandOutcomePrevious;
  }
  if (repeatModeAll && orderCount > 0) {
    return BCOVPreviousQueueCommandOutcomeWrapToLast;
  }
  return BCOVPreviousQueueCommandOutcomeRestartCurrent;
}

NSString *BCOVQueueAtEndMessage(void)
{
  return @"Cannot advance the queue: the last item is already playing and the repeat mode does not wrap the queue";
}

NSString *BCOVNextQueueNotLoadedMessage(void)
{
  return @"Cannot advance the queue: no queue is loaded in this player";
}

NSString *BCOVPreviousQueueNotLoadedMessage(void)
{
  return @"Cannot go to the previous queue item: no queue is loaded in this player";
}
