require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# Optional native feature flags for iOS.
# Core features (audio description, audio tracks, buffering, caption rendering,
# captions, chapter navigation, controls, DRM, fullscreen, lifecycle, live,
# playlists, PiP, preloading, quality, sidecar captions, source loading modes,
# timed metadata, and 360 video) are always present in the build. Offline
# playback is included only when its native SDK support is enabled on Android;
# iOS offline playback uses the core BrightcovePlayerSDK product.
#
# Optional third-party vendor frameworks are gated by parse-time environment
# variables set in the consumer's Podfile before `pod install`:
#   ENV['BRIGHTCOVE_WITH_ADS'] = '1'
#   ENV['BRIGHTCOVE_WITH_CAST'] = '1'
#   ENV['BRIGHTCOVE_WITH_DAI'] = '1'
#   ENV['BRIGHTCOVE_WITH_SSAI'] = '1'
#   ENV['BRIGHTCOVE_WITH_FREEWHEEL'] = '1'
#   ENV['BRIGHTCOVE_WITH_OMNITURE'] = '1'
#   ENV['BRIGHTCOVE_WITH_PULSE'] = '1'
#
# Note: React Native's SwiftPM integration evaluates `spm_dependency` at
# podspec parse time on the root spec, so environment variables directly drive
# SPM product linkage, source_files inclusion, and preprocessor definitions.
with_ads = ENV["BRIGHTCOVE_WITH_ADS"] == "1"
with_cast = ENV["BRIGHTCOVE_WITH_CAST"] == "1"
with_dai = ENV["BRIGHTCOVE_WITH_DAI"] == "1"
with_ssai = ENV["BRIGHTCOVE_WITH_SSAI"] == "1"
with_freewheel = ENV["BRIGHTCOVE_WITH_FREEWHEEL"] == "1"
with_omniture = ENV["BRIGHTCOVE_WITH_OMNITURE"] == "1"
with_pulse = ENV["BRIGHTCOVE_WITH_PULSE"] == "1"

# Mutually exclusive ad models check
# Ads and SSAI can be co-linked when both are requested for independent player instances.
exclusive_ad_flags = [with_dai, with_freewheel, with_pulse]
if exclusive_ad_flags.count(true) > 1 || (exclusive_ad_flags.any? && (with_ads || with_ssai))
  raise "BrightcovePlayer: unsupported combination of ad framework integrations. " \
        "Only BRIGHTCOVE_WITH_ADS and BRIGHTCOVE_WITH_SSAI may be co-enabled."
end

Pod::Spec.new do |s|
  s.name         = "BrightcovePlayer"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => ".git", :tag => "#{s.version}" }

  # Core sources and always-on features
  core_feature_dirs = [
    "airplay",
    "audiodescription",
    "audiotracks",
    "background",
    "buffering",
    "captionrendering",
    "captions",
    "chapternavigation",
    "controls",
    "core",
    "drm",
    "fullscreen",
    "lifecycle",
    "live",
    "offline",
    "pip",
    "playbackevents",
    "playlists",
    "preloading",
    "quality",
    "sidecarcaptions",
    "sourceloadingmodes",
    "thumbnail",
    "timedmetadata",
    "video360"
  ]
  sources = ["ios/*.{h,m,mm}"]
  core_feature_dirs.each do |dir|
    sources << "ios/#{dir}/**/*.{h,m,mm,swift,cpp}"
  end

  # Optional vendor integrations are added only when enabled. The corresponding
  # consumer must also provide any licensed vendor framework required by that
  # integration (for example AdManager for FreeWheel or Pulse's vendor SDK).
  sources << "ios/ads/**/*.{h,m,mm,swift,cpp}" if with_ads
  sources << "ios/cast/**/*.{h,m,mm,swift,cpp}" if with_cast
  sources << "ios/dai/**/*.{h,m,mm,swift,cpp}" if with_dai
  sources << "ios/ssai/**/*.{h,m,mm,swift,cpp}" if with_ssai
  sources << "ios/freewheel/**/*.{h,m,mm,swift,cpp}" if with_freewheel
  sources << "ios/omniture/**/*.{h,m,mm,swift,cpp}" if with_omniture
  sources << "ios/pulse/**/*.{h,m,mm,swift,cpp}" if with_pulse

  s.source_files = sources
  s.private_header_files = "ios/**/*.h"

  s.frameworks = "AVFoundation", "CoreMedia"
  s.weak_frameworks = "GoogleCast" if with_cast

  preprocessor_defs = ["$(inherited)"]
  preprocessor_defs << "BRIGHTCOVE_FEATURE_ADS=1" if with_ads
  preprocessor_defs << "BRIGHTCOVE_FEATURE_CAST=1" if with_cast
  preprocessor_defs << "BRIGHTCOVE_FEATURE_DAI=1" if with_dai
  preprocessor_defs << "BRIGHTCOVE_FEATURE_SSAI=1" if with_ssai
  preprocessor_defs << "BRIGHTCOVE_FEATURE_FREEWHEEL=1" if with_freewheel
  preprocessor_defs << "BRIGHTCOVE_FEATURE_OMNITURE=1" if with_omniture
  preprocessor_defs << "BRIGHTCOVE_FEATURE_PULSE=1" if with_pulse

  s.pod_target_xcconfig = {
    "CLANG_ENABLE_MODULES" => "YES",
    "OTHER_CPLUSPLUSFLAGS" => "$(inherited) -fcxx-modules",
    "GCC_PREPROCESSOR_DEFINITIONS" => preprocessor_defs.join(" "),
  }

  unless defined?(spm_dependency)
    raise "BrightcovePlayer requires React Native's SwiftPM CocoaPods integration."
  end

  spm_products = ["BrightcovePlayerSDK"]
  spm_products << "BrightcoveIMA" if with_ads
  spm_products << "BrightcoveGoogleCast" if with_cast
  spm_products << "BrightcoveDAI" if with_dai
  spm_products << "BrightcoveSSAI" if with_ssai
  spm_products << "BrightcoveFW" if with_freewheel
  spm_products << "BrightcoveAMC" if with_omniture
  spm_products << "BrightcovePulse" if with_pulse

  spm_dependency(
    s,
    url: "https://github.com/brightcove/brightcove-player-sdk-ios.git",
    requirement: {
      kind: "upToNextMajorVersion",
      minimumVersion: "7.2.16",
    },
    products: spm_products,
  )

  install_modules_dependencies(s)
end
