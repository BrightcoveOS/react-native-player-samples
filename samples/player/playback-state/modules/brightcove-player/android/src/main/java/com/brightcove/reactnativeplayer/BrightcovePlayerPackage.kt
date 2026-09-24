package com.brightcove.reactnativeplayer

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager
import java.util.WeakHashMap

class BrightcovePlayerViewPackage : BaseReactPackage() {
  // A package can outlive a React instance. Keep one module map per
  // ReactApplicationContext (not one process-global map), or a reload would
  // reuse a module that invalidated and terminated its OfflineCatalog.
  private val nativeModulesByContext = WeakHashMap<ReactApplicationContext, Map<String, NativeModule>>()

  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
    return listOf(BrightcovePlayerViewManager())
  }

  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    modulesFor(reactContext)[name]

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider =
    FeatureRegistry.createReactModuleInfoProvider()

  @Synchronized
  private fun modulesFor(reactContext: ReactApplicationContext): Map<String, NativeModule> =
    nativeModulesByContext.getOrPut(reactContext) {
      FeatureRegistry.createNativeModules(reactContext).associateBy { it.name }
    }
}
