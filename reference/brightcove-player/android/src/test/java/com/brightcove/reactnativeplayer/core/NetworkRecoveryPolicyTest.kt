package com.brightcove.reactnativeplayer.core

import androidx.media3.common.PlaybackException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkRecoveryPolicyTest {
  @Test
  fun recoversEveryCodeInTheClassifiersNetworkRangeExceptTheTwoNonTransientOnes() {
    for (code in PlaybackException.ERROR_CODE_IO_UNSPECIFIED..
      PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE) {
      val expected = code != PlaybackException.ERROR_CODE_IO_NO_PERMISSION &&
        code != PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND
      assertEquals(
        "code=$code",
        expected,
        NetworkRecoveryPolicy.isRecoverableNetworkError(
          errorCode = code,
          alreadyRecovering = false,
          videoLoaded = true,
        ),
      )
    }
  }

  // The scenario the PR title names: dropping the connection mid-request
  // surfaces as a timeout, not a connection-failed — both must recover.
  @Test
  fun recoversBothConnectionFailedAndConnectionTimeout() {
    assertTrue(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
    assertTrue(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
  }

  @Test
  fun doesNotRecoverPermissionOrFileNotFound() {
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_NO_PERMISSION,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
  }

  @Test
  fun doesNotRecoverACodeOutsideTheIoRange() {
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_DRM_LICENSE_EXPIRED,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
  }

  @Test
  fun doesNotRecoverANullErrorCode() {
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = null,
        alreadyRecovering = false,
        videoLoaded = true,
      ),
    )
  }

  // Exactly one retry per outage: a second IO error while a recovery is
  // already in flight falls through to the terminal path instead of
  // restarting the recovery again.
  @Test
  fun doesNotRecoverASecondErrorWhileAlreadyRecovering() {
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        alreadyRecovering = true,
        videoLoaded = true,
      ),
    )
  }

  // A failure before the source has ever prepared once belongs to the
  // ordinary catalog/source-load error path, not mid-playback recovery.
  @Test
  fun doesNotRecoverBeforeTheVideoHasEverLoaded() {
    assertFalse(
      NetworkRecoveryPolicy.isRecoverableNetworkError(
        errorCode = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        alreadyRecovering = false,
        videoLoaded = false,
      ),
    )
  }

  @Test
  fun resumesWhenPlaybackWasRequested() {
    assertTrue(NetworkRecoveryPolicy.shouldResumeAfterRecovery(playbackRequested = true, isPlaying = false))
  }

  @Test
  fun resumesWhenExoPlayerWasStillReportingPlaying() {
    assertTrue(NetworkRecoveryPolicy.shouldResumeAfterRecovery(playbackRequested = false, isPlaying = true))
  }

  // The case etri flagged as most important: a user who had explicitly
  // paused before the outage must not have playback resumed for them by the
  // recovery — that would be a video starting itself in someone's pocket.
  @Test
  fun doesNotResumeAVideoTheUserHadExplicitlyPaused() {
    assertFalse(NetworkRecoveryPolicy.shouldResumeAfterRecovery(playbackRequested = false, isPlaying = false))
  }
}
