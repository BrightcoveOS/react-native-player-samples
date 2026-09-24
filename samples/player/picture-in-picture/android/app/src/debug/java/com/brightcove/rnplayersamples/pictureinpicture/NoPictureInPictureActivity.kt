package com.brightcove.rnplayersamples.pictureinpicture

import android.content.res.Configuration
import com.brightcove.player.pictureinpicture.PictureInPictureManager
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

/**
 * Debug-only host with no android:supportsPictureInPicture declaration. Launch
 * it with adb to verify that the bridge logs an actionable configuration error
 * and remains safe through backgrounding and teardown.
 */
class NoPictureInPictureActivity : ReactActivity() {
  override fun getMainComponentName(): String = "PictureInPicture"

  override fun createReactActivityDelegate(): ReactActivityDelegate =
    DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)

  override fun onUserLeaveHint() {
    super.onUserLeaveHint()
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
