require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "BrightcovePlayer"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => ".git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  # AVFoundation for playback errors and CoreMedia for CMTime progress values.
  s.frameworks = "AVFoundation", "CoreMedia"

  # BrightcoveIMA's public headers use `@import BrightcovePlayerSDK;` (an
  # Objective-C module import). Files that include them are compiled as
  # Objective-C++ here (the Fabric event emitter is C++), and a module import in
  # that context needs C++ modules enabled — otherwise clang errors with "use of
  # '@import' when C++ modules are disabled".
  #
  # pod_target_xcconfig applies only to this pod's own compilation, not to the
  # app or other pods, so the blast radius is contained to BrightcovePlayer. The
  # OTHER_CPLUSPLUSFLAGS value prepends $(inherited) so it augments — never
  # replaces — flags React Native already sets (e.g. the VFS overlay). A core /
  # captions / pip bridge copy that never imports BrightcoveIMA is unaffected by
  # the flag being present; only the ads sources actually exercise it.
  s.pod_target_xcconfig = {
    "CLANG_ENABLE_MODULES" => "YES",
    "OTHER_CPLUSPLUSFLAGS" => "$(inherited) -fcxx-modules",
  }

  unless defined?(spm_dependency)
    raise "BrightcovePlayer requires React Native's SwiftPM CocoaPods integration."
  end

  spm_dependency(
    s,
    url: "https://github.com/brightcove/brightcove-player-sdk-ios.git",
    requirement: {
      kind: "upToNextMajorVersion",
      minimumVersion: "7.2.16",
    },
    # BRIDGE:SPM_PRODUCTS — the SwiftPM products this bridge copy needs. The core
    # needs BrightcovePlayerSDK; features add their own (ads -> BrightcoveIMA).
    # scripts/assemble-bridge.sh regenerates this line from the installed feature
    # set, so it is a generated composition root — do not hand-edit.
    products: ["BrightcovePlayerSDK", "BrightcoveIMA"],
  )

  install_modules_dependencies(s)
end
