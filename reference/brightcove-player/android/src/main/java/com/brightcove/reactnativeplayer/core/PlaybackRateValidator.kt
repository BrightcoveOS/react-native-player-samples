package com.brightcove.reactnativeplayer.core

internal object PlaybackRateValidator {
  fun validate(value: Double): Float? {
    val floatValue = value.toFloat()
    if (!value.isFinite() || value <= 0.0 || !floatValue.isFinite() || floatValue <= 0f) {
      return null
    }
    return floatValue
  }
}
