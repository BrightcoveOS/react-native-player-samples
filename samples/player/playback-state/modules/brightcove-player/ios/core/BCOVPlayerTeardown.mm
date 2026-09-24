#import "BCOVPlayerTeardown.h"

BOOL BCOVShouldCompletePlayerTearDown(
    NSUInteger completionToken,
    NSUInteger currentToken,
    BOOL teardownPending)
{
  return teardownPending && completionToken == currentToken;
}
