package com.brightcove.rnplayersamples.pictureinpicture

import android.content.res.Configuration
import com.brightcove.player.pictureinpicture.PictureInPictureManager
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

class MainActivity : ReactActivity() {

  /**
   * Returns the name of the main component registered from JavaScript. This is used to schedule
   * rendering of the component.
   */
  override fun getMainComponentName(): String = "PictureInPicture"

  /**
   * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
   * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
   */
  override fun createReactActivityDelegate(): ReactActivityDelegate =
      DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)

  // Picture-in-Picture is driven by two Activity-level callbacks that only the
  // host Activity can receive. The BrightcovePlayerView registers this Activity
  // with the SDK's PictureInPictureManager; forwarding these lets the SDK enter
  // PiP when the user leaves the app and emit the enter/exit events the bridge
  // relays to JavaScript. A real app hosting the player must forward them too.
  override fun onUserLeaveHint() {
    super.onUserLeaveHint()
    // Only forward while an activity is registered: the bridge unregisters
    // when pictureInPictureEnabled becomes false, and the manager throws (not
    // no-ops) if onUserLeaveHint is called with nothing registered.
    val manager = PictureInPictureManager.getInstance()
    if (manager.isPictureInPictureEnabled) {
      manager.onUserLeaveHint()
    }
  }

  override fun onPictureInPictureModeChanged(
    isInPictureInPictureMode: Boolean,
    newConfig: Configuration,
  ) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    PictureInPictureManager.getInstance()
      .onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
  }
}
