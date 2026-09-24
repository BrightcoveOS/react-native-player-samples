package com.brightcove.reactnativeplayer.core

internal fun seekPositionError(positionSeconds: Double): String? = when {
  !positionSeconds.isFinite() -> "positionSeconds must be finite"
  positionSeconds < 0.0 -> "positionSeconds must be non-negative"
  positionSeconds > Long.MAX_VALUE.toDouble() / 1000.0 -> "positionSeconds is too large"
  else -> null
}
