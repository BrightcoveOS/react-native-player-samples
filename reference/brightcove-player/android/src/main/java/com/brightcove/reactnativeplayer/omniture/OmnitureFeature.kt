package com.brightcove.reactnativeplayer.omniture

import com.brightcove.omniture.OmnitureComponent
import com.brightcove.omniture.OmnitureEventType
import com.brightcove.reactnativeplayer.core.FeatureHost
import com.brightcove.reactnativeplayer.core.PlayerFeature

class OmnitureFeature : PlayerFeature {
  private lateinit var host: FeatureHost
  private var omnitureComponent: OmnitureComponent? = null

  private var trackingServer: String? = null
  private var channel: String? = null
  private var appVersion: String? = null
  private var ovp: String? = null
  private var playerName: String? = null
  private var ssl: Boolean = true
  private var debugLogging: Boolean = false

  override val ownedProps = setOf(
    "heartbeatTrackingServer",
    "heartbeatChannel",
    "heartbeatAppVersion",
    "heartbeatOvp",
    "heartbeatPlayerName",
    "heartbeatSsl",
    "heartbeatDebugLogging",
  )

  override val exportedEvents: Map<String, String> = emptyMap()

  override fun attach(host: FeatureHost) {
    this.host = host
  }

  override fun setProp(name: String, value: Any?) {
    when (name) {
      "heartbeatTrackingServer" -> {
        trackingServer = (value as? String)?.ifBlank { null }
        ensureOmnitureComponent()
      }
      "heartbeatChannel" -> {
        channel = (value as? String)?.ifBlank { null }
        ensureOmnitureComponent()
      }
      "heartbeatAppVersion" -> {
        appVersion = (value as? String)?.ifBlank { null }
        ensureOmnitureComponent()
      }
      "heartbeatOvp" -> {
        ovp = (value as? String)?.ifBlank { null }
        ensureOmnitureComponent()
      }
      "heartbeatPlayerName" -> {
        playerName = (value as? String)?.ifBlank { null }
        ensureOmnitureComponent()
      }
      "heartbeatSsl" -> {
        ssl = value as? Boolean ?: true
        ensureOmnitureComponent()
      }
      "heartbeatDebugLogging" -> {
        debugLogging = value as? Boolean ?: false
        ensureOmnitureComponent()
      }
      else -> error("OmnitureFeature owns no prop '$name'")
    }
  }

  private fun ensureOmnitureComponent() {
    if (omnitureComponent != null || host.isDisposed) return
    val server = trackingServer ?: return
    val configuredChannel = channel ?: return
    val configuredAppVersion = appVersion ?: return
    val configuredOvp = ovp ?: return
    val configuredPlayerName = playerName ?: return
    val context = host.hostView.context ?: return

    val pId = "BrightcovePlayer"
    val component = OmnitureComponent(
      host.eventEmitter,
      context,
      configuredPlayerName,
      pId,
      host.videoView,
      true,
    )

    val configData = HashMap<String, Any>().apply {
      put(OmnitureComponent.HEARTBEAT_TRACKING_SERVER, server)
      put(OmnitureComponent.HEARTBEAT_CHANNEL, configuredChannel)
      put(OmnitureComponent.HEARTBEAT_APP_VERSION, configuredAppVersion)
      put(OmnitureComponent.HEARTBEAT_OVP, configuredOvp)
      put(OmnitureComponent.HEARTBEAT_SSL, ssl)
      put(OmnitureComponent.HEARTBEAT_DEBUG_LOGGING, debugLogging)
    }
    host.eventEmitter.emit(OmnitureEventType.SET_HEARTBEAT_CONFIG_DATA, configData)

    omnitureComponent = component
  }

  override fun onRegisterPlaybackListeners() {
    if (omnitureComponent == null) {
      ensureOmnitureComponent()
    }
    if (omnitureComponent == null && !host.isDisposed) {
      throw IllegalStateException(
        "Omniture requires heartbeatTrackingServer, heartbeatChannel, " +
          "heartbeatAppVersion, heartbeatOvp, and heartbeatPlayerName",
      )
    }
  }

  override fun onDispose() {
    omnitureComponent?.removeListeners()
    omnitureComponent = null
  }
}
