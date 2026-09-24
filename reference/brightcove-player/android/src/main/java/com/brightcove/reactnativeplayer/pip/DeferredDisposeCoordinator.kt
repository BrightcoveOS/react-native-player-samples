package com.brightcove.reactnativeplayer.pip

/**
 * Coordinates a React Native drop that occurs while Android still displays the
 * Activity in system PiP. Brightcove's SDK removes its PiP media-action
 * receiver from its DID_EXIT listener, so final native disposal must be posted
 * until after that listener has handled the real system exit.
 */
internal class DeferredDisposeCoordinator {
  private var pending = false

  fun defer(): Boolean {
    if (pending) return false

    pending = true
    return true
  }

  fun completeAfterSystemExit(
    postToMain: ((() -> Unit) -> Unit),
    finalizeSdkRegistration: () -> Unit,
    completeCoreDispose: () -> Unit,
  ) {
    if (!pending) return

    pending = false
    postToMain {
      finalizeSdkRegistration()
      completeCoreDispose()
    }
  }
}
